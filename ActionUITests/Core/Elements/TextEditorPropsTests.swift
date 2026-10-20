// Core/Elements/TextEditorPropsTests.swift
/*
 Tests for TextEditor.Props: the text and markdown sources (the initial value prefers text, then markdown), placeholder, readOnly and the action.
*/

import XCTest
@testable import ActionUI

final class TextEditorPropsTests: XCTestCase {

    func testDefaults() {
        let props = TextEditor.Props([:])
        XCTAssertNil(props.text)
        XCTAssertNil(props.markdown)
        XCTAssertNil(props.placeholder)
        XCTAssertFalse(props.readOnly)
        XCTAssertNil(props.valueChangeActionID)
    }

    func testValidValues() {
        let props = TextEditor.Props([
            "text": "Hello", "markdown": "**Hi**", "placeholder": "Type", "readOnly": true, "valueChangeActionID": "changed",
        ])
        XCTAssertEqual(props.text, "Hello")
        XCTAssertEqual(props.markdown, "**Hi**")
        XCTAssertEqual(props.placeholder, "Type")
        XCTAssertTrue(props.readOnly)
        XCTAssertEqual(props.valueChangeActionID, "changed")
    }

    func testWrongTypesFallBack() {
        let props = TextEditor.Props(["text": 5, "markdown": 5, "placeholder": 5, "readOnly": "yes", "valueChangeActionID": 5])
        XCTAssertNil(props.text)
        XCTAssertNil(props.markdown)
        XCTAssertNil(props.placeholder)
        XCTAssertFalse(props.readOnly)
        XCTAssertNil(props.valueChangeActionID)
    }
}
