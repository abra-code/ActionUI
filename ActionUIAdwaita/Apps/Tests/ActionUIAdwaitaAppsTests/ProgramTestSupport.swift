// ActionUIAdwaita/Apps/Tests/ActionUIAdwaitaAppsTests/ProgramTestSupport.swift
/*
 What the program tests share: a program built next to the test program, the repository, a skip when
 there is no display, solid PNG files for image documents, and an http server for a document.
*/

import XCTest
import CAdwaita
import Foundation
import Glibc

@MainActor
enum ProgramTestSupport {
    private static var hasDisplay: Bool?

    /// Throws XCTSkip when GTK cannot open a display: the programs cannot show a window then.
    static func requireDisplay() throws {
        if hasDisplay == nil {
            hasDisplay = gtk_init_check() != 0
        }
        if hasDisplay != true {
            throw XCTSkip("GTK could not open a display; the program tests run in the desktop session")
        }
    }

    /// A program of this package, built next to the test program.
    static func program(_ name: String) -> URL {
        URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent(name)
    }

    /// The repository, found from this file.
    static var repository: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    /// Runs `program` with `arguments` for at most 30 s; its exit status, or nil when it had to be stopped.
    static func run(_ program: URL, _ arguments: [String]) throws -> Int32? {
        let process = Process()
        process.executableURL = program
        process.arguments = arguments
        try process.run()
        let deadline = Date().addingTimeInterval(30)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard !process.isRunning else {
            process.terminate()
            return nil
        }
        return process.terminationStatus
    }

    /// Saves a 64 x 64 PNG file of one color at `path`.
    static func writeSolidPNG(red: UInt8, green: UInt8, blue: UInt8, to path: String) throws {
        var pixels = [UInt8]()
        for _ in 0..<(64 * 64) {
            pixels += [red, green, blue, 255]
        }
        let bytes = g_bytes_new(pixels, gsize(pixels.count))!
        defer { g_bytes_unref(bytes) }
        let texture = gdk_memory_texture_new(64, 64, GDK_MEMORY_R8G8B8A8, bytes, 64 * 4)!
        defer { g_object_unref(UnsafeMutableRawPointer(texture)) }
        XCTAssertNotEqual(gdk_texture_save_to_png(texture, path), 0, "could not save \(path)")
    }
}

/// An http server on the loopback address, on a thread of its own: /view.json answers with the document, anything
/// else with 404.
final class TestDocumentServer {
    private let listener: Int32
    private let finished = DispatchSemaphore(value: 0)
    /// The server's address, "http://127.0.0.1:<port>", without a trailing slash.
    let base: String

    init(document: String) throws {
        let listener = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        guard listener >= 0 else {
            throw XCTSkip("no loopback http server: errno \(errno)")
        }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = in_addr_t(0x7f00_0001).bigEndian
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                bind(listener, generic, size) == 0 && getsockname(listener, generic, &size) == 0
            }
        }
        guard bound, listen(listener, 8) == 0 else {
            let failure = errno
            close(listener)
            throw XCTSkip("no loopback http server: errno \(failure)")
        }
        self.listener = listener
        base = "http://127.0.0.1:\(UInt16(bigEndian: address.sin_port))"
        let finished = finished
        Thread.detachNewThread {
            defer { finished.signal() }
            while true {
                // stop() ends the wait with an error.
                let connection = accept(listener, nil, nil)
                guard connection >= 0 else { return }
                Self.answer(connection, document: document)
                close(connection)
            }
        }
    }

    /// Reads the request, which can arrive in pieces, to the end of its headers and writes the answer. Closing with
    /// bytes unread would reset the connection, which can lose the answer.
    private static func answer(_ connection: Int32, document: String) {
        var request = ""
        var bytes = [UInt8](repeating: 0, count: 4096)
        while !request.contains("\r\n\r\n") {
            let count = read(connection, &bytes, bytes.count)
            guard count > 0 else { return }
            request += String(decoding: bytes[0..<count], as: UTF8.self)
        }
        let target = request.split(separator: " ").dropFirst().first
        let body = target == "/view.json" ? document : ""
        let status = target == "/view.json" ? "200 OK" : "404 Not Found"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n"
            + "Connection: close\r\n\r\n\(body)"
        let answer = Array(response.utf8)
        var sent = 0
        while sent < answer.count {
            let written = answer[sent...].withUnsafeBytes { send(connection, $0.baseAddress, $0.count, Int32(MSG_NOSIGNAL)) }
            guard written > 0 else { return }
            sent += written
        }
    }

    /// Ends the thread, and only then closes the listener: closed earlier, its number can go to a new socket, and a
    /// thread on its way to accept() would take that socket's connections.
    func stop() {
        shutdown(listener, Int32(SHUT_RDWR))
        finished.wait()
        close(listener)
    }
}
