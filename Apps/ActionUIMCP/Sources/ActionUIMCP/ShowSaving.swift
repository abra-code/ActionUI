// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// ShowSaving.swift - what the Save button of a `show` window saves: the file the content came from,
// the text, a table as CSV, a chart as PNG, a diff as a unified diff. The platform layer asks for a
// place with its save panel and writes there; nothing is written anywhere else.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import ActionUISwiftAdapter
import DiffView
import MCPStdio

/// One side of a diff: inline text, or a file read when saving.
struct DiffSideSource: Codable, Sendable, Equatable {
    let text: String?
    let path: String?
}

/// What Save writes for a `show` window, and the name the save panel offers.
struct ShowSave: Codable, Sendable, Equatable {
    enum Content: Codable, Sendable, Equatable {
        /// A copy of this file.
        case file(path: String)
        /// This text, as UTF-8.
        case text(String)
        /// The window's table, as it is when saving, as CSV with these column headers.
        case table(columns: [String])
        /// A PNG of the chart as the window draws it.
        case chart
        /// A unified diff of the two sides.
        case diff(old: DiffSideSource, new: DiffSideSource)
    }

    let content: Content
    let suggestedName: String

    /// What Save writes for a window titled `title` showing `kind`. Nil for content from the
    /// network, which has a Copy URL button instead.
    static func forViewer(kind: ContentKind, title: String, arguments: [String: JSONValue], sourcePath: String?) -> ShowSave? {
        if let sourcePath {
            return ShowSave(content: .file(path: sourcePath), suggestedName: URL(fileURLWithPath: sourcePath).lastPathComponent)
        }
        func named(_ fileExtension: String) -> String { fileName(from: title) + "." + fileExtension }
        switch kind {
        case .markdown:
            return arguments["text"]?.string.map { ShowSave(content: .text($0), suggestedName: named("md")) }
        case .text:
            return arguments["text"]?.string.map { ShowSave(content: .text($0), suggestedName: named("txt")) }
        case .web:
            guard arguments["url"]?.string == nil else { return nil }
            return arguments["text"]?.string.map { ShowSave(content: .text($0), suggestedName: named("html")) }
        case .table:
            let columns = arguments["columns"]?.array?.compactMap(\.string) ?? []
            return ShowSave(content: .table(columns: columns), suggestedName: named("csv"))
        case .chart:
            return ShowSave(content: .chart, suggestedName: named("png"))
        case .diff:
            let old = DiffSideSource(text: arguments["old_text"]?.string, path: arguments["old_path"]?.string)
            let new = DiffSideSource(text: arguments["new_text"]?.string, path: arguments["new_path"]?.string)
            return ShowSave(content: .diff(old: old, new: new), suggestedName: named("diff"))
        case .image, .pdf, .file, .video:
            return nil  // Shown from a path (handled above) or from the network.
        }
    }

