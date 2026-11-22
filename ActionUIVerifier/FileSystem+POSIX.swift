// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// FileSystem+POSIX.swift - the file system questions SchemaSet asks, on macOS and Linux.
// FileSystem+Windows.swift answers them on Windows.

#if !os(Windows)

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

enum FileSystem {
    /// True for a folder or a link to one.
    static func isDirectory(_ path: String) -> Bool {
        var information = stat()
        return stat(path, &information) == 0 && information.st_mode & S_IFMT == S_IFDIR
    }

    /// The running program's file, nil when the system does not say. Read from Linux's
    /// /proc/self/exe; nil on macOS, which finds the schemas in the library's resource bundle.
    static var programPath: String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let count = readlink("/proc/self/exe", &buffer, buffer.count)
        guard count > 0, count < buffer.count else { return nil }
        return String(decoding: buffer[..<count].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

#endif
