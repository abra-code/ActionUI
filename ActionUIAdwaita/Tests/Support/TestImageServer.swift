// Tests/Support/TestImageServer.swift
/*
 Test images for the URL loading tests: PNG bytes and files of a given size, and an http server on
 the loopback address (libsoup's SoupServer, on the main loop) that serves the PNG at
 /image.png, text at /text.txt, and 404 for anything else. It counts the requests it answers.
*/

import XCTest
import CAdwaita
import CSoup
@testable import ActionUI

@MainActor
enum TestImages {
    /// A red PNG of this size, as bytes.
    static func png(width: Int32, height: Int32) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: Int(width * height * 4))
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = 255
            pixels[index + 3] = 255
        }
        let bytes = g_bytes_new(pixels, gsize(pixels.count))!
        defer { g_bytes_unref(bytes) }
        let texture = gdk_memory_texture_new(width, height, GDK_MEMORY_R8G8B8A8, bytes, gsize(width * 4))!
        defer { g_object_unref(UnsafeMutableRawPointer(texture)) }
        let png = gdk_texture_save_to_png_bytes(texture)!
        defer { g_bytes_unref(png) }
        var size: gsize = 0
        let data = g_bytes_get_data(png, &size)!
        return Array(UnsafeRawBufferPointer(start: data, count: Int(size)))
    }

    /// Writes `bytes` to a new file in the temporary folder; returns its path.
    static func file(_ bytes: [UInt8], name: String) throws -> String {
        let path = NSTemporaryDirectory() + "actionui-\(ProcessInfo.processInfo.processIdentifier)-\(name)"
        try Data(bytes).write(to: URL(fileURLWithPath: path))
        return path
    }

    /// The file URL of a path.
    static func fileURL(_ path: String) -> String {
        URL(fileURLWithPath: path).absoluteString
    }
}

/// What the server serves; read by its C handler, on the main thread.
nonisolated(unsafe) private var servedPNG: [UInt8] = []
nonisolated(unsafe) private var servedRequests = 0

private let handleRequest: @convention(c) (UnsafeMutablePointer<SoupServer>?, OpaquePointer?, UnsafePointer<CChar>?, OpaquePointer?, gpointer?) -> Void = { _, message, path, _, _ in
    guard let message else { return }
    servedRequests += 1
    switch path.map({ String(cString: $0) }) {
    case "/image.png":
        soup_server_message_set_status(message, 200, nil)
        servedPNG.withUnsafeBufferPointer { buffer in
            soup_server_message_set_response(message, "image/png", SOUP_MEMORY_COPY, buffer.baseAddress, gsize(buffer.count))
        }
    case "/text.txt":
        soup_server_message_set_status(message, 200, nil)
        soup_server_message_set_response(message, "text/plain", SOUP_MEMORY_COPY, "not an image", 12)
    default:
        soup_server_message_set_status(message, 404, nil)
    }
}

@MainActor
final class TestImageServer {
    private let server: UnsafeMutablePointer<SoupServer>
    /// The server's address, "http://127.0.0.1:<port>", without a trailing slash.
    let base: String

    init(png: [UInt8]) throws {
        servedPNG = png
        servedRequests = 0
        server = typed(OpaquePointer(g_object_new_with_properties(soup_server_get_type(), 0, nil, nil)!))
        soup_server_add_handler(server, nil, handleRequest, nil, nil)
        var error: UnsafeMutablePointer<GError>?
        guard soup_server_listen_local(server, 0, SOUP_SERVER_LISTEN_IPV4_ONLY, &error) != 0 else {
            let message = error.map { String(cString: $0.pointee.message) } ?? "unknown error"
            if let error { g_error_free(error) }
            g_object_unref(UnsafeMutableRawPointer(server))
            throw XCTSkip("no loopback http server: \(message)")
        }
        let uris = soup_server_get_uris(server)
        defer { g_slist_free_full(uris) { g_uri_unref(OpaquePointer($0)) } }
        let first = OpaquePointer(uris!.pointee.data!)
        let text = takeGString(g_uri_to_string(first)) ?? ""
        base = text.hasSuffix("/") ? String(text.dropLast()) : text
    }

    /// The requests answered since the server started.
    var requests: Int { servedRequests }

    func stop() {
        soup_server_disconnect(server)
        g_object_unref(UnsafeMutableRawPointer(server))
    }
}
