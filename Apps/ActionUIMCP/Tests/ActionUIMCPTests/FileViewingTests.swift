// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// show kind "file": which view a file gets by its type and content (FileViewing), and the CSV and
// TSV reader.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
@testable import ActionUIMCP
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// A new folder for one test's files.
private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("file-viewing-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ bytes: [UInt8], _ name: String, in folder: URL) throws -> String {
    let url = folder.appendingPathComponent(name)
    try Data(bytes).write(to: url)
    return url.path
}

private func write(_ data: Data, _ name: String, in folder: URL) throws -> String {
    try write(Array(data), name, in: folder)
}

private extension PropertyListEncoder {
    static func binary(_ value: [String: String]) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(value)
    }
}

private func write(_ text: String, _ name: String, in folder: URL) throws -> String {
    try write(Array(text.utf8), name, in: folder)
}

private func view(_ path: String) throws -> FileViewing {
    try FileViewing.view(forPath: path, tableViewID: 1, maxTableRows: 50000)
}

@Test func markdownIsShownFormattedWithRichText() throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let shown = try view(write("# Title\n\nSome **bold** text.\n", "notes.md", in: dir))
    #expect(shown.view == .markdown)
    let content = shown.root["content"] as? [String: Any]
    #expect(content?["type"] as? String == "RichText")
    #expect((content?["properties"] as? [String: Any])?["markdown"] as? String == "# Title\n\nSome **bold** text.\n")
    #expect((content?["properties"] as? [String: Any])?["remoteImages"] as? String == "on-click", "a file's images load when clicked")
}

@Test func csvAndTsvAreShownAsATableWithTheFirstRecordAsHeader() throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let csv = try view(write("name,note\r\nAda,\"likes, commas\"\r\nGrace,\"says \"\"hi\"\"\non two lines\"\r\n", "people.csv", in: dir))
    #expect(csv.view == .table)
    #expect((csv.root["properties"] as? [String: Any])?["columns"] as? [String] == ["name", "note"])
    #expect(csv.rows == [["Ada", "likes, commas"], ["Grace", "says \"hi\"\non two lines"]])
    let tsv = try view(write("a\tb\tc\n1\t2\n", "short.tsv", in: dir))
    #expect(tsv.view == .table)
    #expect(tsv.rows == [["1", "2", ""]], "a short record is padded")
}

@Test func aCsvThatIsNotATableIsShownAsText() throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(try view(write("a,b\n1,2,3\n", "wide.csv", in: dir)).view == .text, "a record wider than the header")
    #expect(try view(write("a,\"open\n", "open.csv", in: dir)).view == .text, "an unclosed quote")
    #expect(FileViewing.parseDelimited("a\n1\n2\n3\n", delimiter: UInt8(ascii: ","), maxRows: 2) == nil, "more rows than allowed")
}

@Test func theCsvReaderHandlesTheEdgesOfTheFormat() throws {
    let comma = UInt8(ascii: ",")
    let atLimit = FileViewing.parseDelimited("a\n1\n2\n", delimiter: comma, maxRows: 2)
    #expect(atLimit?.rows == [["1"], ["2"]], "maxRows data rows, the header not counted")
    let lines = FileViewing.parseDelimited("\u{FEFF}a,b\r1,2\r\n\n3,4", delimiter: comma, maxRows: 10)
    #expect(lines?.columns == ["a", "b"], "a byte order mark is dropped")
    #expect(lines?.rows == [["1", "2"], ["3", "4"]], "CR alone ends a record, an empty line is none, the last needs no newline")
    let quotes = FileViewing.parseDelimited("a,b\n5\" disk,\"x\r\ny\"\n", delimiter: comma, maxRows: 10)
    #expect(quotes?.rows == [["5\" disk", "x\r\ny"]], "a quote inside an unquoted field is kept; a quoted line break too")
    let empty = FileViewing.parseDelimited(",\n,\n", delimiter: comma, maxRows: 10)
    #expect(empty?.columns == ["Column 1", "Column 2"], "an empty header cell gets a name")
    #expect(empty?.rows == [["", ""]])
}

@Test func readingTextStopsAtTheLimitAndNeverWaitsOnAPipe() throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let text = try write("12345", "five.txt", in: dir)
    #expect(FileViewing.readText(text, limit: 5) == "12345")
    #expect(FileViewing.readText(text, limit: 4) == nil, "a file that grew past the limit since its size was checked")
    let pipe = dir.appendingPathComponent("pipe.txt").path
    #expect(mkfifo(pipe, 0o600) == 0)
    #expect(FileViewing.readText(pipe, limit: 5) == nil, "a pipe put in place of the file")
    #expect(throws: (any Error).self) { try view(pipe) }
}

@Test func textAndSourceAreShownAsMonospacedText() throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    for name in ["notes.txt", "main.swift", "data.json", "server.log", "Makefile"] {
        let shown = try view(write("line one\nline two\n", name, in: dir))
        #expect(shown.view == .text, "\(name)")
        #expect(shown.root["type"] as? String == "TextEditor", "\(name)")
    }
}

