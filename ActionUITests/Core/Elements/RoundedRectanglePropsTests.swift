// Core/Elements/RoundedRectanglePropsTests.swift
/*
 Tests for RoundedRectangle.Props: the corner radius and style, the fill and stroke color names and the stroke width.
*/

import XCTest
@testable import ActionUI

final class RoundedRectanglePropsTests: XCTestCase {

    func testDefaults() {
        let props = RoundedRectangle.Props([:])
        XCTAssertEqual(props.cornerRadius, 0)
        XCTAssertEqual(props.cornerStyle, .circular)
        XCTAssertNil(props.fill)
        XCTAssertNil(props.stroke)
        XCTAssertEqual(props.strokeLineWidth, 1)
    }

    func testValidValues() {
        XCTAssertEqual(RoundedRectangle.Props(["cornerRadius": 8]).cornerRadius, 8)
        XCTAssertEqual(RoundedRectangle.Props(["cornerRadius": 8.5]).cornerRadius, 8.5)
        for style in RoundedRectangle.Props.CornerStyle.allCases {
            XCTAssertEqual(RoundedRectangle.Props(["cornerStyle": style.rawValue]).cornerStyle, style)
        }
        let props = RoundedRectangle.Props(["fill": "blue", "stroke": "red", "strokeLineWidth": 3])
        XCTAssertEqual(props.fill, "blue")
        XCTAssertEqual(props.stroke, "red")
        XCTAssertEqual(props.strokeLineWidth, 3)
    }

    func testUnusableValuesFallBack() {
        XCTAssertEqual(RoundedRectangle.Props(["cornerRadius": "8"]).cornerRadius, 0)
        XCTAssertEqual(RoundedRectangle.Props(["cornerStyle": "round"]).cornerStyle, .circular)
        XCTAssertEqual(RoundedRectangle.Props(["cornerStyle": 5]).cornerStyle, .circular)
        let props = RoundedRectangle.Props(["fill": 5, "stroke": true, "strokeLineWidth": "thick"])
        XCTAssertNil(props.fill)
        XCTAssertNil(props.stroke)
        XCTAssertEqual(props.strokeLineWidth, 1)
    }
}
