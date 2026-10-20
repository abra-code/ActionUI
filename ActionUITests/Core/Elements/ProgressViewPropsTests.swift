// Core/Elements/ProgressViewPropsTests.swift
/*
 Tests for ProgressView.Props: value and total guards (negative value and non-positive total are none), the style names and the action.
*/

import XCTest
@testable import ActionUI

final class ProgressViewPropsTests: XCTestCase {

    func testDefaults() {
        let props = ProgressView.Props([:])
        XCTAssertNil(props.value)
        XCTAssertNil(props.total)
        XCTAssertNil(props.title)
        XCTAssertNil(props.style)
        XCTAssertNil(props.actionID)
    }

    func testValidValues() {
        let props = ProgressView.Props(["value": 3, "total": 10.5, "title": "Loading", "progressViewStyle": "linear", "actionID": "tapped"])
        XCTAssertEqual(props.value, 3)
        XCTAssertEqual(props.total, 10.5)
        XCTAssertEqual(props.title, "Loading")
        XCTAssertEqual(props.style, .linear)
        XCTAssertEqual(props.actionID, "tapped")
    }

    func testValueThatIsNegativeOrNotANumberIsNone() {
        XCTAssertNil(ProgressView.Props(["value": -1]).value)
        XCTAssertNil(ProgressView.Props(["value": "half"]).value)
        XCTAssertEqual(ProgressView.Props(["value": 0]).value, 0)
    }

    func testTotalThatIsNotPositiveIsNone() {
        // The renderer then uses 1.0 when there is a value, and none otherwise.
        XCTAssertNil(ProgressView.Props(["total": 0]).total)
        XCTAssertNil(ProgressView.Props(["total": -2]).total)
        XCTAssertNil(ProgressView.Props(["total": "all"]).total)
        XCTAssertEqual(ProgressView.Props(["value": 0, "total": 0.5]).total, 0.5)
    }

    func testStyleNames() {
        XCTAssertEqual(ProgressView.Props(["progressViewStyle": "automatic"]).style, .automatic)
        XCTAssertEqual(ProgressView.Props(["progressViewStyle": "circular"]).style, .circular)
        XCTAssertNil(ProgressView.Props(["progressViewStyle": "bar"]).style)
        XCTAssertNil(ProgressView.Props(["progressViewStyle": 5]).style)
    }

    func testWrongTypesFallBack() {
        let props = ProgressView.Props(["title": 5, "actionID": 5])
        XCTAssertNil(props.title)
        XCTAssertNil(props.actionID)
    }
}
