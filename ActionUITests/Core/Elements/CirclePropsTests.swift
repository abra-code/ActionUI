// Core/Elements/CirclePropsTests.swift
/*
 Tests for Circle.Props: the fill and stroke color names and the stroke width.
*/

import XCTest
@testable import ActionUI

final class CirclePropsTests: XCTestCase {

    func testDefaults() {
        let props = Circle.Props([:])
        XCTAssertNil(props.fill)
        XCTAssertNil(props.stroke)
        XCTAssertEqual(props.strokeLineWidth, 1)
    }

    func testValidValues() {
        let props = Circle.Props(["fill": "blue", "stroke": "red", "strokeLineWidth": 3])
        XCTAssertEqual(props.fill, "blue")
        XCTAssertEqual(props.stroke, "red")
        XCTAssertEqual(props.strokeLineWidth, 3)
        XCTAssertEqual(Circle.Props(["strokeLineWidth": 2.5]).strokeLineWidth, 2.5)
    }

    func testUnusableValuesFallBack() {
        let props = Circle.Props(["fill": 5, "stroke": true, "strokeLineWidth": "thick"])
        XCTAssertNil(props.fill)
        XCTAssertNil(props.stroke)
        XCTAssertEqual(props.strokeLineWidth, 1)
    }
}
