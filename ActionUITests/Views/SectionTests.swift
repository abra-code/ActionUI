// Tests/Views/SectionTests.swift
/*
 SectionTests.swift

 Tests for the Section component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class SectionTests: XCTestCase {
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
    
    func testSectionValidatePropertiesValid() {
        let properties: [String: Any] = [
            "header": "Details",
            "padding": 10.0
        ]
        
        let validated = Section.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["header"] as? String, "Details", "header should be valid")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "padding should be passed through")
    }
    
    func testSectionValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "header": 123
        ]
        
        let validated = Section.validateProperties(properties, logger)
        
        XCTAssertNil(validated["header"], "Invalid header should be nil")
    }
    
    func testSectionValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = Section.validateProperties(properties, logger)
        
        XCTAssertNil(validated["header"], "Missing header should be nil")
    }
    
    func testSectionConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Section",
            "properties": [
                "header": "Details",
                "padding": 10.0
            ],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Item 1"]]
            ]
        ]
        
        let element = try ViewElement(from: elementDict, logger: logger)
        let validatedProperties = Section.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }
    
    func testSectionJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Section",
            "properties": {
                "header": "Details",
                "padding": 10.0,
                "offset": {"x": 5.0, "y": -5.0}
            },
            "children": [
                {"type": "Text", "id": 2, "properties": {"text": "Item 1"}}
            ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        
        // Parse JSON into ViewElement
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
                
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Section", "Element type should be Section")
        XCTAssertEqual(element.properties["header"] as? String, "Details", "header should be Details")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 5.0, "offset.x should be 5.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
        
        if let children = element.subviews?["children"] as? [any ActionUIElementBase] {
            XCTAssertEqual(children.count, 1, "Should have one child")
            XCTAssertEqual(children[0].type, "Text", "Child type should be Text")
            XCTAssertEqual(children[0].id, 2, "Child ID should be 2")
            XCTAssertEqual(children[0].properties["text"] as? String, "Item 1", "Child text should be Item 1")
        } else {
            XCTFail("Children should be valid array")
        }
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        XCTAssertNil(viewModel.value, "Initial viewModel value should be nil for Section")
    }
}
