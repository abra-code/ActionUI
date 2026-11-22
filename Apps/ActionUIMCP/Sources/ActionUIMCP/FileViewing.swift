// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// FileViewing.swift - how show kind "file" shows a file: with ActionUI's own views when its type
// allows (Markdown formatted, CSV and TSV as a table, images, audio and video, any other UTF-8 text
// as monospaced text), else with Quick Look on macOS. Decided by the file name's extension, then by
// the content, so it works the same on Linux, where Quick Look does not exist.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import MCPStdio
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// The view a file is shown with, as `show` reports it in `shown_as`.
enum FileView: String {
    case markdown, table, image, video, text
    case quickLook = "quicklook"
}

struct FileViewing {
    let view: FileView
    /// The window's root element.
    let root: [String: Any]
    /// For a table: its rows (Table takes them as state, set once the window exists).
    let rows: [[String]]?

    /// Larger text files go to Quick Look on macOS (and are refused on Linux): the text view and
    /// the Markdown renderer lay out the whole text at once.
    static let maxTextBytes = 4 * 1024 * 1024
    static let maxMarkdownBytes = 1024 * 1024
    /// At most this many columns in a CSV or TSV shown as a table; a wider one is shown as text.
    static let maxTableColumns = 200

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn"]
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "tif", "tiff", "bmp", "webp", "ico", "heic", "heif"]
    #if os(Linux)
    static let mediaExtensions: Set<String> = ["mp4", "m4v", "mov", "mp3", "m4a", "wav", "aac", "aiff", "aif", "flac",
                                               "webm", "mkv", "ogg", "oga", "ogv", "opus"]
    #else
    static let mediaExtensions: Set<String> = ["mp4", "m4v", "mov", "mp3", "m4a", "wav", "aac", "aiff", "aif", "caf", "flac"]
    #endif
    static let delimiters: [String: UInt8] = ["csv": UInt8(ascii: ","), "tsv": UInt8(ascii: "\t"), "tab": UInt8(ascii: "\t")]
    /// Text formats Quick Look draws as what they describe (a page, a picture, formatted text),
    /// not as their source. On Linux they are shown as text.
    static let renderedByQuickLook: Set<String> = ["html", "htm", "xhtml", "svg", "rtf", "webarchive"]

    /// How to show the regular file at `path` (absolute, already checked to exist).
    static func view(forPath path: String, tableViewID: Int, maxTableRows: Int) throws -> FileViewing {
        let fill: [String: Any] = ["maxWidth": "infinity", "maxHeight": "infinity"]
        let fileURL = URL(fileURLWithPath: path)
        let name = fileURL.lastPathComponent
        let ext = fileURL.pathExtension.lowercased()
        guard let size = regularFileSize(path) else {
            throw MCPToolError("cannot show \(path): not a regular file")
        }

        if imageExtensions.contains(ext) {
            return FileViewing(view: .image, root: ["type": "Image", "properties": ["filePath": path, "resizable": true,
                                                                                     "contentMode": "fit", "padding": 12, "frame": fill]],
                               rows: nil)
        }
        if mediaExtensions.contains(ext) {
            return FileViewing(view: .video, root: ["type": "VideoPlayer", "properties": ["url": fileURL.absoluteString,
                                                                                          "frame": fill]],
                               rows: nil)
        }
        #if !os(Linux)
        if renderedByQuickLook.contains(ext) || ext == "pdf" {
            return quickLook(path, fill: fill)
        }
        #endif

        // Everything else is shown as text when it is text: valid UTF-8 with no NUL byte. Markdown
        // over its own limit is still shown, as plain text, up to the text limit.
        let isMarkdown = markdownExtensions.contains(ext) && size <= maxMarkdownBytes
        let limit = isMarkdown ? maxMarkdownBytes : maxTextBytes
        guard size <= limit, let text = readText(path, limit: limit) else {
            #if os(Linux)
            let reason = size > limit ? "it is larger than \(limit / 1024 / 1024) MB" : "it is not UTF-8 text"
            throw MCPToolError("cannot show \(name): \(reason), and Linux has no previewer for other files")
            #else
            return quickLook(path, fill: fill)
            #endif
        }
        if isMarkdown {
            // A file can come from anywhere (a cloned repository's README, say): its remote images
            // load only when clicked, so showing it does not tell their servers it was opened.
            return FileViewing(view: .markdown, root: ["type": "ScrollView", "properties": ["frame": fill],
                                                       "content": ["type": "RichText", "properties": ["markdown": text, "padding": 20,
                                                                                                      "remoteImages": "on-click"]]],
                               rows: nil)
        }
        if let delimiter = delimiters[ext], let table = parseDelimited(text, delimiter: delimiter, maxRows: maxTableRows) {
            return FileViewing(view: .table, root: ["type": "Table", "id": tableViewID,
                                                    "properties": ["columns": table.columns, "frame": fill]],
                               rows: table.rows)
        }
        return FileViewing(view: .text, root: ["type": "TextEditor", "properties": ["text": text, "readOnly": true, "frame": fill,
                                                                                    "font": ["size": 12, "design": "monospaced"]]],
                           rows: nil)
    }

    #if !os(Linux)
    private static func quickLook(_ path: String, fill: [String: Any]) -> FileViewing {
        FileViewing(view: .quickLook, root: ["type": "QuickLook", "properties": ["filePath": path, "frame": fill]], rows: nil)
    }
    #endif

    /// The size of the regular file at `path`, following links; nil for anything else (a folder,
    /// a device or a pipe, which would block a read).
    static func regularFileSize(_ path: String) -> Int? {
        guard !path.utf8.contains(0) else { return nil }
        var information = stat()
        guard stat(path, &information) == 0, information.st_mode & S_IFMT == S_IFREG else { return nil }
        return Int(information.st_size)
    }

    /// The file's text when it is UTF-8 with no NUL byte (a byte no text file holds) and at most
    /// `limit` bytes long, else nil. The size checked before may be stale: the file can have grown
    /// or been replaced since. So this reads at most `limit` + 1 bytes, and opens without blocking
    /// and checks again that it opened a regular file, so a pipe put in its place is not waited on.
    static func readText(_ path: String, limit: Int) -> String? {
        guard !path.utf8.contains(0) else { return nil }
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var information = stat()
        guard fstat(descriptor, &information) == 0, information.st_mode & S_IFMT == S_IFREG else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(min(max(Int(information.st_size), 0), limit) + 1)
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while bytes.count <= limit {
            let count = chunk.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { return nil }
            if count == 0 { break }
            bytes.append(contentsOf: chunk[..<count])
        }
        guard bytes.count <= limit, !bytes.contains(0) else { return nil }
        // Decoding replaces each invalid sequence with U+FFFD, so valid UTF-8 is exactly what
        // decodes back to the same bytes.
        let text = String(decoding: bytes, as: UTF8.self)
        return text.utf8.elementsEqual(bytes) ? text : nil
    }

    /// `text` as CSV or TSV (RFC 4180 quoting: a quoted field may hold the delimiter, line breaks
    /// and doubled quotes): the first record is the header. nil when it is not a table to show:
    /// an unclosed quote, no records, a record wider than the header, more than `maxRows` rows or
    /// `maxTableColumns` columns. Shorter records are padded with empty cells.
    static func parseDelimited(_ text: String, delimiter: UInt8, maxRows: Int) -> (columns: [String], rows: [[String]])? {
        let quote = UInt8(ascii: "\""), newline = UInt8(ascii: "\n"), carriageReturn = UInt8(ascii: "\r")
        var records: [[String]] = []
        var record: [String] = []
        var field: [UInt8] = []
        var inQuotes = false
        var fieldStarted = false
        var bytes = Array(text.utf8)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        var index = 0
        func endField() {
            record.append(String(decoding: field, as: UTF8.self))
            field.removeAll(keepingCapacity: true)
            fieldStarted = false
        }
        func endRecord() -> Bool {
            endField()
            // A line with nothing on it is not a record.
            if !(record.count == 1 && record[0].isEmpty) { records.append(record) }
            record.removeAll(keepingCapacity: true)
            return records.count <= maxRows + 1
        }
        while index < bytes.count {
            let byte = bytes[index]
            if inQuotes {
                if byte == quote {
                    if index + 1 < bytes.count, bytes[index + 1] == quote {
                        field.append(quote)
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(byte)
                }
            } else if byte == quote, !fieldStarted, field.isEmpty {
                inQuotes = true
                fieldStarted = true
            } else if byte == delimiter {
                endField()
            } else if byte == newline || byte == carriageReturn {
                if byte == carriageReturn, index + 1 < bytes.count, bytes[index + 1] == newline { index += 1 }
                guard endRecord() else { return nil }
            } else {
                field.append(byte)
                fieldStarted = true
            }
            index += 1
        }
        guard !inQuotes else { return nil }
        if fieldStarted || !field.isEmpty || !record.isEmpty {
            guard endRecord() else { return nil }
        }
        guard let header = records.first, header.count <= maxTableColumns else { return nil }
        var rows: [[String]] = []
        rows.reserveCapacity(records.count - 1)
        for record in records.dropFirst() {
            guard record.count <= header.count else { return nil }
            rows.append(record + Array(repeating: "", count: header.count - record.count))
        }
        let columns = header.enumerated().map { $1.isEmpty ? "Column \($0 + 1)" : $1 }
        return (columns, rows)
    }
}
