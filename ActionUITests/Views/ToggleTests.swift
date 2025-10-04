// Tests/Views/ToggleTests.swift
/*
 ToggleTests.swift

 Tests for the Toggle component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, state binding, and platform-specific style application.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ToggleTests: XCTestCase {
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
    
    func testToggleValidatePropertiesValid() {
        let properties: [String: Any] = [
            "title": "Enable Feature",
            "style": "switch",
            "actionID": "toggle.submit"
        ]
        
        let validated = Toggle.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["title"] as? String, "Enable Feature", "Title should be valid")
        XCTAssertEqual(validated["style"] as? String, "switch", "Style should be valid")
        XCTAssertEqual(validated["actionID"] as? String, "toggle.submit", "actionID should be valid")
    }
    
    func testToggleValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "title": 123,
            "style": "invalidStyle"
        ]
        
        let validated = Toggle.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["title"] as? Int, 123, "Invalid title should remain unchanged for baseline validation")
        XCTAssertNil(validated["style"], "Invalid style should be nil")
    }
    
    func testToggleValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = Toggle.validateProperties(properties, logger)
        
        XCTAssertNil(validated["title"], "Missing title should be nil")
        XCTAssertNil(validated["style"], "Missing style should be nil")
        XCTAssertNil(validated["actionID"], "Missing actionID should be nil")
    }
    
    #if os(macOS)
    func testToggleValidatePropertiesMacOSCheckbox() {
        let properties: [String: Any] = [
            "title": "Enable Feature",
            "style": "checkbox"
        ]
        
        let validated = Toggle.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["style"] as? String, "checkbox", "Checkbox style should be valid on macOS")
    }
    #else
    func testToggleValidatePropertiesNonMacOSCheckbox() {
        let properties: [String: Any] = [
            "title": "Enable Feature",
            "style": "checkbox"
        ]
        
        let validated = Toggle.validateProperties(properties, logger)
        
        XCTAssertNil(validated["style"], "Checkbox style should be invalid on non-macOS platforms")
    }
    #endif
    
    func testToggleConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Toggle",
            "properties": [
                "title": "Enable Feature",
                "style": "switch",
                "actionID": "toggle.submit",
                "padding": 10.0
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = Toggle.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }
    
    func testToggleJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Toggle",
            "properties": {
                "title": "Enable Feature",
                "style": "switch",
                "actionID": "toggle.submit",
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
        XCTAssertEqual(element.type, "Toggle", "Element type should be Toggle")
        XCTAssertEqual(element.properties["title"] as? String, "Enable Feature", "title should be Enable Feature")
        XCTAssertEqual(element.properties["style"] as? String, "switch", "style should be switch")
        XCTAssertEqual(element.properties["actionID"] as? String, "toggle.submit", "actionID should be toggle.submit")
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
        XCTAssertEqual(viewModel.value as? Bool, false, "Initial viewModel value should be false")
    }
}
