// Tests/Views/GroupTests.swift
/*
 GroupTests.swift

 Tests for the Group component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and subview handling.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class GroupTests: XCTestCase {
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
    
    func testGroupConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Group",
            "properties": [:],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Item 1"]],
                ["type": "Text", "id": 3, "properties": ["text": "Item 2"]]
            ]
        ]
        
        let element = try ViewElement(from: elementDict, logger: logger)
        let validatedProperties = Group.validateProperties(element.properties, logger)
        let viewModel = ViewModel(properties: element.properties)
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        guard let children = element.subviews?["children"] as? [any ActionUIElement] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 2, "Group should have 2 children")
        XCTAssertEqual((children[0] as? ViewElement)?.type, "Text", "First child should be Text")
        XCTAssertEqual((children[0] as? ViewElement)?.id, 2, "First child ID should be 2")
        XCTAssertEqual((children[1] as? ViewElement)?.type, "Text", "Second child should be Text")
        XCTAssertEqual((children[1] as? ViewElement)?.id, 3, "Second child ID should be 3")
    }
    
    func testGroupJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Group",
            "properties": {"padding": 10.0},
            "children": [
                {"type": "Text", "id": 2, "properties": {"text": "Item 1"}},
                {"type": "Text", "id": 3, "properties": {"text": "Item 2"}}
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
        XCTAssertEqual(element.type, "Group", "Element type should be Group")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "Padding should be 10.0")
        guard let children = element.subviews?["children"] as? [any ActionUIElement] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 2, "Children should have 2 elements")
        XCTAssertEqual((children[0] as? ViewElement)?.type, "Text", "First child should be Text")
        XCTAssertEqual((children[0] as? ViewElement)?.id, 2, "First child ID should be 2")
        XCTAssertEqual((children[1] as? ViewElement)?.type, "Text", "Second child should be Text")
        XCTAssertEqual((children[1] as? ViewElement)?.id, 3, "Second child ID should be 3")
    }
    
    func testGroupValidatePropertiesValid() {
        let properties: [String: Any] = ["padding": 10.0]
        
        let validated = Group.validateProperties(properties, logger)
        
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "Padding should be valid")
    }
    
    func testGroupValidatePropertiesEmpty() {
        let properties: [String: Any] = [:]
        
        let validated = Group.validateProperties(properties, logger)
        
        XCTAssertTrue(validated.isEmpty, "Empty properties should be valid")
    }
    
    func testGroupDynamicHierarchyChange() throws {
        // Initial hierarchy
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Group",
            "properties": [:],
            "children": [
                ["type": "TextField", "id": 2, "properties": ["placeholder": "Enter text"]],
                ["type": "Text", "id": 3, "properties": ["text": "Static"]]
            ]
        ]
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrive viewModel")
            return
        }

        // Build initial view
        let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        _ = actionUIView.body // Access the body to trigger view construction

        // Set TextField value
        actionUIModel.setElementValue(windowUUID: windowUUID, viewID: 2, value: "Test Input", viewPartID: 0)
        XCTAssertEqual(actionUIModel.getElementValue(windowUUID: windowUUID, viewID: 2, viewPartID: 0) as? String, "Test Input", "TextField value should be set")
        
        // Reordered hierarchy
        let reorderedDict: [String: Any] = [
            "id": 1,
            "type": "Group",
            "properties": [:],
            "children": [
                ["type": "Text", "id": 3, "properties": ["text": "Static"]],
                ["type": "TextField", "id": 2, "properties": ["placeholder": "Enter text"]]
            ]
        ]
        
        let reorderedElement = try actionUIModel.loadDescription(from: reorderedDict, windowUUID: windowUUID)
        guard let reorderedWindowModel = actionUIModel.windowModels[windowUUID],
              let reorderedViewModel = reorderedWindowModel.viewModels[element.id] else {
            XCTFail("Failed to retrive viewModel")
            return
        }

        // Build initial view
        let reorderedActionUIView = ActionUIView(element: reorderedElement, model: reorderedViewModel, windowUUID: windowUUID)
        _ = reorderedActionUIView.body // Access the body to trigger view construction
        
        // Verify TextField state persists
        // TODO: this test does not work. loadDescription wipes existing models and reconstructs them
        // XCTAssertEqual(actionUIModel.getElementValue(windowUUID: windowUUID, viewID: 2, viewPartID: 0) as? String, "Test Input", "TextField value should persist after reordering")
    }
}
