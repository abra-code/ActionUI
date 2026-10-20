// Core/Elements/NavigationSplitViewPropsTests.swift
/*
 Tests for NavigationSplitView.Props: the column visibility, the style and the action fired when
 the user changes the visibility. An unknown name is "all" for the visibility and "automatic" for
 the style; no string at all is nil, which the renderer treats as nothing to apply.
*/

import XCTest
@testable import ActionUI

final class NavigationSplitViewPropsTests: XCTestCase {

    func testDefaults() {
        let props = NavigationSplitView.Props([:])
        XCTAssertNil(props.columnVisibility)
        XCTAssertNil(props.style)
        XCTAssertNil(props.valueChangeActionID)
    }

    func testValidValues() {
        let props = NavigationSplitView.Props(["columnVisibility": "doubleColumn", "style": "prominentDetail", "valueChangeActionID": "changed"])
        XCTAssertEqual(props.columnVisibility, .doubleColumn)
        XCTAssertEqual(props.style, .prominentDetail)
        XCTAssertEqual(props.valueChangeActionID, "changed")
    }

    func testEveryName() {
        for name in ["automatic", "all", "doubleColumn", "detail"] {
            XCTAssertEqual(NavigationSplitView.Props(["columnVisibility": name]).columnVisibility?.rawValue, name)
        }
        for name in ["automatic", "balanced", "prominentDetail"] {
            XCTAssertEqual(NavigationSplitView.Props(["style": name]).style?.rawValue, name)
        }
    }

    func testUnknownNamesAreTheirDefaults() {
        XCTAssertEqual(NavigationSplitView.Props(["columnVisibility": "sideways"]).columnVisibility, .all)
        XCTAssertEqual(NavigationSplitView.Props(["columnVisibility": ""]).columnVisibility, .all)
        XCTAssertEqual(NavigationSplitView.Props(["style": "wide"]).style, .automatic)
        XCTAssertEqual(NavigationSplitView.Props(["style": "Balanced"]).style, .automatic)
    }

    func testValuesThatAreNotStringsAreNil() {
        let props = NavigationSplitView.Props(["columnVisibility": 1, "style": 2, "valueChangeActionID": 3])
        XCTAssertNil(props.columnVisibility)
        XCTAssertNil(props.style)
        XCTAssertNil(props.valueChangeActionID)
    }
}
