// Core/Elements/ControlGroupPropsTests.swift
/*
 Tests for ControlGroup.Props: the optional title.
*/

import XCTest
@testable import ActionUI

final class ControlGroupPropsTests: XCTestCase {

    func testDefaults() {
        XCTAssertNil(ControlGroup.Props([:]).title)
    }

    func testValidValues() {
        XCTAssertEqual(ControlGroup.Props(["title": "Actions"]).title, "Actions")
        XCTAssertEqual(ControlGroup.Props(["title": ""]).title, "")
    }

    func testWrongTypeFallsBack() {
        XCTAssertNil(ControlGroup.Props(["title": 5]).title)
    }
}
