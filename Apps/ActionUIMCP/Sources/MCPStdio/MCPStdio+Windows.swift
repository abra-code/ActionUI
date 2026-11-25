// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// MCPStdio+Windows.swift - MCPStdio.swift's system parts on Windows, which has no pthreads and no POSIX
// descriptors of its own (the Microsoft C runtime gives _read, _write, _dup and _dup2): the lock, the
// protocol channel off stdout, and the read of stdin. stdin and the protocol channel are binary, so the C
// runtime never turns a "\n" into "\r\n" or stops at a Ctrl+Z byte.

#if os(Windows)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import ucrt
import WinSDK

// MARK: - Lock

/// A mutual-exclusion lock over a slim reader/writer lock, used exclusively; not reentrant. The SRWLOCK
/// lives in allocated memory: it may not move once in use, and Swift may move a stored value.
public final class MCPLock: @unchecked Sendable {
    private let srwLock: UnsafeMutablePointer<SRWLOCK>

    public init() {
        srwLock = UnsafeMutablePointer<SRWLOCK>.allocate(capacity: 1)
        srwLock.initialize(to: SRWLOCK())
        InitializeSRWLock(srwLock)
    }

    deinit {
        // An SRWLOCK holds no resources: nothing to destroy.
        srwLock.deallocate()
    }

    public func lock() {
        AcquireSRWLockExclusive(srwLock)
    }

    public func unlock() {
        ReleaseSRWLockExclusive(srwLock)
    }

    public func withLock<Value>(_ body: () throws -> Value) rethrows -> Value {
        lock()
        defer { unlock() }
        return try body()
    }
}

// MARK: - The protocol channel

extension MCPServer {
    /// The C runtime's descriptors for stdin, stdout and stderr.
    private static let standardInput: Int32 = 0
    private static let standardOutput: Int32 = 1
    private static let standardError: Int32 = 2

    /// The last C runtime error number.
    private static var lastError: Int32 {
        var code: Int32 = 0
        _ = _get_errno(&code)
        return code
    }

    /// Moves the protocol channel off descriptor 1 so nothing else in the process can corrupt it, as on
    /// macOS and Linux: descriptor 1 is duplicated to a private descriptor that only the returned writer
    /// uses, then pointed at stderr, so a stray print from any library lands in the log instead of in the
    /// middle of a JSON-RPC message. The duplicate is not inherited by a child. Windows has no SIGPIPE: a
    /// write to a client that has gone fails, and is dropped. Call once, before anything can print.
    public static func reserveStandardOutput() -> @Sendable (Data) -> Void {
        fflush(nil)
        _ = _setmode(standardInput, _O_BINARY)
        _ = _setmode(standardOutput, _O_BINARY)
        let protocolFD = _dup(standardOutput)
        guard protocolFD >= 0 else {
            writeAll(Data("MCPServer: _dup(stdout) failed (errno \(lastError)); writing to stdout directly\n".utf8), to: standardError)
            return { data in writeAll(data, to: standardOutput) }
        }
        _ = _setmode(protocolFD, _O_BINARY)
        // _dup's handle is inheritable (the C runtime duplicates with bInheritHandle TRUE), so a child started
        // with inherited handles (CreateProcess with bInheritHandles TRUE and no handle list) would hold the
        // client's pipe open after this process ends. The flag goes, as FD_CLOEXEC does on macOS and Linux.
        _ = SetHandleInformation(UnsafeMutableRawPointer(bitPattern: _get_osfhandle(protocolFD)), DWORD(HANDLE_FLAG_INHERIT), 0)
        if _dup2(standardError, standardOutput) < 0 {
            writeAll(Data("MCPServer: _dup2(stderr, stdout) failed (errno \(lastError)); stray output may corrupt the protocol\n".utf8),
                     to: standardError)
        } else {
            // The C runtime updates the process's standard output handle itself only in a console program:
            // a GUI one would keep naming the handle _dup2 just closed, for a child or GetStdHandle to use.
            // STD_OUTPUT_HANDLE, (DWORD)-11: a cast macro Swift does not import.
            _ = SetStdHandle(DWORD(0xFFFF_FFF5), UnsafeMutableRawPointer(bitPattern: _get_osfhandle(standardOutput)))
        }
        return { data in writeAll(data, to: protocolFD) }
    }

    private static func writeAll(_ data: Data, to fd: Int32) {
        data.withUnsafeBytes { raw in
            guard var pointer = raw.baseAddress else { return }
            var remaining = raw.count
            while remaining > 0 {
                let written = Int(_write(fd, pointer, UInt32(min(remaining, Int(Int32.max)))))
                if written <= 0 {
                    return  // the client is gone; nothing useful to do
                }
                pointer += written
                remaining -= written
            }
        }
    }

    /// Up to `chunk.count` bytes of `descriptor` into `chunk`: 0 at its end, -1 on failure.
    static func readChunk(_ descriptor: Int32, _ chunk: inout [UInt8]) -> Int {
        let count = UInt32(min(chunk.count, Int(Int32.max)))
        return Int(_read(descriptor, &chunk, count))
    }
}

#endif
