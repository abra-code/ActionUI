// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// FileSystem+Windows.swift - the file system questions SchemaSet asks, on Windows.
// FileSystem+POSIX.swift answers them on macOS and Linux.

#if os(Windows)

import FoundationEssentials
import WinSDK

enum FileSystem {
    /// True for a folder or a link to one. FileManager rather than the C runtime's stat, as
    /// actionui-verify asks on Windows.
    static func isDirectory(_ path: String) -> Bool {
        // FoundationEssentials takes a Bool here, not an ObjCBool (which it does not have).
        var directory = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory
    }

    /// The running program's file, nil when the system does not say.
    static var programPath: String? {
        // GetModuleFileNameW truncates a longer path and returns the buffer's size: taken as unknown.
        var buffer = [WCHAR](repeating: 0, count: 32_768)
        let count = Int(GetModuleFileNameW(nil, &buffer, DWORD(buffer.count)))
        guard count > 0, count < buffer.count else { return nil }
        return String(decoding: buffer[..<count], as: UTF16.self)
    }
}

#endif
