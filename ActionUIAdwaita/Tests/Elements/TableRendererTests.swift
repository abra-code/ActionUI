// Tests/Elements/TableRendererTests.swift
/*
 Tests for Table on GTK: a GtkColumnView with a column per title, its widths by the Apple
 renderer's rule (the largest ideal width fills, minWidths the narrowest a drag goes); one row per
 content row, each cell showing its column of the row; a rows change shown in the cells already
 bound; a row the user selects becomes the value and fires actionID once, one the host selects
 fires nothing, one GTK selects by itself is undone; a double click fires doubleClickActionID with
 the row's index; Button cells fire their column's actionID with the context actionContext names;
 Toggle cells write their row and fire, disabled by disabledColumn; hidden headers.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class TableRendererTests: XCTestCase {
    private var windowUUID = ""
    private var renderTree: AdwaitaWindow?
    private var gtkWindow: UnsafeMutablePointer<GtkWindow>?
    private var fired: [(actionID: String, viewPartID: Int, context: Any?)] = []
    private let actionIDs = ["test.pick", "test.open", "test.cell"]

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "table-\(name)"
        fired = []
        for id in actionIDs {
            ActionUIModel.shared.registerActionHandler(for: id) { [weak self] actionID, _, _, viewPartID, context in
                MainActor.assumeIsolated { self?.fired.append((actionID, viewPartID, context)) }
            }
        }
    }

    override func tearDown() async throws {
        if let gtkWindow {
            gtk_window_destroy(gtkWindow)
        }
        gtkWindow = nil
        renderTree = nil
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        for id in actionIDs {
            ActionUIModel.shared.unregisterActionHandler(for: id)
        }
    }

    /// `json` in a window on screen: the column view binds cells only once it is allocated.
    private func present(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let tree = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        renderTree = tree
        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        gtkWindow = window
        adw_window_set_content(typed(window), tree.contentWidget)
        gtk_window_set_default_size(window, 640, 400)
        gtk_window_present(window)
        AdwaitaTestHost.drainMainLoop()
        return try XCTUnwrap(tree.root)
    }

    private func state(_ node: RenderNode) throws -> TableState {
        try XCTUnwrap(attached(on: node.widget, key: tableStateKey))
    }

    private func setRows(_ rows: [[String]]) {
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 1, rows: rows)
        AdwaitaTestHost.drainMainLoop()
    }

    /// The bound cell widget of `column` in the row at `position`, once GTK has bound it.
    private func cell(_ state: TableState, _ position: Int, _ column: Int) -> WidgetPointer? {
        _ = AdwaitaTestHost.runMainLoop(until: {
            state.boundCells.contains { item, itemColumn in
                itemColumn == column && Int(gtk_list_item_get_position(OpaquePointer(item))) == position
            }
        })
        for (item, itemColumn) in state.boundCells where itemColumn == column
            && Int(gtk_list_item_get_position(OpaquePointer(item))) == position {
            return gtk_list_item_get_child(OpaquePointer(item))
        }
        return nil
    }

    private func text(_ state: TableState, _ position: Int, _ column: Int) -> String? {
        cell(state, position, column).map { Gtk.Label($0).text }
    }

    private func columns(_ state: TableState) -> [OpaquePointer] {
        let list = gtk_column_view_get_columns(OpaquePointer(state.view))!
        return (0..<g_list_model_get_n_items(list)).compactMap { index in
            guard let item = g_list_model_get_item(list, index) else { return nil }
            g_object_unref(item)
            return OpaquePointer(item)
        }
    }

    /// Selects the row at `position` as the user's click would (its press marks user input).
    private func click(_ state: TableState, _ position: Int) {
        state.input.isActive = true
        gtk_single_selection_set_selected(state.selection, guint(position))
        AdwaitaTestHost.drainMainLoop()
    }

    /// Emits the column view's "activate" for `position`, as a double click or Return does.
    private func activate(_ state: TableState, _ position: Int) {
        var values = [GValue(), GValue()]
        g_value_init(&values[0], gtk_column_view_get_type())
        g_value_set_object(&values[0], UnsafeMutableRawPointer(state.view))
        g_value_init(&values[1], g_type_from_name("guint"))
        g_value_set_uint(&values[1], guint(position))
        g_signal_emitv(&values, g_signal_lookup("activate", gtk_column_view_get_type()), 0, nil)
        for index in values.indices { g_value_unset(&values[index]) }
        AdwaitaTestHost.drainMainLoop()
    }

    private let peopleTable = #"""
        {"type": "Table", "id": 1, "properties": {"columns": ["Name", "Role", "Department"], "widths": [160, 130, 150],
         "minWidths": [120], "actionID": "test.pick", "doubleClickActionID": "test.open"}}
        """#
    private let people = [["Alice", "Engineer", "Platform"], ["Bob", "Designer"], ["Carol", "Manager", "Engineering"]]

    func testColumnsTakeTheirWidthsAndTheWidestFills() throws {
        let state = try state(try present(peopleTable))
        let columns = columns(state)
        XCTAssertEqual(columns.map { swiftString(gtk_column_view_column_get_title($0)) }, ["Name", "Role", "Department"])
        XCTAssertEqual(columns.map { gtk_column_view_column_get_fixed_width($0) }, [160, 130, 150])
        XCTAssertEqual(columns.map { gtk_column_view_column_get_expand($0) != 0 }, [true, false, false], "the largest ideal width fills")
        XCTAssertTrue(columns.allSatisfy { gtk_column_view_column_get_resizable($0) != 0 })
        // A drag sets the fixed width; it goes back between the bounds.
        gtk_column_view_column_set_fixed_width(columns[0], 40)
        XCTAssertEqual(gtk_column_view_column_get_fixed_width(columns[0]), 120, "no narrower than minWidths")
        gtk_column_view_column_set_fixed_width(columns[0], 400)
        XCTAssertEqual(gtk_column_view_column_get_fixed_width(columns[0]), 400, "the filling column grows")
        gtk_column_view_column_set_fixed_width(columns[1], 4)
        XCTAssertEqual(gtk_column_view_column_get_fixed_width(columns[1]), 10, "the default minimum")
        gtk_column_view_column_set_fixed_width(columns[1], 300)
        XCTAssertEqual(gtk_column_view_column_get_fixed_width(columns[1]), 130, "no wider than its ideal width")
    }

    func testAnIdealWidthBelowTheMinimumIsRaisedToIt() {
        let widths = Table.columnWidths(TableState.Columns(titles: ["A", "B", "C"], types: [], widths: [50, 200], minWidths: [80]))
        XCTAssertEqual(widths.map(\.ideal), [80, 200, 100])
        XCTAssertEqual(widths.map(\.minimum), [80, 10, 10])
        XCTAssertEqual(widths.map(\.fills), [false, true, false])
        XCTAssertEqual(Table.clampedWidth(-1, widths[0]), -1, "unset stays unset")
        let negative = Table.columnWidths(TableState.Columns(titles: ["A", "B"], types: [], widths: [-5, 50], minWidths: [-20]))
        XCTAssertEqual(negative.map(\.ideal), [0, 50], "GTK refuses a fixed width below -1")
        XCTAssertEqual(negative.map(\.minimum), [0, 10])
    }

    func testEachRowShowsItsColumnsAndAShortRowShowsNothing() throws {
        let state = try state(try present(peopleTable))
        setRows(people)
        XCTAssertEqual(g_list_model_get_n_items(state.selection), 3)
        XCTAssertEqual(text(state, 0, 0), "Alice")
        XCTAssertEqual(text(state, 2, 1), "Manager")
        XCTAssertEqual(text(state, 1, 2), "", "the row has no third column")
    }

    func testARowsChangeShowsInTheCellsAlreadyBound() throws {
        let state = try state(try present(peopleTable))
        setRows(people)
        XCTAssertEqual(text(state, 1, 0), "Bob")
        setRows([["Alice", "Engineer", "Platform"], ["Robert", "Lead", "Product"]])
        XCTAssertEqual(g_list_model_get_n_items(state.selection), 2)
        XCTAssertEqual(text(state, 1, 0), "Robert")
        XCTAssertEqual(text(state, 1, 2), "Product")
        setRows([])
        XCTAssertEqual(g_list_model_get_n_items(state.selection), 0)
    }

    func testChangedColumnsAreMadeAgainAndOnlyTheirCellsStayBound() throws {
        let node = try present(peopleTable)
        let state = try state(node)
        setRows(people)
        XCTAssertNotNil(cell(state, 0, 2))
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "columns", value: ["Name", "Role"])
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(columns(state).map { swiftString(gtk_column_view_column_get_title($0)) }, ["Name", "Role"])
        XCTAssertEqual(text(state, 2, 1), "Manager")
        XCTAssertFalse(state.boundCells.values.contains(2), "the removed column's cells are unbound")
    }

    func testARowTheUserSelectsBecomesTheValueAndFiresOnce() throws {
        let node = try present(peopleTable)
        let state = try state(node)
        setRows(people)
        click(state, 2)
        XCTAssertEqual(node.model.value as? [String], ["Carol", "Manager", "Engineering"])
        XCTAssertEqual(fired.map(\.actionID), ["test.pick"])
        // A deselect (Ctrl+click) is the user's too.
        state.input.isActive = true
        gtk_single_selection_set_selected(state.selection, guint(GTK_INVALID_LIST_POSITION))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(node.model.value as? [String], [])
        XCTAssertEqual(fired.map(\.actionID), ["test.pick", "test.pick"])
    }

    func testARowTheHostSelectsIsSelectedAndFiresNothing() throws {
        let node = try present(peopleTable)
        let state = try state(node)
        setRows(people)
        _ = ActionUIModel.shared.selectElementRow(windowUUID: windowUUID, viewID: 1, index: 1)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(Table.selectedPosition(state), 1)
        XCTAssertEqual(node.model.value as? [String], ["Bob", "Designer"])
        // The selection stays on its row when a row is inserted before it.
        setRows([["Zed", "Intern", "Platform"]] + people)
        XCTAssertEqual(Table.selectedPosition(state), 2)
        XCTAssertTrue(fired.isEmpty)
    }

    func testASelectionGTKMakesByItselfIsUndone() throws {
        let node = try present(peopleTable)
        let state = try state(node)
        setRows(people)
        state.input.isActive = false
        gtk_single_selection_set_selected(state.selection, 0)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(Table.selectedPosition(state))
        XCTAssertEqual(node.model.value as? [String], [])
        XCTAssertTrue(fired.isEmpty)
    }

    func testADoubleClickFiresWithTheRowIndexAfterTheSelection() throws {
        let node = try present(peopleTable)
        let state = try state(node)
        setRows(people)
        activate(state, 1)
        XCTAssertEqual(node.model.value as? [String], ["Bob", "Designer"])
        XCTAssertEqual(fired.map(\.actionID), ["test.pick", "test.open"], "Return on a row not selected changes the selection first")
        XCTAssertEqual(fired.last?.context as? Int, 1)
        fired = []
        activate(state, 1)
        XCTAssertEqual(fired.map(\.actionID), ["test.open"])
    }

    func testButtonCellsFireTheirColumnsActionWithTheContextNamed() throws {
        let state = try state(try present(#"""
            {"type": "Table", "id": 1, "properties": {"columns": ["Title", "Row", "Column", "Both"], "columnTypes": [
                {"viewType": "Button", "actionID": "test.cell"},
                {"viewType": "Button", "actionID": "test.cell", "actionContext": "rowIndex"},
                {"viewType": "Button", "actionID": "test.cell", "actionContext": "columnIndex"},
                {"viewType": "Button", "actionID": "test.cell", "actionContext": "rowColumnIndex"}]}}
            """#))
        setRows([["a", "b", "c", "d"], ["e", "f", "g", "h"]])
        let title = try XCTUnwrap(cell(state, 1, 0))
        XCTAssertEqual(swiftString(gtk_button_get_label(typed(title))), "e")
        for column in 0..<4 {
            AdwaitaTestHost.emit("clicked", on: UnsafeMutableRawPointer(try XCTUnwrap(cell(state, 1, column))))
        }
        XCTAssertEqual(fired.map(\.viewPartID), [0, 1, 2, 3])
        XCTAssertEqual(fired[0].context as? String, "e")
        XCTAssertEqual(fired[1].context as? Int, 1)
        XCTAssertEqual(fired[2].context as? Int, 2)
        XCTAssertEqual(fired[3].context as? [String: Int], ["row": 1, "column": 3])
        XCTAssertNil(Table.selectedPosition(state), "a click on a button does not select the row")
    }

    func testAnImageButtonCellKeepsItsImageWhileItsTextStays() throws {
        let state = try state(try present(#"""
            {"type": "Table", "id": 1, "properties": {"columns": ["Icon", "Name"], "columnTypes": [
                {"viewType": "Button", "dataInterpretation": "systemName", "actionID": "test.cell"}]}}
            """#))
        setRows([["go-home-symbolic", "One"]])
        let button = try XCTUnwrap(cell(state, 0, 0))
        let image = try XCTUnwrap(gtk_button_get_child(typed(button)))
        g_object_ref(UnsafeMutableRawPointer(image))
        defer { g_object_unref(UnsafeMutableRawPointer(image)) }
        setRows([["go-home-symbolic", "Uno"]])
        XCTAssertEqual(gtk_button_get_child(typed(button)), image, "a rows change that keeps the text keeps the image")
        setRows([["go-up-symbolic", "Uno"]])
        XCTAssertNotEqual(gtk_button_get_child(typed(button)), image, "new text makes the image again")
    }

    func testAToggleCellWritesItsRowAndFiresAndDisabledColumnDisablesIt() throws {
        let node = try present(#"""
            {"type": "Table", "id": 1, "properties": {"columns": ["On", "Name"], "columnTypes": [
                {"viewType": "Toggle", "actionID": "test.cell", "disabledColumn": 3}, {"viewType": "Text"}]}}
            """#)
        let state = try state(node)
        setRows([["false", "One", ""], ["TRUE", "Two", "0"], ["1", "Three", "true"]])
        let first = try XCTUnwrap(cell(state, 0, 0))
        XCTAssertFalse(Gtk.CheckButton(first).isActive)
        XCTAssertTrue(Gtk.CheckButton(try XCTUnwrap(cell(state, 1, 0))).isActive, "any letter case")
        XCTAssertTrue(Gtk.Widget(first).isSensitive)
        XCTAssertFalse(Gtk.Widget(try XCTUnwrap(cell(state, 2, 0))).isSensitive, "the third column disables it")
        // The user's toggle.
        gtk_check_button_set_active(typed(first), 1)
        AdwaitaTestHost.drainMainLoop()
        let rows = ActionUIModel.shared.getElementRows(windowUUID: windowUUID, viewID: 1)
        XCTAssertEqual(rows?.first, ["true", "One", ""])
        XCTAssertEqual(fired.map(\.actionID), ["test.cell"])
        XCTAssertEqual(fired.first?.viewPartID, 0)
        XCTAssertEqual(fired.first?.context as? Int, 0)
        XCTAssertNil(Table.selectedPosition(state), "toggling does not select the row")
        // A host's rows change fires nothing.
        fired = []
        setRows([["false", "One", ""]])
        XCTAssertFalse(Gtk.CheckButton(try XCTUnwrap(cell(state, 0, 0))).isActive)
        XCTAssertTrue(fired.isEmpty)
    }

    func testHiddenHeadersHideTheHeaderRow() throws {
        let node = try present(#"{"type": "Table", "id": 1, "properties": {"columns": ["A"], "columnHeadersVisibility": "hidden"}}"#)
        let state = try state(node)
        XCTAssertEqual(Table.headerRow(state)?.isVisible, false)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "columnHeadersVisibility", value: "automatic")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(Table.headerRow(state)?.isVisible, true)
    }
}
