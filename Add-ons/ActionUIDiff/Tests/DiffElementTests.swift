// Add-ons/ActionUIDiff/Tests/DiffElementTests.swift
//
// Element-level tests of the ActionUIDiff add-on: the Diff wrapper's input-resolution
// helper (text wins over file, tilde expansion, missing / unreadable files, empty sides)
// and how it reads raw, ill-typed properties. Reaches internals via @testable import. The helper is shared by
// Apple and Linux (DiffInput.swift), so these run on both.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import XCTest
@testable import ActionUIDiff
import ActionUI

/// Minimal logger that records what it is handed, so a test can assert a warning fired. No lock: the tests run
/// on the main actor and the code under test logs synchronously, on the caller's thread.
private final class RecordingLogger: ActionUILogger, @unchecked Sendable {
    private var entries: [(String, LoggerLevel)] = []

    func log(_ message: String, _ level: LoggerLevel) {
        entries.append((message, level))
    }

    var warnings: [String] {
        entries.filter { $0.1 == .warning }.map(\.0)
    }
}

@MainActor
final class DiffInputResolutionTests: XCTestCase {

    func testTextWinsOverFileAndWarns() {
        let logger = RecordingLogger()
        let resolved = Diff.resolveInput(text: "inline", file: "/some/path.swift", side: "old", logger: logger)
        XCTAssertEqual(resolved, .text("inline"), "the text property wins over the file property")
        XCTAssertTrue(logger.warnings.contains { $0.contains("both text and file set") },
                      "setting both text and file for a side must warn")
    }

    func testTextAloneDoesNotWarn() {
        let logger = RecordingLogger()
        XCTAssertEqual(Diff.resolveInput(text: "inline", file: nil, side: "old", logger: logger), .text("inline"))
        XCTAssertTrue(logger.warnings.isEmpty, "text with no file is the common case; no warning")
    }

