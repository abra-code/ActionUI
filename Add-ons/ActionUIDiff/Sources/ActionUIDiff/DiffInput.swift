// Add-ons/ActionUIDiff/Sources/ActionUIDiff/DiffInput.swift
//
// How the Diff element reads its properties, on Apple (Diff.swift), Linux (Diff+Adwaita.swift) and Windows
// (Diff+WinUI.swift) alike: each side's text or file, and the two integer settings. No UI, so the rules are
// unit-testable without a view.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import ActionUI
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif os(Windows)
import ucrt
import WinSDK
#endif

extension Diff {

    /// One side's resolved text, or a path the wrapper could not read.
    enum ResolvedInput: Equatable {
        case text(String)
        case unreadable(path: String)
    }

    /// Resolves one side of the diff from its text and file properties.
    /// - text wins over file: if `text` is a string it is used (warning if `file` is also set).
    /// - otherwise `file` is tilde-expanded and read as UTF-8; missing, not a regular file, over
    ///   4 MB, or non-UTF-8 yields `.unreadable`. Only a regular file: a device or a named pipe
    ///   reports a size of 0, passes the cap, and would never finish (or never start) reading on the
    ///   main thread.
    /// - neither given yields `.text("")` (a legitimate empty side: pure addition / removal).
    /// - `readsFile` says whether the content may read the file (the trust policy, as for an
    ///   Image's file); a refused file is `.unreadable`, and the refusal is logged by the policy.
    static func resolveInput(text: Any?, file: Any?, side: String, logger: any ActionUILogger,
                             readsFile: (String) -> Bool) -> ResolvedInput {
        if let text = text as? String {
            if file is String {
                logger.log("Diff \(side): both text and file set; using text", .warning)
            }
            return .text(text)
        }

        guard let path = file as? String else {
            return .text("")
        }

        // A path Windows cannot make whole is not read: the trust check must see the path that is opened.
        guard let expanded = openedPath(expandingTilde(path)) else {
            logger.log("Diff \(side): cannot read '\(path)' (Windows cannot make it a full path); rendering a note", .warning)
            return .unreadable(path: path)
        }
        let fileManager = FileManager.default

        guard readsFile(expanded) else {
            return .unreadable(path: expanded)
        }

        guard let size = fileSize(atPath: expanded), size <= 4_194_304 else {
            logger.log("Diff \(side): cannot read '\(expanded)' (missing, not a regular file, or over 4 MB); rendering a note", .warning)
            return .unreadable(path: expanded)
        }

        guard let data = fileManager.contents(atPath: expanded),
              let contents = String(data: data, encoding: .utf8) else {
            logger.log("Diff \(side): '\(expanded)' is not readable UTF-8; rendering a note", .warning)
            return .unreadable(path: expanded)
        }

        return .text(contents)
    }

    /// Reads an integer property, falling back to `defaultValue` (with a warning) when it is
    /// ill-typed or below `minimum`.
    static func intProperty(_ properties: [String: Any], key: String,
                            default defaultValue: Int, minimum: Int,
                            logger: any ActionUILogger) -> Int {
        guard let raw = properties[key] else {
            return defaultValue
        }
        guard let value = raw as? Int else {
            logger.log("Diff \(key) must be an integer; using \(defaultValue)", .warning)
            return defaultValue
        }
        guard value >= minimum else {
            logger.log("Diff \(key) must be >= \(minimum); using \(defaultValue)", .warning)
            return defaultValue
        }
        return value
    }

    /// The path with a leading "~" (this user's home) or "~name" (that user's home) replaced, as NSString's
    /// expandingTildeInPath does (Apple uses it); any other path as it is. Linux and Windows have no NSString:
    /// FoundationEssentials. On Windows only "~", "~\..." and "~/..." expand, into the user's profile folder
    /// (USERPROFILE): "~name" is no Windows convention and stays as written, so no account is looked up (perhaps
    /// at a domain controller) for a name the content chose, before the trust check.
    static func expandingTilde(_ path: String) -> String {
        #if os(Windows)
        guard path == "~" || path.hasPrefix("~/") || path.hasPrefix("~\\"),
              let home = ProcessInfo.processInfo.environment["USERPROFILE"], !home.isEmpty else {
            return path
        }
        return home + path.dropFirst()
        #elseif os(Linux)
        guard path.hasPrefix("~") else {
            return path
        }
        let rest = path.dropFirst()
        let slash = rest.firstIndex(of: "/") ?? rest.endIndex
        let user = String(rest[..<slash])
        let fileManager = FileManager.default
        guard let home = user.isEmpty ? fileManager.homeDirectoryForCurrentUser : fileManager.homeDirectory(forUser: user) else {
            return path
        }
        // As expandingTildeInPath: no doubled slash after a home of "/", no trailing slash ("~/" is the home).
        let homePath = home.path
        let tail = String(rest[slash...])
        var expanded = homePath.hasSuffix("/") && tail.hasPrefix("/") ? String(homePath.dropLast()) + tail : homePath + tail
        if expanded.count > 1, expanded.hasSuffix("/") {
            expanded.removeLast()
        }
        return expanded
        #else
        return (path as NSString).expandingTildeInPath
        #endif
    }

    /// The path that is opened for `path`. On Windows, the full path Windows makes of it
    /// (GetFullPathNameW, from the text and the current folders alone, touching nothing): a relative
    /// path, "\name" (the current drive's root) and "C:name" (that drive's current folder) are read
    /// from a current folder that may be on a share, and "NUL" or "CON" anywhere name a device
    /// ("\\.\NUL"). The trust check (readsFile) is asked about this path, and this path is read, so
    /// less-trusted content reaches no share or device through a relative path. Elsewhere `path` as it is.
    /// Nil on Windows when Windows cannot make the full path (past its length limit, or the current folder changed
    /// between the two calls): the raw text is not what would be opened, so it is not judged in its place.
    static func openedPath(_ path: String) -> String? {
        #if os(Windows)
        guard !path.isEmpty else { return path }
        return path.withCString(encodedAs: UTF16.self) { text -> String? in
            let needed = GetFullPathNameW(text, 0, nil, nil)
            guard needed > 0 else { return nil }
            var buffer = [WCHAR](repeating: 0, count: Int(needed))
            let written = GetFullPathNameW(text, needed, &buffer, nil)
            guard written > 0, written < needed else { return nil }
            return String(decoding: buffer.prefix(Int(written)), as: UTF16.self)
        }
        #else
        return path
        #endif
    }

    /// The size in bytes of the file at `path`, following symbolic links, so the 4 MB cap holds for the file that
    /// is read; nil when there is none (also for a link to nothing). stat(2) rather than FileManager's attributes:
    /// those describe a link itself, not the file it leads to, and on Linux the size's type depends on which
    /// Foundation is loaded (an NSNumber in the test process, where full Foundation is).
    private static func fileSize(atPath path: String) -> Int? {
        #if os(Windows)
        // The wide-character stat, for any path Windows can name; a device ("\\.\NUL") or a folder is
        // not a regular file.
        var info = _stat64()
        let status = path.withCString(encodedAs: UTF16.self) { _wstat64($0, &info) }
        guard status == 0, Int32(info.st_mode) & _S_IFMT == _S_IFREG else {
            return nil
        }
        return Int(info.st_size)
        #else
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            return nil
        }
        return Int(info.st_size)
        #endif
    }
}
