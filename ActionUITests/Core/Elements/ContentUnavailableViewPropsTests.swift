// Core/Elements/ContentUnavailableViewPropsTests.swift
/*
 Tests for ContentUnavailableView.Props: the title default, the optional image and description, and the search variant with its query.
*/

import XCTest
@testable import ActionUI

final class ContentUnavailableViewPropsTests: XCTestCase {

    func testDefaults() {
        let props = ContentUnavailableView.Props([:])
        XCTAssertEqual(props.title, "No Content")
        XCTAssertNil(props.systemImage)
        XCTAssertNil(props.description)
        XCTAssertFalse(props.search)
        XCTAssertEqual(props.query, "")
    }

    func testValidValues() {
        let props = ContentUnavailableView.Props([
            "title": "Empty", "systemImage": "tray", "description": "Nothing here", "search": true, "query": "cats",
        ])
        XCTAssertEqual(props.title, "Empty")
        XCTAssertEqual(props.systemImage, "tray")
        XCTAssertEqual(props.description, "Nothing here")
        XCTAssertTrue(props.search)
        XCTAssertEqual(props.query, "cats")
    }

    func testWrongTypesFallBack() {
        let props = ContentUnavailableView.Props(["title": 5, "systemImage": 5, "description": 5, "search": "yes", "query": 5])
        XCTAssertEqual(props.title, "No Content")
        XCTAssertNil(props.systemImage)
        XCTAssertNil(props.description)
        XCTAssertFalse(props.search)
        XCTAssertEqual(props.query, "")
    }
}
