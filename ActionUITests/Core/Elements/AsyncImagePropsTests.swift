// Core/Elements/AsyncImagePropsTests.swift
/*
 Tests for AsyncImage.Props: the url, the placeholder and resizable defaults, and the content mode (only "fill" fills).
*/

import XCTest
@testable import ActionUI

final class AsyncImagePropsTests: XCTestCase {

    func testDefaults() {
        let props = AsyncImage.Props([:])
        XCTAssertNil(props.url)
        XCTAssertEqual(props.placeholder, "photo")
        XCTAssertTrue(props.resizable)
        XCTAssertEqual(props.contentMode, .fit)
    }

    func testValidValues() {
        let props = AsyncImage.Props([
            "url": "https://example.com/a.jpg", "placeholder": "star", "resizable": false, "contentMode": "fill",
        ])
        XCTAssertEqual(props.url, "https://example.com/a.jpg")
        XCTAssertEqual(props.placeholder, "star")
        XCTAssertFalse(props.resizable)
        XCTAssertEqual(props.contentMode, .fill)
    }

    func testAnythingButFillIsFit() {
        XCTAssertEqual(AsyncImage.Props(["contentMode": "fit"]).contentMode, .fit)
        XCTAssertEqual(AsyncImage.Props(["contentMode": "stretch"]).contentMode, .fit)
        XCTAssertEqual(AsyncImage.Props(["contentMode": 5]).contentMode, .fit)
        XCTAssertEqual(AsyncImage.Props(["contentMode": "Fill"]).contentMode, .fit)
    }

    func testWrongTypesFallBack() {
        let props = AsyncImage.Props(["url": 5, "placeholder": 5, "resizable": "no"])
        XCTAssertNil(props.url)
        XCTAssertEqual(props.placeholder, "photo")
        XCTAssertTrue(props.resizable)
    }
}
