// Add-ons/ActionUIDiff/Tests/DiffElementTests.swift
//
// Element-level tests of the ActionUIDiff add-on: the Diff wrapper's input-resolution
// helper (text wins over file, tilde expansion, missing / unreadable files, empty sides)
// and its property validation. Reaches internals via @testable import.

import XCTest
@testable import ActionUIDiff
import ActionUI

/// Minimal logger that records what it is handed, so a test can assert a warning fired.
private final class RecordingLogger: ActionUILogger, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(String, LoggerLevel)] = []

    func log(_ message: String, _ level: LoggerLevel) {
        lock.withLock { entries.append((message, level)) }
    }

    var warnings: [String] {
        lock.withLock { entries.filter { $0.1 == .warning }.map(\.0) }
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
        XCTAssertTrue(path.hasPrefix(NSHomeDirectory()), "the tilde must expand to the home directory")
        XCTAssertTrue(path.hasSuffix(unique))
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
final class DiffValidatePropertiesTests: XCTestCase {

    func testDropsIllTypedKeys() {
        let logger = RecordingLogger()
        let input: [String: Any] = [
            "oldText": "ok",
            "newText": 42,            // ill-typed: not a String
            "contextLines": "three",  // ill-typed: not an Int
            "maxRenderedLines": 300   // valid
        ]
        let validated = Diff.validateProperties(input, logger)
        XCTAssertEqual(validated["oldText"] as? String, "ok")
        XCTAssertNil(validated["newText"], "a non-String newText must be dropped")
        XCTAssertNil(validated["contextLines"], "a non-Int contextLines must be dropped")
        XCTAssertEqual(validated["maxRenderedLines"] as? Int, 300)
        XCTAssertEqual(logger.warnings.count, 2, "one warning per dropped key")
    }

    func testValidInputPassesThroughUnchanged() {
        let logger = RecordingLogger()
        let input: [String: Any] = [
            "oldText": "a",
            "newFile": "~/after.swift",
            "contextLines": 2,
            "maxRenderedLines": 100
        ]
        let validated = Diff.validateProperties(input, logger)
        XCTAssertEqual(validated["oldText"] as? String, "a")
        XCTAssertEqual(validated["newFile"] as? String, "~/after.swift")
        XCTAssertEqual(validated["contextLines"] as? Int, 2)
        XCTAssertEqual(validated["maxRenderedLines"] as? Int, 100)
        XCTAssertTrue(logger.warnings.isEmpty)
    }
}
