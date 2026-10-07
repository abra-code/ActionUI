// Tests/Views/ToggleTemplateTests.swift
/*
 ToggleTemplateTests.swift

 Tests for a Toggle whose state is row data: inside a data-driven template (List, VStack, ...)
 and as a Table column type.

 Covered here: the string-to-Bool rule, which "isOn" names one column, the write of a user
 toggle into states["content"], the action's viewID / viewPartID / context, that the action
 fires after the write, that a rows change by the host fires nothing, that the state is kept
 across a re-render, and that a selection resting on the toggled row follows it.

 That a click on the Toggle does not also select its row is a property of the rendered
 hierarchy; it is covered by ActionUITestAppUITests/ToggleRowTests.swift.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ToggleTemplateTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!

    private struct Fired: Equatable {
        let viewID: Int
        let viewPartID: Int
        let context: String
    }

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

    // MARK: - Fixtures

    private let packRows = [
        ["true", "Xcode and Swift builds", "xcode", "false"],
        ["false", "Node", "node", "false"],
        ["false", "Locked", "locked", "true"]
    ]

    @discardableResult
    private func load(_ jsonString: String) throws -> ActionUIElement {
        try ActionUIModel.shared.loadDescription(from: Data(jsonString.utf8), format: "json", windowUUID: windowUUID)
    }

    private func loadPackList() throws -> any ActionUIElementBase {
        let list = try load("""
        {
            "type": "List",
            "id": 600,
            "properties": { "actionID": "packs.selection.changed" },
            "template": {
                "type": "Toggle",
                "properties": {
                    "style": "checkbox", "isOn": "$1", "title": "$2",
                    "disabled": "$4", "actionID": "packs.toggled"
                }
            }
        }
        """)
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 600, rows: packRows)
        return try XCTUnwrap(list.subviews?["template"] as? any ActionUIElementBase)
    }

    @discardableResult
    private func loadPackTable() throws -> ActionUIElement {
        let table = try load("""
        {
            "type": "Table",
            "id": 600,
            "properties": {
                "columns": ["", "Pack"],
                "columnTypes": [
                    { "viewType": "Toggle", "style": "checkbox", "actionID": "packs.toggled", "disabledColumn": 4 },
                    { "viewType": "Text" }
                ],
                "actionID": "packs.selection.changed"
            }
        }
        """)
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 600, rows: packRows)
        return table
    }

    private func rows() -> [[String]] {
        ActionUIModel.shared.getElementRows(windowUUID: windowUUID, viewID: 600) ?? []
    }

    private func context(row: Int) -> TemplateContext {
        TemplateContext(parentID: 600, rowIndex: row, row: packRows[row])
    }

    // MARK: - String to Bool

    func testRowBool_readsTheDocumentedWords() {
        for text in ["true", "TRUE", "True", "1"] {
            XCTAssertEqual(TemplateHelper.rowBool(text), true, "'\(text)' is on")
        }
        for text in ["false", "FALSE", "False", "0", ""] {
            XCTAssertEqual(TemplateHelper.rowBool(text), false, "'\(text)' is off")
        }
        for text in ["yes", "no", "on", " true", "2", "mixed", "$4"] {
            XCTAssertNil(TemplateHelper.rowBool(text), "'\(text)' is not a Boolean")
        }
    }

    func testSingleColumnIndex_onlyAWholeReferenceNamesAColumn() {
        XCTAssertEqual(TemplateHelper.singleColumnIndex("$1"), 0)
        XCTAssertEqual(TemplateHelper.singleColumnIndex("$12"), 11)
        XCTAssertNil(TemplateHelper.singleColumnIndex("$0"), "$0 is all columns")
        XCTAssertNil(TemplateHelper.singleColumnIndex("$1 "))
        XCTAssertNil(TemplateHelper.singleColumnIndex("x$1"))
        XCTAssertNil(TemplateHelper.singleColumnIndex("$1$2"))
        XCTAssertNil(TemplateHelper.singleColumnIndex("true"))
        XCTAssertNil(TemplateHelper.singleColumnIndex(true))
        XCTAssertNil(TemplateHelper.singleColumnIndex(nil))
    }

    // MARK: - Template instance properties

    func testInstanceProperties_readIsOnAndDisabledFromTheRow() throws {
        let template = try loadPackList()

        let first = TemplateHelper.instanceProperties(of: template, row: packRows[0], logger: logger)
        XCTAssertEqual(first["isOn"] as? Bool, true)
        XCTAssertEqual(first["disabled"] as? Bool, false)
        XCTAssertEqual(first["title"] as? String, "Xcode and Swift builds")

        let locked = TemplateHelper.instanceProperties(of: template, row: packRows[2], logger: logger)
        XCTAssertEqual(locked["isOn"] as? Bool, false)
        XCTAssertEqual(locked["disabled"] as? Bool, true)

        // The Bool read from the row passes the ordinary validation, so the toggle starts as
        // the row says instead of being dropped as "not a Bool".
        let validated = ActionUIRegistry.shared.validateProperties(forElementType: "Toggle", properties: locked)
        XCTAssertEqual(validated["isOn"] as? Bool, false)
        XCTAssertEqual(validated["disabled"] as? Bool, true)
    }

    func testInstanceProperties_otherTextIsOff() throws {
        let template = try loadPackList()
        let properties = TemplateHelper.instanceProperties(of: template, row: ["maybe", "Title", "id", "sometimes"], logger: logger)
        XCTAssertEqual(properties["isOn"] as? Bool, false)
        XCTAssertEqual(properties["disabled"] as? Bool, false)
    }

    func testInstanceProperties_aMissingColumnIsOff() throws {
        // "$4" stays literal for a three-column row, which is not a Boolean: off.
        let template = try loadPackList()
        let properties = TemplateHelper.instanceProperties(of: template, row: ["true", "Title", "id"], logger: logger)
        XCTAssertEqual(properties["isOn"] as? Bool, true)
        XCTAssertEqual(properties["disabled"] as? Bool, false)
    }

    func testInstanceProperties_hiddenFromTheRowOnAnyElement() throws {
        let stack = try load("""
        { "type": "VStack", "id": 700,
          "template": { "type": "Text", "properties": { "text": "$1", "hidden": "$2", "disabled": "$3" } } }
        """)
        let template = try XCTUnwrap(stack.subviews?["template"] as? any ActionUIElementBase)
        let properties = TemplateHelper.instanceProperties(of: template, row: ["Alpha", "1", "TRUE"], logger: logger)
        XCTAssertEqual(properties["hidden"] as? Bool, true)
        XCTAssertEqual(properties["disabled"] as? Bool, true)
        XCTAssertEqual(properties["text"] as? String, "Alpha", "a non-Boolean property stays text")
    }

    func testInstanceProperties_aLiteralBoolIsKept() throws {
        let stack = try load("""
        { "type": "VStack", "id": 700,
          "template": { "type": "Toggle", "properties": { "isOn": true, "title": "$1" } } }
        """)
        let template = try XCTUnwrap(stack.subviews?["template"] as? any ActionUIElementBase)
        let properties = TemplateHelper.instanceProperties(of: template, row: ["Alpha"], logger: logger)
        XCTAssertEqual(properties["isOn"] as? Bool, true)
    }

    func testOutsideATemplate_aStringIsOnIsStillInvalid() {
        let validated = Toggle.validateProperties(["isOn": "true"], logger)
        XCTAssertNil(validated["isOn"])
    }

    // MARK: - A user toggle in a template row

    func testCommitRowToggle_writesTheRowThenFiresWithTheRowIndex() throws {
        _ = try loadPackList()
        var fired: [Fired] = []
        var rowsSeenByHandler: [[String]] = []
        ActionUIModel.shared.registerActionHandler(for: "packs.toggled") { _, uuid, viewID, viewPartID, context in
            fired.append(Fired(viewID: viewID, viewPartID: viewPartID, context: String(describing: context)))
            rowsSeenByHandler = ActionUIModel.shared.getElementRows(windowUUID: uuid, viewID: viewID) ?? []
        }

        let taken = TemplateHelper.commitRowToggle(
            true, context: context(row: 1), column: 0, actionID: "packs.toggled", windowUUID: windowUUID
        )

        XCTAssertTrue(taken)
        XCTAssertEqual(rows()[1], ["true", "Node", "node", "false"])
        XCTAssertEqual(rows()[0], packRows[0], "other rows are untouched")
        XCTAssertEqual(fired, [Fired(viewID: 600, viewPartID: 1, context: "Optional(true)")])
        XCTAssertEqual(rowsSeenByHandler[1][0], "true", "the action fires after the write")
    }

    func testCommitRowToggle_turningOffWritesFalse() throws {
        _ = try loadPackList()
        var contexts: [Bool] = []
        ActionUIModel.shared.registerActionHandler(for: "packs.toggled") { _, _, _, _, context in
            if let isOn = context as? Bool { contexts.append(isOn) }
        }
        TemplateHelper.commitRowToggle(
            false, context: context(row: 0), column: 0, actionID: "packs.toggled", windowUUID: windowUUID
        )
        XCTAssertEqual(rows()[0][0], "false")
        XCTAssertEqual(contexts, [false])
    }

    func testCommitRowToggle_theStateSurvivesARerender() throws {
        let template = try loadPackList()
        TemplateHelper.commitRowToggle(true, context: context(row: 1), column: 0, actionID: nil, windowUUID: windowUUID)
        // A re-render builds the instance from the rows as they are now.
        let properties = TemplateHelper.instanceProperties(of: template, row: rows()[1], logger: logger)
        XCTAssertEqual(properties["isOn"] as? Bool, true)
    }

    func testCommitRowToggle_withoutAColumnIsDisplayOnly() throws {
        _ = try loadPackList()
        var firedCount = 0
        ActionUIModel.shared.registerActionHandler(for: "packs.toggled") { _, _, _, _, _ in firedCount += 1 }
        let taken = TemplateHelper.commitRowToggle(
            true, context: context(row: 1), column: nil, actionID: "packs.toggled", windowUUID: windowUUID
        )
        XCTAssertFalse(taken)
        XCTAssertEqual(rows(), packRows)
        XCTAssertEqual(firedCount, 0)
    }

    func testCommitRowToggle_padsARowShorterThanTheColumn() throws {
        _ = try loadPackList()
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 600, rows: [["Alpha"]])
        let short = TemplateContext(parentID: 600, rowIndex: 0, row: ["Alpha"])
        TemplateHelper.commitRowToggle(true, context: short, column: 2, actionID: nil, windowUUID: windowUUID)
        XCTAssertEqual(rows(), [["Alpha", "", "true"]])
    }

    func testCommitRowToggle_followsARowTheHostMoved() throws {
        // The host replaced the rows between the render and the click: the row drawn at
        // index 1 is now at index 2.
        _ = try loadPackList()
        var parts: [Int] = []
        ActionUIModel.shared.registerActionHandler(for: "packs.toggled") { _, _, _, viewPartID, _ in parts.append(viewPartID) }
        let moved = [["false", "New", "new", "false"]] + packRows
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 600, rows: moved)

        TemplateHelper.commitRowToggle(
            true, context: context(row: 1), column: 0, actionID: "packs.toggled", windowUUID: windowUUID
        )

        XCTAssertEqual(rows()[2], ["true", "Node", "node", "false"])
        XCTAssertEqual(rows()[1], packRows[0], "the row now at the drawn index is not the one clicked")
        XCTAssertEqual(parts, [2])
    }

    func testCommitRowToggle_aRowThatIsGoneIsDropped() throws {
        _ = try loadPackList()
        var firedCount = 0
        ActionUIModel.shared.registerActionHandler(for: "packs.toggled") { _, _, _, _, _ in firedCount += 1 }
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 600, rows: [packRows[0]])
        let taken = TemplateHelper.commitRowToggle(
            true, context: context(row: 1), column: 0, actionID: "packs.toggled", windowUUID: windowUUID
        )
        XCTAssertFalse(taken)
        XCTAssertEqual(rows(), [packRows[0]])
        XCTAssertEqual(firedCount, 0)
    }

    // MARK: - Selection and programmatic changes

    func testCommitRowToggle_theSelectionFollowsItsRowAndFiresNothing() throws {
        // The toggled column is the first one, the column a rows change matches the selection
        // by; the write must still keep the row selected.
        _ = try loadPackList()
        var selectionFired = 0
        ActionUIModel.shared.registerActionHandler(for: "packs.selection.changed") { _, _, _, _, _ in selectionFired += 1 }
        _ = ActionUIModel.shared.selectElementRow(windowUUID: windowUUID, viewID: 600, index: 1)

        TemplateHelper.commitRowToggle(true, context: context(row: 1), column: 0, actionID: nil, windowUUID: windowUUID)

        let selected = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 600) as? [String]
        XCTAssertEqual(selected, ["true", "Node", "node", "false"])
        XCTAssertEqual(selectionFired, 0)
    }

    func testCommitRowToggle_aSelectionOnAnotherRowStays() throws {
        _ = try loadPackList()
        _ = ActionUIModel.shared.selectElementRow(windowUUID: windowUUID, viewID: 600, index: 0)
        TemplateHelper.commitRowToggle(true, context: context(row: 1), column: 0, actionID: nil, windowUUID: windowUUID)
        let selected = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 600) as? [String]
        XCTAssertEqual(selected, packRows[0])
    }

    func testRowsChangesByTheHostFireNothing() throws {
        _ = try loadPackList()
        var firedCount = 0
        ActionUIModel.shared.registerActionHandler(for: "packs.toggled") { _, _, _, _, _ in firedCount += 1 }
        ActionUIModel.shared.registerActionHandler(for: "packs.selection.changed") { _, _, _, _, _ in firedCount += 1 }

        let model = ActionUIModel.shared
        model.setElementRows(windowUUID: windowUUID, viewID: 600, rows: [["true", "A", "a", "false"]])
        model.appendElementRows(windowUUID: windowUUID, viewID: 600, rows: [["false", "B", "b", "false"]])
        XCTAssertEqual(rows().map { $0[0] }, ["true", "false"], "the rows carry what the toggles show")
        model.clearElementRows(windowUUID: windowUUID, viewID: 600)

        XCTAssertEqual(firedCount, 0)
    }

    // MARK: - View building

    func testListWithAToggleTemplate_builds() throws {
        let list = try load("""
        {
            "type": "List", "id": 610,
            "properties": { "actionID": "list.selected" },
            "template": {
                "type": "HStack",
                "children": [
                    { "type": "Toggle", "properties": { "isOn": "$1", "title": "$2", "actionID": "row.toggled" } },
                    { "type": "Spacer" },
                    { "type": "Text", "properties": { "text": "$3" } }
                ]
            }
        }
        """)
        let viewModel = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[610])
        viewModel.states["content"] = packRows
        let view = ActionUIRegistry.shared.buildView(
            for: list, model: viewModel, windowUUID: windowUUID,
            validatedProperties: List.validateProperties(list.properties, logger)
        )
        XCTAssertFalse(view is SwiftUI.EmptyView)
    }

    func testListItemTypeToggle_isRefused() {
        let validated = List.validateProperties(["itemType": ["viewType": "Toggle"]], logger)
        XCTAssertEqual((validated["itemType"] as? [String: Any])?["viewType"] as? String, "Text")
    }

    // MARK: - Table column

    func testTableValidate_acceptsAToggleColumn() {
        let validated = Table.validateProperties([
            "columns": ["", "Pack"],
            "columnTypes": [
                ["viewType": "Toggle", "style": "checkbox", "actionID": "packs.toggled", "disabledColumn": 4],
                ["viewType": "Text"]
            ]
        ], logger)
        let toggle = (validated["columnTypes"] as? [[String: Any]])?.first
        XCTAssertEqual(toggle?["viewType"] as? String, "Toggle")
        XCTAssertEqual(toggle?["style"] as? String, "checkbox")
        XCTAssertEqual(toggle?["disabledColumn"] as? Int, 4)
        XCTAssertEqual(toggle?["actionID"] as? String, "packs.toggled")
    }

    func testTableValidate_dropsABadStyleAndDisabledColumn() {
        let validated = Table.validateProperties([
            "columns": ["On"],
            "columnTypes": [["viewType": "Toggle", "style": "radio", "disabledColumn": 0]]
        ], logger)
        let toggle = (validated["columnTypes"] as? [[String: Any]])?.first
        XCTAssertEqual(toggle?["viewType"] as? String, "Toggle")
        XCTAssertNil(toggle?["style"])
        XCTAssertNil(toggle?["disabledColumn"])
    }

    func testTableCommitCellToggle_writesTheCellThenFiresWithColumnAndRow() throws {
        try loadPackTable()
        var fired: [Fired] = []
        var cellSeenByHandler = ""
        ActionUIModel.shared.registerActionHandler(for: "packs.toggled") { _, uuid, viewID, viewPartID, context in
            fired.append(Fired(viewID: viewID, viewPartID: viewPartID, context: String(describing: context)))
            if let row = context as? Int {
                cellSeenByHandler = ActionUIModel.shared.getElementRows(windowUUID: uuid, viewID: viewID)?[row][viewPartID] ?? ""
            }
        }

        let taken = Table.commitCellToggle(
            true, drawnRow: packRows[1], rowIndex: 1, column: 0,
            actionID: "packs.toggled", windowUUID: windowUUID, viewID: 600
        )

        XCTAssertTrue(taken)
        XCTAssertEqual(rows()[1], ["true", "Node", "node", "false"])
        XCTAssertEqual(fired, [Fired(viewID: 600, viewPartID: 0, context: "Optional(1)")])
        XCTAssertEqual(cellSeenByHandler, "true", "the action fires after the write")
    }

    func testTableCommitCellToggle_keepsTheSelectionAndFiresNoSelectionAction() throws {
        try loadPackTable()
        var selectionFired = 0
        ActionUIModel.shared.registerActionHandler(for: "packs.selection.changed") { _, _, _, _, _ in selectionFired += 1 }
        _ = ActionUIModel.shared.selectElementRow(windowUUID: windowUUID, viewID: 600, index: 1)

        Table.commitCellToggle(
            true, drawnRow: packRows[1], rowIndex: 1, column: 0,
            actionID: nil, windowUUID: windowUUID, viewID: 600
        )

        let selected = ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 600) as? [String]
        XCTAssertEqual(selected, ["true", "Node", "node", "false"])
        XCTAssertEqual(selectionFired, 0)
    }

    func testTableWithAToggleColumn_builds() throws {
        let element = try loadPackTable()
        let viewModel = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[600])
        let view = ActionUIRegistry.shared.buildView(
            for: element, model: viewModel, windowUUID: windowUUID,
            validatedProperties: Table.validateProperties(element.properties, logger)
        )
        #if canImport(AppKit)
        XCTAssertFalse(view is SwiftUI.EmptyView)
        #endif
    }
}
