// Core/Elements/LazyHStackPropsTests.swift
/*
 Tests for LazyHStack.Props: spacing and alignment (top, center and bottom), with their defaults.
*/

import XCTest
@testable import ActionUI

final class LazyHStackPropsTests: XCTestCase {

    func testDefaults() {
        let props = LazyHStack.Props([:])
        XCTAssertEqual(props.spacing, 0)
        XCTAssertEqual(props.alignment, .center)
    }

    func testValidValues() {
        XCTAssertEqual(LazyHStack.Props(["spacing": 10]).spacing, 10)
        XCTAssertEqual(LazyHStack.Props(["spacing": 10.5]).spacing, 10.5)
        XCTAssertEqual(LazyHStack.Props(["spacing": "inf"]).spacing, .infinity)
        for alignment in LazyHStack.Props.Alignment.allCases {
            XCTAssertEqual(LazyHStack.Props(["alignment": alignment.rawValue]).alignment, alignment)
        }
    }

    func testUnusableValuesFallBack() {
        XCTAssertEqual(LazyHStack.Props(["spacing": "10"]).spacing, 0)
        XCTAssertEqual(LazyHStack.Props(["spacing": true]).spacing, 0)
        XCTAssertEqual(LazyHStack.Props(["alignment": "leading"]).alignment, .center)
        XCTAssertEqual(LazyHStack.Props(["alignment": 5]).alignment, .center)
    }
}
