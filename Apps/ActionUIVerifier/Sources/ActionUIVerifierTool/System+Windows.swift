// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// System+Windows.swift - what actionui-verify asks of the system, on Windows: writing to a
// descriptor, and what a path names. System+POSIX.swift does the same on macOS and Linux.

#if os(Windows)

import FoundationEssentials
import ucrt
import WinSDK

/// The C runtime's descriptors for standard output and error, under the POSIX names its headers
/// do not have.
let STDOUT_FILENO: Int32 = 1
let STDERR_FILENO: Int32 = 2

/// Writes what it can of `bytes` to `descriptor`: the count written, below 1 when nothing was.
/// The C runtime's write: standard output and error are in text mode, so "\n" goes out as "\r\n",
/// as the Python verifier's print does on Windows.
func writeSome(_ bytes: UnsafeRawBufferPointer, to descriptor: Int32) -> Int {
    Int(_write(descriptor, bytes.baseAddress, UInt32(bytes.count)))
}

/// The C runtime's text for an errno value (strerror_s: its strerror is deprecated).
func errorText(_ code: Int32) -> String {
    var buffer = [CChar](repeating: 0, count: 256)
    guard strerror_s(&buffer, buffer.count, code) == 0 else { return "error \(code)" }
    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

/// A path argument with "/" between its components: a backslash is taken as "/".
func slashSeparated(_ path: String) -> String {
    path.replacing("\\", with: "/")
}

/// True for a folder or a link to one.
func isDirectory(_ path: String) -> Bool {
    // FoundationEssentials takes a Bool here, not an ObjCBool (which it does not have).
    var directory = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &directory) && directory
}

/// A folder itself, not a link or junction to one.
func isFolderNotLink(_ path: String) -> Bool {
    let attributes = path.withCString(encodedAs: UTF16.self) { GetFileAttributesW($0) }
    return attributes != INVALID_FILE_ATTRIBUTES && attributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) != 0
        && attributes & DWORD(FILE_ATTRIBUTE_REPARSE_POINT) == 0
}

/// True for a file, as pathlib's is_file. Windows has no FIFOs or sockets among a folder's files;
/// a device name (NUL, CON) is not a file.
func isRegularFile(_ path: String) -> Bool {
    var directory = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &directory), !directory else { return false }
    let attributes = path.withCString(encodedAs: UTF16.self) { GetFileAttributesW($0) }
    return attributes != INVALID_FILE_ATTRIBUTES && attributes & DWORD(FILE_ATTRIBUTE_DEVICE) == 0
}

#endif
