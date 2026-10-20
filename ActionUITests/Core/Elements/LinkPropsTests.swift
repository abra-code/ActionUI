// Core/Elements/LinkPropsTests.swift
/*
 Tests for Link.Props: the title default ("Link") and the destination as written.
*/

import XCTest
@testable import ActionUI

final class LinkPropsTests: XCTestCase {

    func testDefaults() {
        let props = Link.Props([:])
        XCTAssertEqual(props.title, "Link")
        XCTAssertNil(props.url)
    }

    func testValidValues() {
        let props = Link.Props(["title": "Visit", "url": "https://example.com"])
        XCTAssertEqual(props.title, "Visit")
        XCTAssertEqual(props.url, "https://example.com")
    }

    func testWrongTypesFallBack() {
        let props = Link.Props(["title": 5, "url": 5])
        XCTAssertEqual(props.title, "Link")
        XCTAssertNil(props.url)
    }
}
