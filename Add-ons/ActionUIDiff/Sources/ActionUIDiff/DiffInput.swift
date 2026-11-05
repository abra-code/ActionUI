// Add-ons/ActionUIDiff/Sources/ActionUIDiff/DiffInput.swift
//
// How the Diff element reads its properties, on Apple (Diff.swift) and Linux (Diff+Adwaita.swift) alike: each
// side's text or file, and the two integer settings. No UI, so the rules are unit-testable without a view.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import ActionUI
#if os(Linux)
import Glibc
#endif

extension Diff {

    /// One side's resolved text, or a path the wrapper could not read.
    enum ResolvedInput: Equatable {
        case text(String)
        case unreadable(path: String)
    }

    /// Resolves one side of the diff from its text and file properties.
    /// - text wins over file: if `text` is a string it is used (warning if `file` is also set).
    /// - otherwise `file` is tilde-expanded and read as UTF-8; missing, over 4 MB, or non-UTF-8
    ///   yields `.unreadable`.
    /// - neither given yields `.text("")` (a legitimate empty side: pure addition / removal).
    static func resolveInput(text: Any?, file: Any?, side: String, logger: any ActionUILogger) -> ResolvedInput {
        if let text = text as? String {
            if file is String {
                logger.log("Diff \(side): both text and file set; using text", .warning)
            }
            return .text(text)
        }

        guard let path = file as? String else {
            return .text("")
        }

        let expanded = expandingTilde(path)
        let fileManager = FileManager.default

        guard let size = fileSize(atPath: expanded), size <= 4_194_304 else {
            logger.log("Diff \(side): cannot read '\(expanded)' (missing or over 4 MB); rendering a note", .warning)
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
    /// expandingTildeInPath does (Apple uses it); any other path as it is. Linux has no NSString: FoundationEssentials.
    static func expandingTilde(_ path: String) -> String {
        #if os(Linux)
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

    /// A file's size in bytes, nil when it cannot be found.
    private static func fileSize(atPath path: String) -> Int? {
        #if os(Linux)
        // stat(2): the type of FileManager's size attribute here depends on which Foundation is loaded (an NSNumber in
        // the test process, where full Foundation is), so no one cast reads it everywhere.
        var info = stat()
        guard stat(path, &info) == 0 else {
            return nil
        }
        return Int(info.st_size)
        #else
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int
        #endif
    }
}
