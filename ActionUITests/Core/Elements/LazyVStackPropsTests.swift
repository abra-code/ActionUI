// Core/Elements/LazyVStackPropsTests.swift
/*
 Tests for LazyVStack.Props: spacing and alignment (leading, center and trailing), with their defaults.
*/

import XCTest
@testable import ActionUI

final class LazyVStackPropsTests: XCTestCase {

    func testDefaults() {
        let props = LazyVStack.Props([:])
        XCTAssertEqual(props.spacing, 0)
        XCTAssertEqual(props.alignment, .center)
    }

    func testValidValues() {
        XCTAssertEqual(LazyVStack.Props(["spacing": 10]).spacing, 10)
        XCTAssertEqual(LazyVStack.Props(["spacing": 10.5]).spacing, 10.5)
        XCTAssertEqual(LazyVStack.Props(["spacing": "inf"]).spacing, .infinity)
        for alignment in LazyVStack.Props.Alignment.allCases {
            XCTAssertEqual(LazyVStack.Props(["alignment": alignment.rawValue]).alignment, alignment)
        }
    }

    func testUnusableValuesFallBack() {
        XCTAssertEqual(LazyVStack.Props(["spacing": "10"]).spacing, 0)
        XCTAssertEqual(LazyVStack.Props(["spacing": true]).spacing, 0)
        XCTAssertEqual(LazyVStack.Props(["alignment": "top"]).alignment, .center)
        XCTAssertEqual(LazyVStack.Props(["alignment": 5]).alignment, .center)
    }
}
