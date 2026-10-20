// Core/Elements/MenuPropsTests.swift
/*
 Tests for Menu.Props: the title default.
*/

import XCTest
@testable import ActionUI

final class MenuPropsTests: XCTestCase {

    func testDefaults() {
        XCTAssertEqual(Menu.Props([:]).title, "")
    }

    func testValidValues() {
        XCTAssertEqual(Menu.Props(["title": "File"]).title, "File")
    }

    func testWrongTypeFallsBack() {
        XCTAssertEqual(Menu.Props(["title": 5]).title, "")
    }
}
