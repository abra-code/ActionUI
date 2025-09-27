// Tests/Views/TextTests.swift
/*
 TextTests.swift

 Tests for the Text component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class TextTests: XCTestCase {
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
    
    func testTextConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Text",
            "properties": [
                "text": "Hello, World!",
                "padding": 10.0
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = Text.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }
    
    func testTextJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Text",
            "properties": {
                "text": "Hello, World!",
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
        XCTAssertEqual(element.type, "Text", "Element type should be Text")
        XCTAssertEqual(element.properties["text"] as? String, "Hello, World!", "text should be Hello, World!")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 5.0, "offset.x should be 5.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
    }
    
    func testTextValidatePropertiesValid() {
        let properties: [String: Any] = [
            "text": "Hello, World!",
            "padding": 10.0
        ]
        
        let validated = Text.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["text"] as? String, "Hello, World!", "text should be preserved")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "padding should be passed through")
    }
    
    func testTextValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "text": 123
        ]
        
        let validated = Text.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["text"] as? Int, 123, "Invalid text should be preserved for baseline validation")
    }
    
    func testTextValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = Text.validateProperties(properties, logger)
        
        XCTAssertNil(validated["text"], "Missing text should be nil")
    }
}
