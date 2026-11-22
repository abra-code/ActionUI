// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// System+POSIX.swift - what actionui-verify asks of the system, on macOS and Linux: writing to a
// descriptor, and what a path names. System+Windows.swift does the same on Windows.

#if !os(Windows)

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Writes what it can of `bytes` to `descriptor`: the count written, below 1 when nothing was.
func writeSome(_ bytes: UnsafeRawBufferPointer, to descriptor: Int32) -> Int {
    while true {
        let written = write(descriptor, bytes.baseAddress, bytes.count)
        if written < 0 && errno == EINTR { continue }
        return written
    }
}

/// The C library's text for an errno value.
func errorText(_ code: Int32) -> String {
    String(cString: strerror(code))
}

/// A path argument with "/" between its components (as given here).
func slashSeparated(_ path: String) -> String {
    path
}

/// True for a folder or a link to one.
func isDirectory(_ path: String) -> Bool {
    var info = stat()
    return stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
}

/// A folder itself, not a link to one (lstat's answer).
func isFolderNotLink(_ path: String) -> Bool {
    var info = stat()
    return lstat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
}

/// True for a regular file or a symbolic link to one, as pathlib's is_file: a device, a FIFO or
/// a socket is not a file to validate.
func isRegularFile(_ path: String) -> Bool {
    var info = stat()
    return stat(path, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
}

#endif
