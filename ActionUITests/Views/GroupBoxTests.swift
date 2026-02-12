// Tests/Views/GroupBoxTests.swift
/*
 GroupBoxTests.swift

 Tests for the GroupBox component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.
 */

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class GroupBoxTests: XCTestCase {
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
    
    func testGroupBoxValidatePropertiesValid() {
        let properties: [String: Any] = [
            "title": "Settings",
            "padding": 10.0
        ]
        
        let validated = GroupBox.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["title"] as? String, "Settings", "title should be valid")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "padding should be passed through")
    }
    
    func testGroupBoxValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "title": 123
        ]
        
        let validated = GroupBox.validateProperties(properties, logger)
        
        XCTAssertNil(validated["title"], "Invalid title should be nil")
    }
    
    func testGroupBoxValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = GroupBox.validateProperties(properties, logger)
        
        XCTAssertNil(validated["title"], "Missing title should be nil")
    }
    
    func testGroupBoxConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "GroupBox",
            "properties": [
                "title": "Settings",
                "padding": 10.0
            ],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Content"]]
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = GroupBox.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }
    
    func testGroupBoxConstructionWithoutTitle() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "GroupBox",
            "properties": [:],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Content"]]
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = GroupBox.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }
    
    func testGroupBoxJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "GroupBox",
            "properties": {
                "title": "Settings",
                "padding": 10.0
            },
            "children": [
                {"type": "Text", "id": 2, "properties": {"text": "Content"}}
            ]
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
        XCTAssertEqual(element.type, "GroupBox", "Element type should be GroupBox")
        XCTAssertEqual(element.properties["title"] as? String, "Settings", "title should be Settings")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        
        if let children = element.subviews?["children"] as? [any ActionUIElementBase] {
            XCTAssertEqual(children.count, 1, "Should have one child")
            XCTAssertEqual(children[0].type, "Text", "Child type should be Text")
            XCTAssertEqual(children[0].id, 2, "Child ID should be 2")
        } else {
            XCTFail("Children should be valid array")
        }
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        XCTAssertNil(viewModel.value, "Initial viewModel value should be nil for GroupBox")
    }
}
