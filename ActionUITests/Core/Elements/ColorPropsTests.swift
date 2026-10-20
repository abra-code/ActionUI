// Core/Elements/ColorPropsTests.swift
/*
 Tests for Color.Props: the color name. (The runtime override lives in the value, not in the properties.)
*/

import XCTest
@testable import ActionUI

final class ColorPropsTests: XCTestCase {

    func testDefaults() {
        XCTAssertNil(Color.Props([:]).color)
    }

    func testValidValues() {
        XCTAssertEqual(Color.Props(["color": "red"]).color, "red")
        // Resolving the name, and what an empty one means, is the renderer's job.
        XCTAssertEqual(Color.Props(["color": ""]).color, "")
    }

    func testUnusableValuesFallBack() {
        XCTAssertNil(Color.Props(["color": 5]).color)
        XCTAssertNil(Color.Props(["color": ["r": 1]]).color)
    }
}
