// Core/Elements/TextPropsTests.swift
/*
 Tests for Text.Props: the plain text, the markdown source and which one the renderer prefers (markdown), wrong types.
*/

import XCTest
@testable import ActionUI

final class TextPropsTests: XCTestCase {

    func testDefaults() {
        let props = Text.Props([:])
        XCTAssertEqual(props.text, "")
        XCTAssertNil(props.markdown)
    }

    func testValidValues() {
        let props = Text.Props(["text": "Hello", "markdown": "**Bold**"])
        XCTAssertEqual(props.text, "Hello")
        XCTAssertEqual(props.markdown, "**Bold**")
    }

    func testWrongTypesFallBack() {
        let props = Text.Props(["text": 5, "markdown": 5])
        XCTAssertEqual(props.text, "")
        XCTAssertNil(props.markdown)
    }
}