    /// A window title as a file name: one line, not starting with ".", and each character that a
    /// file system or a save panel on macOS, Linux or Windows reads as more than part of a name
    /// replaced by "-": / and : everywhere, and Windows' backslash, < > " | ? and * (its save
    /// dialog takes a name with a backslash as a path into another folder than the one it shows).
    static func fileName(from title: String) -> String {
        // By Unicode scalar, as csv(...) quotes: a "\" followed by a combining mark is one
        // Character with it, and a path still reads the "\".
        let special = Set(#"/:\<>"|?*"#.unicodeScalars)
        var name = String.UnicodeScalarView()
        for scalar in oneLine(title, limit: 100).unicodeScalars {
            if name.isEmpty && scalar == "." { continue }
            name.append(special.contains(scalar) ? "-" : scalar)
        }
        return name.isEmpty ? "Untitled" : String(name)
    }

    // MARK: Writers

    /// What Save writes for `content` in the window `windowID`, but a file, which each platform
    /// copies itself (nil then): the text as UTF-8, the table's rows as they are now as CSV, the
    /// chart as `chartPNG` draws it, the diff as a unified diff of its two sides as they are now.
    @MainActor static func bytes(of content: Content, windowID: String, chartPNG: () throws -> Data) throws -> Data? {
        switch content {
        case .file:
            return nil
        case .text(let text):
            return Data(text.utf8)
        case .table(let columns):
            // Nil when the window is gone (on Linux the save panel can outlive it): saying so beats a CSV of headers alone.
            guard let rows = ActionUISwift.getElementRows(windowUUID: windowID, viewID: ViewerSpec.tableViewID) else {
                throw MCPToolError("the window was closed, so its table is gone")
            }
            return Data(csv(columns: columns, rows: rows).utf8)
        case .chart:
            return try chartPNG()
        case .diff(let old, let new):
            let oldText = try text(of: old), newText = try text(of: new)
            let diff = try unifiedDiff(oldText: oldText, newText: newText, oldName: old.path ?? "old", newName: new.path ?? "new")
            return Data(diff.utf8)
        }
    }

    /// One side of a diff: its text, else its file read now.
    private static func text(of side: DiffSideSource) throws -> String {
        if let text = side.text { return text }
        guard let path = side.path else { return "" }
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    /// Rows as CSV (RFC 4180): fields with a comma, quote or line break are quoted, quotes doubled,
    /// lines end with CRLF.
    static func csv(columns: [String], rows: [[String]]) -> String {
        // By Unicode scalar: a comma or quote followed by a combining mark is one Character with it.
        let special = Set(",\"\n\r\u{0B}\u{0C}\u{85}\u{2028}\u{2029}".unicodeScalars)
        func field(_ text: String) -> String {
            guard text.unicodeScalars.contains(where: special.contains) else { return text }
            var quoted = String.UnicodeScalarView()
            quoted.append("\"")
            for scalar in text.unicodeScalars {
                if scalar == "\"" { quoted.append(scalar) }
                quoted.append(scalar)
            }
            quoted.append("\"")
            return String(quoted)
        }
        let lines = ([columns] + rows).map { $0.map(field).joined(separator: ",") }
        return lines.map { $0 + "\r\n" }.joined()
    }

    /// The most lines a saved diff compares, the two sides together. The diff is computed on the
    /// main thread, and two texts that differ throughout take time that grows with the square of
    /// their length; the Diff element itself compares at most 4000.
    static let maxDiffLines = 20_000

    /// A unified diff of `oldText` against `newText` with three lines of context, under "---" and
    /// "+++" headers naming the two sides. Empty when the texts are the same. Throws when the texts
    /// are too long to compare. A last line with no line break is followed by
    /// "\\ No newline at end of file", as diff -u writes it, so that patch recreates it.
    static func unifiedDiff(oldText: String, newText: String, oldName: String, newName: String) throws -> String {
        // DiffComputer drops a final line break, which would make "c" and "c\n" the same line. A
        // marker on a last line without one keeps them apart and shows where the note goes.
        var marker = "\u{0}no newline"
        while oldText.contains(marker) || newText.contains(marker) { marker += "\u{0}" }
        func marked(_ text: String) -> String {
            text.isEmpty || text.utf8.last == UInt8(ascii: "\n") ? text : text + marker + "\n"
        }
        let result = DiffComputer.compute(oldText: marked(oldText), newText: marked(newText), context: 3, sizeLimit: maxDiffLines)
        if result.exceedsSizeLimit {
            throw MCPToolError("the texts are too long to compare (more than \(maxDiffLines) lines together)")
        }
        if result.isIdentical { return "" }
        var out = "--- \(oneLine(oldName, limit: 1000))\n+++ \(oneLine(newName, limit: 1000))\n"
        for hunk in result.hunks {
            let oldLines = hunk.lines.filter { $0.kind != .added }
            let newLines = hunk.lines.filter { $0.kind != .removed }
            // An empty side is named by the line before it (0 at the start), as diff -u does.
            let oldStart = oldLines.first?.oldNumber ?? Self.lineBefore(hunk.lines, \.oldNumber)
            let newStart = newLines.first?.newNumber ?? Self.lineBefore(hunk.lines, \.newNumber)
            out += "@@ -\(range(oldStart, oldLines.count)) +\(range(newStart, newLines.count)) @@\n"
            for line in hunk.lines {
                let prefix = switch line.kind {
                case .context: " "
                case .removed: "-"
                case .added: "+"
                }
                if line.text.hasSuffix(marker) {
                    out += prefix + line.text.dropLast(marker.count) + "\n\\ No newline at end of file\n"
                } else {
                    out += prefix + line.text + "\n"
                }
            }
        }
        return out
    }

    private static func range(_ start: Int, _ count: Int) -> String {
        count == 1 ? "\(start)" : "\(start),\(count)"
    }

    /// For a hunk with no line on one side: that side's last line number before the hunk.
    private static func lineBefore(_ lines: [DiffLine], _ number: KeyPath<DiffLine, Int?>) -> Int {
        // With context lines every hunk has both sides; only an empty text gets here.
        lines.compactMap { $0[keyPath: number] }.first.map { max($0 - 1, 0) } ?? 0
    }
}
