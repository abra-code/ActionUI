// Tests/Common/ActionUIModelTests.swift
/*
 ActionUIModelTests.swift

 Tests for the ActionUIModel class in the ActionUI component library.
 Verifies state management, element lookup, and description storage without triggering actions.
*/

import XCTest
import SwiftUI
@testable import ActionUI

// Logger that records messages without failing the test, used for tests that intentionally
// trigger .error-level logs (e.g. type-mismatch rejection in setElementState).
private final class RecordingLogger: ActionUILogger, @unchecked Sendable {
    private(set) var errors: [String] = []
    private(set) var warnings: [String] = []
    func log(_ message: String, _ level: LoggerLevel) {
        switch level {
        case .error:   errors.append(message)
        case .warning: warnings.append(message)
        default:       break
        }
    }
}

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
            "properties": ["title": "Enter text"]
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
                ["id": 2, "type": "TextField", "properties": ["title": "Enter text"]]
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
            "properties": ["title": "Name"]
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
                ["id": 2, "type": "TextField", "properties": ["title": "Name"]],
                ["id": 3, "type": "Toggle", "properties": ["title": "Active"]],
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
            "properties": ["title": "Enter text"]
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

    // MARK: - getElementState tests

    private func loadToggleElement(viewID: Int = 1) throws {
        let elementDict: [String: Any] = [
            "id": viewID,
            "type": "Toggle",
            "properties": ["title": "Feature"]
        ]
        _ = try ActionUIModel.shared.loadDescription(from: elementDict, windowUUID: windowUUID)
    }

    func testGetElementStateNilForUnknownWindow() throws {
        try loadToggleElement()
        let value = ActionUIModel.shared.getElementState(windowUUID: "nonexistent", viewID: 1, key: "isOn")
        XCTAssertNil(value, "Should return nil for unknown windowUUID")
    }

    func testGetElementStateNilForUnknownView() throws {
        try loadToggleElement()
        let value = ActionUIModel.shared.getElementState(windowUUID: windowUUID, viewID: 999, key: "isOn")
        XCTAssertNil(value, "Should return nil for unknown viewID")
    }

    func testGetElementStateNilForMissingKey() throws {
        try loadToggleElement()
        let value = ActionUIModel.shared.getElementState(windowUUID: windowUUID, viewID: 1, key: "nonexistent")
        XCTAssertNil(value, "Should return nil when key has never been set")
    }

    func testGetElementStateReturnsStoredValue() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.windowModels[windowUUID]?.viewModels[1]?.states["counter"] = 7
        let value = model.getElementState(windowUUID: windowUUID, viewID: 1, key: "counter")
        XCTAssertEqual(value as? Int, 7, "Should return the stored state value")
    }

    func testGetElementStateReflectsSetElementState() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.setElementState(windowUUID: windowUUID, viewID: 1, key: "score", value: 42)
        let value = model.getElementState(windowUUID: windowUUID, viewID: 1, key: "score")
        XCTAssertEqual(value as? Int, 42)
    }

    // MARK: - getElementStateAsString tests

    func testGetElementStateAsStringNilForUnknownWindow() throws {
        try loadToggleElement()
        let s = ActionUIModel.shared.getElementStateAsString(windowUUID: "nonexistent", viewID: 1, key: "k")
        XCTAssertNil(s)
    }

    func testGetElementStateAsStringNilForUnknownView() throws {
        try loadToggleElement()
        let s = ActionUIModel.shared.getElementStateAsString(windowUUID: windowUUID, viewID: 999, key: "k")
        XCTAssertNil(s)
    }

    func testGetElementStateAsStringNilForMissingKey() throws {
        try loadToggleElement()
        let s = ActionUIModel.shared.getElementStateAsString(windowUUID: windowUUID, viewID: 1, key: "nonexistent")
        XCTAssertNil(s)
    }

    func testGetElementStateAsStringBool() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.windowModels[windowUUID]?.viewModels[1]?.states["flag"] = true
        XCTAssertEqual(model.getElementStateAsString(windowUUID: windowUUID, viewID: 1, key: "flag"), "true")
        model.windowModels[windowUUID]?.viewModels[1]?.states["flag"] = false
        XCTAssertEqual(model.getElementStateAsString(windowUUID: windowUUID, viewID: 1, key: "flag"), "false")
    }

    func testGetElementStateAsStringDouble() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.windowModels[windowUUID]?.viewModels[1]?.states["progress"] = 0.75
        let s = model.getElementStateAsString(windowUUID: windowUUID, viewID: 1, key: "progress")
        XCTAssertEqual(s, "0.75")
    }

    func testGetElementStateAsStringInt() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.windowModels[windowUUID]?.viewModels[1]?.states["count"] = 3
        let s = model.getElementStateAsString(windowUUID: windowUUID, viewID: 1, key: "count")
        XCTAssertEqual(s, "3")
    }

    func testGetElementStateAsStringString() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.windowModels[windowUUID]?.viewModels[1]?.states["title"] = "hello"
        let s = model.getElementStateAsString(windowUUID: windowUUID, viewID: 1, key: "title")
        XCTAssertEqual(s, "hello")
    }

    // MARK: - setElementState tests

    func testSetElementStateNoOpForUnknownWindow() throws {
        try loadToggleElement()
        ActionUIModel.shared.setElementState(windowUUID: "nonexistent", viewID: 1, key: "k", value: 1)
        // No crash; no state stored in the real window
        XCTAssertNil(ActionUIModel.shared.getElementState(windowUUID: windowUUID, viewID: 1, key: "k"))
    }

    func testSetElementStateNoOpForUnknownView() throws {
        try loadToggleElement()
        ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: 999, key: "k", value: 1)
        // No crash
        XCTAssertNil(ActionUIModel.shared.getElementState(windowUUID: windowUUID, viewID: 999, key: "k"))
    }

    func testSetElementStateNewKey() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.setElementState(windowUUID: windowUUID, viewID: 1, key: "score", value: 10)
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 1, key: "score") as? Int, 10)
    }

    func testSetElementStateOverwritesSameType() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.setElementState(windowUUID: windowUUID, viewID: 1, key: "score", value: 10)
        model.setElementState(windowUUID: windowUUID, viewID: 1, key: "score", value: 20)
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 1, key: "score") as? Int, 20)
    }

    func testSetElementStateRejectsTypeMismatchAndLogsError() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.setElementState(windowUUID: windowUUID, viewID: 1, key: "flag", value: true)

        // Swap in a non-failing recording logger so the expected .error doesn't XCTFail
        let recordingLogger = RecordingLogger()
        model.logger = recordingLogger

        // Attempt to replace Bool with Int — should be rejected
        model.setElementState(windowUUID: windowUUID, viewID: 1, key: "flag", value: 1)

        model.logger = logger   // restore
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 1, key: "flag") as? Bool, true,
                       "Type mismatch should leave the original value unchanged")
        XCTAssertTrue(recordingLogger.errors.count > 0, "Type mismatch should log an error")
    }

    func testSetElementStateMultipleKeys() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.setElementState(windowUUID: windowUUID, viewID: 1, key: "a", value: "hello")
        model.setElementState(windowUUID: windowUUID, viewID: 1, key: "b", value: 3.14)
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 1, key: "a") as? String, "hello")
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 1, key: "b") as? Double, 3.14)
    }

    // MARK: - setElementStateFromString tests

    func testSetElementStateFromStringNoOpForUnknownWindow() throws {
        try loadToggleElement()
        ActionUIModel.shared.setElementStateFromString(windowUUID: "nonexistent", viewID: 1, key: "k", value: "v")
        XCTAssertNil(ActionUIModel.shared.getElementState(windowUUID: windowUUID, viewID: 1, key: "k"))
    }

    func testSetElementStateFromStringNoOpForUnknownView() throws {
        try loadToggleElement()
        ActionUIModel.shared.setElementStateFromString(windowUUID: windowUUID, viewID: 999, key: "k", value: "v")
        XCTAssertNil(ActionUIModel.shared.getElementState(windowUUID: windowUUID, viewID: 999, key: "k"))
    }

    func testSetElementStateFromStringNewKeyPlainString() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.setElementStateFromString(windowUUID: windowUUID, viewID: 1, key: "title", value: "hello")
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 1, key: "title") as? String, "hello",
                       "Plain string should be stored as String")
    }

    func testSetElementStateFromStringNewKeyInfersBool() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.setElementStateFromString(windowUUID: windowUUID, viewID: 1, key: "flag", value: "true")
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 1, key: "flag") as? Bool, true,
                       "JSON fragment 'true' should be stored as Bool")
    }

    func testSetElementStateFromStringNewKeyInfersInt() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.setElementStateFromString(windowUUID: windowUUID, viewID: 1, key: "count", value: "42")
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 1, key: "count") as? Int, 42,
                       "Whole-number JSON fragment should be stored as Int")
    }

    func testSetElementStateFromStringNewKeyInfersDouble() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.setElementStateFromString(windowUUID: windowUUID, viewID: 1, key: "ratio", value: "3.14")
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 1, key: "ratio") as? Double, 3.14,
                       "Fractional JSON fragment should be stored as Double")
    }

    func testSetElementStateFromStringNewKeyInfersArray() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.setElementStateFromString(windowUUID: windowUUID, viewID: 1, key: "items", value: "[1,2,3]")
        let stored = model.getElementState(windowUUID: windowUUID, viewID: 1, key: "items")
        XCTAssertNotNil(stored as? [Any], "JSON array string should be stored as Array")
    }

    func testSetElementStateFromStringExistingBoolTrue() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.setElementState(windowUUID: windowUUID, viewID: 1, key: "enabled", value: false)
        model.setElementStateFromString(windowUUID: windowUUID, viewID: 1, key: "enabled", value: "true")
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 1, key: "enabled") as? Bool, true)
    }

    func testSetElementStateFromStringExistingBoolFalse() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.setElementState(windowUUID: windowUUID, viewID: 1, key: "enabled", value: true)
        model.setElementStateFromString(windowUUID: windowUUID, viewID: 1, key: "enabled", value: "false")
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 1, key: "enabled") as? Bool, false)
    }

    func testSetElementStateFromStringExistingBoolInvalidStringNoOp() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.setElementState(windowUUID: windowUUID, viewID: 1, key: "enabled", value: true)
        model.setElementStateFromString(windowUUID: windowUUID, viewID: 1, key: "enabled", value: "yes")
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 1, key: "enabled") as? Bool, true,
                       "Invalid Bool string should leave existing value unchanged")
    }

    func testSetElementStateFromStringExistingDouble() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.setElementState(windowUUID: windowUUID, viewID: 1, key: "progress", value: 0.0)
        model.setElementStateFromString(windowUUID: windowUUID, viewID: 1, key: "progress", value: "0.75")
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 1, key: "progress") as? Double, 0.75)
    }

    func testSetElementStateFromStringExistingDoubleInvalidStringNoOp() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.setElementState(windowUUID: windowUUID, viewID: 1, key: "progress", value: 0.5)
        model.setElementStateFromString(windowUUID: windowUUID, viewID: 1, key: "progress", value: "notanumber")
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 1, key: "progress") as? Double, 0.5,
                       "Invalid Double string should leave existing value unchanged")
    }

    func testSetElementStateFromStringExistingInt() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.setElementState(windowUUID: windowUUID, viewID: 1, key: "count", value: 0)
        model.setElementStateFromString(windowUUID: windowUUID, viewID: 1, key: "count", value: "7")
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 1, key: "count") as? Int, 7)
    }

    func testSetElementStateFromStringExistingIntInvalidStringNoOp() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.setElementState(windowUUID: windowUUID, viewID: 1, key: "count", value: 5)
        model.setElementStateFromString(windowUUID: windowUUID, viewID: 1, key: "count", value: "abc")
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 1, key: "count") as? Int, 5,
                       "Invalid Int string should leave existing value unchanged")
    }

    func testSetElementStateFromStringExistingString() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.setElementState(windowUUID: windowUUID, viewID: 1, key: "title", value: "old")
        model.setElementStateFromString(windowUUID: windowUUID, viewID: 1, key: "title", value: "new")
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 1, key: "title") as? String, "new")
    }

    func testSetElementStateFromStringRoundTripViaAsString() throws {
        try loadToggleElement()
        let model = ActionUIModel.shared
        model.setElementState(windowUUID: windowUUID, viewID: 1, key: "score", value: 99)
        let asString = model.getElementStateAsString(windowUUID: windowUUID, viewID: 1, key: "score")
        XCTAssertEqual(asString, "99")
        model.setElementStateFromString(windowUUID: windowUUID, viewID: 1, key: "score", value: asString!)
        XCTAssertEqual(model.getElementState(windowUUID: windowUUID, viewID: 1, key: "score") as? Int, 99)
    }
}
