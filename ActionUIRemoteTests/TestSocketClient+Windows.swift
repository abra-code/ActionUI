// ActionUIRemoteTests/TestSocketClient+Windows.swift
//
// TestSocketClient on Windows: a blocking named-pipe client with a receive timeout, with the same
// interface as the Unix-socket one (TestSocketClient.swift), so the server tests drive either. It
// opens the pipe as a careful client does: identification only, so the server may read who it is
// but not act as it. The security tests choose other levels.

#if os(Windows)

import Foundation
import WinSDK
@testable import ActionUIRemote

/// How much of the client's identity the server may use (SECURITY_SQOS_PRESENT and a level).
enum PipeClientIdentity {
    case identification
    case anonymous

    var flags: DWORD {
        // SECURITY_IDENTIFICATION and SECURITY_ANONYMOUS are macros Swift does not import: the level
        // shifted left by 16.
        let level = self == .identification ? SecurityIdentification : SecurityAnonymous
        return DWORD(SECURITY_SQOS_PRESENT) | (DWORD(level.rawValue) << 16)
    }
}

/// Opens `path` as a pipe client, waiting while every instance is busy. The handle, or the error.
func openPipe(_ path: String, access: DWORD = DWORD(GENERIC_READ) | DWORD(GENERIC_WRITE),
              identity: PipeClientIdentity = .identification) -> (HANDLE?, DWORD) {
    for _ in 0..<20 {
        let handle = path.withCString(encodedAs: UTF16.self) {
            CreateFileW($0, access, 0, nil, DWORD(OPEN_EXISTING), DWORD(FILE_FLAG_OVERLAPPED) | identity.flags, nil)
        }
        if let handle, handle != INVALID_HANDLE_VALUE {
            return (handle, 0)
        }
        let code = GetLastError()
        guard code == DWORD(ERROR_PIPE_BUSY) else { return (nil, code) }
        _ = path.withCString(encodedAs: UTF16.self) { WaitNamedPipeW($0, 500) }
    }
    return (nil, DWORD(ERROR_PIPE_BUSY))
}

final class TestSocketClient: @unchecked Sendable {
    let handle: HANDLE
    private let timeout: DWORD
    private let overlapped: UnsafeMutablePointer<OVERLAPPED>
    private var pending: [UInt8] = []

    init(path: String, timeoutSeconds: Int = 5, identity: PipeClientIdentity = .identification) throws {
        let (opened, code) = openPipe(path, identity: identity)
        guard let opened else {
            throw NamedPipeServerError.systemCall("CreateFileW(\(path))", code: code)
        }
        handle = opened
        timeout = DWORD(timeoutSeconds * 1000)
        overlapped = UnsafeMutablePointer<OVERLAPPED>.allocate(capacity: 1)
        overlapped.initialize(to: OVERLAPPED())
        overlapped.pointee.hEvent = CreateEventW(nil, true, false, nil)
    }

    deinit {
        CloseHandle(handle)
        CloseHandle(overlapped.pointee.hEvent)
        overlapped.deallocate()
    }

    /// Runs one overlapped read or write and waits up to the timeout. The bytes moved, or nil when
    /// it failed or timed out (`brokenPipe` tells which).
    private func transfer(_ start: (UnsafeMutablePointer<OVERLAPPED>) -> Bool) -> (count: Int?, brokenPipe: Bool) {
        let event = overlapped.pointee.hEvent
        overlapped.pointee = OVERLAPPED()
        overlapped.pointee.hEvent = event
        if !start(overlapped) {
            let code = GetLastError()
            guard code == DWORD(ERROR_IO_PENDING) else {
                return (nil, code == DWORD(ERROR_BROKEN_PIPE) || code == DWORD(ERROR_NO_DATA))
            }
        }
        if WaitForSingleObject(event, timeout) != WAIT_OBJECT_0 {
            CancelIoEx(handle, overlapped)
        }
        var count: DWORD = 0
        if GetOverlappedResult(handle, overlapped, &count, true) {
            return (Int(count), false)
        }
        let code = GetLastError()
        return (nil, code == DWORD(ERROR_BROKEN_PIPE) || code == DWORD(ERROR_NO_DATA))
    }

    func write(_ text: String) {
        var data = Array(text.utf8)
        var offset = 0
        while offset < data.count {
            let moved = data.withUnsafeMutableBytes { buffer in
                transfer { WriteFile(handle, buffer.baseAddress!.advanced(by: offset), DWORD(buffer.count - offset), nil, $0) }
            }
            guard let count = moved.count, count > 0 else { return }
            offset += count
        }
    }

    /// Reads more bytes into `pending`. False at the end of the stream or on a timeout.
    private func fill() -> (more: Bool, brokenPipe: Bool) {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let moved = chunk.withUnsafeMutableBytes { buffer in
            transfer { ReadFile(handle, buffer.baseAddress, DWORD(buffer.count), nil, $0) }
        }
        guard let count = moved.count, count > 0 else { return (false, moved.brokenPipe) }
        pending += chunk[..<count]
        return (true, false)
    }

    /// Read until a newline (returned without it) or the end of the stream (returns nil).
    func readLine() -> String? {
        while true {
            if let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let line = String(decoding: pending[..<newline], as: UTF8.self)
                pending.removeSubrange(...newline)
                return line
            }
            guard fill().more else {
                return pending.isEmpty ? nil : String(decoding: pending, as: UTF8.self)
            }
        }
    }

    /// True once the server has closed its end within the receive timeout.
    func waitForEOF() -> Bool {
        while true {
            let result = fill()
            if !result.more {
                return result.brokenPipe
            }
        }
    }
}

/// A pipe name for one test's server.
func makeTestEndpoint(_ stem: String) -> String {
    return "\(NamedPipeServer.localPrefix)\(stem)-\(GetCurrentProcessId())-\(UInt32.random(in: 0...UInt32.max))"
}

/// Nothing to remove: a pipe goes with its last handle.
func removeTestEndpoint(_ path: String) {
}

/// An absolute path to nothing, and one to something other than a regular file (a folder).
let absentAbsolutePath = "C:\\nonexistent\\modal.json"
let notARegularFilePath = "C:\\Windows"

#endif
