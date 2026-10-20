// Core/Elements/CapsulePropsTests.swift
/*
 Tests for Capsule.Props: the corner style, the fill and stroke color names and the stroke width.
*/

import XCTest
@testable import ActionUI

final class CapsulePropsTests: XCTestCase {

    func testDefaults() {
        let props = Capsule.Props([:])
        XCTAssertEqual(props.style, .circular)
        XCTAssertNil(props.fill)
        XCTAssertNil(props.stroke)
        XCTAssertEqual(props.strokeLineWidth, 1)
    }

    func testValidValues() {
        for style in Capsule.Props.Style.allCases {
            XCTAssertEqual(Capsule.Props(["style": style.rawValue]).style, style)
        }
        let props = Capsule.Props(["fill": "blue", "stroke": "red", "strokeLineWidth": 3])
        XCTAssertEqual(props.fill, "blue")
        XCTAssertEqual(props.stroke, "red")
        XCTAssertEqual(props.strokeLineWidth, 3)
    }

    func testUnusableValuesFallBack() {
        XCTAssertEqual(Capsule.Props(["style": "round"]).style, .circular)
        XCTAssertEqual(Capsule.Props(["style": 5]).style, .circular)
        let props = Capsule.Props(["fill": 5, "stroke": true, "strokeLineWidth": "thick"])
        XCTAssertNil(props.fill)
        XCTAssertNil(props.stroke)
        XCTAssertEqual(props.strokeLineWidth, 1)
    }
}
