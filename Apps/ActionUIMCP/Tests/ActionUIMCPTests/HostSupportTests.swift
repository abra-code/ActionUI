// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Glibc)
import Glibc
#endif
import Testing
@testable import ActionUIMCP

@Test func timestampsAreInUTC() {
    let date = Date(timeIntervalSince1970: 1_000_000_000.25)
    #expect(HostSupport.timestamp(date) == "2001-09-09T01:46:40Z")
    #expect(HostSupport.preciseTimestamp(date) == "2001-09-09T01:46:40.250Z")
}

@Test func timestampsRoundToTheMillisecond() {
    #expect(HostSupport.preciseTimestamp(Date(timeIntervalSince1970: 1_377_475_820.7297294)) == "2013-08-26T00:10:20.730Z")
    #expect(HostSupport.preciseTimestamp(Date(timeIntervalSince1970: 1_700_000_000.9996)) == "2023-11-14T22:13:21.000Z")
    #expect(HostSupport.timestamp(Date(timeIntervalSince1970: 1_700_000_000.9996)) == "2023-11-14T22:13:21Z")
    #expect(HostSupport.timestamp(Date(timeIntervalSince1970: 1_700_000_000.9994)) == "2023-11-14T22:13:20Z")
}

#if !os(Linux)
/// The text the Foundation formatters wrote before these did.
@Test func timestampsMatchISO8601DateFormatter() {
    let plain = ISO8601DateFormatter()
    let precise = ISO8601DateFormatter()
    precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    // What Date() really gives, with digits past the millisecond, and values near a boundary.
    var seconds = [0, 1_000_000_000.25, 1_793_000_000.5, 86_399.125, -1.5, 1_700_000_000.0004, 1_700_000_000.0005,
                   1_700_000_000.9994, 1_700_000_000.9996, 1_700_000_000.001, 1_700_000_000.7]
    seconds += (0..<2000).map { _ in Double.random(in: 1_000_000_000...2_000_000_000) }
    for second in seconds {
        let date = Date(timeIntervalSince1970: second)
        #expect(HostSupport.timestamp(date) == plain.string(from: date))
        #expect(HostSupport.preciseTimestamp(date) == precise.string(from: date))
    }
}
#endif

@Test func localDayFollowsTheTimeZone() {
    let saved = getenv("TZ").map { String(cString: $0) }
    defer {
        if let saved { setenv("TZ", saved, 1) } else { unsetenv("TZ") }
        tzset()
    }
    // 2001-09-09 20:00 UTC: the next day nine hours east, the same day nine hours west.
    let date = Date(timeIntervalSince1970: 1_000_065_600)
    setenv("TZ", "EAST-9", 1)
    tzset()
    #expect(HostSupport.localDay(date) == "2001-09-10")
    setenv("TZ", "WEST+9", 1)
    tzset()
    #expect(HostSupport.localDay(date) == "2001-09-09")
}

@Test func fixedRoundsAsPrintf() {
    #expect(HostSupport.fixed(0.5, decimals: 0) == "0")
    #expect(HostSupport.fixed(1.5, decimals: 0) == "2")
    #expect(HostSupport.fixed(0.125, decimals: 2) == "0.12")
    #expect(HostSupport.fixed(2, decimals: 3) == "2.000")
    #expect(HostSupport.fixed(-0.25, decimals: 1) == "-0.2")
    #expect(HostSupport.fixed(.greatestFiniteMagnitude, decimals: 3).count == 313)
}

@Test func numbersWithUSSeparators() {
    let parse = { HostSupport.number(from: $0, decimal: ".", grouping: ",") }
    #expect(parse("1234") == 1234)
    #expect(parse("1,234") == 1234)
    #expect(parse("1,234,567.5") == 1234567.5)
    #expect(parse("-1,234.5") == -1234.5)
    #expect(parse("0.5") == 0.5)
    #expect(parse("1,5") == nil)
    #expect(parse("1,2345") == nil)
    #expect(parse(",123") == nil)
    #expect(parse("abc") == nil)
}

@Test func numbersWithGermanSeparators() {
    let parse = { HostSupport.number(from: $0, decimal: ",", grouping: ".") }
    #expect(parse("1.234,5") == 1234.5)
    #expect(parse("1,5") == 1.5)
    #expect(parse("1234") == 1234)
    // A plain point is still a decimal point.
    #expect(parse("1234.5") == 1234.5)
}

@Test func numbersWithNoGroupSeparator() {
    #expect(HostSupport.number(from: "1234.5", decimal: ".", grouping: nil) == 1234.5)
    #expect(HostSupport.number(from: "1,234", decimal: ".", grouping: nil) == nil)
}

@Test func isFolderTellsFoldersFromFiles() {
    #expect(HostSupport.isFolder(atPath: "/") == true)
    #expect(HostSupport.isFolder(atPath: #filePath) == false)
    #expect(HostSupport.isFolder(atPath: "/no/such/path") == nil)
    // No file has a NUL in its name, though a C call stops reading the path there.
    #expect(HostSupport.isFolder(atPath: #filePath + "\0.png") == nil)
}

@Test func parseJSONRefusesWhatIsNotUTF8() throws {
    #expect(try HostSupport.parseJSON(Data(#"{"a": ["b", 1, 2.5, true, null]}"#.utf8)) == ["a": ["b", 1, 2.5, true, nil]])
    #expect(throws: (any Error).self) { try HostSupport.parseJSON(Data([0x22, 0xFF, 0x22])) }
    #expect(throws: (any Error).self) { try HostSupport.parseJSON(Data([0x5B, 0x22, 0xC3, 0x22, 0x5D])) }
}

@Test func executablePathIsThisProgram() throws {
    let path = try #require(HostSupport.executablePath)
    #expect(path.hasPrefix("/"))
    #expect(HostSupport.isFolder(atPath: path) == false)
}

#if os(Linux)
/// The default build system writes .bundle, the older one .resources: both plain folders.
@Test func resourceFolderIsNextToTheProgram() throws {
    let program = URL(fileURLWithPath: try #require(HostSupport.executablePath))
    for suffix in [".bundle", ".resources"] {
        let name = "HostSupportTests-" + UUID().uuidString
        let folder = program.deletingLastPathComponent().appendingPathComponent(name + suffix)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(HostSupport.resourceFolder(ofBundle: name)?.path == folder.path)
    }
    #expect(HostSupport.resourceFolder(ofBundle: "HostSupportTests-none") == nil)
}
#endif

@Test func trimmedRemovesSpacesAndNewlines() {
    #expect(" \t a b \r\n".trimmed == "a b")
    #expect("\u{00A0}x\u{2003}".trimmed == "x")
    #expect("  \n".trimmed == "")
    #expect("".trimmed == "")
}

@Test func trimmedMatchesFoundation() {
    // A zero width space is blank to Foundation, though not to Unicode's White_Space.
    #expect("\u{200B}".trimmed == "")
    #expect("\u{200B}1,234\u{200B}".trimmed == "1,234")
    // By scalar: a mark on a space stays, and so what follows the mark does.
    #expect(Array(" \u{301}x".trimmed.unicodeScalars) == ["\u{301}", "x"])
    #expect(Array("x \u{200D}".trimmed.unicodeScalars) == ["x", " ", "\u{200D}"])
    #expect(Array("\u{FEFF}x".trimmed.unicodeScalars) == ["\u{FEFF}", "x"])
}
