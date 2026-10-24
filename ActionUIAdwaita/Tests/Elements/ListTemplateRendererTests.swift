// Tests/Elements/ListTemplateRendererTests.swift
/*
 Tests for the List renderer's template form on GTK: one row per content row, the template shown
 with the row's data, also in a container's children inside the template; a row the user selects
 becomes the value and fires actionID; a changed row is made again while the others keep their
 instances, and rows that go are detached; a Toggle bound to a column writes a user toggle into its
 row and fires its actionID with the row index, while one bound to no column turns back.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ListTemplateRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var fired: [(actionID: String, viewPartID: Int, context: Any?)] = []
    private let actionIDs = ["test.pick", "test.toggle"]

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

    private func state(_ node: RenderNode) throws -> ListState {
        try XCTUnwrap(attached(on: node.widget, key: listStateKey))
    }

    private func setRows(_ rows: [[String]]) {
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 1, rows: rows)
        AdwaitaTestHost.drainMainLoop()
    }

    private let textTemplate = #"{"type": "List", "id": 1, "properties": {"actionID": "test.pick"}, "template": {"type": "Text", "properties": {"text": "$1"}}}"#

    func testEachRowShowsTheTemplateWithItsData() throws {
        let node = try render(textTemplate)
        setRows([["Apple", "a"], ["Cherry", "c"]])
        let rows = try state(node).rowNodes
        XCTAssertEqual(rows.map { Gtk.Label($0.widget).text }, ["Apple", "Cherry"])
        XCTAssertEqual(rows.map { $0.model.templateContext?.rowIndex }, [0, 1])
        XCTAssertNotNil(gtk_list_box_get_row_at_index(OpaquePointer(try state(node).box), 1))
    }

    func testAContainerInTheTemplateShowsItsChildrenWithTheRowsData() throws {
        let node = try render(#"""
            {"type": "List", "id": 1, "template": {"type": "HStack", "children": [
              {"type": "Text", "properties": {"text": "$1"}},
              {"type": "Text", "properties": {"text": "$2"}}]}}
            """#)
        setRows([["Apple", "red"]])
        let row = try XCTUnwrap(try state(node).rowNodes.first)
        let texts = row.childNodes.values.map { Gtk.Label($0.widget).text }.sorted()
        XCTAssertEqual(texts, ["Apple", "red"])
    }

    func testARowTheUserSelectsBecomesTheValue() throws {
        let node = try render(textTemplate)
        setRows([["Apple", "a"], ["Cherry", "c"]])
        let state = try state(node)
        state.userInput = true
        let box = OpaquePointer(state.box)
        gtk_list_box_select_row(box, try XCTUnwrap(gtk_list_box_get_row_at_index(box, 1)))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(node.model.value as? [String], ["Cherry", "c"])
        XCTAssertEqual(fired.map(\.actionID), ["test.pick"])
    }

    func testAChangedRowIsMadeAgainAndTheOthersAreKept() throws {
        let node = try render(textTemplate)
        setRows([["Apple"], ["Cherry"], ["Plum"]])
        let before = try state(node).rowNodes
        setRows([["Apple"], ["Banana"]])
        let after = try state(node).rowNodes
        XCTAssertTrue(after[0] === before[0], "the same row at the same place keeps its instance")
        XCTAssertFalse(after[1] === before[1])
        XCTAssertEqual(Gtk.Label(after[1].widget).text, "Banana")
        XCTAssertFalse(before[1].isAttached, "a replaced row is detached")
        XCTAssertFalse(before[2].isAttached, "a row that went is detached")
        XCTAssertNil(gtk_list_box_get_row_at_index(OpaquePointer(try state(node).box), 2))
    }

    func testLabelsHiddenOnTheListReachesTheTemplateRows() throws {
        let node = try render(#"{"type": "List", "id": 1, "template": {"type": "Toggle", "properties": {"style": "checkbox", "title": "$1"}}}"#)
        setRows([["Apple"]])
        let check: UnsafeMutablePointer<GtkCheckButton> = typed(try XCTUnwrap(try state(node).rowNodes.first).widget)
        XCTAssertEqual(swiftString(gtk_check_button_get_label(check)), "Apple")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "labelsHidden", value: true)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(swiftString(gtk_check_button_get_label(check)), "a kept row sees the list's new environment")
    }

    private let toggleTemplate = #"{"type": "List", "id": 1, "template": {"type": "Toggle", "properties": {"style": "checkbox", "isOn": "$1", "title": "$2", "actionID": "test.toggle"}}}"#

    func testAToggleWritesItsRowAndFiresWithTheRowIndex() throws {
        let node = try render(toggleTemplate)
        setRows([["false", "Apple"], ["true", "Cherry"]])
        let check: UnsafeMutablePointer<GtkCheckButton> = typed(try XCTUnwrap(try state(node).rowNodes.first).widget)
        XCTAssertEqual(gtk_check_button_get_active(check), 0)
        gtk_check_button_set_active(check, 1)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(node.model.states["content"] as? [[String]], [["true", "Apple"], ["true", "Cherry"]])
        XCTAssertEqual(fired.map(\.actionID), ["test.toggle"])
        XCTAssertEqual(fired.first?.viewPartID, 0)
        XCTAssertEqual(fired.first?.context as? Bool, true)
        let shown: UnsafeMutablePointer<GtkCheckButton> = typed(try XCTUnwrap(try state(node).rowNodes.first).widget)
        XCTAssertNotEqual(gtk_check_button_get_active(shown), 0, "the row shown again from its new data")
    }

    func testToggleInTheSelectedRowKeepsTheSelection() throws {
        let node = try render(#"{"type": "List", "id": 1, "properties": {"actionID": "test.pick"}, "template": {"type": "Toggle", "properties": {"style": "checkbox", "isOn": "$1", "title": "$2", "actionID": "test.toggle"}}}"#)
        setRows([["false", "Apple"], ["false", "Cherry"]])
        node.model.value = ["false", "Cherry"]
        AdwaitaTestHost.drainMainLoop()
        let box = OpaquePointer(try state(node).box)
        XCTAssertEqual(gtk_list_box_get_selected_row(box).map { gtk_list_box_row_get_index($0) }, 1)
        let check: UnsafeMutablePointer<GtkCheckButton> = typed(try XCTUnwrap(try state(node).rowNodes.last).widget)
        gtk_check_button_set_active(check, 1)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(node.model.value as? [String], ["true", "Cherry"])
        XCTAssertEqual(gtk_list_box_get_selected_row(box).map { gtk_list_box_row_get_index($0) }, 1, "the remade row is selected")
        XCTAssertEqual(fired.map(\.actionID), ["test.toggle"], "the write fires no selection action")
    }

    func testAToggleBoundToNoColumnTurnsBack() throws {
        let node = try render(#"{"type": "List", "id": 1, "template": {"type": "Toggle", "properties": {"style": "checkbox", "isOn": "false", "title": "$1", "actionID": "test.toggle"}}}"#)
        setRows([["Apple"]])
        let check: UnsafeMutablePointer<GtkCheckButton> = typed(try XCTUnwrap(try state(node).rowNodes.first).widget)
        gtk_check_button_set_active(check, 1)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_check_button_get_active(check), 0, "display-only: it shows the row")
        XCTAssertTrue(fired.isEmpty)
        XCTAssertEqual(node.model.states["content"] as? [[String]], [["Apple"]])
    }
}
