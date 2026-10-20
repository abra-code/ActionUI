// Core/Elements/RectanglePropsTests.swift
/*
 Tests for Rectangle.Props: the fill and stroke color names and the stroke width.
*/

import XCTest
@testable import ActionUI

final class RectanglePropsTests: XCTestCase {

    func testDefaults() {
        let props = Rectangle.Props([:])
        XCTAssertNil(props.fill)
        XCTAssertNil(props.stroke)
        XCTAssertEqual(props.strokeLineWidth, 1)
    }

    func testValidValues() {
        let props = Rectangle.Props(["fill": "blue", "stroke": "red", "strokeLineWidth": 3])
        XCTAssertEqual(props.fill, "blue")
        XCTAssertEqual(props.stroke, "red")
        XCTAssertEqual(props.strokeLineWidth, 3)
        XCTAssertEqual(Rectangle.Props(["strokeLineWidth": 2.5]).strokeLineWidth, 2.5)
    }

    func testUnusableValuesFallBack() {
        let props = Rectangle.Props(["fill": 5, "stroke": true, "strokeLineWidth": "thick"])
        XCTAssertNil(props.fill)
        XCTAssertNil(props.stroke)
        XCTAssertEqual(props.strokeLineWidth, 1)
    }
}
