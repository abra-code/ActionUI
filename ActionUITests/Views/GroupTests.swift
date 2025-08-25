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
    
    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.setLogger(logger)
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
    }
    
    override func tearDown() {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        super.tearDown()
    }
    
    func testGroupConstruction() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Group",
            "properties": [:],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Item 1"]],
                ["type": "Text", "id": 3, "properties": ["text": "Item 2"]]
            ]
        ]
        let element = try! ViewElement(from: elementDict, logger: logger)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = Group.validateProperties(element.properties, logger)
        
        let _ = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
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
    
    func testGroupJSONDecoding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Group",
            "properties": ["padding": 10.0],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Item 1"]],
                ["type": "Text", "id": 3, "properties": ["text": "Item 2"]]
            ]
        ]
        
        let element = try! ViewElement(from: elementDict, logger: logger)
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Group", "Element type should be Group")
        XCTAssertEqual(element.properties["padding"] as? Double, 10.0, "Padding should be 10.0")
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
        
        XCTAssertEqual(validated["padding"] as? Double, 10.0, "Padding should be valid")
    }
    
    func testGroupValidatePropertiesEmpty() {
        let properties: [String: Any] = [:]
        
        let validated = Group.validateProperties(properties, logger)
        
        XCTAssertTrue(validated.isEmpty, "Empty properties should be valid")
    }
    
    func testGroupDynamicHierarchyChange() {
        let windowUUID = UUID().uuidString
        let state = ActionUIModel.shared.state(for: windowUUID)
        
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
        let element = try! ViewElement(from: elementDict, logger: logger)
        ActionUIModel.shared.descriptions[windowUUID] = element
        let validatedProperties = Group.validateProperties(element.properties, logger)
        
        // Build initial view
        _ = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        // Set TextField value
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 2, value: "Test Input", viewPartID: 0)
        XCTAssertEqual(ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 2, viewPartID: 0) as? String, "Test Input", "TextField value should be set")
        
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
        let reorderedElement = try! ViewElement(from: reorderedDict, logger: logger)
        ActionUIModel.shared.descriptions[windowUUID] = reorderedElement
        let reorderedValidatedProperties = Group.validateProperties(reorderedElement.properties, logger)
        
        // Build reordered view
        _ = ActionUIRegistry.shared.buildView(for: reorderedElement, state: state, windowUUID: windowUUID, validatedProperties: reorderedValidatedProperties)
        
        // Verify TextField state persists
        XCTAssertEqual(ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 2, viewPartID: 0) as? String, "Test Input", "TextField value should persist after reordering")
    }
}
