// Core/Elements/ZStackPropsTests.swift
/*
 Tests for ZStack.Props: the alignment, with its default.
*/

import XCTest
@testable import ActionUI

final class ZStackPropsTests: XCTestCase {

    func testDefaults() {
        XCTAssertEqual(ZStack.Props([:]).alignment, .center)
    }

    func testValidValues() {
        for alignment in ZStack.Props.Alignment.allCases {
            XCTAssertEqual(ZStack.Props(["alignment": alignment.rawValue]).alignment, alignment)
        }
    }

    func testUnusableValuesFallBack() {
        XCTAssertEqual(ZStack.Props(["alignment": "middle"]).alignment, .center)
        XCTAssertEqual(ZStack.Props(["alignment": 5]).alignment, .center)
    }
}