@Test func imagesAndMediaGetTheirOwnElements() throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let image = try view(write([0x89, 0x50, 0x4E, 0x47], "picture.PNG", in: dir))
    #expect(image.view == .image)
    #expect((image.root["properties"] as? [String: Any])?["filePath"] as? String == dir.appendingPathComponent("picture.PNG").path)
    let movie = try view(write([0, 0, 0, 0], "clip.mp4", in: dir))
    #expect(movie.view == .video)
    #expect(((movie.root["properties"] as? [String: Any])?["url"] as? String)?.hasPrefix("file://") == true)
}

@Test func whatIsNotTextGoesToQuickLookOnMacOSAndIsRefusedOnLinux() throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let binary = try write([0x00, 0x01, 0x02, 0xFF], "data.bin", in: dir)
    let latin1 = try write([0x63, 0x61, 0x66, 0xE9], "cafe.txt", in: dir)
    #if os(Linux)
    #expect(throws: (any Error).self) { try view(binary) }
    #expect(throws: (any Error).self) { try view(latin1) }
    #else
    #expect(try view(binary).view == .quickLook, "a NUL byte")
    #expect(try view(latin1).view == .quickLook, "not UTF-8")
    #expect(try view(write("{\\rtf1 text}", "note.rtf", in: dir)).view == .quickLook, "RTF is drawn formatted")
    #expect(try view(write([0x25, 0x50, 0x44, 0x46], "doc.pdf", in: dir)).view == .quickLook)
    #endif
}

@Test func htmlAndSVGAreShownAsAWebPageOfTheFile() throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    for name in ["page.html", "page.HTM", "page.xhtml", "logo.svg"] {
        let path = try write("<p>page</p>", name, in: dir)
        let shown = try view(path)
        #expect(shown.view == .web, "\(name)")
        #expect(shown.root["type"] as? String == "WebView")
        #expect((shown.root["properties"] as? [String: Any])?["url"] as? String == URL(fileURLWithPath: path).absoluteString)
    }
}

private func address(_ shown: FileViewing) -> String? {
    (shown.root["properties"] as? [String: Any])?["url"] as? String
}

@Test func aLinkFileIsShownAsTheWebPageItNames() throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>URL</key><string>https://example.com/a?b=1</string></dict></plist>
        """
    let webloc = try view(write(xml, "site.webloc", in: dir))
    #expect(webloc.view == .web)
    #expect(address(webloc) == "https://example.com/a?b=1")
    let binary = try PropertyListEncoder.binary(["URL": "http://example.org/"])
    #expect(address(try view(write(binary, "binary.webloc", in: dir))) == "http://example.org/")
    let shortcut = "[DEFAULT]\r\nBASEURL=https://wrong.example/\r\n[InternetShortcut]\r\nIconIndex=0\r\n url = https://example.net/page \r\n"
    #expect(address(try view(write(shortcut, "page.url", in: dir))) == "https://example.net/page")
    #expect(address(try view(write("\u{FEFF}[InternetShortcut]\nURL=https://example.com/\n", "marked.url", in: dir))) == "https://example.com/",
            "a byte order mark")
}

@Test func aLinkFileToAnythingButAWebAddressIsRefused() throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    for target in ["file:///etc/passwd", "javascript:alert(1)", "ssh://host", "https://", "not a url"] {
        let shortcut = "[InternetShortcut]\nURL=\(target)\n"
        #expect(throws: (any Error).self, "\(target)") { try view(write(shortcut, "link.url", in: dir)) }
    }
    #expect(throws: (any Error).self, "no URL line") { try view(write("[InternetShortcut]\nIconIndex=0\n", "none.url", in: dir)) }
    #expect(throws: (any Error).self, "not a property list") { try view(write("https://example.com", "plain.webloc", in: dir)) }
    let large = "[InternetShortcut]\nURL=https://example.com/\n" + String(repeating: ";", count: FileViewing.maxLinkFileBytes)
    #expect(throws: (any Error).self, "over the link file limit") { try view(write(large, "large.url", in: dir)) }
}

@Test func markdownOverItsLimitIsShownAsPlainText() throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    let markdown = try write(String(repeating: "x", count: FileViewing.maxMarkdownBytes + 1), "big.md", in: dir)
    #expect(try view(markdown).view == .text, "not laid out as Markdown, still shown")
    let text = try write(String(repeating: "x", count: FileViewing.maxTextBytes + 1), "huge.md", in: dir)
    #if os(Linux)
    #expect(throws: (any Error).self) { try view(text) }
    #else
    #expect(try view(text).view == .quickLook)
    #endif
}

@Test func onlyARegularFileIsShown() throws {
    let dir = try folder()
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(throws: (any Error).self) { try view(dir.path) }
    #expect(throws: (any Error).self) { try view("/dev/zero") }
}
