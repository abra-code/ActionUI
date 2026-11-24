// Tests/Support/TestImageServer.swift
/*
 Test images for the URL loading tests: PNG bytes and files of a given size, and an http server on
 the loopback address (libsoup's SoupServer, on the main loop) that serves the PNG at
 /image.png (and after a second at /slow.png), text at /text.txt, a document at /view.json, and 404
 for anything else. It counts
 the requests it answers. Redirects: /redirect-stalled to /image.png (relative) with a body that
 never ends, /loop to itself, /to-file to a file URL, /to-never to /never.json.
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
nonisolated(unsafe) private var servedJSON = ""
nonisolated(unsafe) private var servedRequests = 0
/// The size of the body "/big.bin" serves (zero bytes).
nonisolated(unsafe) var servedBigSize = 0

/// Answers a paused /slow.png request with the PNG, then releases the reference taken for it.
private let answerSlowly: @convention(c) (gpointer?) -> gboolean = { data in
    guard let data else { return 0 }
    let message = OpaquePointer(data)
    soup_server_message_set_status(message, 200, nil)
    servedPNG.withUnsafeBufferPointer { buffer in
        soup_server_message_set_response(message, "image/png", SOUP_MEMORY_COPY, buffer.baseAddress, gsize(buffer.count))
    }
    soup_server_message_unpause(message)
    g_object_unref(data)
    return 0   // G_SOURCE_REMOVE
}

private let handleRequest: @convention(c) (UnsafeMutablePointer<SoupServer>?, OpaquePointer?, UnsafePointer<CChar>?, OpaquePointer?, gpointer?) -> Void = { _, message, path, _, _ in
    guard let message else { return }
    servedRequests += 1
    switch path.map({ String(cString: $0) }) {
    case "/image.png":
        soup_server_message_set_status(message, 200, nil)
        servedPNG.withUnsafeBufferPointer { buffer in
            soup_server_message_set_response(message, "image/png", SOUP_MEMORY_COPY, buffer.baseAddress, gsize(buffer.count))
        }
    case "/slow.png":
        // Answered a second later, on the main loop.
        soup_server_message_pause(message)
        g_timeout_add(1000, answerSlowly, g_object_ref(UnsafeMutableRawPointer(message)))
    case "/text.txt":
        soup_server_message_set_status(message, 200, nil)
        soup_server_message_set_response(message, "text/plain", SOUP_MEMORY_COPY, "not an image", 12)
    case "/view.json":
        soup_server_message_set_status(message, 200, nil)
        let bytes = Array(servedJSON.utf8)
        bytes.withUnsafeBufferPointer { buffer in
            soup_server_message_set_response(message, "application/json", SOUP_MEMORY_COPY, buffer.baseAddress, gsize(buffer.count))
        }
    case "/big.bin":
        soup_server_message_set_status(message, 200, nil)
        let bytes = [UInt8](repeating: 0, count: servedBigSize)
        bytes.withUnsafeBufferPointer { buffer in
            soup_server_message_set_response(message, "application/octet-stream", SOUP_MEMORY_COPY, buffer.baseAddress, gsize(buffer.count))
        }
    case "/redirect-stalled":
        // A redirect whose body never ends: a client that reads it before following waits for good.
        soup_server_message_set_status(message, 302, nil)
        let headers = soup_server_message_get_response_headers(message)
        soup_message_headers_replace(headers, "Location", "/image.png")
        soup_message_headers_set_encoding(headers, SOUP_ENCODING_CHUNKED)
        soup_message_body_append(soup_server_message_get_response_body(message), SOUP_MEMORY_COPY, "partial", 7)
    case "/loop":
        soup_server_message_set_status(message, 302, nil)
        soup_message_headers_replace(soup_server_message_get_response_headers(message), "Location", "/loop")
    case "/to-file":
        soup_server_message_set_status(message, 301, nil)
        soup_message_headers_replace(soup_server_message_get_response_headers(message), "Location", "file:///etc/hostname")
    case "/to-never":
        soup_server_message_set_status(message, 307, nil)
        soup_message_headers_replace(soup_server_message_get_response_headers(message), "Location", "never.json")
    case "/never.json":
        // Never answered: the request waits until the client gives up or the server stops.
        soup_server_message_pause(message)
    default:
        soup_server_message_set_status(message, 404, nil)
    }
}

@MainActor
final class TestImageServer {
    private let server: UnsafeMutablePointer<SoupServer>
    /// The server's address, "http://127.0.0.1:<port>", without a trailing slash.
    let base: String

    init(png: [UInt8], json: String = "") throws {
        servedPNG = png
        servedJSON = json
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
