// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// HostSupport.swift - what the server needs from the platform, written once. Linux builds on
// FoundationEssentials, which has no Bundle, FileHandle, JSONSerialization, CharacterSet,
// NumberFormatter, DateFormatter or Error.localizedDescription. Most of these are one code path on
// both platforms; the rest are the #if blocks in this file.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if os(Linux)
import ActionUI
#endif
import MCPStdio

enum HostSupport {
    // MARK: Log

    /// Writes `text` and a newline to stderr, the server's log: stdout belongs to the protocol.
    static func logLine(_ text: String) {
        let bytes = Array((text + "\n").utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { write(STDERR_FILENO, $0.baseAddress, $0.count) }
            if written < 0 && errno == EINTR { continue }
            if written <= 0 { return }
            offset += written
        }
    }

    // MARK: JSON

    /// Parses a JSON document: ActionUI's own parser on Linux, which has no JSONSerialization.
    static func parseJSON(_ data: Data) throws -> JSONValue {
        #if os(Linux)
        // String(decoding:) replaces broken bytes, where JSONSerialization refuses them.
        let text = String(decoding: data, as: UTF8.self)
        guard text.utf8.elementsEqual(data) else { throw ActionUIJSONError("the text is not UTF-8") }
        return JSONValue(any: try ActionUIJSON.value(from: text))
        #else
        return JSONValue(any: try JSONSerialization.jsonObject(with: data))
        #endif
    }

    /// Parses a protocol message, for MCPServer; nil for text that is not JSON.
    @Sendable static func parseMessage(_ text: String) -> JSONValue? {
        #if os(Linux)
        (try? ActionUIJSON.value(from: text)).map { JSONValue(any: $0) }
        #else
        JSONValue.parsedByFoundation(text)
        #endif
    }

    // MARK: Paths

    /// The folder for this session's staged documents and screenshots. The temporary folder on macOS
    /// is the user's own. On Linux it is /tmp, open to every user of the machine, so the folder is
    /// made private there, under a name nobody can take first: a staged document replaced in a
    /// folder someone else owns would load past the document checks, and a screenshot shows what
    /// the user has on screen.
    static let sessionFolder: URL = {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("actionui-mcp-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        #if os(Linux)
        var template = Array((folder.path + "-XXXXXX").utf8CString)
        if mkdtemp(&template) != nil {
            return URL(fileURLWithPath: String(cString: template), isDirectory: true)
        }
        #endif
        return folder
    }()

    /// The running program's path, symbolic links resolved: a client launching the bare name
    /// through PATH passes just that in argv[0].
    static var executablePath: String? {
        #if os(Linux)
        var buffer = [CChar](repeating: 0, count: 4096)
        let count = readlink("/proc/self/exe", &buffer, buffer.count)
        guard count > 0, count < buffer.count else { return nil }
        return String(decoding: buffer[..<count].map { UInt8(bitPattern: $0) }, as: UTF8.self)
        #else
        return Bundle.main.executableURL?.resolvingSymlinksInPath().path
        #endif
    }

    /// Whether a folder is at `path`, following links; nil when nothing is there.
    static func isFolder(atPath path: String) -> Bool? {
        // stat would stop reading the path at a NUL, and report on the file named before it.
        guard !path.utf8.contains(0) else { return nil }
        var information = stat()
        guard stat(path, &information) == 0 else { return nil }
        return information.st_mode & S_IFMT == S_IFDIR
    }

    /// The folder holding the resources of `name`, a resource bundle SwiftPM built: next to the
    /// executable, or on Apple in the app bundle's Resources. nil when there is none.
    static func resourceFolder(ofBundle name: String) -> URL? {
        let executableFolder = executablePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
        #if os(Linux)
        // A plain folder on Linux, with no Contents/Resources inside: .bundle from SwiftPM's
        // default build system, .resources from the older one.
        return [".bundle", ".resources"].lazy
            .compactMap { executableFolder?.appendingPathComponent(name + $0) }
            .first { isFolder(atPath: $0.path) == true }
        #else
        for folder in [executableFolder, Bundle.main.resourceURL].compactMap({ $0 }) {
            if let resources = Bundle(url: folder.appendingPathComponent(name + ".bundle"))?.resourceURL {
                return resources
            }
        }
        return nil
        #endif
    }

    // MARK: Dates

    /// `date` in UTC with seconds, as 2026-11-01T11:14:03Z.
    static func timestamp(_ date: Date) -> String {
        Date.ISO8601FormatStyle().format(nearestMillisecond(date))
    }

    /// `date` in UTC with milliseconds, as 2026-11-01T11:14:03.125Z.
    static func preciseTimestamp(_ date: Date) -> String {
        Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(nearestMillisecond(date))
    }

    /// The format style cuts off what is past the millisecond, which puts half of the Date() values
    /// a millisecond early. Rounded first, as ISO8601DateFormatter did; the extra quarter of a
    /// millisecond keeps a rounded value that a Double holds just short of it from being cut too.
    private static func nearestMillisecond(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000 + 0.00025)
    }

