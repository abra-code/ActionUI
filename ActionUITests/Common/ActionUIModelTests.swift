// Tests/Common/ActionUIModelTests.swift
/*
 ActionUIModelTests.swift

 Tests for the ActionUIModel class in the ActionUI component library.
 Verifies state management, element lookup, and description storage without triggering actions.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ActionUIModelTests: XCTestCase {
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
    
    func testSetAndGetElementValue() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TextField",
            "properties": ["placeholder": "Enter text"]
        ]
        
        let actionUIModel = ActionUIModel.shared
        _ = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)

        actionUIModel.setElementValue(windowUUID: windowUUID, viewID: 1, value: "Test")
        let value = actionUIModel.getElementValue(windowUUID: windowUUID, viewID: 1)
        XCTAssertEqual(value as? String, "Test", "Value should be set and retrieved correctly")

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[1] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        logger.log("Value for viewID 1: \(String(describing: viewModel.value))", .debug)
        XCTAssertEqual(viewModel.value as? String, "Test", "viewModel should store value")
    }
    
    func testSetElementProperty() {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Gauge",
            "properties": ["value": 0.5]
        ]
        
        let actionUIModel = ActionUIModel.shared
        do {
            _ = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)
        } catch {
            XCTFail("Failed to load element from dictionary. Error: \(error)")
            return
        }

        actionUIModel.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "value", value: 0.75)

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[1] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        logger.log("Value for viewID 1: \(String(describing: viewModel.value))", .debug)
        let validatedProperties = viewModel.validatedProperties
        XCTAssertEqual(validatedProperties.double(forKey: "value"), 0.75, "Property value should be updated")
    }
    
    func testFindElement() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Form",
            "properties": [:],
            "children": [
                ["id": 2, "type": "TextField", "properties": ["placeholder": "Enter text"]]
            ]
        ]

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)        
        let foundElement = element.findElement(by: 2)
        
        logger.log("Found element: \(String(describing: foundElement))", .debug)
        XCTAssertNotNil(foundElement, "Should find element with ID 2")
        XCTAssertEqual(foundElement?.id, 2, "Found element should have ID 2")
        XCTAssertEqual(foundElement?.type, "TextField", "Found element should be TextField")
    }
    
    func testMissingElement() {
        let actionUIModel = ActionUIModel.shared
        actionUIModel.setElementValue(windowUUID: windowUUID, viewID: 999, value: "Test")

        let value = actionUIModel.getElementValue(windowUUID: windowUUID, viewID: 999)
        XCTAssertNil(value, "Value for missing element should be nil")
    }

    // MARK: - getElementInfo tests

    func testGetElementInfoSingleElement() throws {
        let elementDict: [String: Any] = [
            "id": 5,
            "type": "TextField",
            "properties": ["placeholder": "Name"]
        ]

        let actionUIModel = ActionUIModel.shared
        _ = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)

        let info = actionUIModel.getElementInfo(windowUUID: windowUUID)
        XCTAssertEqual(info.count, 1)
        XCTAssertEqual(info[5], "TextField")
    }

    func testGetElementInfoWithChildren() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Form",
            "properties": [:],
            "children": [
                ["id": 2, "type": "TextField", "properties": ["placeholder": "Name"]],
                ["id": 3, "type": "Toggle", "properties": ["label": "Active"]],
                ["id": 4, "type": "Slider", "properties": [:]]
            ]
        ]

        let actionUIModel = ActionUIModel.shared
        _ = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)

        let info = actionUIModel.getElementInfo(windowUUID: windowUUID)
        XCTAssertEqual(info.count, 4)
        XCTAssertEqual(info[1], "Form")
        XCTAssertEqual(info[2], "TextField")
        XCTAssertEqual(info[3], "Toggle")
        XCTAssertEqual(info[4], "Slider")
    }

    func testGetElementInfoExcludesNegativeAndZeroIDs() throws {
        // Element with no explicit id gets auto-assigned a negative id
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Form",
            "properties": [:],
            "children": [
                ["id": 2, "type": "TextField", "properties": [:]],
                ["type": "Text", "properties": ["text": "Label"]]  // no id, auto-assigned negative
            ]
        ]

        let actionUIModel = ActionUIModel.shared
        _ = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)

        let info = actionUIModel.getElementInfo(windowUUID: windowUUID)
        XCTAssertEqual(info.count, 2, "Should only include positive IDs")
        XCTAssertEqual(info[1], "Form")
        XCTAssertEqual(info[2], "TextField")
        for key in info.keys {
            XCTAssertGreaterThan(key, 0, "All returned IDs should be positive")
        }
    }

    func testGetElementInfoNestedChildren() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "VStack",
            "properties": [:],
            "children": [
                [
                    "id": 2,
                    "type": "Form",
                    "properties": [:],
                    "children": [
                        ["id": 3, "type": "TextField", "properties": [:]],
                        ["id": 4, "type": "SecureField", "properties": [:]]
                    ]
                ],
                ["id": 5, "type": "Button", "properties": [:]]
            ]
        ]

        let actionUIModel = ActionUIModel.shared
        _ = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)

        let info = actionUIModel.getElementInfo(windowUUID: windowUUID)
        XCTAssertEqual(info.count, 5)
        XCTAssertEqual(info[1], "VStack")
        XCTAssertEqual(info[2], "Form")
        XCTAssertEqual(info[3], "TextField")
        XCTAssertEqual(info[4], "SecureField")
        XCTAssertEqual(info[5], "Button")
    }

    func testGetElementInfoContainerWithoutID() throws {
        let elementDict: [String: Any] = [
            "type": "VStack",
            "properties": [:],
            "children": [
                ["id": 2, "type": "TextField", "properties": [:]],
                ["id": 3, "type": "Toggle", "properties": [:]]
            ]
        ]

        let actionUIModel = ActionUIModel.shared
        _ = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)

        let info = actionUIModel.getElementInfo(windowUUID: windowUUID)
        XCTAssertEqual(info.count, 2, "Container without id should be excluded but children included")
        XCTAssertEqual(info[2], "TextField")
        XCTAssertEqual(info[3], "Toggle")
    }

    func testGetElementInfoEmptyForUnknownWindow() {
        let actionUIModel = ActionUIModel.shared
        let info = actionUIModel.getElementInfo(windowUUID: "nonexistent-uuid")
        XCTAssertTrue(info.isEmpty, "Should return empty dict for unknown window")
    }

    func testGetElementInfoEmptyAfterTestReset() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TextField",
            "properties": [:]
        ]

        let actionUIModel = ActionUIModel.shared
        _ = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)

        XCTAssertFalse(actionUIModel.getElementInfo(windowUUID: windowUUID).isEmpty)

        ActionUIModel.resetForTesting()

        let info = actionUIModel.getElementInfo(windowUUID: windowUUID)
        XCTAssertTrue(info.isEmpty, "Should return empty dict after test reset")
    }

    // MARK: - getElementRows / setElementRows / clearElementRows / appendElementRows tests

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

    func testGetElementRowsEmptyOnLoad() throws {
        try loadListElement()
        let rows = ActionUIModel.shared.getElementRows(windowUUID: windowUUID, viewID: 1)
        XCTAssertEqual(rows, [], "Freshly loaded List should have empty rows")
    }

    func testGetElementRowsNilForUnknownView() throws {
        try loadListElement()
        let rows = ActionUIModel.shared.getElementRows(windowUUID: windowUUID, viewID: 999)
        XCTAssertNil(rows, "Should return nil for an unknown viewID")
    }

    func testGetElementRowsNilForUnknownWindow() {
        let rows = ActionUIModel.shared.getElementRows(windowUUID: "nonexistent", viewID: 1)
        XCTAssertNil(rows, "Should return nil for an unknown windowUUID")
    }

    func testSetElementRowsAndGet() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        let newRows = [["Alice", "30"], ["Bob", "25"]]
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: newRows)
        XCTAssertEqual(model.getElementRows(windowUUID: windowUUID, viewID: 1), newRows)
    }

    func testSetElementRowsReplacesExisting() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Alice"], ["Bob"]])
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Charlie"]])
        XCTAssertEqual(model.getElementRows(windowUUID: windowUUID, viewID: 1), [["Charlie"]])
    }

    func testSetElementRowsClearsSelectionWhenRowRemoved() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        let rows = [["Alice", "30"], ["Bob", "25"]]
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: rows)
        // Simulate selection of "Alice" row
        model.windowModels[windowUUID]?.viewModels[1]?.value = ["Alice", "30"]
        // Replace rows without "Alice"
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Bob", "25"]])
        let selectedValue = model.windowModels[windowUUID]?.viewModels[1]?.value as? [String]
        XCTAssertEqual(selectedValue, [], "Selection should be cleared when selected row is removed")
    }

    func testSetElementRowsPreservesSelectionWhenRowRetained() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        let rows = [["Alice", "30"], ["Bob", "25"]]
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: rows)
        model.windowModels[windowUUID]?.viewModels[1]?.value = ["Alice", "30"]
        // Replace rows keeping "Alice"
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Alice", "30"], ["Charlie", "22"]])
        let selectedValue = model.windowModels[windowUUID]?.viewModels[1]?.value as? [String]
        XCTAssertEqual(selectedValue, ["Alice", "30"], "Selection should be preserved when selected row is still present")
    }

    func testSetElementRowsNoOpForUnknownView() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        model.setElementRows(windowUUID: windowUUID, viewID: 999, rows: [["Alice"]])
        // No crash; the known element is unaffected
        XCTAssertEqual(model.getElementRows(windowUUID: windowUUID, viewID: 1), [])
    }

    func testClearElementRows() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Alice"], ["Bob"]])
        model.clearElementRows(windowUUID: windowUUID, viewID: 1)
        XCTAssertEqual(model.getElementRows(windowUUID: windowUUID, viewID: 1), [], "Rows should be empty after clear")
    }

    func testClearElementRowsClearsSelection() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Alice"]])
        model.windowModels[windowUUID]?.viewModels[1]?.value = ["Alice"]
        model.clearElementRows(windowUUID: windowUUID, viewID: 1)
        let selectedValue = model.windowModels[windowUUID]?.viewModels[1]?.value as? [String]
        XCTAssertEqual(selectedValue, [], "Selection should be cleared after clearElementRows")
    }

    func testClearElementRowsNoOpForUnknownView() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Alice"]])
        model.clearElementRows(windowUUID: windowUUID, viewID: 999) // no-op
        XCTAssertEqual(model.getElementRows(windowUUID: windowUUID, viewID: 1), [["Alice"]])
    }

    func testAppendElementRows() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Alice"]])
        model.appendElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Bob"], ["Charlie"]])
        XCTAssertEqual(model.getElementRows(windowUUID: windowUUID, viewID: 1), [["Alice"], ["Bob"], ["Charlie"]])
    }

    func testAppendElementRowsToEmpty() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        model.appendElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Alice"]])
        XCTAssertEqual(model.getElementRows(windowUUID: windowUUID, viewID: 1), [["Alice"]])
    }

    func testAppendElementRowsNoOpForUnknownView() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        model.appendElementRows(windowUUID: windowUUID, viewID: 999, rows: [["Alice"]])
        XCTAssertEqual(model.getElementRows(windowUUID: windowUUID, viewID: 1), [])
    }

    // MARK: - getElementColumnCount tests

    func testGetElementColumnCountFromContent() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["A", "B", "C"], ["D", "E", "F"]])
        XCTAssertEqual(model.getElementColumnCount(windowUUID: windowUUID, viewID: 1), 3)
    }

    func testGetElementColumnCountMaxAcrossRows() throws {
        try loadListElement()
        let model = ActionUIModel.shared
        // Rows with varying column counts; max should be reported
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["A", "B"], ["C", "D", "E"]])
        XCTAssertEqual(model.getElementColumnCount(windowUUID: windowUUID, viewID: 1), 3)
    }

    func testGetElementColumnCountFromPropertiesWhenNoContent() throws {
        #if os(macOS)
        // columns is a Table-only property; List does not validate or expose it
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Table",
            "properties": [
                "itemType": ["viewType": "Text"],
                "columns": ["Name", "Age", "Score"]
            ]
        ]
        _ = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)
        XCTAssertEqual(ActionUIModel.shared.getElementColumnCount(windowUUID: windowUUID, viewID: 1), 3,
                       "Should fall back to column count from validated 'columns' property when no content is loaded")
        #endif
    }

    func testGetElementColumnCountZeroForNonTableElement() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "TextField",
            "properties": ["placeholder": "Enter text"]
        ]
        _ = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)
        XCTAssertEqual(ActionUIModel.shared.getElementColumnCount(windowUUID: windowUUID, viewID: 1), 0,
                       "Should return 0 for non-table elements")
    }

    func testGetElementColumnCountZeroForUnknownView() {
        XCTAssertEqual(ActionUIModel.shared.getElementColumnCount(windowUUID: windowUUID, viewID: 999), 0)
    }

    // MARK: - getElementProperty tests

    func testGetElementPropertyReturnsValue() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Gauge",
            "properties": ["value": 0.5]
        ]
        let model = ActionUIModel.shared
        _ = try model.loadDescription(from: elementDict, windowUUID: windowUUID)
        let value = model.getElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "value")
        XCTAssertEqual(value as? Double, 0.5, "Should return validated property value")
    }

    func testGetElementPropertyNilForMissingProperty() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Gauge",
            "properties": ["value": 0.5]
        ]
        let model = ActionUIModel.shared
        _ = try model.loadDescription(from: elementDict, windowUUID: windowUUID)
        let value = model.getElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "nonexistent")
        XCTAssertNil(value, "Should return nil for a property that does not exist")
    }

    func testGetElementPropertyNilForUnknownView() {
        let value = ActionUIModel.shared.getElementProperty(windowUUID: windowUUID, viewID: 999, propertyName: "value")
        XCTAssertNil(value, "Should return nil for an unknown viewID")
    }

    func testGetElementPropertyReflectsSetElementProperty() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Gauge",
            "properties": ["value": 0.5]
        ]
        let model = ActionUIModel.shared
        _ = try model.loadDescription(from: elementDict, windowUUID: windowUUID)
        model.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "value", value: 0.9)
        let retrieved = model.getElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "value")
        XCTAssertEqual(retrieved as? Double, 0.9, "getElementProperty should reflect value set by setElementProperty")
    }
}
