// Tests/Elements/VerticalTextFieldRendererTests.swift
/*
 Tests for a TextField with axis vertical on GTK (VerticalTextField): one line is as tall as a
 one-line field and it grows with its text; lineLimit n caps the lines, a range sets the fewest too,
 a huge one is no limit; typing sets the value and fires valueChangeActionID; Return fires actionID
 (not while an input method composes), and with Option, Control or Shift inserts a new line; in a
 Form its title stands beside its first line; the axis changing makes the other field; the text view
 is what assistive technologies read, named after the title.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class VerticalTextFieldRendererTests: XCTestCase {
    private var windowUUID = ""
    private var renderTree: AdwaitaWindow?
    private var gtkWindow: UnsafeMutablePointer<GtkWindow>?
    private var fired: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "vertical-textfield-\(name)"
        fired = []
        for actionID in ["test.changed", "test.submit"] {
            ActionUIModel.shared.registerActionHandler(for: actionID) { [weak self] id, _, _, _, _ in
                MainActor.assumeIsolated { self?.fired.append(id) }
            }
        }
    }

    override func tearDown() async throws {
        renderTree?.detach()
        renderTree = nil
        if let gtkWindow {
            gtk_window_destroy(gtkWindow)
        }
        gtkWindow = nil
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIModel.shared.unregisterActionHandler(for: "test.changed")
        ActionUIModel.shared.unregisterActionHandler(for: "test.submit")
    }

    private func present(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let tree = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        renderTree = tree
        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        gtkWindow = window
        gtk_window_set_default_size(window, 300, 400)
        adw_window_set_content(typed(window), tree.contentWidget)
        gtk_window_present(window)
        AdwaitaTestHost.drainMainLoop()
        return try XCTUnwrap(tree.root)
    }

    /// The field's height once laid out: GtkTextView measures its lines when idle, and the window
    /// lays out on its next frame.
    private func height(_ node: RenderNode) -> Int32 {
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: 150)
        return gtk_widget_get_height(node.outerWidget)
    }

    private func view(_ node: RenderNode) throws -> UnsafeMutablePointer<GtkTextView> {
        typed(try XCTUnwrap(VerticalTextField.parts(node.widget)).view)
    }

    private func setText(_ text: String, _ node: RenderNode) {
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: node.element.id, value: text)
        AdwaitaTestHost.drainMainLoop()
    }

    /// What typing does: an edit the user makes to the buffer.
    private func type(_ text: String, into node: RenderNode) throws {
        let buffer = gtk_text_view_get_buffer(try view(node))!
        gtk_text_buffer_begin_user_action(buffer)
        gtk_text_buffer_insert_interactive_at_cursor(buffer, text, -1, 1)
        gtk_text_buffer_end_user_action(buffer)
        AdwaitaTestHost.drainMainLoop()
    }

    /// Emits the text view's capture-phase key controller's "key-pressed" for `keyval`, no modifiers;
    /// returns whether it was handled.
    private func pressKey(_ node: RenderNode, _ keyval: Int32) throws -> Bool {
        let controllers = gtk_widget_observe_controllers(UnsafeMutablePointer(OpaquePointer(try view(node))))!
        defer { g_object_unref(UnsafeMutableRawPointer(controllers)) }
        var keys: UnsafeMutableRawPointer?
        for index in 0..<g_list_model_get_n_items(controllers) {
            guard let item = g_list_model_get_item(controllers, index) else { continue }
            g_object_unref(item)
            if g_type_check_instance_is_a(item.assumingMemoryBound(to: GTypeInstance.self), gtk_event_controller_key_get_type()) != 0,
               gtk_event_controller_get_propagation_phase(OpaquePointer(item)) == GTK_PHASE_CAPTURE {
                keys = item
            }
        }
        var handled = GValue()
        g_value_init(&handled, g_type_from_name("gboolean"))
        var values = [GValue](repeating: GValue(), count: 4)
        g_value_init(&values[0], gtk_event_controller_key_get_type())
        g_value_set_object(&values[0], try XCTUnwrap(keys))
        g_value_init(&values[1], g_type_from_name("guint"))
        g_value_set_uint(&values[1], guint(keyval))
        g_value_init(&values[2], g_type_from_name("guint"))
        g_value_init(&values[3], gdk_modifier_type_get_type())
        g_signal_emitv(&values, g_signal_lookup("key-pressed", gtk_event_controller_key_get_type()), 0, &handled)
        for index in values.indices { g_value_unset(&values[index]) }
        defer { g_value_unset(&handled) }
        AdwaitaTestHost.drainMainLoop()
        return g_value_get_boolean(&handled) != 0
    }

    func testOneLineIsAsTallAsAOneLineFieldAndItGrowsWithItsText() throws {
        let root = try present(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "TextField", "id": 2, "properties": {"prompt": "Notes", "axis": "vertical"}},
              {"type": "TextField", "id": 3, "properties": {"prompt": "Name"}}]}
            """#)
        let field = try XCTUnwrap(root.childNodes[2])
        let one = height(field)
        XCTAssertEqual(one, height(try XCTUnwrap(root.childNodes[3])))
        setText("a\nb", field)
        let two = height(field)
        setText("a\nb\nc", field)
        let three = height(field)
        XCTAssertGreaterThan(two, one)
        XCTAssertEqual(three - two, two - one, "a line more each time")
    }

    func testLineLimitCapsTheLinesAndARangeSetsTheFewest() throws {
        let root = try present(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "TextField", "id": 2, "properties": {"axis": "vertical"}},
              {"type": "TextField", "id": 3, "properties": {"axis": "vertical", "lineLimit": 2}},
              {"type": "TextField", "id": 4, "properties": {"axis": "vertical", "lineLimit": {"min": 3, "max": 4}}}]}
            """#)
        let free = try XCTUnwrap(root.childNodes[2])
        let one = height(free)
        setText("a\nb", free)
        let line = height(free) - one
        // lineLimit 2: from one line, at most two (SwiftUI reserves no space for them).
        let capped = try XCTUnwrap(root.childNodes[3])
        XCTAssertEqual(height(capped), one)
        setText("a\nb\nc\nd", capped)
        XCTAssertEqual(height(capped), one + line)
        // {min 3, max 4}: three lines empty, four at most.
        let ranged = try XCTUnwrap(root.childNodes[4])
        XCTAssertEqual(height(ranged), one + 2 * line)
        setText("a\nb\nc\nd\ne\nf", ranged)
        XCTAssertEqual(height(ranged), one + 3 * line)
    }

    func testAHugeLineLimitIsNoLimit() throws {
        // Lines times a line's height past Int32 (and Int) trapped.
        let root = try present(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "TextField", "id": 2, "properties": {"axis": "vertical"}},
              {"type": "TextField", "id": 3, "properties": {"axis": "vertical", "lineLimit": 9223372036854775807}}]}
            """#)
        let free = try XCTUnwrap(root.childNodes[2])
        let huge = try XCTUnwrap(root.childNodes[3])
        XCTAssertEqual(height(huge), height(free))
        setText("a\nb\nc", free)
        setText("a\nb\nc", huge)
        XCTAssertEqual(height(huge), height(free))
    }

    func testTypingSetsTheValueAndReturnSubmits() throws {
        let root = try present(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "TextField", "id": 2, "properties": {"axis": "vertical", "valueChangeActionID": "test.changed", "actionID": "test.submit"}}]}
            """#)
        let field = try XCTUnwrap(root.childNodes[2])
        try type("Hello", into: field)
        XCTAssertEqual(field.model.value as? String, "Hello")
        XCTAssertEqual(fired, ["test.changed"])
        XCTAssertTrue(try pressKey(field, GDK_KEY_Return))
        XCTAssertEqual(fired, ["test.changed", "test.submit"])
        XCTAssertEqual(TextEditor.bufferText(gtk_text_view_get_buffer(try view(field))!), "Hello", "Return inserted no line")
        // A host's value changes the text and fires nothing.
        setText("Hi\nthere", field)
        XCTAssertEqual(TextEditor.bufferText(gtk_text_view_get_buffer(try view(field))!), "Hi\nthere")
        XCTAssertEqual(fired, ["test.changed", "test.submit"])
    }

    /// Emits the text view's "preedit-changed" with `preedit`, as an input method does.
    private func preeditChanged(_ node: RenderNode, _ preedit: String) throws {
        var values = [GValue(), GValue()]
        g_value_init(&values[0], gtk_text_view_get_type())
        g_value_set_object(&values[0], UnsafeMutableRawPointer(try view(node)))
        g_value_init(&values[1], g_type_from_name("gchararray"))
        g_value_set_string(&values[1], preedit)
        g_signal_emitv(&values, g_signal_lookup("preedit-changed", gtk_text_view_get_type()), 0, nil)
        for index in values.indices { g_value_unset(&values[index]) }
    }

    func testReturnGoesToTheInputMethodWhileItComposes() throws {
        let root = try present(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "TextField", "id": 2, "properties": {"axis": "vertical", "actionID": "test.submit"}}]}
            """#)
        let field = try XCTUnwrap(root.childNodes[2])
        try preeditChanged(field, "ka")
        XCTAssertFalse(try pressKey(field, GDK_KEY_Return), "left to the input method")
        XCTAssertEqual(fired, [])
        // Composing ends with an empty preedit.
        try preeditChanged(field, "")
        XCTAssertTrue(try pressKey(field, GDK_KEY_Return))
        XCTAssertEqual(fired, ["test.submit"])
    }

    func testReturnWithOptionControlOrShiftInsertsANewLine() {
        XCTAssertFalse(VerticalTextField.returnInsertsNewLine(GdkModifierType(rawValue: 0)))
        for modifier in [GDK_ALT_MASK, GDK_CONTROL_MASK, GDK_SHIFT_MASK] {
            XCTAssertTrue(VerticalTextField.returnInsertsNewLine(modifier))
        }
        XCTAssertFalse(VerticalTextField.returnInsertsNewLine(GDK_SUPER_MASK))
    }

    func testInAFormTheTitleStandsBesideTheFirstLine() throws {
        let root = try present(#"""
            {"type": "Form", "id": 1, "children": [
              {"type": "TextField", "id": 2, "properties": {"title": "Notes", "axis": "vertical", "lineLimit": {"min": 3}}}]}
            """#)
        let field = try XCTUnwrap(root.childNodes[2])
        let title = try XCTUnwrap(Gtk.Widget(field.widget).firstChild)
        XCTAssertEqual(Gtk.Label(title.pointer).text, "Notes")
        XCTAssertNotNil(VerticalTextField.parts(field.widget))
        // The title's text starts where the field's first line does (the same font: the same
        // baseline), not at the middle of the field's three lines.
        var titleBounds = graphene_rect_t()
        XCTAssertNotEqual(gtk_widget_compute_bounds(title.pointer, field.widget, &titleBounds), 0)
        var offsetX: Int32 = 0
        var offsetY: Int32 = 0
        gtk_label_get_layout_offsets(opaque(title.pointer), &offsetX, &offsetY)
        var viewBounds = graphene_rect_t()
        XCTAssertNotEqual(gtk_widget_compute_bounds(UnsafeMutablePointer(OpaquePointer(try view(field))), field.widget, &viewBounds), 0)
        XCTAssertEqual(Int(titleBounds.origin.y) + Int(offsetY), Int(viewBounds.origin.y) + Int(VerticalTextField.inset.vertical))
    }

    func testTheAxisChangingMakesTheOtherField() throws {
        let root = try present(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "TextField", "id": 2, "properties": {"title": "Name", "axis": "vertical", "text": "Ann"}}]}
            """#)
        let field = try XCTUnwrap(root.childNodes[2])
        let view = TextField.accessibleWidget(field.widget)
        XCTAssertTrue(Gtk.Widget(view).isA(gtk_text_view_get_type()))
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(view), GTK_ACCESSIBLE_PROPERTY_LABEL), 0, "named after its title")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 2, propertyName: "axis", value: "horizontal")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertTrue(Gtk.Widget(field.widget).isA(gtk_entry_get_type()))
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(field.widget), GTK_ACCESSIBLE_PROPERTY_LABEL), 0)
        XCTAssertEqual(swiftString(gtk_editable_get_text(OpaquePointer(field.widget))), "Ann")
    }
}