    func testTildeExpansionResolvesToHome() {
        let logger = RecordingLogger()
        // The file does not exist, but the tilde must still expand to the home directory before
        // the read is attempted - the reported .unreadable path proves the expansion happened.
        let unique = "actionui-diff-tilde-\(UUID().uuidString)"
        let resolved = Diff.resolveInput(text: nil, file: "~/\(unique)", side: "old", logger: logger)
        guard case .unreadable(let path) = resolved else {
            return XCTFail("a missing file must resolve to .unreadable")
        }
        XCTAssertFalse(path.hasPrefix("~"), "the tilde must be expanded, not left literal")
        XCTAssertTrue(path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path), "the tilde must expand to the home directory")
        XCTAssertTrue(path.hasSuffix(unique))
    }

    func testTildeAloneAndWithASlashAreTheHomeWithoutATrailingSlash() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expected = home.count > 1 && home.hasSuffix("/") ? String(home.dropLast()) : home
        XCTAssertEqual(Diff.expandingTilde("~"), expected)
        XCTAssertEqual(Diff.expandingTilde("~/"), expected)
        XCTAssertEqual(Diff.expandingTilde("/a/~/b"), "/a/~/b", "only a leading tilde expands")
    }

    func testTildeWithAUserNameResolvesToThatUsersHome() throws {
        let logger = RecordingLogger()
        let home = try XCTUnwrap(FileManager.default.homeDirectory(forUser: "root")).path
        let resolved = Diff.resolveInput(text: nil, file: "~root/actionui-diff-\(UUID().uuidString)", side: "old", logger: logger)
        guard case .unreadable(let path) = resolved else {
            return XCTFail("a missing file must resolve to .unreadable")
        }
        XCTAssertTrue(path.hasPrefix(home + "/actionui-diff-"), "~root is root's home, \(home); got \(path)")
    }

    func testExistingFileIsReadAsText() throws {
        let logger = RecordingLogger()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("actionui-diff-\(UUID().uuidString).txt")
        try "line1\nline2\n".write(to: fileURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }
        let resolved = Diff.resolveInput(text: nil, file: fileURL.path, side: "new", logger: logger)
        XCTAssertEqual(resolved, .text("line1\nline2\n"))
    }

    func testALinkToAFileOverTheCapIsUnreadable() throws {
        let logger = RecordingLogger()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("actionui-diff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        let big = folder.appendingPathComponent("big.txt")
        try Data(repeating: 0x61, count: 4_194_305).write(to: big)
        let link = folder.appendingPathComponent("link.txt").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: big.path)
        XCTAssertEqual(Diff.resolveInput(text: nil, file: link, side: "old", logger: logger), .unreadable(path: link),
                       "the cap is the size of the file the link leads to, not of the link")
        XCTAssertTrue(logger.warnings.contains { $0.contains("over 4 MB") })
    }

    func testALinkToAFileUnderTheCapIsRead() throws {
        let logger = RecordingLogger()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("actionui-diff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        let small = folder.appendingPathComponent("small.txt")
        try "linked\n".write(to: small, atomically: true, encoding: .utf8)
        let link = folder.appendingPathComponent("link.txt").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: small.path)
        XCTAssertEqual(Diff.resolveInput(text: nil, file: link, side: "new", logger: logger), .text("linked\n"))
    }

    func testALinkToNothingIsUnreadable() throws {
        let logger = RecordingLogger()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("actionui-diff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        let link = folder.appendingPathComponent("dangling.txt").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: folder.appendingPathComponent("gone.txt").path)
        XCTAssertEqual(Diff.resolveInput(text: nil, file: link, side: "old", logger: logger), .unreadable(path: link))
        XCTAssertTrue(logger.warnings.contains { $0.contains("missing or over 4 MB") }, "refused as a missing file")
    }

    func testNonexistentFileYieldsUnreadableAndWarns() {
        let logger = RecordingLogger()
        let missing = "/definitely/not/here/\(UUID().uuidString).txt"
        let resolved = Diff.resolveInput(text: nil, file: missing, side: "old", logger: logger)
        guard case .unreadable = resolved else {
            return XCTFail("a missing file must resolve to .unreadable")
        }
        XCTAssertFalse(logger.warnings.isEmpty, "an unreadable file must warn")
    }

    func testNeitherTextNorFileYieldsEmptySide() {
        let logger = RecordingLogger()
        XCTAssertEqual(Diff.resolveInput(text: nil, file: nil, side: "old", logger: logger), .text(""),
                       "a side with neither text nor file is empty (a new-file / deleted-file diff)")
        XCTAssertTrue(logger.warnings.isEmpty)
    }
}

@MainActor
final class DiffRawPropertiesTests: XCTestCase {

    // buildView reads the raw properties: a side given with the wrong type is no side.
    func testIllTypedTextIsIgnored() {
        let logger = RecordingLogger()
        XCTAssertEqual(Diff.resolveInput(text: 42, file: nil, side: "new", logger: logger), .text(""))
        XCTAssertTrue(logger.warnings.isEmpty)
    }

    func testIllTypedTextFallsBackToTheFileWithoutTheBothSetWarning() {
        let logger = RecordingLogger()
        let missing = "/nonexistent-\(UUID().uuidString).swift"
        XCTAssertEqual(Diff.resolveInput(text: 42, file: missing, side: "old", logger: logger), .unreadable(path: missing))
        XCTAssertFalse(logger.warnings.contains { $0.contains("both text and file") })
    }

    func testIllTypedFileIsIgnored() {
        let logger = RecordingLogger()
        XCTAssertEqual(Diff.resolveInput(text: nil, file: 7, side: "old", logger: logger), .text(""))
    }

    // An ill-typed integer falls back to the default with one warning; a valid one is read.
    func testIllTypedIntegerFallsBackToTheDefault() {
        let logger = RecordingLogger()
        let properties: [String: Any] = ["contextLines": "three", "maxRenderedLines": 100]
        XCTAssertEqual(Diff.intProperty(properties, key: "contextLines", default: 3, minimum: 0, logger: logger), 3)
        XCTAssertEqual(Diff.intProperty(properties, key: "maxRenderedLines", default: 300, minimum: 1, logger: logger), 100)
        XCTAssertEqual(logger.warnings.count, 1, "one warning, for the ill-typed key")
    }
}
