// Tests/Elements/TextFieldRendererTests.swift
/*
 Tests for the TextField renderer on GTK: the text from the value or the text property; the
 placeholder from the prompt, else the title; typing sets the value and fires valueChangeActionID,
 and a value set by the host changes the text and fires nothing; Return and leaving the field fire
 actionID, the window becoming inactive or closing does not; Return falls to the default widget
 only without an actionID; the field is greedy in width; textContentType sets the input purpose.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class TextFieldRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var fired: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "textfield-\(name)"
        fired = []
        for actionID in ["test.changed", "test.submit"] {
            ActionUIModel.shared.registerActionHandler(for: actionID) { [weak self] id, _, _, _, _ in
                MainActor.assumeIsolated { self?.fired.append(id) }
            }
        }
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIModel.shared.unregisterActionHandler(for: "test.changed")
        ActionUIModel.shared.unregisterActionHandler(for: "test.submit")
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func entry(_ node: RenderNode) -> UnsafeMutablePointer<GtkEntry> {
        typed(node.widget)
    }

    private func text(_ node: RenderNode) -> String? {
        swiftString(gtk_editable_get_text(OpaquePointer(node.widget)))
    }

    /// What typing does: the entry's text changes outside a renderer update.
    private func type(_ text: String, into node: RenderNode) {
        gtk_editable_set_text(OpaquePointer(node.widget), text)
    }

    func testTheTextAndPlaceholder() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "TextField", "id": 2, "properties": {"title": "Name", "text": "Ann"}},
              {"type": "TextField", "id": 3, "properties": {"title": "Name", "prompt": "Your name"}}]}
            """#)
        let titled = try XCTUnwrap(root.childNodes[2])
        XCTAssertEqual(text(titled), "Ann")
        XCTAssertEqual(swiftString(gtk_entry_get_placeholder_text(entry(titled))), "Name", "no prompt: the title, as on macOS")
        XCTAssertEqual(swiftString(gtk_entry_get_placeholder_text(entry(try XCTUnwrap(root.childNodes[3])))), "Your name")
        XCTAssertNotEqual(gtk_widget_get_hexpand(titled.widget), 0, "greedy in width")
    }

    func testTypingSetsTheValueAndAHostValueFiresNothing() throws {
        let node = try render(#"{"type": "TextField", "id": 1, "properties": {"valueChangeActionID": "test.changed"}}"#)
        XCTAssertEqual(fired, [], "rendering fires nothing")
        type("hello", into: node)
        XCTAssertEqual(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1]?.value as? String, "hello")
        XCTAssertEqual(fired, ["test.changed"])
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(text(node), "hello")

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "from host")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(text(node), "from host")
        XCTAssertEqual(fired, ["test.changed"], "the host's value fires no action")
    }

    func testReturnAndLeavingTheFieldSubmit() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "TextField", "id": 2, "properties": {"actionID": "test.submit"}},
              {"type": "TextField", "id": 3}]}
            """#)
        let first = try XCTUnwrap(root.childNodes[2])
        let second = try XCTUnwrap(root.childNodes[3])
        AdwaitaTestHost.emit("activate", on: first.widget)
        XCTAssertEqual(fired, ["test.submit"])
        XCTAssertEqual(gtk_entry_get_activates_default(entry(first)), 0, "its actionID takes Return")
        XCTAssertNotEqual(gtk_entry_get_activates_default(entry(second)), 0, "no actionID: Return goes to the default widget")

        let window = gtk_window_new()!
        defer { gtk_window_destroy(typed(window)) }
        gtk_window_set_child(typed(window), root.outerWidget)
        defer { gtk_window_set_child(typed(window), nil) }
        gtk_window_present(typed(window))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(first.widget) != 0 }))
        // The focus is in the entry's text widget. (has_focus is false while the test window is
        // not the active one, which it never becomes.)
        XCTAssertNotEqual(gtk_widget_grab_focus(first.widget), 0)
        let focus = try XCTUnwrap(gtk_root_get_focus(OpaquePointer(window)))
        XCTAssertNotEqual(gtk_widget_is_ancestor(focus, first.widget), 0)
        fired = []
        gtk_widget_grab_focus(second.widget)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired, ["test.submit"], "leaving the field submits it, as on macOS")
    }

    func testTheWindowGoingInactiveOrAwayDoesNotSubmit() throws {
        let node = try render(#"{"type": "TextField", "id": 1, "properties": {"actionID": "test.submit"}}"#)
        let window = gtk_window_new()!
        gtk_window_set_child(typed(window), node.outerWidget)
        gtk_window_present(typed(window))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.widget) != 0 }))
        XCTAssertNotEqual(gtk_widget_grab_focus(node.widget), 0)
        AdwaitaTestHost.drainMainLoop()

        // A window that becomes inactive keeps its focus and emits "leave" on the focus
        // controllers (a test window never becomes active, so the signal is emitted by hand).
        let controllers = gtk_widget_observe_controllers(node.widget)!
        defer { g_object_unref(UnsafeMutableRawPointer(controllers)) }
        var focusController: UnsafeMutableRawPointer?
        for index in 0..<g_list_model_get_n_items(controllers) {
            guard let item = g_list_model_get_item(controllers, index) else { continue }
            defer { g_object_unref(item) }
            if g_type_check_instance_is_a(item.assumingMemoryBound(to: GTypeInstance.self), gtk_event_controller_focus_get_type()) != 0 {
                focusController = item
            }
        }
        AdwaitaTestHost.emit("leave", on: try XCTUnwrap(focusController))
        XCTAssertEqual(fired, [], "the focus is still in the field")

        // A closed window drops its focus after unmapping the field.
        gtk_window_destroy(typed(window))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired, [], "closing the window does not submit")
    }

    func testTheContentTypeSetsTheInputPurpose() throws {
        let node = try render(#"{"type": "TextField", "id": 1, "properties": {"textContentType": "emailAddress"}}"#)
        XCTAssertEqual(gtk_entry_get_input_purpose(entry(node)), GTK_INPUT_PURPOSE_EMAIL)
    }
}
