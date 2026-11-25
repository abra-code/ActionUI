// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// HostSupport+Windows.swift - HostSupport's system parts on Windows: the log on stderr, the private
// session folder, the program's path, folder checks, the resource folders and the local day.

#if os(Windows)

import FoundationEssentials
import ucrt
import WinSDK
import ActionUI

extension HostSupport {
    // MARK: Log

    /// Writes `text` and a newline to stderr, the server's log: stdout belongs to the protocol.
    static func logLine(_ text: String) {
        let bytes = Array((text + "\n").utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { Int(_write(2, $0.baseAddress, UInt32($0.count))) }
            if written <= 0 { return }
            offset += written
        }
    }

    // MARK: Paths

    /// Whether `path` names a file from a drive's root, as every path the server takes must: a drive letter,
    /// a colon and a slash (`C:\a.json`, or `C:/a.json`). Not a network path (`\\server\share\...` or
    /// `//server/...`, whose open would send the user's sign-in to that server), a `\\.\` or `\\?\` path
    /// (devices and pipes), a path from the current drive's root (`\a.json`) or one relative to a drive's
    /// current folder (`C:a.json`).
    static func isAbsolutePath(_ path: String) -> Bool {
        let units = Array(path.utf16.prefix(3))
        guard units.count == 3 else { return false }
        let letter = units[0]
        let isLetter = (letter >= 0x41 && letter <= 0x5A) || (letter >= 0x61 && letter <= 0x7A)
        return isLetter && units[1] == 0x3A && (units[2] == 0x5C || units[2] == 0x2F)
    }

    /// The folder for this session's staged JSON files and screenshots, removed when the session ends
    /// (`removeSessionFolder`). In the user's temporary folder, under a name nobody can guess and take
    /// first, made in one call that fails if anything has the name, with an access list that lets only
    /// this user in, inherited by what is made inside: a staged JSON file another process replaced would
    /// load past the ActionUI JSON checks, and a screenshot shows what the user has on screen. If no folder
    /// can be made (logged), the name is still unguessable, but the later writes make it with the temporary
    /// folder's own rights (the user's, SYSTEM's and the Administrators group's).
    static let sessionFolder: URL = {
        let base = FileManager.default.temporaryDirectory
        var attempted = base
        for _ in 0..<3 {
            let random = UInt64.random(in: .min ... .max)
            let name = "actionui-mcp-\(GetCurrentProcessId())-" + String(random, radix: 16)
            attempted = base.appendingPathComponent(name, isDirectory: true)
            if makePrivateFolder(attempted.path) {
                return attempted
            }
        }
        logLine("actionui-mcp: the session folder could not be made in \(base.path) (Windows error \(GetLastError()))")
        return attempted
    }()

    /// Makes the folder `path`, failing if anything is there, with an access list that grants only this
    /// process's user (protected, inherited by files and folders inside).
    private static func makePrivateFolder(_ path: String) -> Bool {
        guard let user = currentUserSIDText() else { return false }
        let sddl = "O:\(user)D:P(A;OICI;FA;;;\(user))"
        var descriptor: PSECURITY_DESCRIPTOR? = nil
        guard sddl.withCString(encodedAs: UTF16.self, {
            ConvertStringSecurityDescriptorToSecurityDescriptorW($0, DWORD(SDDL_REVISION_1), &descriptor, nil)
        }), let descriptor else { return false }
        defer { LocalFree(descriptor) }
        var attributes = SECURITY_ATTRIBUTES(nLength: DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size),
                                             lpSecurityDescriptor: descriptor, bInheritHandle: false)
        return path.withCString(encodedAs: UTF16.self) { CreateDirectoryW($0, &attributes) }
    }

    /// This process's user SID as text (S-1-5-21-...), or nil.
    private static func currentUserSIDText() -> String? {
        var token: HANDLE? = nil
        guard OpenProcessToken(GetCurrentProcess(), DWORD(TOKEN_QUERY), &token), let token else { return nil }
        defer { CloseHandle(token) }
        var size: DWORD = 0
        _ = GetTokenInformation(token, TokenUser, nil, 0, &size)
        guard size > 0 else { return nil }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { buffer.deallocate() }
        guard GetTokenInformation(token, TokenUser, buffer, size, &size) else { return nil }
        var text: LPWSTR? = nil
        guard ConvertSidToStringSidW(buffer.assumingMemoryBound(to: TOKEN_USER.self).pointee.User.Sid, &text), let text else {
            return nil
        }
        defer { LocalFree(text) }
        return String(decodingCString: text, as: UTF16.self)
    }

    /// The running program's path.
    static var executablePath: String? {
        var buffer = [WCHAR](repeating: 0, count: 32_768)
        let count = Int(GetModuleFileNameW(nil, &buffer, DWORD(buffer.count)))
        guard count > 0, count < buffer.count else { return nil }
        return String(decoding: buffer[..<count], as: UTF16.self)
    }

    /// Whether a folder is at `path`, following links; nil when nothing is there.
    static func isFolder(atPath path: String) -> Bool? {
        guard !path.utf8.contains(0) else { return nil }
        let attributes = path.withCString(encodedAs: UTF16.self) { GetFileAttributesW($0) }
        guard attributes != INVALID_FILE_ATTRIBUTES else { return nil }
        return attributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) != 0
    }

    /// The folder holding the resources of `name`, a resource bundle SwiftPM built: a plain folder next to
    /// the executable (.bundle, or .resources from the older build system), as on Linux. nil when there is
    /// none.
    static func resourceFolder(ofBundle name: String) -> URL? {
        let executableFolder = executablePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
        return [".bundle", ".resources"].lazy
            .compactMap { executableFolder?.appendingPathComponent(name + $0) }
            .first { isFolder(atPath: $0.path) == true }
    }

    // MARK: Numbers

    /// The user's decimal and grouping separators (Region settings), as GetLocaleInfoEx gives them: the C
    /// library stays in the "C" locale on Windows, where nothing sets it from the user's settings.
    static func userNumberSeparators() -> (decimal: Character, grouping: Character?) {
        func info(_ type: LCTYPE) -> Character? {
            var buffer = [WCHAR](repeating: 0, count: 8)
            let count = GetLocaleInfoEx(nil, type, &buffer, Int32(buffer.count))
            guard count > 1 else { return nil }
            return String(decoding: buffer[..<Int(count - 1)], as: UTF16.self).first
        }
        return (info(LCTYPE(LOCALE_SDECIMAL)) ?? ".", info(LCTYPE(LOCALE_STHOUSAND)))
    }

    // MARK: Dates

    /// The calendar day `date` falls on in the user's time zone, as 2026-11-01 (localtime_s: as on Linux,
    /// FoundationEssentials has no named time zones).
    static func localDay(_ date: Date) -> String {
        var seconds = time_t(date.timeIntervalSince1970.rounded(.down))
        var parts = tm()
        guard localtime_s(&parts, &seconds) == 0 else { return timestamp(date).prefix(10).description }
        return padded(Int(parts.tm_year) + 1900, 4) + "-" + padded(Int(parts.tm_mon) + 1, 2) + "-" + padded(Int(parts.tm_mday), 2)
    }
}

#endif
