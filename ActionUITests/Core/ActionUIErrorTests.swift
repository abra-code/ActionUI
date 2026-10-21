// Core/ActionUIErrorTests.swift
/*
 Tests for ActionUIError: every way a host reads its text gives the message, as the NSError it
 replaced gave through localizedDescription.
*/

import Foundation
import XCTest
@testable import ActionUI

@MainActor
final class ActionUIErrorTests: XCTestCase {

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
    }
}
