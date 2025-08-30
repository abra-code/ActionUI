// Tests/Views/TextFieldTests.swift
/*
 TextFieldTests.swift

 Tests for the TextField component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, state binding, and textContentType application.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class TextFieldTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!
    
    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.setLogger(logger)
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }
    
    override func tearDown() {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        super.tearDown()
    }
        
    func testTextFieldValidatePropertiesValid() {
        let properties: [String: Any] = [
            "placeholder": "Enter text",
            "textContentType": "username",
            "actionID": "text.submit"
        ]
        
        let validated = TextField.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["placeholder"] as? String, "Enter text", "Placeholder should be valid")
        XCTAssertEqual(validated["textContentType"] as? String, "username", "textContentType should be valid")
        XCTAssertEqual(validated["actionID"] as? String, "text.submit", "actionID should be valid")
    }
    
    func testTextFieldValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "placeholder": 123,
            "textContentType": 456
        ]
        
        let validated = TextField.validateProperties(properties, logger)
        
        XCTAssertNil(validated["placeholder"], "Invalid placeholder should be nil")
        XCTAssertNil(validated["textContentType"], "Invalid textContentType should be nil")
    }
    
    func testTextFieldValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = TextField.validateProperties(properties, logger)
        
        XCTAssertNil(validated["placeholder"], "Missing placeholder should be nil")
        XCTAssertNil(validated["textContentType"], "Missing textContentType should be nil")
        XCTAssertNil(validated["actionID"], "Missing actionID should be nil")
    }
}

