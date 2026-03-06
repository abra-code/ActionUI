// Tests/Views/SecureFieldTests.swift
/*
 SecureFieldTests.swift

 Tests for the SecureField component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and state binding, including placeholder defaults and restricted textContentType values.
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
        ActionUIModel.shared.logger = logger
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
        
        XCTAssertEqual(validated["placeholder"] as? String, nil, "Invalid placeholder should be nil")
        XCTAssertNil(validated["textContentType"], "Invalid textContentType should be nil")
    }
    
    func testSecureFieldValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = SecureField.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["placeholder"] as? String, nil, "Missing placeholder should be nil")
        XCTAssertNil(validated["textContentType"], "Missing textContentType should be nil")
        XCTAssertNil(validated["actionID"], "Missing actionID should be nil")
    }
    
    func testSecureFieldConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "SecureField",
            "properties": [
                "placeholder": "Enter password",
                "textContentType": "password",
                "actionID": "secure.submit",
                "padding": 10.0
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = SecureField.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }
    
    func testSecureFieldJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "SecureField",
            "properties": {
                "placeholder": "Enter password",
                "textContentType": "password",
                "actionID": "secure.submit",
                "padding": 10.0,
                "offset": {"x": 5.0, "y": -5.0}
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        
        // Parse JSON into ActionUIElement
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
                
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "SecureField", "Element type should be SecureField")
        XCTAssertEqual(element.properties["placeholder"] as? String, "Enter password", "placeholder should be Enter password")
        XCTAssertEqual(element.properties["textContentType"] as? String, "password", "textContentType should be password")
        XCTAssertEqual(element.properties["actionID"] as? String, "secure.submit", "actionID should be secure.submit")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 5.0, "offset.x should be 5.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        XCTAssertEqual(viewModel.value as? String, "", "Initial viewModel value should be empty string")
    }

    func testSecureFieldTextPropertyValidation() {
        let valid = SecureField.validateProperties(["text": "secret"], logger)
        XCTAssertEqual(valid["text"] as? String, "secret", "Valid text should be preserved")

        let invalid = SecureField.validateProperties(["text": 123], logger)
        XCTAssertNil(invalid["text"], "Non-String text should be removed")
    }

    func testSecureFieldInitialValueFromTextProperty() {
        let viewModel = ViewModel()
        viewModel.validatedProperties = ["text": "prefilled"]

        let value = SecureField.initialValue(viewModel) as? String
        XCTAssertEqual(value, "prefilled", "initialValue should fall back to text property")
    }

    func testSecureFieldInitialValuePrefersModelValue() {
        let viewModel = ViewModel()
        viewModel.value = "typed"
        viewModel.validatedProperties = ["text": "prefilled"]

        let value = SecureField.initialValue(viewModel) as? String
        XCTAssertEqual(value, "typed", "initialValue should prefer model.value over text property")
    }
}
