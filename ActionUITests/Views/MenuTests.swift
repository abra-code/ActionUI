// Tests/Views/MenuTests.swift
/*
 MenuTests.swift

 Tests for the Menu component in the ActionUI component library.
 Verifies JSON decoding, property validation, and view construction.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class MenuTests: XCTestCase {
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
    
    func testMenuValidatePropertiesValid() {
        let properties: [String: Any] = [
            "label": "Options",
            "padding": 10.0
        ]
        
        let validated = Menu.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["label"] as? String, "Options", "label should be valid")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "padding should be passed through")
    }
    
    func testMenuValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "label": 123
        ]
        
        let validated = Menu.validateProperties(properties, logger)
        
        XCTAssertNil(validated["label"], "Invalid label should be nil")
    }
    
    func testMenuValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = Menu.validateProperties(properties, logger)
        
        XCTAssertNil(validated["label"], "Missing label should be nil")
    }
    
    func testMenuConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Menu",
            "properties": [
                "label": "Options",
                "padding": 10.0
            ],
            "children": [
                ["type": "Button", "id": 2, "properties": ["title": "Option 1"]]
            ]
        ]
        
        let element = try ViewElement(from: elementDict, logger: logger)
        let validatedProperties = Menu.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }
    
    func testMenuJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Menu",
            "properties": {
                "label": "Options",
                "padding": 10.0,
                "offset": {"x": 5.0, "y": -5.0}
            },
            "children": [
                {"type": "Button", "id": 2, "properties": {"title": "Option 1"}}
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
        XCTAssertEqual(element.type, "Menu", "Element type should be Menu")
        XCTAssertEqual(element.properties["label"] as? String, "Options", "label should be Options")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 5.0, "offset.x should be 5.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
        
        if let children = element.subviews?["children"] as? [any ActionUIElement] {
            XCTAssertEqual(children.count, 1, "Should have one child")
            XCTAssertEqual(children[0].type, "Button", "Child type should be Button")
            XCTAssertEqual(children[0].id, 2, "Child ID should be 2")
            XCTAssertEqual(children[0].properties["title"] as? String, "Option 1", "Child title should be Option 1")
        } else {
            XCTFail("Children should be valid array")
        }
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        XCTAssertNil(viewModel.value, "Initial viewModel value should be nil for Menu")
    }
}
