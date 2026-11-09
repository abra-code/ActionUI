// Core/Elements/TextEditorPropsTests.swift
/*
 Tests for TextEditor.Props: the text and markdown sources (the initial value prefers text, then markdown), placeholder, readOnly, the implementation and the action.
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
        XCTAssertEqual(props.implementation, .swiftUI)
        XCTAssertNil(props.valueChangeActionID)
    }

    func testImplementation() {
        XCTAssertEqual(TextEditor.Props(["implementation": "native"]).implementation, .native)
        XCTAssertEqual(TextEditor.Props(["implementation": "swiftUI"]).implementation, .swiftUI)
        XCTAssertEqual(TextEditor.Props(["implementation": "NSTextView"]).implementation, .swiftUI, "an unknown value is the default")
        XCTAssertEqual(TextEditor.Props(["implementation": true]).implementation, .swiftUI)
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
