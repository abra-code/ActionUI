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
        
    func testTextFieldValidatePropertiesValid() {
        let properties: [String: Any] = [
            "prompt": "Enter text",
            "textContentType": "username",
            "actionID": "text.submit"
        ]

        let validated = TextField.validateProperties(properties, logger)

        XCTAssertEqual(validated["prompt"] as? String, "Enter text", "Prompt should be valid")
        XCTAssertEqual(validated["textContentType"] as? String, "username", "textContentType should be valid")
        XCTAssertEqual(validated["actionID"] as? String, "text.submit", "actionID should be valid")
    }
    
    func testTextFieldValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "prompt": 123,
            "textContentType": 456
        ]

        let validated = TextField.validateProperties(properties, logger)

        XCTAssertNil(validated["prompt"], "Invalid prompt should be nil")
        XCTAssertNil(validated["textContentType"], "Invalid textContentType should be nil")
    }
    
    func testTextFieldValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = TextField.validateProperties(properties, logger)
        
        XCTAssertNil(validated["prompt"], "Missing prompt should be nil")
        XCTAssertNil(validated["textContentType"], "Missing textContentType should be nil")
        XCTAssertNil(validated["actionID"], "Missing actionID should be nil")
    }
    
    func testTextFieldConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TextField",
            "properties": [
                "prompt": "Enter text",
                "textContentType": "username",
                "actionID": "text.submit",
                "padding": 10.0
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = TextField.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }
    
    func testTextFieldJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "TextField",
            "properties": {
                "prompt": "Enter text",
                "textContentType": "username",
                "actionID": "text.submit",
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
        XCTAssertEqual(element.type, "TextField", "Element type should be TextField")
        XCTAssertEqual(element.properties["prompt"] as? String, "Enter text", "prompt should be Enter text")
        XCTAssertEqual(element.properties["textContentType"] as? String, "username", "textContentType should be username")
        XCTAssertEqual(element.properties["actionID"] as? String, "text.submit", "actionID should be text.submit")
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
        XCTAssertEqual(viewModel.value as? String, "", "Initial viewModel value should be an empty string")
    }

    func testTextFieldTextPropertyValidation() {
        let valid = TextField.validateProperties(["text": "hello"], logger)
        XCTAssertEqual(valid["text"] as? String, "hello", "Valid text should be preserved")

        let invalid = TextField.validateProperties(["text": 123], logger)
        XCTAssertNil(invalid["text"], "Non-String text should be removed")
    }

    func testTextFieldInitialValueFromTextProperty() {
        let viewModel = ViewModel()
        viewModel.validatedProperties = ["text": "prefilled"]

        let value = TextField.initialValue(viewModel) as? String
        XCTAssertEqual(value, "prefilled", "initialValue should fall back to text property")
    }

    func testTextFieldInitialValuePrefersModelValue() {
        let viewModel = ViewModel()
        viewModel.value = "typed"
        viewModel.validatedProperties = ["text": "prefilled"]

        let value = TextField.initialValue(viewModel) as? String
        XCTAssertEqual(value, "typed", "initialValue should prefer model.value over text property")
    }
}
