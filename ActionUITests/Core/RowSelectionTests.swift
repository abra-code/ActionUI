// Core/RowSelectionTests.swift
/*
 Tests for RowSelection: the maps between a list's child element IDs and the destination view IDs
 the children name with "destinationViewId" (an Int only), a data-driven list's selected row as an
 index into the rows drawn, a heterogeneous list's selected child, and storing a selection.
 (The SwiftUI bindings over these are tested in ListTests.)
*/

import XCTest
@testable import ActionUI

@MainActor
final class RowSelectionTests: XCTestCase {
    private var windowUUID: String!

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = nil
    }

    private let rows = [["Alpha", "a"], ["Beta", "b"], ["Gamma", "c"]]

    /// The model of a loaded data-driven List (id 1, actionID "list.action") showing `rows`.
    private func loadRowList() throws -> ViewModel {
        let json = """
        { "id": 1, "type": "List", "properties": { "actionID": "list.action" } }
        """
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 1, rows: rows)
        return try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1])
    }

    /// Lets the deferred main-queue work of a commit run.
    private func drainMainQueue() async {
        let done = expectation(description: "main queue drained")
        DispatchQueue.main.async { done.fulfill() }
        await fulfillment(of: [done], timeout: 2)
    }

    func testSelectedIndexIsTheRowAmongThoseDrawn() {
        XCTAssertEqual(RowSelection.selectedIndex(value: ["Beta", "b"], in: rows), 1)
        XCTAssertNil(RowSelection.selectedIndex(value: [String](), in: rows), "nothing selected")
        XCTAssertNil(RowSelection.selectedIndex(value: nil, in: rows))
        XCTAssertNil(RowSelection.selectedIndex(value: ["Beta"], in: rows), "a row matches with all its columns")
        XCTAssertNil(RowSelection.selectedIndex(value: "Beta", in: rows), "a value that is no row")
        XCTAssertEqual(RowSelection.selectedIndex(value: ["A"], in: [["A"], ["A"]]), 0, "the first of equal rows")
    }

    func testClickedRowFromTheIndexReported() {
        XCTAssertEqual(RowSelection.clickedRow(index: 2, in: rows), ["Gamma", "c"])
        XCTAssertEqual(RowSelection.clickedRow(index: nil, in: rows), [], "no index is a deselect")
        XCTAssertNil(RowSelection.clickedRow(index: 3, in: rows), "past the rows drawn: ignored")
        XCTAssertNil(RowSelection.clickedRow(index: -1, in: rows))
    }

    func testSelectedChildIDFromAHeterogeneousListValue() {
        XCTAssertEqual(RowSelection.selectedChildID(value: ["12"]), 12)
        XCTAssertNil(RowSelection.selectedChildID(value: [String]()))
        XCTAssertNil(RowSelection.selectedChildID(value: ["twelve"]))
        XCTAssertNil(RowSelection.selectedChildID(value: nil))
    }

    func testCommitRowSelectionStoresTheRowAndFiresTheActionOncePerChange() async throws {
        let model = try loadRowList()
        var calls = 0
        ActionUIModel.shared.registerActionHandler(for: "list.action") { _, _, viewID, viewPartID, context in
            XCTAssertEqual(viewID, 1)
            XCTAssertEqual(viewPartID, 0)
            XCTAssertNil(context)
            calls += 1
        }
        RowSelection.commitRowSelection(["Beta", "b"], drawnRows: rows, model: model,
                                        actionID: "list.action", windowUUID: windowUUID, viewID: 1)
        await drainMainQueue()
        XCTAssertEqual(model.value as? [String], ["Beta", "b"])
        XCTAssertEqual(calls, 1)

        RowSelection.commitRowSelection(["Beta", "b"], drawnRows: rows, model: model,
                                        actionID: "list.action", windowUUID: windowUUID, viewID: 1)
        await drainMainQueue()
        XCTAssertEqual(calls, 1, "the same row again is no change")

        RowSelection.commitRowSelection([], drawnRows: rows, model: model,
                                        actionID: "list.action", windowUUID: windowUUID, viewID: 1)
        await drainMainQueue()
        XCTAssertEqual(model.value as? [String], [])
        XCTAssertEqual(calls, 2, "a deselect fires too")
    }

    func testCommitChildSelectionStoresTheIDAsTextWithTheIDAsContext() async throws {
        let model = try loadRowList()
        var contexts: [Int?] = []
        ActionUIModel.shared.registerActionHandler(for: "list.action") { _, _, _, _, context in
            contexts.append(context as? Int)
        }
        RowSelection.commitChildSelection(12, model: model, actionID: "list.action", windowUUID: windowUUID, viewID: 1)
        await drainMainQueue()
        XCTAssertEqual(model.value as? [String], ["12"])
        RowSelection.commitChildSelection(nil, model: model, actionID: "list.action", windowUUID: windowUUID, viewID: 1)
        await drainMainQueue()
        XCTAssertEqual(model.value as? [String], [])
        XCTAssertEqual(contexts, [12, nil])
    }

    func testCommitChildSelectionFiresOncePerChangeAndADeselectOfNoValueFires() async throws {
        let model = try loadRowList()
        var calls = 0
        ActionUIModel.shared.registerActionHandler(for: "list.action") { _, _, _, _, _ in calls += 1 }
        model.value = nil
        RowSelection.commitChildSelection(nil, model: model, actionID: "list.action", windowUUID: windowUUID, viewID: 1)
        await drainMainQueue()
        XCTAssertEqual(model.value as? [String], [], "no value is not [], so a deselect writes []")
        XCTAssertEqual(calls, 1)
        RowSelection.commitChildSelection(12, model: model, actionID: "list.action", windowUUID: windowUUID, viewID: 1)
        await drainMainQueue()
        RowSelection.commitChildSelection(12, model: model, actionID: "list.action", windowUUID: windowUUID, viewID: 1)
        await drainMainQueue()
        XCTAssertEqual(calls, 2, "the same child again is no change")
    }

    func testChildrenWithAnIntDestinationAreMappedBothWays() throws {
        let json = """
        {
            "id": 1,
            "type": "List",
            "properties": { "actionID": "row.selected" },
            "children": [
                { "id": 10, "type": "Text", "properties": { "text": "One", "destinationViewId": 100 } },
                { "id": 11, "type": "Text", "properties": { "text": "Two", "destinationViewId": "101" } },
                { "id": 12, "type": "Text", "properties": { "text": "Three" } },
                { "id": 13, "type": "Text", "properties": { "text": "Four", "destinationViewId": 103 } }
            ]
        }
        """
        let element = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        let maps = RowSelection.buildIDMaps(children: children, windowModel: ActionUIModel.shared.windowModels[windowUUID])

        XCTAssertEqual(maps.childToDestination, [10: 100, 13: 103])
        XCTAssertEqual(maps.destinationToChild, [100: 10, 103: 13])
    }

    func testUnfilteredPropertiesGiveTheSameMaps() throws {
        // Loading filters the properties; here the children's view models hold them as written.
        let json = """
        {
            "id": 1,
            "type": "List",
            "children": [
                { "id": 10, "type": "Text", "properties": { "text": "One" } },
                { "id": 11, "type": "Text", "properties": { "text": "Two" } }
            ]
        }
        """
        let element = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let windowModel = ActionUIModel.shared.windowModels[windowUUID]
        windowModel?.viewModels[10]?.properties = ["text": "One", "destinationViewId": 100]
        windowModel?.viewModels[11]?.properties = ["text": "Two", "destinationViewId": "101"]
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        let maps = RowSelection.buildIDMaps(children: children, windowModel: windowModel)

        XCTAssertEqual(maps.childToDestination, [10: 100])
        XCTAssertEqual(maps.destinationToChild, [100: 10])
    }
}
