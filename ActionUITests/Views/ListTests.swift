// Tests/Views/ListTests.swift
/*
 ListTests.swift

 Tests for the List component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, and state handling.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ListTests: XCTestCase {
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
    
    func testListConstruction() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "List",
            "properties": [
                "itemType": ["viewType": "Text"],
                "items": ["Item1", "Item2"],
                "actionID": "list.action",
                "padding": 10.0
            ]
        ]
        let element = try! ViewElement(from: elementDict)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = List.validateProperties(element.properties, logger)
        
        let _ = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
        if let stateDict = state.wrappedValue[element.id] as? [String: Any] {
            XCTAssertEqual(stateDict["content"] as? [[String]], [["Item1"], ["Item2"]], "State content should match items")
            XCTAssertEqual(stateDict["value"] as? [String], [], "State value should be empty initially")
        } else {
            XCTFail("State should be a dictionary")
        }
    }
    
    func testListJSONDecoding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "List",
            "properties": [
                "itemType": ["viewType": "Button", "actionContext": "rowIndex"],
                "items": [["Item1", "Extra"], ["Item2", "Data"]],
                "actionID": "list.action",
                "doubleClickActionID": "list.doubleClick",
                "padding": 10.0
            ]
        ]
        
        let element = try! ViewElement(from: elementDict)
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "List", "Element type should be List")
        if let itemType = element.properties["itemType"] as? [String: Any] {
            XCTAssertEqual(itemType["viewType"] as? String, "Button", "itemType.viewType should be Button")
            XCTAssertEqual(itemType["actionContext"] as? String, "rowIndex", "itemType.actionContext should be rowIndex")
        } else {
            XCTFail("itemType should be valid dictionary")
        }
        XCTAssertEqual(element.properties["items"] as? [[String]], [["Item1", "Extra"], ["Item2", "Data"]], "items should match")
        XCTAssertEqual(element.properties["actionID"] as? String, "list.action", "actionID should be list.action")
        XCTAssertEqual(element.properties["doubleClickActionID"] as? String, "list.doubleClick", "doubleClickActionID should be list.doubleClick")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
    }
    
    func testListValidatePropertiesValid() {
        let properties: [String: Any] = [
            "itemType": ["viewType": "Image", "dataInterpretation": "systemName"],
            "items": ["star.fill", "heart.fill"],
            "actionID": "list.action",
            "doubleClickActionID": "list.doubleClick",
            "padding": 10.0
        ]
        
        let validated = List.validateProperties(properties, logger)
        
        if let itemType = validated["itemType"] as? [String: Any] {
            XCTAssertEqual(itemType["viewType"] as? String, "Image", "itemType.viewType should be preserved")
            XCTAssertEqual(itemType["dataInterpretation"] as? String, "systemName", "itemType.dataInterpretation should be preserved")
        } else {
            XCTFail("itemType should be valid dictionary")
        }
        XCTAssertEqual(validated["items"] as? [[String]], [["star.fill"], ["heart.fill"]], "items should be converted to string arrays")
        XCTAssertEqual(validated["actionID"] as? String, "list.action", "actionID should be preserved")
        XCTAssertEqual(validated["doubleClickActionID"] as? String, "list.doubleClick", "doubleClickActionID should be preserved")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "padding should be passed through")
    }
    
    func testListValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "itemType": ["viewType": "Invalid", "dataInterpretation": "invalid", "actionContext": "invalid"],
            "items": 123,
            "doubleClickActionID": 456
        ]
        
        let validated = List.validateProperties(properties, logger)
        
        if let itemType = validated["itemType"] as? [String: Any] {
            XCTAssertEqual(itemType["viewType"] as? String, "Text", "Invalid viewType should default to Text")
            XCTAssertEqual(itemType["dataInterpretation"] as? String, "invalid", "Invalid dataInterpretation should be preserved")
            XCTAssertEqual(itemType["actionContext"] as? String, "invalid", "Invalid actionContext should be preserved")
        } else {
            XCTFail("itemType should be valid dictionary")
        }
        XCTAssertEqual(validated["items"] as? [[String]], [], "Invalid items should default to []")
        XCTAssertNil(validated["doubleClickActionID"], "Invalid doubleClickActionID should be nil")
    }
    
    func testListValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = List.validateProperties(properties, logger)
        
        if let itemType = validated["itemType"] as? [String: Any] {
            XCTAssertEqual(itemType["viewType"] as? String, "Text", "Missing itemType should default to Text")
        } else {
            XCTFail("itemType should be valid dictionary")
        }
        XCTAssertEqual(validated["items"] as? [[String]], [], "Missing items should default to []")
        XCTAssertNil(validated["doubleClickActionID"], "Missing doubleClickActionID should be nil")
    }
}
