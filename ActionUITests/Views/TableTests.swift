// Tests/Views/TableTests.swift
/*
 TableTests.swift

 Tests for the Table component in the ActionUI component library (macOS only).
 Verifies JSON decoding, property validation, view construction, and state handling.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class TableTests: XCTestCase {
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
    
    func testTableConstruction() {
        #if os(macOS)
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Table",
            "properties": [
                "itemType": ["viewType": "Text"],
                "columns": ["Name", "Action"],
                "rows": [["Alice", "Click"], ["Bob", "Edit"]],
                "widths": [100, 80],
                "actionID": "table.action",
                "padding": 10.0
            ]
        ]
        let element = try! ViewElement(from: elementDict)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = Table.validateProperties(element.properties, logger)
        
        let view = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
        if let stateDict = state.wrappedValue[element.id] as? [String: Any] {
            XCTAssertEqual(stateDict["content"] as? [[String]], [["Alice", "Click"], ["Bob", "Edit"]], "State content should match rows")
            XCTAssertEqual(stateDict["value"] as? [String], [], "State value should be empty initially")
        } else {
            XCTFail("State should be a dictionary")
        }
        #else
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Table",
            "properties": [
                "itemType": ["viewType": "Text"],
                "columns": ["Name"],
                "rows": [["Alice"]]
            ]
        ]
        let element = try! ViewElement(from: elementDict)
        let state = ActionUIModel.shared.state(for: UUID().uuidString)
        let validatedProperties = Table.validateProperties(element.properties, logger)
        
        let view = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: UUID().uuidString, validatedProperties: validatedProperties)
        
        XCTAssertTrue(view is SwiftUI.EmptyView, "View should be EmptyView on non-macOS platforms")
        #endif
    }
    
    func testTableJSONDecoding() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Table",
            "properties": [
                "itemType": ["viewType": "Button", "actionContext": "rowColumnIndex"],
                "columns": ["Name", "Action"],
                "rows": [["Alice", "Click"], ["Bob", "Edit"]],
                "widths": [100, 80],
                "actionID": "table.action",
                "doubleClickActionID": "table.doubleClick",
                "padding": 10.0
            ]
        ]
        
        let element = try! ViewElement(from: elementDict)
        
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Table", "Element type should be Table")
        if let itemType = element.properties["itemType"] as? [String: Any] {
            XCTAssertEqual(itemType["viewType"] as? String, "Button", "itemType.viewType should be Button")
            XCTAssertEqual(itemType["actionContext"] as? String, "rowColumnIndex", "itemType.actionContext should be rowColumnIndex")
        } else {
            XCTFail("itemType should be valid dictionary")
        }
        XCTAssertEqual(element.properties["columns"] as? [String], ["Name", "Action"], "columns should match")
        XCTAssertEqual(element.properties["rows"] as? [[String]], [["Alice", "Click"], ["Bob", "Edit"]], "rows should match")
        XCTAssertEqual(element.properties["widths"] as? [Int], [100, 80], "widths should match")
        XCTAssertEqual(element.properties["actionID"] as? String, "table.action", "actionID should be table.action")
        XCTAssertEqual(element.properties["doubleClickActionID"] as? String, "table.doubleClick", "doubleClickActionID should be table.doubleClick")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
    }
    
    func testTableValidatePropertiesValid() {
        let properties: [String: Any] = [
            "itemType": ["viewType": "Image", "dataInterpretation": "systemName"],
            "columns": ["Icon"],
            "rows": [["star.fill"], ["heart.fill"]],
            "widths": [50],
            "actionID": "table.action",
            "doubleClickActionID": "table.doubleClick",
            "padding": 10.0
        ]
        
        let validated = Table.validateProperties(properties, logger)
        
        if let itemType = validated["itemType"] as? [String: Any] {
            XCTAssertEqual(itemType["viewType"] as? String, "Image", "itemType.viewType should be preserved")
            XCTAssertEqual(itemType["dataInterpretation"] as? String, "systemName", "itemType.dataInterpretation should be preserved")
        } else {
            XCTFail("itemType should be valid dictionary")
        }
        XCTAssertEqual(validated["columns"] as? [String], ["Icon"], "columns should be preserved")
        XCTAssertEqual(validated["rows"] as? [[String]], [["star.fill"], ["heart.fill"]], "rows should be preserved")
        XCTAssertEqual(validated["widths"] as? [Int], [50], "widths should be preserved")
        XCTAssertEqual(validated["actionID"] as? String, "table.action", "actionID should be preserved")
        XCTAssertEqual(validated["doubleClickActionID"] as? String, "table.doubleClick", "doubleClickActionID should be preserved")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "padding should be passed through")
    }
    
    func testTableValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "itemType": ["viewType": "Invalid", "dataInterpretation": "invalid", "actionContext": "invalid"],
            "columns": 123,
            "rows": 456,
            "widths": ["100"],
            "doubleClickActionID": 789
        ]
        
        let validated = Table.validateProperties(properties, logger)
        
        if let itemType = validated["itemType"] as? [String: Any] {
            XCTAssertEqual(itemType["viewType"] as? String, "Text", "Invalid viewType should default to Text")
            XCTAssertEqual(itemType["dataInterpretation"] as? String, "invalid", "Invalid dataInterpretation should be preserved")
            XCTAssertEqual(itemType["actionContext"] as? String, "invalid", "Invalid actionContext should be preserved")
        } else {
            XCTFail("itemType should be valid dictionary")
        }
        XCTAssertEqual(validated["columns"] as? [String], [], "Invalid columns should default to []")
        XCTAssertEqual(validated["rows"] as? [[String]], [], "Invalid rows should default to []")
        XCTAssertNil(validated["widths"], "Invalid widths should be nil")
        XCTAssertNil(validated["doubleClickActionID"], "Invalid doubleClickActionID should be nil")
    }
    
    func testTableValidatePropertiesMissing() {
        let properties: [String: Any] = [:]
        
        let validated = Table.validateProperties(properties, logger)
        
        if let itemType = validated["itemType"] as? [String: Any] {
            XCTAssertEqual(itemType["viewType"] as? String, "Text", "Missing itemType should default to Text")
        } else {
            XCTFail("itemType should be valid dictionary")
        }
        XCTAssertEqual(validated["columns"] as? [String], [], "Missing columns should default to []")
        XCTAssertEqual(validated["rows"] as? [[String]], [], "Missing rows should default to []")
        XCTAssertNil(validated["widths"], "Missing widths should be nil")
        XCTAssertNil(validated["doubleClickActionID"], "Missing doubleClickActionID should be nil")
    }
}
