// Tests/Elements/ListRendererTests.swift
/*
 Tests for the List renderer on GTK. Rows: one per content row with a first column, its text that
 column; a row the user selects becomes the value and fires actionID once; a row the host selects
 (selectElementRow) is selected and fires nothing; a rows change keeps the selection on its row; a
 double click makes the row the value and fires doubleClickActionID with its content index (and
 actionID first when that changes the selection, as Return on a row not yet selected does).
 Children: one row per child; selectable with an actionID (the child's id as value and context),
 not without, its content at the leading edge. A selection GTK makes when focus enters (not the
 user's) is undone. Styles: separated rows by default, navigation-sidebar for sidebar, boxed-list
 for the iOS styles (row metrics and styling: ListRowStyleRendererTests).
 (Its size against SwiftUI is in the layout parity fixtures list-in-hstack-shares and
 list-in-vstack-shares.)
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ListRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var fired: [(actionID: String, context: Any?)] = []
    private let actionIDs = ["test.pick", "test.open"]

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "list-\(name)"
        fired = []
        for id in actionIDs {
            ActionUIModel.shared.registerActionHandler(for: id) { [weak self] actionID, _, _, _, context in
                MainActor.assumeIsolated { self?.fired.append((actionID, context)) }
            }
        }
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        for id in actionIDs {
            ActionUIModel.shared.unregisterActionHandler(for: id)
        }
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func box(_ node: RenderNode) throws -> OpaquePointer {
        OpaquePointer(try XCTUnwrap(attached(on: node.widget, key: listStateKey)).box)
    }

    private func rowTexts(_ node: RenderNode) throws -> [String] {
        let box = try box(node)
        var texts: [String] = []
        var index: Int32 = 0
        while let row = gtk_list_box_get_row_at_index(box, index) {
            texts.append(gtk_list_box_row_get_child(row).map { Gtk.Label($0).text } ?? "")
            index += 1
        }
        return texts
    }

    private func selectedPosition(_ node: RenderNode) throws -> Int? {
        gtk_list_box_get_selected_row(try box(node)).map { Int(gtk_list_box_row_get_index($0)) }
    }

    /// Selects the row at `position` as the user's click would (its press marks user input).
    private func click(_ node: RenderNode, _ position: Int32) throws {
        let box = try box(node)
        try XCTUnwrap(attached(on: node.widget, key: listStateKey)).input.isActive = true
        gtk_list_box_select_row(box, try XCTUnwrap(gtk_list_box_get_row_at_index(box, position)))
        AdwaitaTestHost.drainMainLoop()
    }

    /// Emits "row-activated" for `row`, as a double click does.
    private func activate(_ box: OpaquePointer, _ row: UnsafeMutablePointer<GtkListBoxRow>) {
        var values = [GValue(), GValue()]
        g_value_init(&values[0], gtk_list_box_get_type())
        g_value_set_object(&values[0], UnsafeMutableRawPointer(box))
        g_value_init(&values[1], gtk_list_box_row_get_type())
        g_value_set_object(&values[1], UnsafeMutableRawPointer(row))
        g_signal_emitv(&values, g_signal_lookup("row-activated", gtk_list_box_get_type()), 0, nil)
        g_value_unset(&values[0])
        g_value_unset(&values[1])
    }

    private let rowsList = #"{"type": "List", "id": 1, "properties": {"actionID": "test.pick", "doubleClickActionID": "test.open"}}"#

    private func setRows(_ rows: [[String]]) {
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 1, rows: rows)
        AdwaitaTestHost.drainMainLoop()
    }

    func testEachContentRowWithAFirstColumnIsARow() throws {
        let node = try render(rowsList)
        setRows([["Apple", "a"], ["", "hidden"], ["Cherry", "c"]])
        XCTAssertEqual(try rowTexts(node), ["Apple", "Cherry"])
        setRows([["Banana"]])
        XCTAssertEqual(try rowTexts(node), ["Banana"], "fewer rows")
    }

    func testARowTheUserSelectsBecomesTheValueAndFiresOnce() throws {
        let node = try render(rowsList)
        setRows([["Apple", "a"], ["", "hidden"], ["Cherry", "c"]])
        try click(node, 1)
        XCTAssertEqual(node.model.value as? [String], ["Cherry", "c"], "the content row, past the hidden one")
        XCTAssertEqual(fired.map(\.actionID), ["test.pick"])
    }

    func testARowTheHostSelectsIsSelectedAndFiresNothing() throws {
        let node = try render(rowsList)
        setRows([["Apple"], ["Cherry"]])
        _ = ActionUIModel.shared.selectElementRow(windowUUID: windowUUID, viewID: 1, index: 1)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try selectedPosition(node), 1)
        ActionUIModel.shared.clearElementSelection(windowUUID: windowUUID, viewID: 1)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(try selectedPosition(node))
        XCTAssertTrue(fired.isEmpty)
    }

    func testARowsChangeKeepsTheSelectionOnItsRow() throws {
        let node = try render(rowsList)
        setRows([["Apple"], ["Cherry"]])
        try click(node, 1)
        setRows([["Banana"], ["Apple"], ["Cherry"]])
        XCTAssertEqual(try selectedPosition(node), 2)
        XCTAssertEqual(fired.count, 1, "no action for the rows change")
    }

    func testReturnOnARowNotYetSelectedFiresBothActions() throws {
        let node = try render(rowsList)
        setRows([["Apple"], ["Cherry"]])
        // Return on a row reached with Tab: GTK selects it and activates it in the same press.
        let box = try box(node)
        try XCTUnwrap(attached(on: node.widget, key: listStateKey)).input.isActive = true
        let row = try XCTUnwrap(gtk_list_box_get_row_at_index(box, 1))
        gtk_list_box_select_row(box, row)
        activate(box, row)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired.map(\.actionID), ["test.pick", "test.open"], "the selection change once, then the activation")
        XCTAssertEqual(node.model.value as? [String], ["Cherry"])
    }

    func testADoubleClickFiresWithTheContentIndex() throws {
        let node = try render(rowsList)
        setRows([["", "hidden"], ["Apple"], ["Cherry"]])
        try click(node, 1)
        fired = []
        let box = try box(node)
        activate(box, try XCTUnwrap(gtk_list_box_get_row_at_index(box, 1)))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired.map(\.actionID), ["test.open"])
        XCTAssertEqual(fired.first?.context as? Int, 2, "the index in the content, hidden rows counted")
        XCTAssertEqual(node.model.value as? [String], ["Cherry"])
    }

    /// The list's capture-phase controller of `type`: its watch on the user's input.
    private func inputWatch(_ node: RenderNode, _ type: GType) throws -> UnsafeMutableRawPointer {
        let list = gtk_widget_observe_controllers(typed(try box(node)))!
        defer { g_object_unref(UnsafeMutableRawPointer(list)) }
        for index in 0..<g_list_model_get_n_items(list) {
            guard let item = g_list_model_get_item(list, index) else { continue }
            g_object_unref(item)
            if g_type_check_instance_is_a(item.assumingMemoryBound(to: GTypeInstance.self), type) != 0,
               gtk_event_controller_get_propagation_phase(OpaquePointer(item)) == GTK_PHASE_CAPTURE {
                return item
            }
        }
        throw XCTSkip("no capture-phase controller of that type")
    }

    /// Emits the click gesture's "pressed" (press count, x, y).
    private func press(_ gesture: UnsafeMutableRawPointer) {
        var values = [GValue(), GValue(), GValue(), GValue()]
        g_value_init(&values[0], gtk_gesture_click_get_type())
        g_value_set_object(&values[0], gesture)
        g_value_init(&values[1], g_type_from_name("gint"))
        g_value_set_int(&values[1], 1)
        g_value_init(&values[2], g_type_from_name("gdouble"))
        g_value_init(&values[3], g_type_from_name("gdouble"))
        g_signal_emitv(&values, g_signal_lookup("pressed", gtk_gesture_click_get_type()), 0, nil)
        for index in values.indices { g_value_unset(&values[index]) }
    }

    /// Emits the key controller's "key-pressed" for `keyval`.
    private func pressKey(_ controller: UnsafeMutableRawPointer, _ keyval: Int32) {
        var handled = GValue()
        g_value_init(&handled, g_type_from_name("gboolean"))
        var values = [GValue](repeating: GValue(), count: 4)
        g_value_init(&values[0], gtk_event_controller_key_get_type())
        g_value_set_object(&values[0], controller)
        g_value_init(&values[1], g_type_from_name("guint"))
        g_value_set_uint(&values[1], guint(keyval))
        g_value_init(&values[2], g_type_from_name("guint"))
        g_value_init(&values[3], gdk_modifier_type_get_type())
        g_signal_emitv(&values, g_signal_lookup("key-pressed", gtk_event_controller_key_get_type()), 0, &handled)
        for index in values.indices { g_value_unset(&values[index]) }
        g_value_unset(&handled)
    }

    func testAClickHeldPastTheDoubleClickTimeStillSelects() throws {
        let node = try render(rowsList)
        setRows([["Apple"], ["Cherry"]])
        let box = try box(node)
        let click = try inputWatch(node, gtk_gesture_click_get_type())
        press(click)
        // GTK's double-click timer (started by the press) stops the click count while the button
        // is still down; so does a press away from the last click within the double-click time.
        AdwaitaTestHost.emit("stopped", on: click)
        AdwaitaTestHost.drainMainLoop()
        // The release: the list selects the row under the pointer.
        gtk_list_box_select_row(box, try XCTUnwrap(gtk_list_box_get_row_at_index(box, 1)))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(node.model.value as? [String], ["Cherry"])
        XCTAssertEqual(fired.map(\.actionID), ["test.pick"])
        // The gesture ends (released or canceled): a selection after that is not the user's.
        var values = [GValue(), GValue()]
        g_value_init(&values[0], gtk_gesture_click_get_type())
        g_value_set_object(&values[0], click)
        g_value_init(&values[1], gdk_event_sequence_get_type())
        g_signal_emitv(&values, g_signal_lookup("end", gtk_gesture_get_type()), 0, nil)
        for index in values.indices { g_value_unset(&values[index]) }
        AdwaitaTestHost.drainMainLoop()
        gtk_list_box_select_row(box, try XCTUnwrap(gtk_list_box_get_row_at_index(box, 0)))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try selectedPosition(node), 1, "the model's selection again")
        XCTAssertEqual(fired.count, 1)
    }

    func testAKeyPressSelectsButLeavesNoUserInputBehind() throws {
        let node = try render(rowsList)
        setRows([["Apple"], ["Cherry"]])
        let box = try box(node)
        let keys = try inputWatch(node, gtk_event_controller_key_get_type())
        // An arrow key: the list selects the next row while the press is handled.
        pressKey(keys, GDK_KEY_Down)
        gtk_list_box_select_row(box, try XCTUnwrap(gtk_list_box_get_row_at_index(box, 1)))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(node.model.value as? [String], ["Cherry"])
        // Tab moves the focus out of the list, so its release reaches another widget; focus
        // coming back (Shift+Tab) selects the row it lands on, which is not the user's selection.
        pressKey(keys, GDK_KEY_Tab)
        AdwaitaTestHost.drainMainLoop()
        gtk_list_box_select_row(box, try XCTUnwrap(gtk_list_box_get_row_at_index(box, 0)))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try selectedPosition(node), 1, "the model's selection again")
        XCTAssertEqual(node.model.value as? [String], ["Cherry"])
        XCTAssertEqual(fired.map(\.actionID), ["test.pick"])
    }

    private let childrenList = #"""
        {"type": "List", "id": 1, "properties": {"actionID": "test.pick"}, "children": [
          {"type": "Text", "id": 2, "properties": {"text": "First"}},
          {"type": "Text", "id": 3, "properties": {"text": "Second"}}]}
        """#

    func testChildrenAreRowsSelectedByTheirIDs() throws {
        let node = try render(childrenList)
        let box = try box(node)
        XCTAssertNotNil(gtk_list_box_get_row_at_index(box, 1))
        XCTAssertNil(gtk_list_box_get_row_at_index(box, 2))
        let second = try XCTUnwrap(node.childNodes[3])
        XCTAssertTrue(gtk_widget_is_ancestor(second.outerWidget, typed(gtk_list_box_get_row_at_index(box, 1)!)) != 0)
        try click(node, 1)
        XCTAssertEqual(node.model.value as? [String], ["3"])
        XCTAssertEqual(fired.first?.context as? Int, 3)
        // A value set another way (state restored): its child's row is selected.
        node.model.value = ["2"]
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try selectedPosition(node), 0)
    }

    func testASelectionGTKMakesOnFocusIsUndone() throws {
        let node = try render(childrenList)
        let box = try box(node)
        // What GTK does when the window first focuses the list: select the focused row.
        gtk_list_box_select_row(box, try XCTUnwrap(gtk_list_box_get_row_at_index(box, 0)))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(try selectedPosition(node), "the model has no selection")
        XCTAssertTrue(fired.isEmpty)
        XCTAssertEqual(node.model.value as? [String] ?? [], [])
    }

    func testAChildRowStartsAtTheLeadingEdge() throws {
        let node = try render(childrenList)
        gtk_widget_allocate(node.outerWidget, 400, 300, -1, nil)
        let first = try XCTUnwrap(node.childNodes[2])
        var row = graphene_rect_t()
        var child = graphene_rect_t()
        let rowWidget: WidgetPointer = typed(try XCTUnwrap(gtk_list_box_get_row_at_index(try box(node), 0)))
        XCTAssertNotEqual(gtk_widget_compute_bounds(rowWidget, node.outerWidget, &row), 0)
        XCTAssertNotEqual(gtk_widget_compute_bounds(first.outerWidget, node.outerWidget, &child), 0)
        XCTAssertLessThan(Double(child.origin.x - row.origin.x), 20, "at the row's leading edge, not centered")
        XCTAssertLessThan(Double(child.size.width), Double(row.size.width) / 2, "at its own width")
    }

    func testChildrenWithoutAnActionIDAreNotSelectable() throws {
        let node = try render(#"{"type": "List", "id": 1, "children": [{"type": "Text", "id": 2, "properties": {"text": "Only"}}]}"#)
        XCTAssertEqual(gtk_list_box_get_selection_mode(try box(node)), GTK_SELECTION_NONE)
    }

    func testChildrenAddedAtRunTimeBecomeRows() throws {
        let node = try render(childrenList)
        _ = try ActionUIModel.shared.insertElement(windowUUID: windowUUID, parentID: 1,
                                                   json: #"{"type": "Text", "id": 4, "properties": {"text": "Third"}}"#)
        AdwaitaTestHost.drainMainLoop()
        let box = try box(node)
        let third = try XCTUnwrap(node.childNodes[4])
        XCTAssertTrue(gtk_widget_is_ancestor(third.outerWidget, typed(try XCTUnwrap(gtk_list_box_get_row_at_index(box, 2)))) != 0)
        try ActionUIModel.shared.removeElement(windowUUID: windowUUID, viewID: 2)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(gtk_list_box_get_row_at_index(box, 2), "two rows left")
    }

    func testStylesMapToListBoxLooks() throws {
        let node = try render(rowsList)
        let box: WidgetPointer = typed(try box(node))
        XCTAssertNotEqual(gtk_list_box_get_show_separators(OpaquePointer(box)), 0)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "listStyle", value: "sidebar")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertTrue(Gtk.Widget(box).hasCSSClass("navigation-sidebar"))
        XCTAssertEqual(gtk_list_box_get_show_separators(OpaquePointer(box)), 0)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "listStyle", value: "insetGrouped")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertTrue(Gtk.Widget(box).hasCSSClass("boxed-list"))
        XCTAssertEqual(gtk_list_box_get_show_separators(OpaquePointer(box)), 0)
    }
}
