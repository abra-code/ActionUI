// Core/Elements/DisclosureGroupPropsTests.swift
/*
 Tests for DisclosureGroup.Props: the title default, the initial expanded state and the action.
*/

import XCTest
@testable import ActionUI

final class DisclosureGroupPropsTests: XCTestCase {

    func testDefaults() {
        let props = DisclosureGroup.Props([:])
        XCTAssertEqual(props.title, "")
        XCTAssertFalse(props.isExpanded)
        XCTAssertNil(props.valueChangeActionID)
    }

    func testValidValues() {
        let props = DisclosureGroup.Props(["title": "Details", "isExpanded": true, "valueChangeActionID": "toggled"])
        XCTAssertEqual(props.title, "Details")
        XCTAssertTrue(props.isExpanded)
        XCTAssertEqual(props.valueChangeActionID, "toggled")
    }

    func testWrongTypesFallBack() {
        let props = DisclosureGroup.Props(["title": 5, "isExpanded": "yes", "valueChangeActionID": 5])
        XCTAssertEqual(props.title, "")
        XCTAssertFalse(props.isExpanded)
        XCTAssertNil(props.valueChangeActionID)
    }
}
