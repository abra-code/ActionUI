// Tests/Views/SecureFieldTests.swift
/*
 SecureFieldTests.swift

 Tests for the SecureField component in the ActionUI component library.
 Verifies JSON decoding, Props reading, view construction, and state binding, including prompt defaults and restricted textContentType values.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class SecureFieldTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!
    
    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }
    
    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        try await super.tearDown()
    }
        
    func testSecureFieldPropsValid() {
        let properties: [String: Any] = [
            "prompt": "Enter password",
            "textContentType": "password",
            "actionID": "secure.submit"
        ]

        let props = SecureField.Props(properties)

        XCTAssertEqual(props.prompt, "Enter password", "Prompt should be valid")
        XCTAssertEqual(props.textContentType, .password, "textContentType should be valid")
        XCTAssertEqual(props.actionID, "secure.submit", "actionID should be valid")
    }
    
    func testSecureFieldPropsIgnoreInvalid() {
        let properties: [String: Any] = [
            "prompt": 123,
            "textContentType": "username"
        ]

        let props = SecureField.Props(properties)

        XCTAssertNil(props.prompt, "Invalid prompt should be ignored")
        XCTAssertNil(props.textContentType, "Invalid textContentType should be ignored")
    }
    
    func testSecureFieldPropsMissing() {
        let properties: [String: Any] = [:]
        
        let props = SecureField.Props(properties)
        
        XCTAssertNil(props.prompt, "Missing prompt should be nil")
        XCTAssertNil(props.textContentType, "Missing textContentType should be nil")
        XCTAssertNil(props.actionID, "Missing actionID should be nil")
    }
    
    func testSecureFieldConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "SecureField",
            "properties": [
                "prompt": "Enter password",
                "textContentType": "password",
                "actionID": "secure.submit",
                "padding": 10.0
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }
    
    func testSecureFieldJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "SecureField",
            "properties": {
                "prompt": "Enter password",
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
        XCTAssertEqual(element.properties["prompt"] as? String, "Enter password", "prompt should be Enter password")
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

    func testSecureFieldPropsText() {
        let valid = SecureField.Props(["text": "secret"])
        XCTAssertEqual(valid.text, "secret", "Valid text should be preserved")

        let invalid = SecureField.Props(["text": 123])
        XCTAssertEqual(invalid.text, "", "Non-String text should be ignored")
    }

    func testSecureFieldInitialValueFromTextProperty() {
        let viewModel = ViewModel()
        viewModel.properties = ["text": "prefilled"]

        let value = SecureField.initialValue(viewModel) as? String
        XCTAssertEqual(value, "prefilled", "initialValue should fall back to text property")
    }

    func testSecureFieldInitialValuePrefersModelValue() {
        let viewModel = ViewModel()
        viewModel.value = "typed"
        viewModel.properties = ["text": "prefilled"]

        let value = SecureField.initialValue(viewModel) as? String
        XCTAssertEqual(value, "typed", "initialValue should prefer model.value over text property")
    }
}
