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
    
    func testTextFieldConstructionAndStateBinding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "TextField",
            "properties": {
                "placeholder": "Enter text",
                "textContentType": "username",
                "actionID": "text.submit",
                "padding": 10.0
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let model = ActionUIModel.shared
        try model.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let element = model.descriptions[windowUUID] else {
            XCTFail("Failed to retrieve element from model for windowUUID: \(String(describing: windowUUID))")
            return
        }
        
        let state = ActionUIModel.shared.state(for: windowUUID)
        let validatedProperties = TextField.validateProperties(element.properties, logger)
        
        let view = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: windowUUID, validatedProperties: validatedProperties)
        _ = TextField.applyModifiers(view, validatedProperties, logger)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "TextField", "Element type should be TextField")
        XCTAssertEqual(element.properties["placeholder"] as? String, "Enter text", "Placeholder should be Enter text")
        XCTAssertEqual(element.properties["textContentType"] as? String, "username", "textContentType should be username")
        XCTAssertEqual(element.properties["actionID"] as? String, "text.submit", "actionID should be text.submit")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "Padding should be 10.0")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
        
        if let viewState = state.wrappedValue[element.id] as? [String: Any] {
            XCTAssertEqual(viewState["value"] as? String, "", "TextField state should initialize value to empty string")
        } else {
            XCTFail("State should be a dictionary")
        }
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

