// Core/Elements/VStackPropsTests.swift
/*
 Tests for VStack.Props: spacing and horizontal alignment, with their defaults.
*/

import XCTest
@testable import ActionUI

final class VStackPropsTests: XCTestCase {

    func testDefaults() {
        let props = VStack.Props([:])
        XCTAssertEqual(props.spacing, 0)
        XCTAssertEqual(props.alignment, .center)
    }

    func testValidValues() {
        XCTAssertEqual(VStack.Props(["spacing": 10]).spacing, 10)
        XCTAssertEqual(VStack.Props(["spacing": 10.5]).spacing, 10.5)
        for alignment in VStack.Props.Alignment.allCases {
            XCTAssertEqual(VStack.Props(["alignment": alignment.rawValue]).alignment, alignment)
        }
    }

    func testUnusableValuesFallBack() {
        XCTAssertEqual(VStack.Props(["spacing": "10"]).spacing, 0)
        XCTAssertEqual(VStack.Props(["alignment": "top"]).alignment, .center)
        XCTAssertEqual(VStack.Props(["alignment": 5]).alignment, .center)
    }
}
