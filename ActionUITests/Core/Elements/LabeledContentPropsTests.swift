// Core/Elements/LabeledContentPropsTests.swift
/*
 Tests for LabeledContent.Props: the title default.
*/

import XCTest
@testable import ActionUI

final class LabeledContentPropsTests: XCTestCase {

    func testDefaults() {
        XCTAssertEqual(LabeledContent.Props([:]).title, "")
    }

    func testValidValues() {
        XCTAssertEqual(LabeledContent.Props(["title": "Username"]).title, "Username")
    }

    func testWrongTypeFallsBack() {
        XCTAssertEqual(LabeledContent.Props(["title": 5]).title, "")
    }
}
