// Tests/Views/TableTests.swift
/*
 TableTests.swift

 Tests for the Table component in the ActionUI component library (macOS only).
 Verifies JSON decoding, element creation from dictionaries, view construction, and state handling.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class TableTests: XCTestCase {
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
    
    func testTableConstruction() throws {
        #if os(macOS)
        let jsonString = """
        {
            "id": 1,
            "type": "Table",
            "properties": {
                "itemType": {"viewType": "Text"},
                "columns": ["Name", "Action"],
                "rows": [["Alice", "Click"], ["Bob", "Edit"]],
                "widths": [100, 80],
                "actionID": "table.action",
                "padding": 10.0
            }
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
        let validatedProperties = Table.validateProperties(element.properties, logger)
        
        let _ = ActionUIRegistry.shared.buildView(for: element, state: state, windowUUID: windowUUID, validatedProperties: validatedProperties)
        
        logger.log("After registry build: state[\(element.id)] = \(String(describing: state.wrappedValue[element.id]))", .debug)
        
        if let stateDict = state.wrappedValue[element.id] as? [String: Any] {
            XCTAssertEqual(stateDict["content"] as? [[String]], [["Alice", "Click"], ["Bob", "Edit"]], "State content should match rows")
        }
        
        if let itemType = element.properties["itemType"] as? [String: Any] {
            XCTAssertEqual(itemType["viewType"] as? String, "Text", "ItemType viewType should be Text")
        } else {
            XCTFail("itemType should be a dictionary")
        }
        XCTAssertEqual((element.properties["columns"] as? [String])?.count, 2, "Columns should have 2 elements")
        XCTAssertEqual((element.properties["rows"] as? [[String]])?.count, 2, "Rows should have 2 elements")
        XCTAssertEqual((element.properties["widths"] as? [Int])?.count, 2, "Widths should have 2 elements")
        XCTAssertEqual(element.properties["actionID"] as? String, "table.action", "ActionID should be table.action")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "Padding should be 10.0")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
        
        if state.wrappedValue[element.id] == nil {
            logger.log("Warning: State for id \(element.id) is nil", .warning)
        } else if let stateDict = state.wrappedValue[element.id] as? [String: Any] {
            logger.log("State dictionary: \(stateDict)", .debug)
        } else {
            XCTFail("State should be a dictionary or nil")
        }
        #endif
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
