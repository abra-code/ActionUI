// Core/Elements/ShareLinkPropsTests.swift
/*
 Tests for ShareLink.Props: the item (kept only when it is a String that makes a URL), the subject
 and the message.
*/

import XCTest
@testable import ActionUI

final class ShareLinkPropsTests: XCTestCase {
    func testDefaults() {
        let props = ShareLink.Props([:])
        XCTAssertNil(props.item)
        XCTAssertNil(props.subject)
        XCTAssertNil(props.message)
    }

    func testValidValues() {
        let props = ShareLink.Props(["item": "https://example.com", "subject": "Check this out", "message": "Look!"])
        XCTAssertEqual(props.item, "https://example.com")
        XCTAssertEqual(props.subject, "Check this out")
        XCTAssertEqual(props.message, "Look!")
    }

    func testItemMustMakeAURL() {
        XCTAssertNil(ShareLink.Props(["item": ""]).item)
        XCTAssertNil(ShareLink.Props(["item": "http://[bad"]).item)
        XCTAssertEqual(ShareLink.Props(["item": "mailto:a@b.c"]).item, "mailto:a@b.c")
    }

    func testWrongTypesAreNone() {
        let props = ShareLink.Props(["item": 5, "subject": 6, "message": true])
        XCTAssertNil(props.item)
        XCTAssertNil(props.subject)
        XCTAssertNil(props.message)
    }
}