    /// The calendar day `date` falls on in the user's time zone, as 2026-11-01. localtime_r, not
    /// Calendar: FoundationEssentials has no named time zones, so TimeZone.current is GMT there.
    static func localDay(_ date: Date) -> String {
        var seconds = time_t(date.timeIntervalSince1970.rounded(.down))
        var parts = tm()
        guard localtime_r(&seconds, &parts) != nil else { return timestamp(date).prefix(10).description }
        return padded(Int(parts.tm_year) + 1900, 4) + "-" + padded(Int(parts.tm_mon) + 1, 2) + "-" + padded(Int(parts.tm_mday), 2)
    }

    private static func padded(_ number: Int, _ width: Int) -> String {
        let digits = String(abs(number))
        return (number < 0 ? "-" : "") + String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    // MARK: Numbers

    /// `value` with `decimals` digits after the point, as printf's %f rounds it.
    static func fixed(_ value: Double, decimals: Int) -> String {
        // 309 digits for the largest double, a sign, a point and the decimals.
        var buffer = [CChar](repeating: 0, count: 312 + max(0, decimals))
        let count = withVaList([Int32(decimals), value]) { vsnprintf(&buffer, buffer.count, "%.*f", $0) }
        guard count > 0, count < buffer.count else { return String(value) }
        return String(decoding: buffer[..<Int(count)].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// What a person typed, in the user's locale ("1,234.5" in the US, "1.234,5" in Germany) or
    /// with a plain point ("1234.5"); nil when it is not a number.
    static func number(from text: String) -> Double? {
        #if os(Linux)
        // GTK sets the C library's locale from the environment.
        let conventions = localeconv()?.pointee
        let decimal = conventions.flatMap { String(cString: $0.decimal_point).first } ?? "."
        let grouping = conventions.flatMap { String(cString: $0.thousands_sep).first }
        return number(from: text, decimal: decimal, grouping: grouping)
        #else
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.number(from: text)?.doubleValue ?? Double(text)
        #endif
    }

    /// `text` with the given separators, or as Swift reads it. Separators count only where they
    /// make sense, groups of three after the first: "1,5" in the US is no number rather than 15,
    /// and "1234.5" in Germany is 1234.5 rather than 12345.
    static func number(from text: String, decimal: Character, grouping: Character?) -> Double? {
        let sides = text.split(separator: decimal, maxSplits: 1, omittingEmptySubsequences: false)
        var whole = String(sides[0])
        if let grouping, whole.contains(grouping) {
            let groups = whole.split(separator: grouping, omittingEmptySubsequences: false)
            let leading = groups[0].drop { $0 == "-" || $0 == "+" }
            guard (1...3).contains(leading.count), groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return Double(text) }
            whole = groups.joined()
        }
        return Double(sides.count > 1 ? whole + "." + sides[1] : whole) ?? Double(text)
    }
}

extension String {
    /// The text without the whitespace and newlines around it. By scalar, with the zero width
    /// space, as Foundation's whitespacesAndNewlines; a Character would take a mark on a space too.
    var trimmed: String {
        func isBlank(_ scalar: Unicode.Scalar) -> Bool { scalar.properties.isWhitespace || scalar == "\u{200B}" }
        var slice = unicodeScalars[...]
        while let first = slice.first, isBlank(first) { slice.removeFirst() }
        while let last = slice.last, isBlank(last) { slice.removeLast() }
        return String(slice)
    }
}

extension Error {
    /// The error as a person reads it.
    var displayText: String {
        #if os(Linux)
        String(describing: self)
        #else
        localizedDescription
        #endif
    }
}
