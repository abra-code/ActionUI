// Tests/Elements/TextFieldRendererTests.swift
/*
 Tests for the TextField renderer on GTK: the text from the value or the text property; the
 placeholder from the prompt, else the title; typing sets the value and fires valueChangeActionID,
 and a value set by the host changes the text and fires nothing; Return and leaving the field fire
 actionID, the window becoming inactive or closing does not; Return falls to the default widget
 only without an actionID; the field is greedy in width; textContentType sets the input purpose.
 A number format (measured on macOS 27): the value as the locale writes it, typing takes the number
 the text starts with, Return and leaving round to what is shown, entering takes the shown value,
 the program's value replaces the text being edited, an integer drops the fraction.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class TextFieldRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var fired: [String] = []
    private var testWindows: [WidgetPointer] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "textfield-\(name)"
        fired = []
        NumberFormatting.localeForTesting = "en_US"
        for actionID in ["test.changed", "test.submit"] {
            ActionUIModel.shared.registerActionHandler(for: actionID) { [weak self] id, _, _, _, _ in
                MainActor.assumeIsolated { self?.fired.append(id) }
            }
        }
    }

    override func tearDown() async throws {
        windows = []
        for window in testWindows { gtk_window_destroy(typed(window)) }
        testWindows = []
        AdwaitaTestHost.drainMainLoop()
        NumberFormatting.localeForTesting = nil
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

    func testTheTitleNamesTheField() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "TextField", "id": 2, "properties": {"title": "Name", "prompt": "Your name"}},
              {"type": "TextField", "id": 3, "properties": {"prompt": "Anything"}}]}
            """#)
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(try XCTUnwrap(root.childNodes[2]).widget), GTK_ACCESSIBLE_PROPERTY_LABEL), 0,
                          "named after its title, as in SwiftUI")
        XCTAssertEqual(gtk_test_accessible_has_property(OpaquePointer(try XCTUnwrap(root.childNodes[3]).widget), GTK_ACCESSIBLE_PROPERTY_LABEL), 0,
                       "no title, no name")
    }

    func testTheContentTypeSetsTheInputPurpose() throws {
        let node = try render(#"{"type": "TextField", "id": 1, "properties": {"textContentType": "emailAddress"}}"#)
        XCTAssertEqual(gtk_entry_get_input_purpose(entry(node)), GTK_INPUT_PURPOSE_EMAIL)
    }

    // MARK: - Number formats

    private func value(_ id: Int) -> String? {
        ActionUIModel.shared.windowModels[windowUUID]?.viewModels[id]?.value as? String
    }

    /// Shows `root` in a window and puts the focus in `node`'s entry, as when the user types.
    private func focusInWindow(_ root: RenderNode, _ node: RenderNode) throws {
        let window = gtk_window_new()!
        testWindows.append(window)
        gtk_window_set_child(typed(window), root.outerWidget)
        gtk_window_present(typed(window))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.widget) != 0 }))
        XCTAssertNotEqual(gtk_widget_grab_focus(node.widget), 0)
        AdwaitaTestHost.drainMainLoop()
    }

    func testANumberFormatShowsTheValueAsTheLocaleWritesIt() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "TextField", "id": 2, "properties": {"format": "currency", "currencyCode": "USD", "value": 9.99}},
              {"type": "TextField", "id": 3, "properties": {"format": "integer", "value": 1234, "axis": "vertical"}}]}
            """#)
        let price = try XCTUnwrap(root.childNodes[2])
        XCTAssertEqual(text(price), "$9.99")
        XCTAssertEqual(value(2), "9.99", "the value stays a String")
        let count = try XCTUnwrap(root.childNodes[3])
        XCTAssertNotEqual(g_type_check_instance_is_a(count.widget.withMemoryRebound(to: GTypeInstance.self, capacity: 1) { $0 }, gtk_entry_get_type()), 0,
                          "one line whatever its axis, as on Apple")
        XCTAssertEqual(text(count), "1,234")

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 2, value: "0.5")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(text(price), "$0.50")
    }

    func testTypingTakesTheNumberTheTextStartsWith() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "TextField", "id": 2, "properties": {"format": "decimal", "value": 31, "valueChangeActionID": "test.changed"}}]}
            """#)
        let node = try XCTUnwrap(root.childNodes[2])
        try focusInWindow(root, node)
        fired = []
        type("12abc", into: node)
        XCTAssertEqual(value(2), "12.0", "as the Apple binding writes a Double")
        XCTAssertEqual(fired, ["test.changed"])
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(text(node), "12abc", "the text being edited stays")
        type("abc", into: node)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(value(2), "12.0", "no number: the value stays")
        XCTAssertEqual(fired, ["test.changed"])
        XCTAssertEqual(text(node), "abc")
    }

    func testReturnRoundsTheValueToWhatIsShown() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "TextField", "id": 2, "properties": {"format": "decimal", "fractionLength": 2, "value": 31,
                                                             "valueChangeActionID": "test.changed", "actionID": "test.submit"}}]}
            """#)
        let node = try XCTUnwrap(root.childNodes[2])
        try focusInWindow(root, node)
        fired = []
        type("0.999", into: node)
        XCTAssertEqual(value(2), "0.999")
        AdwaitaTestHost.emit("activate", on: node.widget)
        XCTAssertEqual(value(2), "1.0")
        XCTAssertEqual(text(node), "1.00")
        XCTAssertEqual(fired, ["test.changed", "test.changed", "test.submit"], "actionID after the rounding")

        type("abc", into: node)
        AdwaitaTestHost.emit("activate", on: node.widget)
        XCTAssertEqual(value(2), "1.0")
        XCTAssertEqual(text(node), "1.00", "text that is no number is undone")
    }

    func testLeavingTheFieldRoundsTheValue() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "TextField", "id": 2, "properties": {"format": "currency", "currencyCode": "USD", "value": 31}},
              {"type": "TextField", "id": 3}]}
            """#)
        let node = try XCTUnwrap(root.childNodes[2])
        try focusInWindow(root, node)
        type("1,234.567", into: node)
        XCTAssertEqual(value(2), "1234.567")
        gtk_widget_grab_focus(try XCTUnwrap(root.childNodes[3]).widget)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(value(2), "1234.57")
        XCTAssertEqual(text(node), "$1,234.57")
    }

    func testEnteringTheFieldTakesTheValueItShows() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "TextField", "id": 2, "properties": {"format": "decimal", "fractionLength": 2, "value": 1.239,
                                                             "valueChangeActionID": "test.changed"}}]}
            """#)
        let node = try XCTUnwrap(root.childNodes[2])
        XCTAssertEqual(text(node), "1.24")
        XCTAssertEqual(value(2), "1.239")
        try focusInWindow(root, node)
        XCTAssertEqual(value(2), "1.24", "as SwiftUI's field reads its text when editing begins")
        XCTAssertEqual(fired, ["test.changed"])
    }

    func testTheWindowBecomingActiveAgainDoesNotTakeTheShownValue() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "TextField", "id": 2, "properties": {"format": "decimal", "fractionLength": 2, "value": 31,
                                                             "valueChangeActionID": "test.changed"}},
              {"type": "TextField", "id": 3}]}
            """#)
        let node = try XCTUnwrap(root.childNodes[2])
        try focusInWindow(root, node)
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 2, value: "1.239")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(text(node), "1.24")
        fired = []
        // A window that becomes inactive and then active again keeps its focus and emits "leave"
        // and "enter" on the focus controllers (a test window never becomes active: emitted by hand).
        let controller = try XCTUnwrap(focusController(node.widget))
        AdwaitaTestHost.emit("leave", on: controller)
        AdwaitaTestHost.emit("enter", on: controller)
        XCTAssertEqual(value(2), "1.239", "the editing goes on: the focus never left the field")
        XCTAssertEqual(fired, [])

        // The focus really leaving and coming back is new editing.
        gtk_widget_grab_focus(try XCTUnwrap(root.childNodes[3]).widget)
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 2, value: "1.239")
        AdwaitaTestHost.drainMainLoop()
        gtk_widget_grab_focus(node.widget)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(value(2), "1.24")
    }

    /// The widget's GtkEventControllerFocus.
    private func focusController(_ widget: WidgetPointer) -> UnsafeMutableRawPointer? {
        let controllers = gtk_widget_observe_controllers(widget)!
        defer { g_object_unref(UnsafeMutableRawPointer(controllers)) }
        for index in 0..<g_list_model_get_n_items(controllers) {
            guard let item = g_list_model_get_item(controllers, index) else { continue }
            // The widget keeps a reference: the pointer outlives the list's.
            g_object_unref(item)
            if g_type_check_instance_is_a(item.assumingMemoryBound(to: GTypeInstance.self), gtk_event_controller_focus_get_type()) != 0 {
                return item
            }
        }
        return nil
    }

    func testTheProgramsValueReplacesTheTextBeingEdited() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "TextField", "id": 2, "properties": {"format": "percent", "value": 0.25}}]}
            """#)
        let node = try XCTUnwrap(root.childNodes[2])
        try focusInWindow(root, node)
        type("77", into: node)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(value(2), "0.77")
        XCTAssertEqual(text(node), "77")
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 2, value: "0.770")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(text(node), "77", "the same number written another way is no change")
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 2, value: "0.5")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(text(node), "50%")
    }

    func testAnIntegerFieldDropsTheFraction() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "TextField", "id": 2, "properties": {"format": "integer", "value": 31}}]}
            """#)
        let node = try XCTUnwrap(root.childNodes[2])
        try focusInWindow(root, node)
        type("12.7", into: node)
        XCTAssertEqual(value(2), "12")
        type("0.999", into: node)
        XCTAssertEqual(value(2), "0")
        AdwaitaTestHost.emit("activate", on: node.widget)
        XCTAssertEqual(text(node), "0")
    }
}
