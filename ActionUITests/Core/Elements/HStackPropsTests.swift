// Core/Elements/HStackPropsTests.swift
/*
 Tests for HStack.Props: spacing (absent: the system's default) and vertical alignment, with its default.
*/

import XCTest
@testable import ActionUI

final class HStackPropsTests: XCTestCase {

    func testDefaults() {
        let props = HStack.Props([:])
        XCTAssertNil(props.spacing)
        XCTAssertEqual(props.alignment, .center)
    }

    func testValidValues() {
        XCTAssertEqual(HStack.Props(["spacing": 10]).spacing, 10)
        XCTAssertEqual(HStack.Props(["spacing": 10.5]).spacing, 10.5)
        XCTAssertEqual(HStack.Props(["spacing": 0]).spacing, 0)
        XCTAssertEqual(HStack.Props(["spacing": "inf"]).spacing, .infinity)
        for alignment in HStack.Props.Alignment.allCases {
            XCTAssertEqual(HStack.Props(["alignment": alignment.rawValue]).alignment, alignment)
        }
    }

    func testUnusableValuesFallBack() {
        XCTAssertNil(HStack.Props(["spacing": "10"]).spacing)
        XCTAssertNil(HStack.Props(["spacing": true]).spacing)
        XCTAssertEqual(HStack.Props(["alignment": "leading"]).alignment, .center)
        XCTAssertEqual(HStack.Props(["alignment": 5]).alignment, .center)
    }
}
