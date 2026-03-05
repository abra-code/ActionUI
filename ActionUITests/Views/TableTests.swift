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
    
    func testTableConstruction() throws {
        #if os(macOS)
        let jsonString = """
        {
            "id": 1,
            "type": "Table",
            "properties": {
                "columns": ["Name", "Action"],
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

        let actionUIModel = ActionUIModel.shared

        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        let validatedProperties = Table.validateProperties(element.properties, logger)

        let _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

        XCTAssertEqual(viewModel.states["content"] as? [[String]], [], "State content should start empty")

        // columnTypes should be auto-populated with Text defaults for each column
        if let columnTypes = validatedProperties["columnTypes"] as? [[String: Any]] {
            XCTAssertEqual(columnTypes.count, 2, "columnTypes should have 2 entries")
            XCTAssertEqual(columnTypes[0]["viewType"] as? String, "Text", "Default viewType should be Text")
            XCTAssertEqual(columnTypes[1]["viewType"] as? String, "Text", "Default viewType should be Text")
        } else {
            XCTFail("columnTypes should be a valid array")
        }
        XCTAssertEqual((element.properties["columns"] as? [String])?.count, 2, "Columns should have 2 elements")
        XCTAssertEqual((element.properties["widths"] as? [Int])?.count, 2, "Widths should have 2 elements")
        XCTAssertEqual(element.properties["actionID"] as? String, "table.action", "ActionID should be table.action")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "Padding should be 10.0")
        XCTAssertNil(element.subviews?["children"], "Children should be nil")
        #endif
    }
    
    func testTableValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "columnTypes": [
                ["viewType": "Invalid", "dataInterpretation": "invalid", "actionContext": "invalid"]
            ],
            "columns": 123,
            "widths": ["100"],
            "doubleClickActionID": 789
        ]

        let validated = Table.validateProperties(properties, logger)

        if let columnTypes = validated["columnTypes"] as? [[String: Any]] {
            XCTAssertEqual(columnTypes.count, 1, "columnTypes should have 1 entry")
            XCTAssertEqual(columnTypes[0]["viewType"] as? String, "Text", "Invalid viewType should default to Text")
        } else {
            XCTFail("columnTypes should be valid array")
        }
        XCTAssertEqual(validated["columns"] as? [String], [], "Invalid columns should default to []")
        XCTAssertNil(validated["widths"], "Invalid widths should be nil")
        XCTAssertNil(validated["doubleClickActionID"], "Invalid doubleClickActionID should be nil")
    }

    func testTableValidatePropertiesMissing() {
        let properties: [String: Any] = [:]

        let validated = Table.validateProperties(properties, logger)

        if let columnTypes = validated["columnTypes"] as? [[String: Any]] {
            XCTAssertEqual(columnTypes.count, 0, "Missing columnTypes with no columns should be empty")
        } else {
            XCTFail("columnTypes should be valid array")
        }
        XCTAssertEqual(validated["columns"] as? [String], [], "Missing columns should default to []")
        XCTAssertNil(validated["widths"], "Missing widths should be nil")
        XCTAssertNil(validated["doubleClickActionID"], "Missing doubleClickActionID should be nil")
    }

    // MARK: - Row management tests (macOS only, Table is macOS-only)

    #if os(macOS)
    private func loadTableElement(columns: [String] = ["Name", "Age"]) throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Table",
            "properties": [
                "columns": columns,
                "actionID": "table.action"
            ]
        ]
        _ = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)
    }

    func testTableGetRowsEmptyOnLoad() throws {
        try loadTableElement()
        let rows = ActionUIModel.shared.getElementRows(windowUUID: windowUUID, viewID: 1)
        XCTAssertEqual(rows, [], "Freshly loaded Table should have empty rows")
    }

    func testTableSetAndGetRows() throws {
        try loadTableElement()
        let model = ActionUIModel.shared
        let newRows = [["Alice", "30"], ["Bob", "25"]]
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: newRows)
        XCTAssertEqual(model.getElementRows(windowUUID: windowUUID, viewID: 1), newRows)
    }

    func testTableClearRows() throws {
        try loadTableElement()
        let model = ActionUIModel.shared
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Alice", "30"]])
        model.clearElementRows(windowUUID: windowUUID, viewID: 1)
        XCTAssertEqual(model.getElementRows(windowUUID: windowUUID, viewID: 1), [])
    }

    func testTableAppendRows() throws {
        try loadTableElement()
        let model = ActionUIModel.shared
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Alice", "30"]])
        model.appendElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Bob", "25"], ["Charlie", "22"]])
        XCTAssertEqual(model.getElementRows(windowUUID: windowUUID, viewID: 1), [
            ["Alice", "30"], ["Bob", "25"], ["Charlie", "22"]
        ])
    }

    func testTableGetColumnCountFromContent() throws {
        try loadTableElement(columns: ["Name", "Age"])
        let model = ActionUIModel.shared
        // Load a row with a hidden 3rd column (e.g. a row ID not shown in the UI)
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Alice", "30", "hidden-id"]])
        XCTAssertEqual(model.getElementColumnCount(windowUUID: windowUUID, viewID: 1), 3,
                       "Column count from content should include hidden columns beyond visible ones")
    }

    func testTableGetColumnCountFromPropertiesBeforeContentLoaded() throws {
        try loadTableElement(columns: ["Name", "Age"])
        XCTAssertEqual(ActionUIModel.shared.getElementColumnCount(windowUUID: windowUUID, viewID: 1), 2,
                       "Column count should reflect the 'columns' property when no content is loaded")
    }
    #endif
}
