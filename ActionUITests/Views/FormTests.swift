// Tests/Views/FormTests.swift
/*
 FormTests.swift

 Tests for the Form component in the ActionUI component library.
 Verifies JSON decoding, element creation from dictionaries, view construction, and state initialization.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class FormTests: XCTestCase {
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
    
    func testFormConstructionWithChildren() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Form",
            "properties": [:],
            "children": [
                ["id": 2, "type": "Text", "properties": ["text": "Field 1"]],
                ["id": 3, "type": "Button", "properties": ["label": "Submit", "actionID": "submitAction"]]
            ]
        ]
        let element = try! ViewElement(from: elementDict)
        let state = ActionUIModel.shared.state(for: windowUUID)
        let validatedProperties = Form.validateProperties(element.properties, logger)
        
        _ = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        XCTAssertNotNil(state.wrappedValue[element.id], "Registry should initialize state for Form")
        XCTAssertTrue(
            PropertyComparison.arePropertiesEqual(
                (state.wrappedValue[element.id] as? [String: Any])?["validatedProperties"] as? [String: Any] ?? [:],
                validatedProperties
            ),
            "State should include validated properties"
        )
        
        // Verify children
        guard let children = element.subviews?["children"] as? [any ActionUIElement] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 2, "Should have 2 children")
        XCTAssertEqual((children[0] as? ViewElement)?.type, "Text", "First child should be Text")
        XCTAssertEqual((children[0] as? ViewElement)?.properties["text"] as? String, "Field 1", "First child text should be correct")
        XCTAssertEqual((children[1] as? ViewElement)?.type, "Button", "Second child should be Button")
        XCTAssertEqual((children[1] as? ViewElement)?.properties["label"] as? String, "Submit", "Second child label should be correct")
    }
    
    func testFormJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Form",
            "properties": {
                "padding": 10.0
            },
            "children": [
                {"id": 2, "type": "Text", "properties": {"text": "Field 1"}}
            ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let model = ActionUIModel.shared
        
        // Parse JSON into ViewElement
        try model.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let element = model.descriptions[windowUUID] else {
            XCTFail("Failed to retrieve element from model for windowUUID: \(String(describing: windowUUID))")
            return
        }
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Form", "Element type should be Form")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "Padding should be 10.0")
        
        guard let children = element.subviews?["children"] as? [any ActionUIElement] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 1, "Should have 1 child")
        XCTAssertEqual((children[0] as? ViewElement)?.type, "Text", "Child should be Text")
        XCTAssertEqual((children[0] as? ViewElement)?.properties["text"] as? String, "Field 1", "Child text should be correct")
    }
    
    func testFormElementCreation() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Form",
            "properties": ["padding": 10],
            "children": [
                ["id": 2, "type": "Text", "properties": ["text": "Field 1"]]
            ]
        ]
        
        let element = try! ViewElement(from: elementDict)
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Form", "Element type should be Form")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "Padding should be 10.0")
        
        guard let children = element.subviews?["children"] as? [any ActionUIElement] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 1, "Should have 1 child")
        XCTAssertEqual((children[0] as? ViewElement)?.type, "Text", "Child should be Text")
        XCTAssertEqual((children[0] as? ViewElement)?.properties["text"] as? String, "Field 1", "Child text should be correct")
    }
    
    func testFormValidateProperties() {
        let properties: [String: Any] = ["padding": 10.0]
        let validated = Form.validateProperties(properties, logger)
        
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "Padding should be valid")
    }
}
