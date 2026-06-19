// Tests/Common/ActionUIModelInsertionTests.swift
/*
 Tests for the runtime structural mutation API:
   ActionUIModel.insertElement / insertRow / removeElement
*/

import XCTest
import SwiftUI
@testable import ActionUI

// Logger that records messages without failing the test, used when testing
// intentional error conditions (e.g. id conflict, notAContainer).
private final class RecordingLogger: ActionUILogger, @unchecked Sendable {
    private(set) var errors: [String] = []
    func log(_ message: String, _ level: LoggerLevel) {
        if level == .error { errors.append(message) }
    }
}

@MainActor
final class ActionUIModelInsertionTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!
    private let model = ActionUIModel.shared

    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        model.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func loadVStack(id: Int = 1, children: [[String: Any]] = []) throws {
        var dict: [String: Any] = ["id": id, "type": "VStack", "properties": [:]]
        if !children.isEmpty { dict["children"] = children }
        _ = try model.loadDescription(from: dict, windowUUID: windowUUID)
    }

    private func loadGrid(id: Int = 1, rows: [[[String: Any]]] = []) throws {
        var dict: [String: Any] = ["id": id, "type": "Grid", "properties": [:]]
        if !rows.isEmpty { dict["rows"] = rows }
        _ = try model.loadDescription(from: dict, windowUUID: windowUUID)
    }

    private func textDict(id: Int, text: String = "hello") -> [String: Any] {
        ["id": id, "type": "Text", "properties": ["text": text]]
    }

    // MARK: - insertElement — happy path

    func testInsertElementAppendToVStack() throws {
        try loadVStack(id: 1)
        let insertedID = try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 10))
        XCTAssertEqual(insertedID, 10)
        XCTAssertNotNil(model.windowModels[windowUUID]?.viewModels[10])
    }

    func testInsertElementPrepend() throws {
        try loadVStack(id: 1, children: [textDict(id: 10)])
        let insertedID = try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 11), position: .prepend)
        XCTAssertEqual(insertedID, 11)

        let container = model.windowModels[windowUUID]?.viewModels[1]?.dynamicSubviews?["children"] as? [ActionUIElement]
        XCTAssertEqual(container?.first?.id, 11, "Prepended element should be first")
    }

    func testInsertElementAtIndex() throws {
        try loadVStack(id: 1, children: [textDict(id: 10), textDict(id: 11)])
        _ = try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 12), position: .at(1))

        let container = model.windowModels[windowUUID]?.viewModels[1]?.dynamicSubviews?["children"] as? [ActionUIElement]
        XCTAssertEqual(container?[1].id, 12, "Element inserted at index 1 should be at position 1")
    }

    func testInsertElementBeforeSibling() throws {
        try loadVStack(id: 1, children: [textDict(id: 10), textDict(id: 11)])
        _ = try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 12), position: .before(siblingID: 11))

        let container = model.windowModels[windowUUID]?.viewModels[1]?.dynamicSubviews?["children"] as? [ActionUIElement]
        // Should order: 10, 12, 11
        XCTAssertEqual(container?.map(\.id), [10, 12, 11])
    }

    func testInsertElementAfterSibling() throws {
        try loadVStack(id: 1, children: [textDict(id: 10), textDict(id: 11)])
        _ = try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 12), position: .after(siblingID: 10))

        let container = model.windowModels[windowUUID]?.viewModels[1]?.dynamicSubviews?["children"] as? [ActionUIElement]
        // Should order: 10, 12, 11
        XCTAssertEqual(container?.map(\.id), [10, 12, 11])
    }

    func testInsertElementContainerAutoDerived() throws {
        // VStack has exactly one flat container ("children"), so container param can be omitted
        try loadVStack(id: 1)
        let id = try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 5))
        XCTAssertEqual(id, 5)
    }

    func testInsertElementExplicitContainer() throws {
        try loadVStack(id: 1)
        let id = try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 6), container: "children")
        XCTAssertEqual(id, 6)
    }

    func testInsertElementViaJSONString() throws {
        try loadVStack(id: 1)
        let json = #"{"id": 20, "type": "Text", "properties": {"text": "from json"}}"#
        let id = try model.insertElement(windowUUID: windowUUID, parentID: 1, json: json)
        XCTAssertEqual(id, 20)
        XCTAssertNotNil(model.windowModels[windowUUID]?.viewModels[20])
    }

    // MARK: - insertElement — NavigationStack (single flat container: destinations)

    func testInsertElementNavigationStackAutoSelectsDestinations() throws {
        // NavigationStack has only one flat container ("destinations"), so the framework
        // auto-selects it — no explicit container name required.
        let dict: [String: Any] = ["id": 1, "type": "NavigationStack", "properties": [:]]
        _ = try model.loadDescription(from: dict, windowUUID: windowUUID)
        let id = try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 9))
        XCTAssertEqual(id, 9)
    }

    func testInsertElementNavigationStackWithExplicitContainer() throws {
        let dict: [String: Any] = ["id": 1, "type": "NavigationStack", "properties": [:]]
        _ = try model.loadDescription(from: dict, windowUUID: windowUUID)
        let id = try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 9), container: "destinations")
        XCTAssertEqual(id, 9)
    }

    func testInsertElementNavigationStackUnknownContainer() throws {
        let dict: [String: Any] = ["id": 1, "type": "NavigationStack", "properties": [:]]
        _ = try model.loadDescription(from: dict, windowUUID: windowUUID)
        XCTAssertThrowsError(try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 9), container: "children")) { error in
            guard case InsertError.unknownContainer(let name, let valid) = error else {
                return XCTFail("Expected unknownContainer, got \(error)")
            }
            XCTAssertEqual(name, "children")
            XCTAssertEqual(valid, ["destinations"])
        }
    }

    // MARK: - insertElement — error cases

    func testInsertElementWindowNotFound() {
        XCTAssertThrowsError(try model.insertElement(windowUUID: "bad-uuid", parentID: 1, dict: textDict(id: 5))) { error in
            guard case InsertError.windowNotFound = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testInsertElementParentNotFound() throws {
        try loadVStack(id: 1)
        XCTAssertThrowsError(try model.insertElement(windowUUID: windowUUID, parentID: 999, dict: textDict(id: 5))) { error in
            guard case InsertError.parentNotFound(let pid) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(pid, 999)
        }
    }

    func testInsertElementNotAContainer() throws {
        let dict: [String: Any] = ["id": 1, "type": "Text", "properties": ["text": "hi"]]
        _ = try model.loadDescription(from: dict, windowUUID: windowUUID)

        XCTAssertThrowsError(try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 5))) { error in
            guard case InsertError.notAContainer = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testInsertElementUnknownContainer() throws {
        try loadVStack(id: 1)
        XCTAssertThrowsError(try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 5), container: "bogusContainer")) { error in
            guard case InsertError.unknownContainer(let container, _) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(container, "bogusContainer")
        }
    }

    func testInsertElementWrongMethodForRowContainer() throws {
        try loadGrid(id: 1)
        XCTAssertThrowsError(try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 5), container: "rows")) { error in
            guard case InsertError.wrongMethod(let container, _, _) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(container, "rows")
        }
    }

    func testInsertElementIDConflict() throws {
        try loadVStack(id: 1, children: [textDict(id: 10)])
        XCTAssertThrowsError(try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 10))) { error in
            guard case InsertError.idConflict(let ids) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(ids.contains(10))
        }
    }

    func testInsertElementPositionOutOfBounds() throws {
        try loadVStack(id: 1, children: [textDict(id: 10)])
        XCTAssertThrowsError(try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 11), position: .at(99))) { error in
            guard case InsertError.positionOutOfBounds(let idx, _) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(idx, 99)
        }
    }

    func testInsertElementSiblingNotFound() throws {
        try loadVStack(id: 1, children: [textDict(id: 10)])
        XCTAssertThrowsError(try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 11), position: .before(siblingID: 999))) { error in
            guard case InsertError.siblingNotFound(let sib, _) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(sib, 999)
        }
    }

    func testInsertElementInvalidJSON() throws {
        try loadVStack(id: 1)
        XCTAssertThrowsError(try model.insertElement(windowUUID: windowUUID, parentID: 1, json: "not json at all")) { error in
            guard case InsertError.invalidJSON = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testInsertElementJSONNotObject() throws {
        try loadVStack(id: 1)
        XCTAssertThrowsError(try model.insertElement(windowUUID: windowUUID, parentID: 1, json: "[1,2,3]")) { error in
            guard case InsertError.invalidJSON = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    // MARK: - insertRow — happy path

    func testInsertRowAppend() throws {
        try loadGrid(id: 1)
        let cells = [textDict(id: 10), textDict(id: 11)]
        let ids = try model.insertRow(windowUUID: windowUUID, parentID: 1, cells: cells)
        XCTAssertEqual(ids, [10, 11])
        XCTAssertNotNil(model.windowModels[windowUUID]?.viewModels[10])
        XCTAssertNotNil(model.windowModels[windowUUID]?.viewModels[11])
    }

    func testInsertRowPrepend() throws {
        let existingRow = [textDict(id: 10)]
        try loadGrid(id: 1, rows: [existingRow])
        let ids = try model.insertRow(windowUUID: windowUUID, parentID: 1, cells: [textDict(id: 20)], position: .prepend)
        XCTAssertEqual(ids, [20])

        let rows = model.windowModels[windowUUID]?.viewModels[1]?.dynamicSubviews?["rows"] as? [[ActionUIElement]]
        XCTAssertEqual(rows?.first?.first?.id, 20, "Prepended row should be first")
    }

    func testInsertRowAtIndex() throws {
        let rows: [[[String: Any]]] = [[textDict(id: 10)], [textDict(id: 11)]]
        try loadGrid(id: 1, rows: rows)
        _ = try model.insertRow(windowUUID: windowUUID, parentID: 1, cells: [textDict(id: 20)], position: .at(1))

        let resultRows = model.windowModels[windowUUID]?.viewModels[1]?.dynamicSubviews?["rows"] as? [[ActionUIElement]]
        XCTAssertEqual(resultRows?[1].first?.id, 20, "Row inserted at index 1 should be at position 1")
    }

    func testInsertRowContainerAutoDerived() throws {
        // Grid has exactly one row container ("rows"), so container param can be omitted
        try loadGrid(id: 1)
        let ids = try model.insertRow(windowUUID: windowUUID, parentID: 1, cells: [textDict(id: 5)])
        XCTAssertEqual(ids, [5])
    }

    func testInsertRowViaJSONString() throws {
        try loadGrid(id: 1)
        let json = #"[{"id": 30, "type": "Text", "properties": {"text": "cell1"}}, {"id": 31, "type": "Text", "properties": {"text": "cell2"}}]"#
        let ids = try model.insertRow(windowUUID: windowUUID, parentID: 1, json: json)
        XCTAssertEqual(ids, [30, 31])
        XCTAssertNotNil(model.windowModels[windowUUID]?.viewModels[30])
        XCTAssertNotNil(model.windowModels[windowUUID]?.viewModels[31])
    }

    // MARK: - insertRow — error cases

    func testInsertRowBeforePositionThrows() throws {
        try loadGrid(id: 1)
        XCTAssertThrowsError(try model.insertRow(windowUUID: windowUUID, parentID: 1, cells: [textDict(id: 5)], position: .before(siblingID: 99))) { error in
            guard case InsertError.unsupportedPositionForRowContainer = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testInsertRowAfterPositionThrows() throws {
        try loadGrid(id: 1)
        XCTAssertThrowsError(try model.insertRow(windowUUID: windowUUID, parentID: 1, cells: [textDict(id: 5)], position: .after(siblingID: 99))) { error in
            guard case InsertError.unsupportedPositionForRowContainer = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testInsertRowWrongMethodForFlatContainer() throws {
        try loadVStack(id: 1)
        XCTAssertThrowsError(try model.insertRow(windowUUID: windowUUID, parentID: 1, cells: [textDict(id: 5)], container: "children")) { error in
            guard case InsertError.wrongMethod(let container, _, _) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(container, "children")
        }
    }

    func testInsertRowIDConflict() throws {
        try loadGrid(id: 1, rows: [[textDict(id: 10)]])
        XCTAssertThrowsError(try model.insertRow(windowUUID: windowUUID, parentID: 1, cells: [textDict(id: 10)])) { error in
            guard case InsertError.idConflict(let ids) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(ids.contains(10))
        }
    }

    func testInsertRowPositionOutOfBounds() throws {
        try loadGrid(id: 1)
        XCTAssertThrowsError(try model.insertRow(windowUUID: windowUUID, parentID: 1, cells: [textDict(id: 5)], position: .at(99))) { error in
            guard case InsertError.positionOutOfBounds = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testInsertRowJSONNotArray() throws {
        try loadGrid(id: 1)
        let json = #"{"id": 5, "type": "Text", "properties": {}}"#
        XCTAssertThrowsError(try model.insertRow(windowUUID: windowUUID, parentID: 1, json: json)) { error in
            guard case InsertError.invalidJSON = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    // MARK: - removeElement — happy path

    func testRemoveElementFromFlatContainer() throws {
        try loadVStack(id: 1, children: [textDict(id: 10), textDict(id: 11)])
        try model.removeElement(windowUUID: windowUUID, viewID: 10)

        XCTAssertNil(model.windowModels[windowUUID]?.viewModels[10], "ViewModel for removed element should be gone")
        let container = model.windowModels[windowUUID]?.viewModels[1]?.dynamicSubviews?["children"] as? [ActionUIElement]
        XCTAssertEqual(container?.map(\.id), [11], "Only element 11 should remain")
    }

    func testRemoveElementCascadesDescendants() throws {
        // Insert a VStack child that itself has children (ids 20, 21)
        try loadVStack(id: 1)
        let nestedJSON = """
        {
            "id": 10,
            "type": "VStack",
            "properties": {},
            "children": [
                {"id": 20, "type": "Text", "properties": {"text": "a"}},
                {"id": 21, "type": "Text", "properties": {"text": "b"}}
            ]
        }
        """
        _ = try model.insertElement(windowUUID: windowUUID, parentID: 1, json: nestedJSON)
        XCTAssertNotNil(model.windowModels[windowUUID]?.viewModels[10])
        XCTAssertNotNil(model.windowModels[windowUUID]?.viewModels[20])
        XCTAssertNotNil(model.windowModels[windowUUID]?.viewModels[21])

        try model.removeElement(windowUUID: windowUUID, viewID: 10)

        XCTAssertNil(model.windowModels[windowUUID]?.viewModels[10], "Parent should be removed")
        XCTAssertNil(model.windowModels[windowUUID]?.viewModels[20], "Descendant 20 should be cascade-removed")
        XCTAssertNil(model.windowModels[windowUUID]?.viewModels[21], "Descendant 21 should be cascade-removed")
    }

    func testRemoveElementFromRowsContainer() throws {
        try loadGrid(id: 1, rows: [[textDict(id: 10), textDict(id: 11)], [textDict(id: 12)]])
        try model.removeElement(windowUUID: windowUUID, viewID: 10)

        XCTAssertNil(model.windowModels[windowUUID]?.viewModels[10])
        let rows = model.windowModels[windowUUID]?.viewModels[1]?.dynamicSubviews?["rows"] as? [[ActionUIElement]]
        XCTAssertEqual(rows?[0].map(\.id), [11], "Cell 10 removed; cell 11 remains in row 0")
        XCTAssertEqual(rows?[1].map(\.id), [12], "Row 1 unchanged")
    }

    func testRemoveElementDynamicallyInsertedIDs() throws {
        try loadVStack(id: 1)
        _ = try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 10))
        XCTAssertNotNil(model.windowModels[windowUUID]?.dynamicallyInsertedIDs[1])

        try model.removeElement(windowUUID: windowUUID, viewID: 10)
        // After removing the only dynamic child, the parent's entry should be cleaned up
        XCTAssertNil(model.windowModels[windowUUID]?.dynamicallyInsertedIDs[1])
    }

    // MARK: - removeElement — error cases

    func testRemoveElementRootForbidden() throws {
        try loadVStack(id: 1)
        XCTAssertThrowsError(try model.removeElement(windowUUID: windowUUID, viewID: 1)) { error in
            guard case InsertError.rootRemovalForbidden(let id) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(id, 1)
        }
    }

    func testRemoveElementViewNotFound() throws {
        try loadVStack(id: 1)
        XCTAssertThrowsError(try model.removeElement(windowUUID: windowUUID, viewID: 999)) { error in
            guard case InsertError.viewNotFound(let id) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(id, 999)
        }
    }

    func testRemoveElementWindowNotFound() {
        XCTAssertThrowsError(try model.removeElement(windowUUID: "bad-uuid", viewID: 1)) { error in
            guard case InsertError.windowNotFound = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    // MARK: - Multiple insertions / ordering

    func testMultipleInsertsPreserveOrder() throws {
        try loadVStack(id: 1)
        _ = try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 10))
        _ = try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 11))
        _ = try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 12))

        let container = model.windowModels[windowUUID]?.viewModels[1]?.dynamicSubviews?["children"] as? [ActionUIElement]
        XCTAssertEqual(container?.map(\.id), [10, 11, 12])
    }

    func testInsertThenRemoveThenInsertSameID() throws {
        try loadVStack(id: 1)
        _ = try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 10))
        try model.removeElement(windowUUID: windowUUID, viewID: 10)
        // After removal, same id should be re-insertable
        let id = try model.insertElement(windowUUID: windowUUID, parentID: 1, dict: textDict(id: 10))
        XCTAssertEqual(id, 10)
    }
}
