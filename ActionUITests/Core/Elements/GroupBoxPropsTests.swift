// Core/Elements/GroupBoxPropsTests.swift
/*
 Tests for GroupBox.Props: the title.
*/

import XCTest
@testable import ActionUI

final class GroupBoxPropsTests: XCTestCase {

    func testDefaults() {
        XCTAssertNil(GroupBox.Props([:]).title)
    }

    func testValidValues() {
        XCTAssertEqual(GroupBox.Props(["title": "Options"]).title, "Options")
    }

    func testUnusableValuesFallBack() {
        XCTAssertNil(GroupBox.Props(["title": 5]).title)
    }
}
