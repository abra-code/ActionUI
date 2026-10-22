// Tests/Elements/TextEditorRendererTests.swift
/*
 Tests for the TextEditor renderer on GTK: a word-wrapping text view, greedy in both axes; the text
 from the value, else text, else markdown (as its source); typing sets the value and fires
 valueChangeActionID, and a host value changes the text and fires nothing; typing over a selection
 and undo are one edit each; readOnly makes it not editable (its cursor stays); the placeholder
 shows while the text is empty, also as the user types, and names the text view.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class TextEditorRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var fired: [String] = []
    /// The value when each action fired.
    private var firedValues: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "texteditor-\(name)"
        fired = []
        firedValues = []
        ActionUIModel.shared.registerActionHandler(for: "test.edited") { [weak self] actionID, windowUUID, viewID, _, _ in
            MainActor.assumeIsolated {
                self?.fired.append(actionID)
                self?.firedValues.append(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[viewID]?.value as? String ?? "")
            }
        }
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIModel.shared.unregisterActionHandler(for: "test.edited")
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ properties: String) throws -> RenderNode {
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let json = #"{"type": "TextEditor", "id": 1, "properties": {"# + properties + "}}"
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func view(_ node: RenderNode) -> UnsafeMutablePointer<GtkTextView> {
        typed(TextEditor.accessibleWidget(node.widget))
    }

    private func buffer(_ node: RenderNode) -> UnsafeMutablePointer<GtkTextBuffer> {
        gtk_text_view_get_buffer(view(node))!
    }

    private func placeholder(_ node: RenderNode) throws -> WidgetPointer {
        try XCTUnwrap(gtk_widget_get_last_child(node.widget))
    }

    func testTheTextAndTheSize() throws {
        let node = try render(#""text": "Hello""#)
        XCTAssertEqual(TextEditor.bufferText(buffer(node)), "Hello")
        XCTAssertEqual(gtk_text_view_get_wrap_mode(view(node)), GTK_WRAP_WORD_CHAR)
        XCTAssertNotEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_HORIZONTAL), 0)
        XCTAssertNotEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_VERTICAL), 0, "greedy in both axes, as on macOS")
        let markdown = try render(#""markdown": "**Bold**""#)
        XCTAssertEqual(TextEditor.bufferText(buffer(markdown)), "**Bold**", "markdown as its source for now")
    }

    func testTypingSetsTheValueAndAHostValueFiresNothing() throws {
        let node = try render(#""valueChangeActionID": "test.edited""#)
        gtk_text_buffer_set_text(buffer(node), "typed", -1)
        XCTAssertEqual(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1]?.value as? String, "typed")
        XCTAssertEqual(fired, ["test.edited"])
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired.count, 1, "the sync after typing fires nothing")

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "from host")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(TextEditor.bufferText(buffer(node)), "from host")
        XCTAssertEqual(fired.count, 1, "host values fire nothing")
    }

    func testTypingOverASelectionIsOneEdit() throws {
        let node = try render(#""text": "abc", "valueChangeActionID": "test.edited""#)
        let buffer = buffer(node)
        var start = GtkTextIter()
        var end = GtkTextIter()
        gtk_text_buffer_get_bounds(buffer, &start, &end)
        gtk_text_buffer_select_range(buffer, &start, &end)
        // What GtkTextView does with typed text (gtk_text_view_commit_text), and pasting too: one
        // user action that deletes the selection, then inserts.
        gtk_text_buffer_begin_user_action(buffer)
        gtk_text_buffer_delete_selection(buffer, 1, 1)
        gtk_text_buffer_insert_interactive_at_cursor(buffer, "x", -1, 1)
        gtk_text_buffer_end_user_action(buffer)
        XCTAssertEqual(fired, ["test.edited"], "one edit, one action")
        XCTAssertEqual(firedValues, ["x"], "no empty value in between")
    }

    func testReadOnlyIsNotEditable() throws {
        let node = try render(#""text": "Fixed", "readOnly": true"#)
        XCTAssertEqual(gtk_text_view_get_editable(view(node)), 0)
        XCTAssertNotEqual(gtk_text_view_get_cursor_visible(view(node)), 0, "the cursor stays, for selecting from the keyboard")
    }

    func testUndoIsOneEdit() throws {
        let node = try render(#""valueChangeActionID": "test.edited""#)
        let buffer = buffer(node)
        // Two user edits: "abc", then "x" over all of it (a delete, then an insert).
        gtk_text_buffer_begin_user_action(buffer)
        gtk_text_buffer_insert_at_cursor(buffer, "abc", -1)
        gtk_text_buffer_end_user_action(buffer)
        var start = GtkTextIter()
        var end = GtkTextIter()
        gtk_text_buffer_get_bounds(buffer, &start, &end)
        gtk_text_buffer_begin_user_action(buffer)
        gtk_text_buffer_delete(buffer, &start, &end)
        gtk_text_buffer_insert_at_cursor(buffer, "x", -1)
        gtk_text_buffer_end_user_action(buffer)
        firedValues = []
        gtk_text_buffer_undo(buffer)
        XCTAssertEqual(firedValues, ["abc"], "undoing the replace is one edit, with no empty text between")
        gtk_text_buffer_redo(buffer)
        XCTAssertEqual(firedValues, ["abc", "x"])
    }

    func testThePlaceholderShowsWhileEmptyAndNamesTheView() throws {
        let node = try render(#""placeholder": "Notes""#)
        let label = try placeholder(node)
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(label))), "Notes")
        XCTAssertNotEqual(gtk_widget_get_visible(label), 0)
        XCTAssertEqual(gtk_accessible_get_accessible_role(OpaquePointer(label)), GTK_ACCESSIBLE_ROLE_PRESENTATION)
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(view(node)), GTK_ACCESSIBLE_PROPERTY_LABEL), 0)
        gtk_text_buffer_set_text(buffer(node), "x", -1)
        XCTAssertEqual(gtk_widget_get_visible(label), 0, "hidden as soon as the user types")
        gtk_text_buffer_set_text(buffer(node), "", -1)
        XCTAssertNotEqual(gtk_widget_get_visible(label), 0)
    }
}
