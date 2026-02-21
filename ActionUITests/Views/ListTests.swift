// Tests/Views/ListTests.swift
/*
 ListTests.swift

 Tests for the List component in the ActionUI component library.
 Verifies JSON decoding, element creation from dictionaries, view construction, and state handling.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ListTests: XCTestCase {
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
    
    func testListConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "List",
            "properties": [
                "itemType": ["viewType": "Text"],
                "actionID": "list.action",
                "padding": 10.0
            ]
        ]

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        let validatedProperties = List.validateProperties(element.properties, logger)
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

        XCTAssertEqual(viewModel.states["content"] as? [[String]], [], "State content should start empty")
    }
    
    func testListJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "List",
            "properties": {
                "itemType": {"viewType": "Button", "actionContext": "rowIndex"},
                "actionID": "list.action",
                "doubleClickActionID": "list.doubleClick",
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

        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "List", "Element type should be List")
        if let itemType = element.properties["itemType"] as? [String: Any] {
            XCTAssertEqual(itemType["viewType"] as? String, "Button", "itemType.viewType should be Button")
            XCTAssertEqual(itemType["actionContext"] as? String, "rowIndex", "itemType.actionContext should be rowIndex")
        } else {
            XCTFail("itemType should be valid dictionary")
        }
        XCTAssertEqual(element.properties["actionID"] as? String, "list.action", "actionID should be list.action")
        XCTAssertEqual(element.properties["doubleClickActionID"] as? String, "list.doubleClick", "doubleClickActionID should be list.doubleClick")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        XCTAssertEqual(viewModel.states["content"] as? [[String]], [], "State content should start empty")
        XCTAssertEqual(viewModel.value as? [String], [], "State value should be empty")
    }

    func testListValidatePropertiesValid() {
        let properties: [String: Any] = [
            "itemType": ["viewType": "Image", "dataInterpretation": "systemName"],
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
        XCTAssertEqual(validated["actionID"] as? String, "list.action", "actionID should be preserved")
        XCTAssertEqual(validated["doubleClickActionID"] as? String, "list.doubleClick", "doubleClickActionID should be preserved")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "padding should be passed through")
    }

    func testListValidatePropertiesInvalid() {
        let properties: [String: Any] = [
            "itemType": ["viewType": "Invalid", "dataInterpretation": "invalid", "actionContext": "invalid"],
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
        XCTAssertNil(validated["doubleClickActionID"], "Missing doubleClickActionID should be nil")
    }

    // MARK: - Row management tests

    private func loadListElement(viewID: Int = 1) throws {
        let elementDict: [String: Any] = [
            "id": viewID,
            "type": "List",
            "properties": [
                "itemType": ["viewType": "Text"],
                "actionID": "list.action"
            ]
        ]
        _ = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)
    }

    func testListGetRowsEmptyOnLoad() throws {
        try loadListElement()
        let rows = ActionUIModel.shared.getElementRows(windowUUID: windowUUID, viewID: 1)
        XCTAssertEqual(rows, [], "Freshly loaded List should have empty rows")
    }

    func testListSetAndGetRows() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        let newRows = [["Row One"], ["Row Two"], ["Row Three"]]
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: newRows)
        XCTAssertEqual(model.getElementRows(windowUUID: windowUUID, viewID: 1), newRows)
    }

    func testListSetRowsReplacesExisting() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Old"]])
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["New"]])
        XCTAssertEqual(model.getElementRows(windowUUID: windowUUID, viewID: 1), [["New"]])
    }

    func testListClearRows() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["A"], ["B"]])
        model.clearElementRows(windowUUID: windowUUID, viewID: 1)
        XCTAssertEqual(model.getElementRows(windowUUID: windowUUID, viewID: 1), [])
    }

    func testListClearRowsClearsSelection() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Selected"]])
        model.windowModels[windowUUID]?.viewModels[1]?.value = ["Selected"]
        model.clearElementRows(windowUUID: windowUUID, viewID: 1)
        let selectedValue = model.windowModels[windowUUID]?.viewModels[1]?.value as? [String]
        XCTAssertEqual(selectedValue, [], "Selection should be cleared after clearElementRows")
    }

    func testListAppendRows() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["First"]])
        model.appendElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Second"], ["Third"]])
        XCTAssertEqual(model.getElementRows(windowUUID: windowUUID, viewID: 1), [["First"], ["Second"], ["Third"]])
    }

    func testListAppendRowsToEmpty() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        model.appendElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Only"]])
        XCTAssertEqual(model.getElementRows(windowUUID: windowUUID, viewID: 1), [["Only"]])
    }

    func testListGetColumnCountFromContent() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["A", "B"], ["C", "D", "E"]])
        XCTAssertEqual(model.getElementColumnCount(windowUUID: windowUUID, viewID: 1), 3,
                       "Should report max column count across all rows")
    }

    func testListRowsNilForUnknownViewID() throws {
        try loadListElement()
        XCTAssertNil(ActionUIModel.shared.getElementRows(windowUUID: windowUUID, viewID: 999))
    }
}
