// Tests/Views/SecureFieldTests.swift
/*
 SecureFieldTests.swift

 Tests for the SecureField component in the ActionUI component library.
 Verifies property validation, including placeholder defaults and restricted textContentType values.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class SecureFieldTests: XCTestCase {
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
        
    func testSecureFieldValidatePropertiesValid() {
        let properties: [String: Any] = [
            "placeholder": "Enter password",
            "textContentType": "password",
            "actionID": "secure.submit"
        ]
        
        let validated = SecureField.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["placeholder"] as? String, "Enter password", "Placeholder should be valid")
        XCTAssertEqual(validated["textContentType"] as? String, "password", "textContentType should be valid")
        XCTAssertEqual(validated["actionID"] as? String, "secure.submit", "actionID should be valid")
    }
    
    func testSecureFieldValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "placeholder": 123,
            "textContentType": "username"
        ]
        
        let validated = SecureField.validateProperties(properties, logger)
        
        XCTAssertNil(validated["placeholder"], "Invalid placeholder should be nil")
        XCTAssertNil(validated["textContentType"], "Invalid textContentType should be nil")
    }
    
    func testSecureFieldValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = SecureField.validateProperties(properties, logger)
        
        XCTAssertNil(validated["placeholder"], "Missing placeholder should be nil")
        XCTAssertNil(validated["textContentType"], "Missing textContentType should be nil")
        XCTAssertNil(validated["actionID"], "Missing actionID should be nil")
    }
}
