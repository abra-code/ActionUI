// Tests/Views/TextEditorTests.swift
/*
 TextEditorTests.swift

 Tests for the TextEditor component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and state binding.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class TextEditorTests: XCTestCase {
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
    
    func testTextEditorValidatePropertiesValid() {
        let properties: [String: Any] = [
            "placeholder": "Enter text here",
            "actionID": "texteditor.submit"
        ]
        
        let validated = TextEditor.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["placeholder"] as? String, "Enter text here", "Placeholder should be valid")
        XCTAssertEqual(validated["actionID"] as? String, "texteditor.submit", "actionID should be valid")
    }
    
    func testTextEditorValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "placeholder": 123
        ]
        
        let validated = TextEditor.validateProperties(properties, logger)
        
        XCTAssertNil(validated["placeholder"], "Invalid placeholder should be nil")
    }
    
    func testTextEditorValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = TextEditor.validateProperties(properties, logger)
        
        XCTAssertNil(validated["placeholder"], "Missing placeholder should be nil")
        XCTAssertNil(validated["actionID"], "Missing actionID should be nil")
    }
    
    func testTextEditorConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TextEditor",
            "properties": [
                "placeholder": "Enter text here",
                "actionID": "texteditor.submit",
                "padding": 10.0
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = TextEditor.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }
    
    func testTextEditorJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "TextEditor",
            "properties": {
                "placeholder": "Enter text here",
                "actionID": "texteditor.submit",
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
        XCTAssertEqual(element.type, "TextEditor", "Element type should be TextEditor")
        XCTAssertEqual(element.properties["placeholder"] as? String, "Enter text here", "placeholder should be Enter text here")
        XCTAssertEqual(element.properties["actionID"] as? String, "texteditor.submit", "actionID should be texteditor.submit")
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
}
