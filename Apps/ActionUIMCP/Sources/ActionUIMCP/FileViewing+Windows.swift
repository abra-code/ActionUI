// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// FileViewing+Windows.swift - FileViewing's file reads on Windows: a regular file's size and bytes, never a
// folder, a device or a pipe (whose read would block), checked again on the open handle, as on POSIX.

#if os(Windows)

import FoundationEssentials
import WinSDK

extension FileViewing {
    /// SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION (WinBase.h; the second is a macro Swift does not
    /// import): a named pipe's server that the path reaches ("//./pipe/name" passes the absolute-path check)
    /// may learn who connects through this open but cannot act as this user. Ignored for a file on a disk.
    private static let identificationOnly = DWORD(0x0010_0000) | DWORD(0x0001_0000)

    /// An open handle to `path` for reading, following links, sharing with other readers and writers;
    /// nil when it cannot be opened.
    private static func openForReading(_ path: String) -> HANDLE? {
        guard !path.utf8.contains(0) else { return nil }
        let handle = path.withCString(encodedAs: UTF16.self) {
            CreateFileW($0, DWORD(GENERIC_READ), DWORD(FILE_SHARE_READ) | DWORD(FILE_SHARE_WRITE) | DWORD(FILE_SHARE_DELETE),
                        nil, DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL) | identificationOnly, nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { return nil }
        return handle
    }

    /// The size of `handle`'s file when it is a regular file on a disk (not a folder, device or pipe).
    private static func regularSize(_ handle: HANDLE) -> Int? {
        guard GetFileType(handle) == DWORD(FILE_TYPE_DISK) else { return nil }
        var information = BY_HANDLE_FILE_INFORMATION()
        guard GetFileInformationByHandle(handle, &information),
              information.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) == 0 else { return nil }
        return Int(information.nFileSizeHigh) << 32 | Int(information.nFileSizeLow)
    }

    /// The size of the regular file at `path`, following links; nil for anything else.
    static func regularFileSize(_ path: String) -> Int? {
        guard let handle = openForReading(path) else { return nil }
        defer { CloseHandle(handle) }
        return regularSize(handle)
    }

    /// The bytes of the regular file at `path` when it is at most `limit` bytes long, else nil. The size
    /// checked before may be stale, so this checks the opened file again and stops once it has more than
    /// `limit` bytes.
    static func readBytes(_ path: String, limit: Int) -> [UInt8]? {
        guard let handle = openForReading(path) else { return nil }
        defer { CloseHandle(handle) }
        guard let size = regularSize(handle) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(min(max(size, 0), limit) + 1)
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while bytes.count <= limit {
            var count: DWORD = 0
            let read = chunk.withUnsafeMutableBytes { ReadFile(handle, $0.baseAddress, DWORD($0.count), &count, nil) }
            guard read else { return nil }
            if count == 0 { break }
            bytes.append(contentsOf: chunk[..<Int(count)])
        }
        return bytes.count <= limit ? bytes : nil
    }
}

#endif
