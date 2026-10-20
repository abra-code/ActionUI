// Core/Elements/SecureFieldPropsTests.swift
/*
 Tests for SecureField.Props: the title and text defaults, the prompt, the secure-only content types and the action keys.
*/

import XCTest
@testable import ActionUI

final class SecureFieldPropsTests: XCTestCase {

    func testDefaults() {
        let props = SecureField.Props([:])
        XCTAssertEqual(props.title, "")
        XCTAssertNil(props.prompt)
        XCTAssertEqual(props.text, "")
        XCTAssertNil(props.textContentType)
        XCTAssertNil(props.actionID)
        XCTAssertNil(props.valueChangeActionID)
    }

    func testValidValues() {
        let props = SecureField.Props([
            "title": "Password", "prompt": "Enter", "text": "secret", "textContentType": "newPassword",
            "actionID": "submit", "valueChangeActionID": "changed",
        ])
        XCTAssertEqual(props.title, "Password")
        XCTAssertEqual(props.prompt, "Enter")
        XCTAssertEqual(props.text, "secret")
        XCTAssertEqual(props.textContentType, .newPassword)
        XCTAssertEqual(props.actionID, "submit")
        XCTAssertEqual(props.valueChangeActionID, "changed")
    }

    func testOnlySecureContentTypes() {
        XCTAssertEqual(SecureField.Props(["textContentType": "password"]).textContentType, .password)
        XCTAssertEqual(SecureField.Props(["textContentType": "oneTimeCode"]).textContentType, .oneTimeCode)
        XCTAssertNil(SecureField.Props(["textContentType": "username"]).textContentType)
        XCTAssertNil(SecureField.Props(["textContentType": 5]).textContentType)
    }

    func testWrongTypesFallBack() {
        let props = SecureField.Props(["title": 5, "prompt": 5, "text": 5, "actionID": 5, "valueChangeActionID": 5])
        XCTAssertEqual(props.title, "")
        XCTAssertNil(props.prompt)
        XCTAssertEqual(props.text, "")
        XCTAssertNil(props.actionID)
        XCTAssertNil(props.valueChangeActionID)
    }
}
