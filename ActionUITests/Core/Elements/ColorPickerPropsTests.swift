// Core/Elements/ColorPickerPropsTests.swift
/*
 Tests for ColorPicker.Props: the title default, the initial color as written and the action.
*/

import XCTest
@testable import ActionUI

final class ColorPickerPropsTests: XCTestCase {

    func testDefaults() {
        let props = ColorPicker.Props([:])
        XCTAssertEqual(props.title, "")
        XCTAssertNil(props.selectedColor)
        XCTAssertNil(props.actionID)
    }

    func testValidValues() {
        let props = ColorPicker.Props(["title": "Tint", "selectedColor": "#FF0000", "actionID": "picked"])
        XCTAssertEqual(props.title, "Tint")
        XCTAssertEqual(props.selectedColor, "#FF0000")
        XCTAssertEqual(props.actionID, "picked")
    }

    func testWrongTypesFallBack() {
        let props = ColorPicker.Props(["title": 5, "selectedColor": 5, "actionID": 5])
        XCTAssertEqual(props.title, "")
        XCTAssertNil(props.selectedColor)
        XCTAssertNil(props.actionID)
    }
}
