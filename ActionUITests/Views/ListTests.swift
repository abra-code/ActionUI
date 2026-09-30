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
    
    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIModel.shared.logger = logger
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
                "doubleClickActionID": "list.double.click",
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
        XCTAssertEqual(element.properties["doubleClickActionID"] as? String, "list.double.click", "doubleClickActionID should be list.double.click")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        XCTAssertEqual(viewModel.states["content"] as? [[String]], [], "State content should start empty")
        XCTAssertEqual(viewModel.value as? [String], [], "State value should be empty")
    }

    func testListValidatePropertiesValid() {
        let properties: [String: Any] = [
            "itemType": ["viewType": "Image", "dataInterpretation": "systemName"],
            "actionID": "list.action",
            "doubleClickActionID": "list.double.click",
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
        XCTAssertEqual(validated["doubleClickActionID"] as? String, "list.double.click", "doubleClickActionID should be preserved")
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

    // MARK: - Heterogeneous list tests

    func testHeterogeneousListJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "List",
            "properties": {
                "actionID": "list.selection"
            },
            "children": [
                { "type": "Text", "id": 10, "properties": { "text": "Item A" } },
                { "type": "Button", "id": 11, "properties": { "title": "Item B" } }
            ]
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let element = try ActionUIModel.shared.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        XCTAssertEqual(element.id, 1)
        XCTAssertEqual(element.type, "List")

        let children = element.subviews?["children"] as? [any ActionUIElementBase]
        XCTAssertNotNil(children, "children should be parsed into subviews")
        XCTAssertEqual(children?.count, 2, "Should have 2 children")
        XCTAssertEqual((children?[0] as? ActionUIElement)?.type, "Text")
        XCTAssertEqual((children?[1] as? ActionUIElement)?.type, "Button")
    }

    func testHeterogeneousListConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "List",
            "properties": [
                "actionID": "list.selection"
            ],
            "children": [
                ["type": "Text", "id": 10, "properties": ["text": "Item A"]],
                ["type": "Button", "id": 11, "properties": ["title": "Item B"]]
            ]
        ]

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        // Verify child view models were created
        XCTAssertNotNil(windowModel.viewModels[10], "ViewModel should be created for child id 10")
        XCTAssertNotNil(windowModel.viewModels[11], "ViewModel should be created for child id 11")

        let validatedProperties = List.validateProperties(element.properties, logger)
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        XCTAssertNotNil(view, "buildView should succeed with heterogeneous children")
    }

    func testHeterogeneousListEmptyChildren() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "List",
            "properties": [
                "itemType": ["viewType": "Text"],
                "actionID": "list.action"
            ],
            "children": [] as [[String: Any]]
        ]

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        // Empty children should fall back to homogeneous mode
        let children = element.subviews?["children"] as? [any ActionUIElementBase] ?? []
        XCTAssertTrue(children.isEmpty, "Empty children array should result in empty subviews")

        // Should still build successfully (homogeneous mode)
        let validatedProperties = List.validateProperties(element.properties, logger)
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)
        XCTAssertNotNil(view, "buildView should succeed with empty children (homogeneous fallback)")
        XCTAssertEqual(viewModel.states["content"] as? [[String]], [], "State content should start empty in homogeneous mode")
    }

    // MARK: - Row selection binding (homogeneous and template modes)
    // SelectionListHelper.makeRowSelectionBinding is what both data-driven modes hand to
    // List(selection:); SwiftUI writes the set of selected row indices into it.

    /// The loaded List's model with three rows, the selection binding the List would get, and a
    /// count of the actionID calls.
    private func rowSelectionFixture() throws -> (ViewModel, Binding<Set<Int>>, () -> Int) {
        try loadListElement()
        let model = ActionUIModel.shared
        model.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Alpha", "a"], ["Beta", "b"], ["Gamma", "c"]])
        let viewModel = try XCTUnwrap(model.windowModels[windowUUID]?.viewModels[1])
        final class Counter { var calls = 0 }
        let counter = Counter()
        model.registerActionHandler(for: "list.action") { _, _, viewID, viewPartID, context in
            XCTAssertEqual(viewID, 1)
            XCTAssertEqual(viewPartID, 0)
            XCTAssertNil(context, "the host reads the selection from the value, as for a Table")
            counter.calls += 1
        }
        let binding = SelectionListHelper.makeRowSelectionBinding(
            model: viewModel, actionID: "list.action", windowUUID: windowUUID, viewID: 1)
        return (viewModel, binding, { counter.calls })
    }

    /// Lets the binding's deferred main-queue work run.
    private func drainMainQueue() async {
        let done = expectation(description: "main queue drained")
        DispatchQueue.main.async { done.fulfill() }
        await fulfillment(of: [done], timeout: 2)
    }

    func testRowSelection_selectingARowSetsValueAndFiresAction() async throws {
        let (viewModel, binding, calls) = try rowSelectionFixture()
        binding.wrappedValue = [1]
        await drainMainQueue()
        XCTAssertEqual(viewModel.value as? [String], ["Beta", "b"], "value is the selected row, hidden columns included")
        XCTAssertEqual(calls(), 1)
        XCTAssertEqual(binding.wrappedValue, [1], "the binding reads the selection back as its index")
    }

    func testRowSelection_deselectingClearsValueAndFiresAction() async throws {
        let (viewModel, binding, calls) = try rowSelectionFixture()
        binding.wrappedValue = [2]
        await drainMainQueue()
        binding.wrappedValue = []
        await drainMainQueue()
        XCTAssertEqual(viewModel.value as? [String], [], "a deselect clears the value")
        XCTAssertEqual(calls(), 2, "a deselect fires actionID too, so the host learns of it")
        XCTAssertEqual(binding.wrappedValue, [])
    }

    func testRowSelection_noChangeFiresNothing() async throws {
        let (viewModel, binding, calls) = try rowSelectionFixture()
        binding.wrappedValue = []
        await drainMainQueue()
        XCTAssertEqual(calls(), 0, "clearing an empty selection is no change")
        binding.wrappedValue = [0]
        await drainMainQueue()
        binding.wrappedValue = [0]
        await drainMainQueue()
        XCTAssertEqual(calls(), 1, "selecting the selected row again is no change")
        binding.wrappedValue = [7]
        await drainMainQueue()
        XCTAssertEqual(calls(), 1, "an index past the rows is ignored")
        XCTAssertEqual(viewModel.value as? [String], ["Alpha", "a"], "and leaves the selection alone")
    }

    func testRowSelection_clearElementSelectionFiresNothing() async throws {
        let (viewModel, binding, calls) = try rowSelectionFixture()
        binding.wrappedValue = [1]
        await drainMainQueue()
        ActionUIModel.shared.clearElementSelection(windowUUID: windowUUID, viewID: 1)
        await drainMainQueue()
        XCTAssertEqual(viewModel.value as? [String], [])
        XCTAssertEqual(calls(), 1, "only the user's selection fired; the host's own clear does not")
    }

    func testRowSelection_aRefreshBeforeTheDeferredWriteKeepsTheNewColumns() async throws {
        let (viewModel, binding, calls) = try rowSelectionFixture()
        binding.wrappedValue = [1] // the click takes ["Beta", "b"]; the write waits for the main queue
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Beta", "b2"], ["Alpha", "a"]])
        await drainMainQueue()
        XCTAssertEqual(viewModel.value as? [String], ["Beta", "b2"], "the clicked row as it is now, so the list can highlight it")
        XCTAssertEqual(binding.wrappedValue, [0])
        XCTAssertEqual(calls(), 1)
    }

    func testHomogeneousRows_shownRowsKeepTheirContentIndex() async throws {
        let items = [["Alpha"], [""], [], ["Delta", "d"]]
        let shown = List.shownRowIndices(items)
        XCTAssertEqual(shown, [0, 3], "rows with an empty first column are not shown, and the rest keep their content index")

        // A click on the second shown row reaches the binding as its tag, which must name Delta.
        let (viewModel, binding, _) = try rowSelectionFixture()
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 1, rows: items)
        binding.wrappedValue = [shown[1]]
        await drainMainQueue()
        XCTAssertEqual(viewModel.value as? [String], ["Delta", "d"])
    }
}
