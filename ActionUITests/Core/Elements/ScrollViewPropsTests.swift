// Core/Elements/ScrollViewPropsTests.swift
/*
 Tests for ScrollView.Props: the axis, the scroll indicators and the pull-to-refresh action. The
 indicators default to shown and are always applied, so a nested view does not inherit hidden ones
 from an enclosing scroll view.
*/

import XCTest
@testable import ActionUI

final class ScrollViewPropsTests: XCTestCase {

    func testDefaults() {
        let props = ScrollView.Props([:])
        XCTAssertEqual(props.axis, .vertical)
        XCTAssertTrue(props.showsIndicators)
        XCTAssertNil(props.onRefreshActionID)
    }

    func testValidValues() {
        let props = ScrollView.Props(["axis": "both", "showsIndicators": false, "onRefreshActionID": "refresh"])
        XCTAssertEqual(props.axis, .both)
        XCTAssertFalse(props.showsIndicators)
        XCTAssertEqual(props.onRefreshActionID, "refresh")
    }

    func testEveryAxisName() {
        for name in ["vertical", "horizontal", "both"] {
            XCTAssertEqual(ScrollView.Props(["axis": name]).axis.rawValue, name)
        }
    }

    func testAxisThatIsUnknownOrNotAStringIsVertical() {
        XCTAssertEqual(ScrollView.Props(["axis": "diagonal"]).axis, .vertical)
        XCTAssertEqual(ScrollView.Props(["axis": "Horizontal"]).axis, .vertical)
        XCTAssertEqual(ScrollView.Props(["axis": 1]).axis, .vertical)
    }

    func testShowsIndicatorsThatIsNotABoolIsTrue() {
        XCTAssertTrue(ScrollView.Props(["showsIndicators": "false"]).showsIndicators)
        XCTAssertTrue(ScrollView.Props(["showsIndicators": 0]).showsIndicators)
        XCTAssertTrue(ScrollView.Props(["showsIndicators": true]).showsIndicators)
    }

    func testRefreshActionThatIsNotAStringIsNil() {
        XCTAssertNil(ScrollView.Props(["onRefreshActionID": 5]).onRefreshActionID)
    }
}
