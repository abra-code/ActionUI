// Core/Elements/SectionPropsTests.swift
/*
 Tests for Section.Props: the header.
*/

import XCTest
@testable import ActionUI

final class SectionPropsTests: XCTestCase {

    func testDefaults() {
        XCTAssertNil(Section.Props([:]).header)
    }

    func testValidValues() {
        XCTAssertEqual(Section.Props(["header": "General"]).header, "General")
    }

    func testUnusableValuesFallBack() {
        XCTAssertNil(Section.Props(["header": 5]).header)
    }
}
