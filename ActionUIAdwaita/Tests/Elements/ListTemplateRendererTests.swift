// Tests/Elements/ListTemplateRendererTests.swift
/*
 Tests for the List renderer's template form on GTK: one row per content row, the template shown
 with the row's data, also in a container's children inside the template; a row the user selects
 becomes the value and fires actionID; a changed row is made again while the others keep their
 instances, and rows that go are detached; a Toggle bound to a column writes a user toggle into its
 row and fires its actionID with the row index, while one bound to no column turns back. The rows
 are made lazily (a GtkListView binds them when it lays them out): of 2000 rows only those near
 view are made, and scrolling lets the first ones go; the grouped styles make every row in a
 GtkListBox.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ListTemplateRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var gtkWindows: [UnsafeMutablePointer<GtkWindow>] = []
    private var fired: [(actionID: String, viewPartID: Int, context: Any?)] = []
    private let actionIDs = ["test.pick", "test.toggle", "test.open"]

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "list-template-\(name)"
        fired = []
        for id in actionIDs {
            ActionUIModel.shared.registerActionHandler(for: id) { [weak self] actionID, _, _, viewPartID, context in
                MainActor.assumeIsolated { self?.fired.append((actionID, viewPartID, context)) }
            }
        }
    }

    override func tearDown() async throws {
        for window in gtkWindows {
            gtk_window_destroy(window)
        }
        gtkWindows = []
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
        // On screen, 300 x 400: the list view makes its rows only when it lays them out there.
        let gtkWindow: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        gtkWindows.append(gtkWindow)
        gtk_window_set_default_size(gtkWindow, 300, 400)
        adw_window_set_content(typed(gtkWindow), window.contentWidget)
        gtk_window_present(gtkWindow)
        layOut()
        return try XCTUnwrap(window.root)
    }

    private func state(_ node: RenderNode) throws -> ListState {
        try XCTUnwrap(attached(on: node.widget, key: listStateKey))
    }

    private func setRows(_ rows: [[String]]) {
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 1, rows: rows)
        AdwaitaTestHost.drainMainLoop()
        layOut()
    }

    /// Runs the main loop long enough for the window to lay the List out, which binds its rows.
    private func layOut() {
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: 300)
        AdwaitaTestHost.drainMainLoop()
    }

    private func lazy(_ node: RenderNode) throws -> LazyListRows {
        try XCTUnwrap(try state(node).lazy, "the lazy template form")
    }

    /// The rows made, in row order.
    private func rowNodes(_ node: RenderNode) throws -> [RenderNode] {
        try lazy(node).made.sorted { $0.key < $1.key }.map(\.value)
    }

    private func rowCount(_ node: RenderNode) throws -> Int {
        Int(g_list_model_get_n_items(try lazy(node).strings))
    }

    private let textTemplate = #"{"type": "List", "id": 1, "properties": {"actionID": "test.pick"}, "template": {"type": "Text", "properties": {"text": "$1"}}}"#

    func testALoadableViewInARowIsJudgedByTheListAndMayNotTakeAnotherElementsPlace() throws {
        let path = try TestImages.file(Array(#"{"type": "Text", "id": 800, "properties": {"text": "Row"}}"#.utf8), name: "template-row.json")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let savedFolders = ActionUIRendererHooks.resourceFolders
        defer { ActionUIRendererHooks.resourceFolders = savedFolders }
        ActionUIRendererHooks.resourceFolders = { [URL(fileURLWithPath: path).deletingLastPathComponent().path] }
        func row(templateID: Int) throws -> RenderNode {
            ActionUIModel.shared.windowModels[windowUUID] = nil
            let root = try render(#"""
                {"type": "VStack", "id": 2, "children": [
                  {"type": "LoadableView", "id": 100},
                  {"type": "List", "id": 1, "template": {"type": "LoadableView", "id": \#(templateID),
                    "properties": {"filePath": "\#(path)", "viewDidLoadActionID": "test.open"}}}]}
                """#)
            setRows([["One"]])
            return try XCTUnwrap(try rowNodes(try XCTUnwrap(root.childNodes[1])).first)
        }
        // The id of the host's LoadableView 100: refused, so nothing loads into its place.
        let refused = try row(templateID: 100)
        let status = Gtk.Widget(refused.widget).children.map(\.pointer).first.map { Gtk.Label($0).text }
        XCTAssertEqual(status, "Failed to load view: id 100 is another element's in the window")
        XCTAssertNil(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[800])
        XCTAssertEqual(fired.map(\.actionID), [])
        // An id nothing has: the app's own file in a row of the host's List is as trusted as the List.
        _ = try row(templateID: 555)
        let origin = try XCTUnwrap(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 800))
        XCTAssertEqual(origin.trust, .trusted)
    }

    func testEachRowShowsTheTemplateWithItsData() throws {
        let node = try render(textTemplate)
        setRows([["Apple", "a"], ["Cherry", "c"]])
        let rows = try rowNodes(node)
        XCTAssertEqual(rows.map { Gtk.Label($0.widget).text }, ["Apple", "Cherry"])
        XCTAssertEqual(rows.map { $0.model.templateContext?.rowIndex }, [0, 1])
        XCTAssertEqual(try rowCount(node), 2)
    }

    func testAContainerInTheTemplateShowsItsChildrenWithTheRowsData() throws {
        let node = try render(#"""
            {"type": "List", "id": 1, "template": {"type": "HStack", "children": [
              {"type": "Text", "properties": {"text": "$1"}},
              {"type": "Text", "properties": {"text": "$2"}}]}}
            """#)
        setRows([["Apple", "red"]])
        let row = try XCTUnwrap(try rowNodes(node).first)
        let texts = row.childNodes.values.map { Gtk.Label($0.widget).text }.sorted()
        XCTAssertEqual(texts, ["Apple", "red"])
    }

    func testARowTheUserSelectsBecomesTheValue() throws {
        let node = try render(textTemplate)
        setRows([["Apple", "a"], ["Cherry", "c"]])
        let state = try state(node)
        state.input.isActive = true
        gtk_single_selection_set_selected(try lazy(node).selection, 1)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(node.model.value as? [String], ["Cherry", "c"])
        XCTAssertEqual(fired.map(\.actionID), ["test.pick"])
    }

    func testAChangedRowIsMadeAgainAndTheOthersAreKept() throws {
        let node = try render(textTemplate)
        setRows([["Apple"], ["Cherry"], ["Plum"]])
        let before = try rowNodes(node)
        setRows([["Apple"], ["Banana"]])
        let after = try rowNodes(node)
        guard after.count == 2, before.count == 3 else { return XCTFail("made: \(before.count) then \(after.count)") }
        XCTAssertTrue(after[0] === before[0], "the same row at the same place keeps its instance")
        XCTAssertFalse(after[1] === before[1])
        XCTAssertEqual(Gtk.Label(after[1].widget).text, "Banana")
        XCTAssertFalse(before[1].isAttached, "a replaced row is detached")
        XCTAssertFalse(before[2].isAttached, "a row that went is detached")
        XCTAssertEqual(after.count, 2)
        XCTAssertEqual(try rowCount(node), 2)
    }

    func testLabelsHiddenOnTheListReachesTheTemplateRows() throws {
        let node = try render(#"{"type": "List", "id": 1, "template": {"type": "Toggle", "properties": {"style": "checkbox", "title": "$1"}}}"#)
        setRows([["Apple"]])
        let check: UnsafeMutablePointer<GtkCheckButton> = typed(try XCTUnwrap(try rowNodes(node).first).widget)
        XCTAssertEqual(swiftString(gtk_check_button_get_label(check)), "Apple")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "labelsHidden", value: true)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(swiftString(gtk_check_button_get_label(check)), "a kept row sees the list's new environment")
    }

    private let toggleTemplate = #"{"type": "List", "id": 1, "template": {"type": "Toggle", "properties": {"style": "checkbox", "isOn": "$1", "title": "$2", "actionID": "test.toggle"}}}"#

    func testAToggleWritesItsRowAndFiresWithTheRowIndex() throws {
        let node = try render(toggleTemplate)
        setRows([["false", "Apple"], ["true", "Cherry"]])
        let check: UnsafeMutablePointer<GtkCheckButton> = typed(try XCTUnwrap(try rowNodes(node).first).widget)
        XCTAssertEqual(gtk_check_button_get_active(check), 0)
        gtk_check_button_set_active(check, 1)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(node.model.states["content"] as? [[String]], [["true", "Apple"], ["true", "Cherry"]])
        XCTAssertEqual(fired.map(\.actionID), ["test.toggle"])
        XCTAssertEqual(fired.first?.viewPartID, 0)
        XCTAssertEqual(fired.first?.context as? Bool, true)
        layOut()
        let shown: UnsafeMutablePointer<GtkCheckButton> = typed(try XCTUnwrap(try rowNodes(node).first).widget)
        XCTAssertNotEqual(gtk_check_button_get_active(shown), 0, "the row shown again from its new data")
    }

    func testToggleInTheSelectedRowKeepsTheSelection() throws {
        let node = try render(#"{"type": "List", "id": 1, "properties": {"actionID": "test.pick"}, "template": {"type": "Toggle", "properties": {"style": "checkbox", "isOn": "$1", "title": "$2", "actionID": "test.toggle"}}}"#)
        setRows([["false", "Apple"], ["false", "Cherry"]])
        node.model.value = ["false", "Cherry"]
        AdwaitaTestHost.drainMainLoop()
        let rows = try lazy(node)
        XCTAssertEqual(rows.selectedPosition, 1)
        let check: UnsafeMutablePointer<GtkCheckButton> = typed(try XCTUnwrap(try rowNodes(node).last).widget)
        gtk_check_button_set_active(check, 1)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(node.model.value as? [String], ["true", "Cherry"])
        XCTAssertEqual(rows.selectedPosition, 1, "the remade row is selected")
        XCTAssertEqual(fired.map(\.actionID), ["test.toggle"], "the write fires no selection action")
    }

    func testAToggleBoundToNoColumnTurnsBack() throws {
        let node = try render(#"{"type": "List", "id": 1, "template": {"type": "Toggle", "properties": {"style": "checkbox", "isOn": "false", "title": "$1", "actionID": "test.toggle"}}}"#)
        setRows([["Apple"]])
        let check: UnsafeMutablePointer<GtkCheckButton> = typed(try XCTUnwrap(try rowNodes(node).first).widget)
        gtk_check_button_set_active(check, 1)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_check_button_get_active(check), 0, "display-only: it shows the row")
        XCTAssertTrue(fired.isEmpty)
        XCTAssertEqual(node.model.states["content"] as? [[String]], [["Apple"]])
    }

    func testOnlyTheRowsNearViewAreMadeAndScrollingLetsTheFirstGo() throws {
        let node = try render(textTemplate)
        setRows((0..<2000).map { ["Row \($0)"] })
        let rows = try lazy(node)
        // GTK's list view keeps about 200 rows bound around the view, and the cursor's row.
        XCTAssertGreaterThan(rows.made.count, 0)
        XCTAssertLessThan(rows.made.count, 300, "made: \(rows.made.count) of 2000")
        XCTAssertEqual(Gtk.Label(try XCTUnwrap(rows.made[0]).widget).text, "Row 0")
        let early = try XCTUnwrap(rows.made[50])
        let adjustment = try XCTUnwrap(gtk_scrolled_window_get_vadjustment(OpaquePointer(node.widget)))
        gtk_adjustment_set_value(adjustment, gtk_adjustment_get_upper(adjustment) / 2)
        layOut()
        XCTAssertLessThan(rows.made.count, 300, "made: \(rows.made.count) of 2000")
        XCTAssertNil(rows.made[50], "a row far above the view is let go")
        XCTAssertFalse(early.isAttached)
        let middle = rows.made.keys.filter { $0 > 0 }.sorted()
        XCTAssertGreaterThan(try XCTUnwrap(middle.first), 500)
        XCTAssertEqual(Gtk.Label(try XCTUnwrap(rows.made[middle[0]]).widget).text, "Row \(middle[0])")
        print("[list rows] \(rows.made.count) of 2000 made, rows \(middle[0]) to \(middle[middle.count - 1]) after scrolling to the middle")
    }

    func testTheGroupedStylesMakeEveryRowInAListBox() throws {
        let node = try render(#"{"type": "List", "id": 1, "properties": {"listStyle": "insetGrouped"}, "template": {"type": "Text", "properties": {"text": "$1"}}}"#)
        setRows((0..<50).map { ["Row \($0)"] })
        let state = try state(node)
        XCTAssertNil(state.lazy)
        XCTAssertEqual(state.rowNodes.count, 50)
        XCTAssertTrue(Gtk.Widget(state.box).isA(gtk_list_box_get_type()))
    }

    func testReturnOnARowNotSelectedSelectsAndActivatesIt() throws {
        let node = try render(#"{"type": "List", "id": 1, "properties": {"actionID": "test.pick", "doubleClickActionID": "test.open"}, "template": {"type": "Text", "properties": {"text": "$1"}}}"#)
        setRows([["Apple"], ["Cherry"], ["Plum"]])
        node.model.value = ["Apple"]
        AdwaitaTestHost.drainMainLoop()
        let rows = try lazy(node)
        XCTAssertEqual(rows.selectedPosition, 0)
        // Return on the row focus moved onto without selecting it (Ctrl and an arrow key): the list
        // view activates that row, as a list box selects and activates it.
        try state(node).input.isActive = true
        XCTAssertNotEqual(gtk_widget_activate_action_variant(rows.view, "list.activate-item", g_variant_new_uint32(2)), 0)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(node.model.value as? [String], ["Plum"])
        XCTAssertEqual(rows.selectedPosition, 2)
        XCTAssertEqual(fired.map(\.actionID), ["test.pick", "test.open"])
        XCTAssertEqual(fired.last?.context as? Int, 2)
    }

    func testAStyleChangeSwitchesTheFormAndLetsTheOldRowsGo() throws {
        let node = try render(#"{"type": "List", "id": 1, "properties": {"listStyle": "insetGrouped"}, "template": {"type": "Text", "properties": {"text": "$1"}}}"#)
        setRows([["Apple"], ["Cherry"]])
        let eager = try state(node).rowNodes
        XCTAssertEqual(eager.count, 2)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "listStyle", value: "plain")
        AdwaitaTestHost.drainMainLoop()
        layOut()
        XCTAssertEqual(try rowNodes(node).map { Gtk.Label($0.widget).text }, ["Apple", "Cherry"])
        XCTAssertEqual(eager.map(\.isAttached), [false, false], "the list box's rows are let go")
        let made = try rowNodes(node)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "listStyle", value: "grouped")
        AdwaitaTestHost.drainMainLoop()
        layOut()
        XCTAssertEqual(try state(node).rowNodes.map { Gtk.Label($0.widget).text }, ["Apple", "Cherry"])
        XCTAssertEqual(made.map(\.isAttached), [false, false], "the list view's rows are let go")
    }

    func testARunOfChangedRowsIsOneModelChange() throws {
        let node = try render(textTemplate)
        setRows((0..<2000).map { ["Row \($0)"] })
        modelChanges = 0
        let handler = g_signal_connect_data(UnsafeMutableRawPointer(try lazy(node).strings), "items-changed",
                                            unsafeBitCast(countModelChange, to: GCallback.self), nil, nil, GConnectFlags(rawValue: 0))
        defer { g_signal_handler_disconnect(UnsafeMutableRawPointer(try? lazy(node).strings), handler) }
        // Every row changes but the third: two runs.
        setRows((0..<2000).map { $0 == 2 ? ["Row 2"] : ["Item \($0)"] })
        XCTAssertEqual(modelChanges, 2)
        XCTAssertEqual(try rowCount(node), 2000)
        XCTAssertEqual(try rowNodes(node).prefix(4).map { Gtk.Label($0.widget).text }, ["Item 0", "Item 1", "Row 2", "Item 3"])
    }
}

nonisolated(unsafe) private var modelChanges = 0
private let countModelChange: @convention(c) (gpointer?, guint, guint, guint, gpointer?) -> Void = { _, _, _, _, _ in
    modelChanges += 1
}
