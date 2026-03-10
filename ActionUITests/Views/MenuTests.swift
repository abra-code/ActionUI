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
    
    func testMenuValidatePropertiesValid() {
        let properties: [String: Any] = [
            "title": "Options",
            "padding": 10.0
        ]
        
        let validated = Menu.validateProperties(properties, logger)
        
        XCTAssertEqual(validated["title"] as? String, "Options", "title should be valid")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "padding should be passed through")
    }
    
    func testMenuValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "title": 123
        ]
        
        let validated = Menu.validateProperties(properties, logger)
        
        XCTAssertNil(validated["title"], "Invalid title should be nil")
    }
    
    func testMenuValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = Menu.validateProperties(properties, logger)
        
        XCTAssertNil(validated["title"], "Missing title should be nil")
    }
    
    func testMenuConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Menu",
            "properties": [
                "title": "Options",
                "padding": 10.0
            ],
            "children": [
                ["type": "Button", "id": 2, "properties": ["title": "Option 1"]]
            ]
        ]
        
        let element = try ActionUIElement(from: elementDict, logger: logger)
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
                "title": "Options",
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
        
        // Parse JSON into ActionUIElement
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
                
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Menu", "Element type should be Menu")
        XCTAssertEqual(element.properties["title"] as? String, "Options", "title should be Options")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 5.0, "offset.x should be 5.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
        
        if let children = element.subviews?["children"] as? [any ActionUIElementBase] {
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

    func testMenuWithDivider() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Menu",
            "properties": {
                "title": "Edit"
            },
            "children": [
                {"type": "Button", "id": 2, "properties": {"title": "Cut"}},
                {"type": "Button", "id": 3, "properties": {"title": "Copy"}},
                {"type": "Divider"},
                {"type": "Button", "id": 4, "properties": {"title": "Delete"}}
            ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        XCTAssertEqual(element.type, "Menu")
        if let children = element.subviews?["children"] as? [any ActionUIElementBase] {
            XCTAssertEqual(children.count, 4, "Should have 4 children including Divider")
            XCTAssertEqual(children[0].type, "Button")
            XCTAssertEqual(children[1].type, "Button")
            XCTAssertEqual(children[2].type, "Divider")
            XCTAssertEqual(children[3].type, "Button")
        } else {
            XCTFail("Children should be valid array")
        }

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        XCTAssertFalse(actionUIView.body is SwiftUI.EmptyView, "Menu with Divider should render")
    }

    func testMenuWithSections() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Menu",
            "properties": {
                "title": "Actions"
            },
            "children": [
                {
                    "type": "Section",
                    "id": 10,
                    "properties": {"header": "Clipboard"},
                    "children": [
                        {"type": "Button", "id": 2, "properties": {"title": "Cut"}},
                        {"type": "Button", "id": 3, "properties": {"title": "Copy"}}
                    ]
                },
                {
                    "type": "Section",
                    "id": 11,
                    "properties": {"header": "File"},
                    "children": [
                        {"type": "Button", "id": 4, "properties": {"title": "Save"}}
                    ]
                }
            ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        XCTAssertEqual(element.type, "Menu")
        if let children = element.subviews?["children"] as? [any ActionUIElementBase] {
            XCTAssertEqual(children.count, 2, "Should have 2 Section children")
            XCTAssertEqual(children[0].type, "Section")
            XCTAssertEqual(children[0].properties["header"] as? String, "Clipboard")
            XCTAssertEqual(children[1].type, "Section")
            XCTAssertEqual(children[1].properties["header"] as? String, "File")

            // Verify nested children in first section
            if let sectionChildren = children[0].subviews?["children"] as? [any ActionUIElementBase] {
                XCTAssertEqual(sectionChildren.count, 2, "Clipboard section should have 2 buttons")
                XCTAssertEqual(sectionChildren[0].properties["title"] as? String, "Cut")
                XCTAssertEqual(sectionChildren[1].properties["title"] as? String, "Copy")
            } else {
                XCTFail("Section children should be valid array")
            }
        } else {
            XCTFail("Children should be valid array")
        }

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        XCTAssertFalse(actionUIView.body is SwiftUI.EmptyView, "Menu with Sections should render")
    }
}
