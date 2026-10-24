// Sources/Runtime/URLLoader.swift
/*
 Loads the bytes a URL names without blocking the GLib main loop: http and https with libsoup 3
 (one shared session), file URLs with GIO, data URLs (base64 or percent-encoded) with libsoup's
 decoder. The completion runs on the main thread, always after fetch returns, with the bytes, or
 nil for a URL that names nothing loadable: another scheme, a malformed URL, an http status outside
 200-299, a read or network error. https needs glib-networking, which GNOME desktops install. No
 FoundationNetworking: it needs full Foundation and libcurl on Linux.
*/

import CAdwaita
import CSoup

/// Bytes GLib owns (a GBytes), released with the last Swift reference. GBytes is immutable and its
/// reference count atomic, so the bytes can be read on another thread (decoding an image).
final class LoadedBytes: @unchecked Sendable {
    let bytes: OpaquePointer

    init(adopting bytes: OpaquePointer) {
        self.bytes = bytes
    }

    deinit {
        g_bytes_unref(bytes)
    }
}

/// An asynchronous call's completion: runs with the call's GAsyncResult.
private typealias ReadyRun = @MainActor (OpaquePointer?) -> Void

/// GIO's ready callback for one call: runs the box's closure once, then releases the box.
private let readyTrampoline: @convention(c) (UnsafeMutablePointer<GObject>?, OpaquePointer?, gpointer?) -> Void = { _, result, data in
    guard let data else { return }
    let box = Unmanaged<CallbackBox<ReadyRun>>.fromOpaque(data).takeRetainedValue()
    // A pointer is not Sendable; its address is. GIO calls back on the main thread.
    let address = result.map { Int(bitPattern: UnsafeRawPointer($0)) }
    MainActor.assumeIsolated { box.run(address.flatMap { OpaquePointer(bitPattern: $0) }) }
}

@MainActor
enum URLLoader {
    /// How long one step of an http request (connecting, a read, a write) may wait before the
    /// request fails, in seconds; a server that keeps sending slowly can take longer in all.
    static let timeout: guint = 30

    private static var session: UnsafeMutablePointer<SoupSession>?

    /// Loads `url`'s bytes and passes them to `completion`, or nil (see the header).
    static func fetch(_ url: String, _ completion: @escaping @MainActor (LoadedBytes?) -> Void) {
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

    private static func sharedSession() -> UnsafeMutablePointer<SoupSession> {
        if let session { return session }
        let made = soup_session_new()!
        soup_session_set_timeout(made, timeout)
        session = made
        return made
    }

    private static func fetchHTTP(_ url: String, _ completion: @escaping @MainActor (LoadedBytes?) -> Void) {
        guard let message = soup_message_new("GET", url) else {
            _ = runAfter(milliseconds: 0) { completion(nil) }
            return
        }
        let session = sharedSession()
        let run: ReadyRun = { result in
            var error: UnsafeMutablePointer<GError>?
            let bytes = soup_session_send_and_read_finish(session, result, &error)
            let status = soup_message_get_status(message).rawValue
            g_object_unref(UnsafeMutableRawPointer(message))
            if let error { g_error_free(error) }
            guard let bytes else { return completion(nil) }
            let loaded = LoadedBytes(adopting: bytes)
            completion((200...299).contains(status) ? loaded : nil)
        }
        let data = Unmanaged.passRetained(CallbackBox(run)).toOpaque()
        soup_session_send_and_read_async(session, message, G_PRIORITY_DEFAULT, nil, readyTrampoline, data)
    }

    private static func fetchFile(_ url: String, _ completion: @escaping @MainActor (LoadedBytes?) -> Void) {
        let file = g_file_new_for_uri(url)!
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
