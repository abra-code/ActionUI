// Core/Elements/SpacerPropsTests.swift
/*
 Tests for Spacer.Props: the minimum length.
*/

import XCTest
@testable import ActionUI

final class SpacerPropsTests: XCTestCase {

    func testDefaults() {
        XCTAssertNil(Spacer.Props([:]).minLength)
    }

    func testValidValues() {
        XCTAssertEqual(Spacer.Props(["minLength": 20]).minLength, 20)
        XCTAssertEqual(Spacer.Props(["minLength": 20.5]).minLength, 20.5)
        XCTAssertEqual(Spacer.Props(["minLength": "inf"]).minLength, .infinity)
    }

    func testUnusableValuesFallBack() {
        XCTAssertNil(Spacer.Props(["minLength": "20"]).minLength)
        XCTAssertNil(Spacer.Props(["minLength": true]).minLength)
    }
}
