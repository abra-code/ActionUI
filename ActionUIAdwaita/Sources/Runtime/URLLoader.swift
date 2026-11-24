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
 http or to another scheme, after more than 20 redirects, when the body grows past maximumSize, or
 when the whole load takes longer than totalTimeout (the configuration's maximumDownloadTime); the
 body is read in pieces, so a large one is cut off rather than held whole first. The loader follows redirects itself, dropping a redirect's
 own body unread (libsoup would read it whole first, outside the cap). Plain http itself stays
 allowed, as macOS allows it with an App Transport Security exception.
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
    /// The address the bytes finally came from, after redirects; nil when not known.
    package let url: String?

    init(adopting bytes: OpaquePointer, url: String? = nil) {
        self.bytes = bytes
        self.url = url
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

    /// The largest body an http or https load reads, in bytes (32 MB, the cap for remote
    /// downloads); a larger one is refused. Settable for tests.
    static var maximumSize = 32 * 1024 * 1024

    /// How long a whole http or https load may take, in milliseconds, however the server sends: a
    /// server that keeps sending slowly is cut off here. The configuration's maximumDownloadTime,
    /// at least 1 ms; nil: no limit.
    static var totalTimeout: UInt32? {
        ActionUIConfiguration.current.limits.maximumDownloadTime.map { seconds in
            UInt32(min(max((seconds * 1000).rounded(.up), 1), Double(UInt32.max)))
        }
    }

    /// Whether the https warning (glib-networking missing) was logged in this process.
    private static var warnedNoTLS = false

    private static var session: UnsafeMutablePointer<SoupSession>?

    /// Loads `url`'s bytes and passes them to `completion`, or nil (see the header). An http or
    /// https body may be at most `maximumSize` bytes (nil: URLLoader.maximumSize).
    package static func fetch(_ url: String, maximumSize: Int? = nil, _ completion: @escaping @MainActor (LoadedBytes?) -> Void) {
        // Lowercase and interned by GLib: not freed.
        switch swiftString(g_uri_peek_scheme(url)) {
        case "http", "https":
            fetchHTTP(url, maximumSize: maximumSize ?? Self.maximumSize, completion)
        case "file":
            fetchFile(url, completion)
        case "data":
            let bytes = soup_uri_decode_data_uri(url, nil).map { LoadedBytes(adopting: $0, url: url) }
            _ = runAfter(milliseconds: 0) { completion(bytes) }
        default:
            _ = runAfter(milliseconds: 0) { completion(nil) }
        }
    }

    /// `url`'s bytes as Data, with the address they finally came from (after redirects), for a
    /// caller that takes an asynchronous fetch (ActionUIContentLoader); throws when fetch gives nil.
    static func data(_ url: URL, maximumSize: Int? = nil) async throws -> (data: Data, finalURL: URL) {
        let bytes = await withCheckedContinuation { continuation in
            fetch(url.absoluteString, maximumSize: maximumSize) { continuation.resume(returning: $0) }
        }
        guard let bytes else { throw ActionUIError("Could not load \(url.absoluteString)") }
        // Not `url` for a final address Foundation cannot read: a trusted server's redirect would
        // then pass for the trusted address.
        guard let finalText = bytes.url else { return (bytes.data, url) }
        guard let finalURL = URL(string: finalText) else {
            throw ActionUIError("Could not load \(url.absoluteString): it was redirected to an address that cannot be read")
        }
        return (bytes.data, finalURL)
    }

    /// The most an http or https load of ActionUI JSON reads: URLLoader.maximumSize, or the
    /// configuration's JSON size limit when the host raised it above that (larger JSON is refused
    /// when it loads anyway).
    package static var maximumJSONFetchSize: Int {
        max(maximumSize, ActionUIConfiguration.current.limits.maximumJSONSize)
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

    private static func fetchHTTP(_ url: String, maximumSize: Int, _ completion: @escaping @MainActor (LoadedBytes?) -> Void) {
        guard let message = soup_message_new("GET", url) else {
            _ = runAfter(milliseconds: 0) { completion(nil) }
            return
        }
        if swiftString(g_uri_peek_scheme(url)) == "https", !warnedNoTLS,
           g_tls_backend_supports_tls(g_tls_backend_get_default()) == 0 {
            warnedNoTLS = true
            ActionUIModel.shared.logger.log("https addresses cannot load: GIO has no TLS backend; install glib-networking", .warning)
        }
        HTTPLoad(url: url, message: message, session: sharedSession(), maximumSize: maximumSize, completion: completion).start()
    }

    private static func fetchFile(_ url: String, _ completion: @escaping @MainActor (LoadedBytes?) -> Void) {
        // Only a regular file: the JSON names the address, and GIO would read a device such as
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
            completion(bytes.map { LoadedBytes(adopting: $0, url: url) })
        }
        let data = Unmanaged.passRetained(CallbackBox(run)).toOpaque()
        g_file_load_bytes_async(file, nil, readyTrampoline, data)
    }
}

/// One http or https load: sends the request, follows redirects (301, 302, 303, 307, 308) itself,
/// refusing one from https to http, reads the body in pieces up to its maximumSize, and gives
/// up after URLLoader.totalTimeout, as it was when the load started. Keeps itself alive (through
/// the callbacks it registers) until it has called its completion once.
@MainActor
private final class HTTPLoad {
    private let url: String
    /// The request being sent: the first one, then each redirect's.
    private var message: OpaquePointer
    /// The address `message` asks for, which a relative redirect is read against.
    private var current: String
    private var redirects = 0
    private let session: UnsafeMutablePointer<SoupSession>
    /// The largest body it reads, in bytes.
    private let maximumSize: Int
    private let completion: @MainActor (LoadedBytes?) -> Void
    private let cancellable = g_cancellable_new()!
    private var stream: UnsafeMutablePointer<GInputStream>?
    private var body = Data()
    private var timer: guint = 0
    /// Why the load was stopped, logged when it ends; nil while it runs or when it failed on its own.
    private var refusal: String?
    private var finished = false
    private static let pieceSize = 64 * 1024
    /// The most redirects one load follows (libsoup's own limit is 20 too).
    private static let maximumRedirects = 20
    /// The statuses that redirect a GET, as libsoup's own following reads them.
    private static let redirectStatuses: Set<UInt32> = [301, 302, 303, 307, 308]

    init(url: String, message: OpaquePointer, session: UnsafeMutablePointer<SoupSession>, maximumSize: Int,
         completion: @escaping @MainActor (LoadedBytes?) -> Void) {
        self.url = url
        self.current = url
        self.message = message
        self.session = session
        self.maximumSize = maximumSize
        self.completion = completion
    }

    func start() {
        if let limit = URLLoader.totalTimeout {
            timer = runAfter(milliseconds: limit) { [self] in
                timer = 0
                stop("it took longer than \(limit) ms", callInFlight: true)
            }
        }
        send()
    }

    /// Sends `message`, then reads its body, or follows its redirect.
    private func send() {
        // libsoup's own following reads a redirect's whole body into memory before going on,
        // outside the size cap.
        soup_message_add_flags(message, SOUP_MESSAGE_NO_REDIRECT)
        let run: ReadyRun = { [self] result in
            var error: UnsafeMutablePointer<GError>?
            let opened = soup_session_send_finish(session, result, &error)
            if let error { g_error_free(error) }
            let status = soup_message_get_status(message).rawValue
            if let opened, Self.redirectStatuses.contains(UInt32(status)) {
                // The redirect's own body is dropped unread.
                g_object_unref(UnsafeMutableRawPointer(opened))
                return followRedirect()
            }
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

    /// Sends a new request to the Location of `message`'s redirect response, unless the load has
    /// followed too many, or the new address is not http or https, or lowers https to http.
    private func followRedirect() {
        guard redirects < Self.maximumRedirects else {
            return stop("it was redirected more than \(Self.maximumRedirects) times", callInFlight: false)
        }
        // The header as GLib holds it, so a Location that is not UTF-8 is resolved as sent.
        guard let location = soup_message_headers_get_one(soup_message_get_response_headers(message), "Location") else {
            return finish(nil)
        }
        // G_URI_FLAGS_ENCODED (1 << 3): escapes in the Location are kept as they are, for libsoup to read.
        var error: UnsafeMutablePointer<GError>?
        let resolved = takeGString(g_uri_resolve_relative(current, location, GUriFlags(rawValue: 1 << 3), &error))
        if let error { g_error_free(error) }
        guard let next = resolved else { return finish(nil) }
        let scheme = swiftString(g_uri_peek_scheme(next))
        guard scheme == "http" || scheme == "https" else {
            return stop("a redirect would take it to a \(scheme ?? "malformed") address", callInFlight: false)
        }
        if URLLoader.isDowngrade(from: swiftString(g_uri_peek_scheme(url)), to: scheme) {
            return stop("a redirect would take it from https to plain http", callInFlight: false)
        }
        guard let nextMessage = soup_message_new("GET", next) else { return finish(nil) }
        g_object_unref(UnsafeMutableRawPointer(message))
        message = nextMessage
        current = next
        redirects += 1
        send()
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
            guard body.count + Int(size) <= maximumSize else {
                stop("it is larger than \(maximumSize) bytes", callInFlight: false)
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
        completion(LoadedBytes(adopting: bytes, url: current))
    }
}
