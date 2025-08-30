// Tests/Views/HStackTests.swift
/*
 HStackTests.swift

 Tests for the HStack component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and subview handling.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class HStackTests: XCTestCase {
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
    
    func testHStackConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "HStack",
            "properties": ["spacing": 10.0],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Item 1"]],
                ["type": "Text", "id": 3, "properties": ["text": "Item 2"]]
            ]
        ]
        
        let element = try ViewElement(from: elementDict, logger: logger)
        let validatedProperties = HStack.validateProperties(element.properties, logger)
        let viewModel = ViewModel(properties: element.properties)
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        guard let children = element.subviews?["children"] as? [any ActionUIElement] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 2, "HStack should have 2 children")
        XCTAssertEqual((children[0] as? ViewElement)?.type, "Text", "First child should be Text")
        XCTAssertEqual((children[0] as? ViewElement)?.id, 2, "First child ID should be 2")
        XCTAssertEqual((children[1] as? ViewElement)?.type, "Text", "Second child should be Text")
        XCTAssertEqual((children[1] as? ViewElement)?.id, 3, "Second child ID should be 3")
    }
    
    func testHStackJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "HStack",
            "properties": {"spacing": 10.0},
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
        XCTAssertEqual(element.type, "HStack", "Element type should be HStack")
        XCTAssertEqual(element.properties.cgFloat(forKey: "spacing"), 10.0, "Spacing should be 10.0")
        
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
    
    func testHStackValidatePropertiesValid() {
        let properties: [String: Any] = ["spacing": 10.0]
        
        let validated = HStack.validateProperties(properties, logger)
        
        XCTAssertEqual(validated.cgFloat(forKey: "spacing"), 10.0, "Spacing should be valid")
    }
    
    func testHStackValidatePropertiesInvalid() {
        let properties: [String: Any] = ["spacing": "10"]
        
        let validated = HStack.validateProperties(properties, logger)
        
        XCTAssertNil(validated.cgFloat(forKey: "spacing"), "Invalid spacing should be nil")
    }
    
    func testHStackValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = HStack.validateProperties(properties, logger)
        
        XCTAssertNil(validated.cgFloat(forKey: "spacing"), "Missing spacing should be nil")
    }
    
    func testHStackNilSpacing() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "HStack",
            "properties": [:],
            "children": [
                ["type": "Text", "id": 2, "properties": ["text": "Item 1"]],
                ["type": "Text", "id": 3, "properties": ["text": "Item 2"]]
            ]
        ]

        let element = try! ViewElement(from: elementDict, logger: logger)
        let validatedProperties = HStack.validateProperties(element.properties, logger)
        let viewModel = ViewModel(properties: element.properties)
        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        let children = element.subviews?["children"] as? [any ActionUIElement]
        XCTAssertEqual(children?.count, 2, "HStack should have 2 children")
        XCTAssertNil(validatedProperties.cgFloat(forKey: "spacing"), "Spacing should be nil")
    }
}
