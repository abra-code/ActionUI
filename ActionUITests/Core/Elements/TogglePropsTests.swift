// Core/Elements/TogglePropsTests.swift
/*
 Tests for Toggle.Props: the initial state, the title default, the style names, the action.
*/

import XCTest
@testable import ActionUI

final class TogglePropsTests: XCTestCase {

    func testDefaults() {
        let props = Toggle.Props([:])
        XCTAssertNil(props.isOn)
        XCTAssertEqual(props.title, "Toggle")
        XCTAssertNil(props.style)
        XCTAssertNil(props.actionID)
    }

    func testValidValues() {
        let props = Toggle.Props(["isOn": true, "title": "Enable", "style": "button", "actionID": "toggled"])
        XCTAssertEqual(props.isOn, true)
        XCTAssertEqual(props.title, "Enable")
        XCTAssertEqual(props.style, .button)
        XCTAssertEqual(props.actionID, "toggled")
    }

    func testIsOnMustBeABool() {
        XCTAssertNil(Toggle.Props(["isOn": "true"]).isOn)
        XCTAssertNil(Toggle.Props(["isOn": 1]).isOn)
        XCTAssertEqual(Toggle.Props(["isOn": false]).isOn, false)
    }

    func testWrongTypesFallBack() {
        let props = Toggle.Props(["title": 5, "style": 5, "actionID": 5])
        XCTAssertEqual(props.title, "Toggle")
        XCTAssertNil(props.style)
        XCTAssertNil(props.actionID)
    }

    func testStyleNames() {
        for style in Toggle.Props.Style.allCases {
            XCTAssertEqual(Toggle.Props(["style": style.rawValue]).style, style)
        }
        XCTAssertNil(Toggle.Props(["style": "fancy"]).style)
    }
}
