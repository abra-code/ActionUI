// Sources/Runtime/URLLoader.swift
/*
 Loads the bytes a URL names without blocking the GLib main loop: http and https with libsoup 3
 (one shared session), file URLs with GIO (regular files only), data URLs (base64 or
 percent-encoded) with libsoup's decoder. The completion runs on the main thread, always after fetch returns, with the bytes, or
 nil for a URL that names nothing loadable: another scheme, a malformed URL, an http status outside
 200-299, a read or network error. https needs glib-networking, which GNOME desktops install; without
 it, the first https load logs a warning naming it. No FoundationNetworking: it needs full Foundation
 and libcurl on Linux.
 An http or https load is refused (nil, logged) when a redirect would take an https address to plain
 http, when the body grows past maximumSize, or when the whole load takes longer than totalTimeout;
 the body is read in pieces, so a large one is cut off rather than held whole first. Plain http
 itself stays allowed, as macOS allows it with an App Transport Security exception.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita
import CSoup

/// Bytes GLib owns (a GBytes), released with the last Swift reference. GBytes is immutable and its
/// reference count atomic, so the bytes can be read on another thread (decoding an image).
package final class LoadedBytes: @unchecked Sendable {
    let bytes: OpaquePointer

    init(adopting bytes: OpaquePointer) {
        self.bytes = bytes
    }

    /// A copy of the bytes.
    package var data: Data {
        var size: gsize = 0
        guard let start = g_bytes_get_data(bytes, &size), size > 0 else { return Data() }
        return Data(bytes: start, count: Int(size))
    }

    deinit {
        g_bytes_unref(bytes)
    }
}

/// An asynchronous call's completion: runs with the call's GAsyncResult.
package typealias ReadyRun = @MainActor (OpaquePointer?) -> Void

/// GIO's ready callback for one call: runs the box's closure once, then releases the box. Its user
/// data is `Unmanaged.passRetained(CallbackBox(run)).toOpaque()` (also used by ShareLink's D-Bus call).
package let readyTrampoline: @convention(c) (UnsafeMutablePointer<GObject>?, OpaquePointer?, gpointer?) -> Void = { _, result, data in
    guard let data else { return }
    let box = Unmanaged<CallbackBox<ReadyRun>>.fromOpaque(data).takeRetainedValue()
    // A pointer is not Sendable; its address is. GIO calls back on the main thread.
    let address = result.map { Int(bitPattern: UnsafeRawPointer($0)) }
    MainActor.assumeIsolated { box.run(address.flatMap { OpaquePointer(bitPattern: $0) }) }
}

@MainActor
package enum URLLoader {
    /// How long one step of an http request (connecting, a read, a write) may wait before the
    /// request fails, in seconds.
    static let timeout: guint = 30

    /// The largest body an http or https load reads, in bytes (32 MB, the owner's cap for remote
    /// downloads); a larger one is refused. Settable for tests.
    static var maximumSize = 32 * 1024 * 1024

    /// How long a whole http or https load may take, in milliseconds, however the server sends: a
    /// server that keeps sending slowly is cut off here. Settable for tests.
    static var totalTimeout: UInt32 = 120_000

    /// Whether the https warning (glib-networking missing) was logged in this process.
    private static var warnedNoTLS = false

    private static var session: UnsafeMutablePointer<SoupSession>?

    /// Loads `url`'s bytes and passes them to `completion`, or nil (see the header).
    package static func fetch(_ url: String, _ completion: @escaping @MainActor (LoadedBytes?) -> Void) {
        // Lowercase and interned by GLib: not freed.
        switch swiftString(g_uri_peek_scheme(url)) {
        case "http", "https":
            fetchHTTP(url, completion)
        case "file":
            fetchFile(url, completion)
        case "data":
            let bytes = soup_uri_decode_data_uri(url, nil).map { LoadedBytes(adopting: $0) }
            _ = runAfter(milliseconds: 0) { completion(bytes) }
        default:
            _ = runAfter(milliseconds: 0) { completion(nil) }
        }
    }

    /// `url`'s bytes as Data, for a caller that takes an asynchronous fetch (ActionUIDocumentLoader);
    /// throws when fetch gives nil.
    static func data(_ url: URL) async throws -> Data {
        let bytes = await withCheckedContinuation { continuation in
            fetch(url.absoluteString) { continuation.resume(returning: $0) }
        }
        guard let bytes else { throw ActionUIError("Could not load \(url.absoluteString)") }
        return bytes.data
    }

    private static func sharedSession() -> UnsafeMutablePointer<SoupSession> {
        if let session { return session }
        let made = soup_session_new()!
        soup_session_set_timeout(made, timeout)
        session = made
        return made
    }

    /// Whether following a redirect from `original` to `next` (two URL schemes) lowers https to
    /// plain http, which a load refuses: the page asked for a protected address.
    static func isDowngrade(from original: String?, to next: String?) -> Bool {
        return original?.lowercased() == "https" && next?.lowercased() == "http"
    }

    private static func fetchHTTP(_ url: String, _ completion: @escaping @MainActor (LoadedBytes?) -> Void) {
        guard let message = soup_message_new("GET", url) else {
            _ = runAfter(milliseconds: 0) { completion(nil) }
            return
        }
        if swiftString(g_uri_peek_scheme(url)) == "https", !warnedNoTLS,
           g_tls_backend_supports_tls(g_tls_backend_get_default()) == 0 {
            warnedNoTLS = true
            ActionUIModel.shared.logger.log("https addresses cannot load: GIO has no TLS backend; install glib-networking", .warning)
        }
        HTTPLoad(url: url, message: message, session: sharedSession(), completion: completion).start()
    }

    private static func fetchFile(_ url: String, _ completion: @escaping @MainActor (LoadedBytes?) -> Void) {
        // Only a regular file: a document names the address, and GIO would read a device such as
        // /dev/zero until memory runs out, or hold a worker thread on a named pipe for good.
        // GIO checks the file it will read (symbolic links followed): a path through Swift's String
        // would lose a file name that is not UTF-8.
        let file = g_file_new_for_uri(url)!
        guard g_file_query_file_type(file, GFileQueryInfoFlags(rawValue: 0), nil) == G_FILE_TYPE_REGULAR else {
            g_object_unref(UnsafeMutableRawPointer(file))
            ActionUIModel.shared.logger.log("Not loading \(url): it names no regular file", .warning)
            _ = runAfter(milliseconds: 0) { completion(nil) }
            return
        }
        let run: ReadyRun = { result in
            var error: UnsafeMutablePointer<GError>?
            let bytes = g_file_load_bytes_finish(file, result, nil, &error)
            g_object_unref(UnsafeMutableRawPointer(file))
            if let error { g_error_free(error) }
            completion(bytes.map { LoadedBytes(adopting: $0) })
        }
        let data = Unmanaged.passRetained(CallbackBox(run)).toOpaque()
        g_file_load_bytes_async(file, nil, readyTrampoline, data)
    }
}

/// One http or https load: sends the request, refuses a redirect from https to http, reads the
/// body in pieces up to URLLoader.maximumSize, and gives up after URLLoader.totalTimeout. Keeps
/// itself alive (through the callbacks it registers) until it has called its completion once.
@MainActor
private final class HTTPLoad {
    private let url: String
    private let message: OpaquePointer
    private let session: UnsafeMutablePointer<SoupSession>
    private let completion: @MainActor (LoadedBytes?) -> Void
    private let cancellable = g_cancellable_new()!
    private var stream: UnsafeMutablePointer<GInputStream>?
    private var body = Data()
    private var timer: guint = 0
    /// Why the load was stopped, logged when it ends; nil while it runs or when it failed on its own.
    private var refusal: String?
    private var finished = false
    private static let pieceSize = 64 * 1024

    init(url: String, message: OpaquePointer, session: UnsafeMutablePointer<SoupSession>,
         completion: @escaping @MainActor (LoadedBytes?) -> Void) {
        self.url = url
        self.message = message
        self.session = session
        self.completion = completion
    }

    func start() {
        let originalScheme = swiftString(g_uri_peek_scheme(url))
        // Emitted before a redirect is sent: stop it there, so the plain http request never goes out.
        connectSignal(UnsafeMutableRawPointer(message), "restarted", .instanceOnly) { [self] in
            guard let uri = soup_message_get_uri(message) else { return }
            let next = swiftString(g_uri_get_scheme(uri))
            if URLLoader.isDowngrade(from: originalScheme, to: next) {
                stop("a redirect would take it from https to plain http", callInFlight: true)
            }
        }
        timer = runAfter(milliseconds: URLLoader.totalTimeout) { [self] in
            timer = 0
            stop("it took longer than \(URLLoader.totalTimeout) ms", callInFlight: true)
        }
        let run: ReadyRun = { [self] result in
            var error: UnsafeMutablePointer<GError>?
            let opened = soup_session_send_finish(session, result, &error)
            if let error { g_error_free(error) }
            let status = soup_message_get_status(message).rawValue
            guard let opened, (200...299).contains(status) else {
                if let opened { g_object_unref(UnsafeMutableRawPointer(opened)) }
                return finish(nil)
            }
            stream = opened
            readPiece()
        }
        soup_session_send_async(session, message, G_PRIORITY_DEFAULT, cancellable, readyTrampoline,
                                Unmanaged.passRetained(CallbackBox(run)).toOpaque())
    }

    private func readPiece() {
        guard let stream else { return finish(nil) }
        let run: ReadyRun = { [self] result in
            var error: UnsafeMutablePointer<GError>?
            let piece = g_input_stream_read_bytes_finish(stream, result, &error)
            if let error { g_error_free(error) }
            guard let piece else { return finish(nil) }
            defer { g_bytes_unref(piece) }
            var size: gsize = 0
            let start = g_bytes_get_data(piece, &size)
            if size == 0 {
                return finish(body)
            }
            guard body.count + Int(size) <= URLLoader.maximumSize else {
                stop("it is larger than \(URLLoader.maximumSize) bytes", callInFlight: false)
                return
            }
            if let start {
                body.append(start.assumingMemoryBound(to: UInt8.self), count: Int(size))
            }
            readPiece()
        }
        g_input_stream_read_bytes_async(stream, gsize(Self.pieceSize), G_PRIORITY_DEFAULT, cancellable, readyTrampoline,
                                        Unmanaged.passRetained(CallbackBox(run)).toOpaque())
    }

    /// Stops the load for `reason`. With a call in flight, cancelling it makes it end with an
    /// error, which finishes the load; without one (a read has just ended), it finishes here.
    private func stop(_ reason: String, callInFlight: Bool) {
        guard !finished, refusal == nil else { return }
        refusal = reason
        g_cancellable_cancel(cancellable)
        if !callInFlight {
            finish(nil)
        }
    }

    private func finish(_ data: Data?) {
        guard !finished else { return }
        finished = true
        if timer != 0 {
            g_source_remove(timer)
            timer = 0
        }
        if let stream {
            g_object_unref(UnsafeMutableRawPointer(stream))
            self.stream = nil
        }
        g_object_unref(UnsafeMutableRawPointer(message))
        g_object_unref(UnsafeMutableRawPointer(cancellable))
        if let refusal {
            ActionUIModel.shared.logger.log("Not loading \(url): \(refusal)", .warning)
            return completion(nil)
        }
        guard let data else { return completion(nil) }
        let bytes = data.withUnsafeBytes { buffer in g_bytes_new(buffer.baseAddress, gsize(buffer.count))! }
        completion(LoadedBytes(adopting: bytes))
    }
}
