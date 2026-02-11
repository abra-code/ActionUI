// Tests/Views/TabViewTests.swift
/*
 TabViewTests.swift

 Tests for the TabView component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and state binding.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class TabViewTests: XCTestCase {
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
    
    func testTabViewValidatePropertiesValid() {
        let properties: [String: Any] = [
            "selection": 0,
            "padding": 10.0
        ]
        
        let validated = TabView.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["selection"] as? Int, 0, "selection should be valid")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "padding should be passed through")
    }
    
    func testTabViewValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "selection": "invalid"
        ]
        
        let validated = TabView.validateProperties(properties, logger)
        
        XCTAssertNil(validated["selection"], "Invalid selection should be nil")
    }
    
    func testTabViewValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = TabView.validateProperties(properties, logger)
        
        XCTAssertNil(validated["selection"], "Missing selection should be nil")
    }
    
    func testTabViewConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TabView",
            "properties": [
                "selection": 0,
                "padding": 10.0
            ],
            "children": [
                [
                    "type": "Tab",
                    "properties": ["title": "Home", "systemImage": "house.fill"],
                    "content": ["type": "Text", "id": 3, "properties": ["text": "Home"]]
                ]
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let validatedProperties = TabView.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
    }
    
    func testTabViewJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "TabView",
            "properties": {
                "selection": 0,
                "padding": 10.0,
                "offset": {"x": 5.0, "y": -5.0}
            },
            "children": [
                {
                    "type": "Tab",
                    "properties": {"title": "Home", "systemImage": "house.fill"},
                    "content": {"type": "Text", "id": 3, "properties": {"text": "Home"}}
                }
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
        XCTAssertEqual(element.type, "TabView", "Element type should be TabView")
        XCTAssertEqual(element.properties["selection"] as? Int, 0, "selection should be 0")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 5.0, "offset.x should be 5.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
        
        if let children = element.subviews?["children"] as? [any ActionUIElementBase] {
            XCTAssertEqual(children.count, 1, "Should have one child")
            XCTAssertEqual(children[0].type, "Tab", "Child type should be TabBarItem")
            XCTAssertEqual(children[0].properties["title"] as? String, "Home", "Child title should be Home")
            if let content = children[0].subviews?["content"] as? any ActionUIElementBase {
                XCTAssertEqual(content.type, "Text", "Content type should be Text")
                XCTAssertEqual(content.properties["text"] as? String, "Home", "Content text should be Home")
            } else {
                XCTFail("Content should be valid")
            }
        } else {
            XCTFail("Children should be valid array")
        }
        
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        XCTAssertEqual(viewModel.value as? Int, 0, "Initial viewModel value should be 0")
    }
}
