// ActionUIRemoteTests/TestSocketClient.swift
//
// A blocking Unix-socket client with a receive timeout, for driving the server from tests.
// Deliberately primitive: raw BSD calls, one byte at a time on read, so the tests depend on
// nothing but the wire format.

#if os(macOS)

import Foundation
import Darwin
@testable import ActionUIRemote

final class TestSocketClient: @unchecked Sendable {
    let fd: Int32

    init(path: String, timeoutSeconds: Int = 5) throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocketServerError.systemCall("socket", errno: errno) }
        var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutablePointer(to: &address.sun_path) { sunPath in
            sunPath.withMemoryRebound(to: CChar.self, capacity: capacity) { buffer in
                _ = path.withCString { strncpy(buffer, $0, capacity) }
                buffer[capacity - 1] = 0
            }
        }
        let result: Int32 = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            close(fd)
            throw UnixSocketServerError.systemCall("connect", errno: code)
        }
    }

    deinit {
        close(fd)
    }

    func write(_ text: String) {
        var data = Array(text.utf8)
        var offset = 0
        while offset < data.count {
            let n = data.withUnsafeMutableBytes { buffer -> Int in
                Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
            }
            if n <= 0 { return }
            offset += n
        }
    }

    /// Shut the write side down, as `nc` does when its stdin ends. The read side stays open.
    func halfClose() {
        shutdown(fd, SHUT_WR)
    }

    /// Read until a newline (returned without it) or EOF (returns nil).
    func readLine() -> String? {
        var bytes: [UInt8] = []
        var byte: UInt8 = 0
        while true {
            let n = Darwin.read(fd, &byte, 1)
            if n <= 0 { return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self) }
            if byte == UInt8(ascii: "\n") { return String(decoding: bytes, as: UTF8.self) }
            bytes.append(byte)
        }
    }

    /// True once the peer has closed (read returns 0) within the receive timeout.
    func waitForEOF() -> Bool {
        var byte: UInt8 = 0
        while true {
            let n = Darwin.read(fd, &byte, 1)
            if n == 0 { return true }
            if n < 0 { return false }
        }
    }
}

#endif
