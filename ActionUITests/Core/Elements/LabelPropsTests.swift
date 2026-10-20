// Core/Elements/LabelPropsTests.swift
/*
 Tests for Label.Props: the title default and the two image keys.
*/

import XCTest
@testable import ActionUI

final class LabelPropsTests: XCTestCase {

    func testDefaults() {
        let props = Label.Props([:])
        XCTAssertEqual(props.title, "")
        XCTAssertNil(props.systemImage)
        XCTAssertNil(props.imageName)
    }

    func testValidValues() {
        let props = Label.Props(["title": "Star", "systemImage": "star.fill", "imageName": "custom"])
        XCTAssertEqual(props.title, "Star")
        XCTAssertEqual(props.systemImage, "star.fill")
        XCTAssertEqual(props.imageName, "custom")
    }

    func testWrongTypesFallBack() {
        let props = Label.Props(["title": 5, "systemImage": 5, "imageName": true])
        XCTAssertEqual(props.title, "")
        XCTAssertNil(props.systemImage)
        XCTAssertNil(props.imageName)
    }
}
