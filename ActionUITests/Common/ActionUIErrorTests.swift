// Tests/Common/ActionUIErrorTests.swift
/*
 Tests for ActionUIError: every way a host reads its text gives the message, as the NSError it
 replaced gave through localizedDescription. And a JSON parse failure's localizedDescription, as
 JSONDecoder's DecodingError gave it.
*/

import Foundation
import XCTest
@testable import ActionUI

/// Records what the loads log: the failures here are expected, and the shared logger another test
/// class left behind (an XCTestLogger fails a test on any error) is not this class's to rely on.
private final class RecordingLogger: ActionUILogger, @unchecked Sendable {
    private(set) var errors: [String] = []
    func log(_ message: String, _ level: LoggerLevel) {
        if level == .error { errors.append(message) }
    }
}

@MainActor
final class ActionUIErrorTests: XCTestCase {
    private var savedLogger: (any ActionUILogger)!
    private var logger: RecordingLogger!

    override func setUp() async throws {
        try await super.setUp()
        savedLogger = ActionUIModel.shared.logger
        logger = RecordingLogger()
        ActionUIModel.shared.logger = logger
    }

    override func tearDown() async throws {
        ActionUIModel.shared.logger = savedLogger
        savedLogger = nil
        logger = nil
        try await super.tearDown()
    }

    func testEveryReadingOfTheTextIsTheMessage() {
        let error: any Error = ActionUIError("Unsupported format: yaml")
        XCTAssertEqual("\(error)", "Unsupported format: yaml")
        XCTAssertEqual(error.localizedDescription, "Unsupported format: yaml")
        XCTAssertEqual((error as NSError).localizedDescription, "Unsupported format: yaml",
                       "Objective-C hosts get the error as an NSError")
    }

    func testAnUnsupportedFormatThrowsActionUIError() throws {
        ActionUIModel.resetForTesting()
        defer { ActionUIModel.resetForTesting() }
        let data = Data(#"{"type": "Text"}"#.utf8)
        XCTAssertThrowsError(try ActionUIModel.shared.loadDescription(from: data, format: "yaml", windowUUID: UUID().uuidString)) { error in
            XCTAssertEqual((error as? ActionUIError)?.message, "Unsupported format: yaml")
            XCTAssertEqual(error.localizedDescription, "Unsupported format: yaml")
        }
        XCTAssertEqual(logger.errors, ["Unsupported format: yaml"])
    }

    // ActionUI JSON that does not parse reads as it did when JSONDecoder parsed it, in a
    // LoadableView's "Failed to load view: ..." among others; the parser's own message stays the
    // description.
    func testJSONThatDoesNotParseHasJSONDecodersDescription() throws {
        ActionUIModel.resetForTesting()
        defer { ActionUIModel.resetForTesting() }
        XCTAssertThrowsError(try ActionUIModel.shared.loadDescription(from: Data("not json".utf8), format: "json", windowUUID: UUID().uuidString)) { error in
            XCTAssertEqual(error.localizedDescription, "The data couldn't be read because it isn't in the correct format.")
            XCTAssertEqual("\(error)", "Unexpected character at byte 0")
        }
    }
}
