// Tests/Views/VStackTests.swift
/*
 VStackTests.swift

 Tests for the VStack component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and subview handling.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class VStackTests: XCTestCase {
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
    
    func testVStackConstruction() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "VStack",
            "properties": {"spacing": 10.0, "alignment": "center"},
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
        
        let model = ActionUIModel.shared
        try model.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let element = model.descriptions[windowUUID] else {
            XCTFail("Failed to retrieve element from model for windowUUID: \(String(describing: windowUUID))")
            return
        }
        
        let state = ActionUIModel.shared.state(for: windowUUID)
        let validatedProperties = VStack.validateProperties(element.properties, logger)
        
        let view = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
        guard let children = element.subviews?["children"] as? [any ActionUIElement] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 2, "VStack should have 2 children")
        XCTAssertEqual((children[0] as? ViewElement)?.type, "Text", "First child should be Text")
        XCTAssertEqual((children[0] as? ViewElement)?.id, 2, "First child ID should be 2")
        XCTAssertEqual((children[1] as? ViewElement)?.type, "Text", "Second child should be Text")
        XCTAssertEqual((children[1] as? ViewElement)?.id, 3, "Second child ID should be 3")
        XCTAssertEqual(element.properties.cgFloat(forKey: "spacing"), 10.0, "spacing should be 10.0")
        XCTAssertEqual(element.properties["alignment"] as? String, "center", "alignment should be center")
        XCTAssertFalse(view is SwiftUI.EmptyView, "View should not be EmptyView")
        
        if state.wrappedValue[element.id] == nil {
            logger.log("Warning: State for id \(element.id) is nil", .warning)
        } else if let stateDict = state.wrappedValue[element.id] as? [String: Any] {
            logger.log("State dictionary: \(stateDict)", .debug)
        } else {
            XCTFail("State should be a dictionary or nil")
        }
    }
    
    func testVStackJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "VStack",
            "properties": {"spacing": 10.0, "alignment": "center"},
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
        
        let model = ActionUIModel.shared
        try model.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let element = model.descriptions[windowUUID] else {
            XCTFail("Failed to retrieve element from model for windowUUID: \(String(describing: windowUUID))")
            return
        }
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "VStack", "Element type should be VStack")
        XCTAssertEqual(element.properties.cgFloat(forKey: "spacing"), 10.0, "spacing should be 10.0")
        XCTAssertEqual(element.properties["alignment"] as? String, "center", "alignment should be center")
        
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
    
    func testVStackValidatePropertiesValid() {
        let properties: [String: Any] = ["spacing": 10.0, "alignment": "center"]
        
        let validated = VStack.validateProperties(properties, logger)
        
        XCTAssertEqual(validated.cgFloat(forKey: "spacing"), 10.0, "spacing should be valid")
        XCTAssertEqual(validated["alignment"] as? String, "center", "alignment should be valid")
    }
    
    func testVStackValidatePropertiesInvalid() {
        let properties: [String: Any] = ["spacing": "10", "alignment": "invalid"]
        
        let validated = VStack.validateProperties(properties, logger)
        
        XCTAssertNil(validated["spacing"], "Invalid spacing should be nil")
        XCTAssertNil(validated["alignment"], "Invalid alignment should be nil")
    }
    
    func testVStackValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = VStack.validateProperties(properties, logger)
        
        XCTAssertNil(validated["spacing"], "Missing spacing should be nil")
        XCTAssertNil(validated["alignment"], "Missing alignment should be nil")
    }
    
    func testVStackNilProperties() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "VStack",
            "properties": {},
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
        
        let model = ActionUIModel.shared
        try model.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        guard let element = model.descriptions[windowUUID] else {
            XCTFail("Failed to retrieve element from model for windowUUID: \(String(describing: windowUUID))")
            return
        }
        
        let state = ActionUIModel.shared.state(for: windowUUID)
        let validatedProperties = VStack.validateProperties(element.properties, logger)
        
        let view = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
        guard let children = element.subviews?["children"] as? [any ActionUIElement] else {
            XCTFail("Children should not be nil")
            return
        }
        
        XCTAssertEqual(children.count, 2, "VStack should have 2 children")
        XCTAssertNil(validatedProperties["spacing"], "spacing should be nil")
        XCTAssertNil(validatedProperties["alignment"], "alignment should be nil")
        XCTAssertFalse(view is SwiftUI.EmptyView, "View should not be EmptyView")
        
        if state.wrappedValue[element.id] == nil {
            logger.log("Warning: State for id \(element.id) is nil", .warning)
        } else if let stateDict = state.wrappedValue[element.id] as? [String: Any] {
            logger.log("State dictionary: \(stateDict)", .debug)
        } else {
            XCTFail("State should be a dictionary or nil")
        }
    }
}
