// Tests/Elements/TextEditorRendererTests.swift
/*
 Tests for the TextEditor renderer on GTK: a word-wrapping text view, greedy in both axes; the text
 from the value, else text, else markdown, which is styled text whose typed characters take the
 style around them as on macOS 27 (measured), with an AttributedString value; typing sets the value and fires
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
                let value = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[viewID]?.value
                self?.firedValues.append(value as? String ?? (value as? AttributedString).map { String($0.characters) } ?? "")
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

    // MARK: - Markdown

    private struct Run: Equatable, CustomStringConvertible {
        var text: String
        var style: MarkdownStyle = []
        var link: String?
        var description: String { "[\(text)] \(style.rawValue) \(link ?? "")" }
    }

    private func runs(_ attributed: AttributedString) -> [Run] {
        attributed.runs.map { run in
            Run(text: String(attributed[run.range].characters), style: run[MarkdownStyleAttribute.self] ?? [],
                link: run.link?.absoluteString)
        }
    }

    private func runs(_ node: RenderNode) -> [Run] {
        runs(MarkdownBuffer.of(buffer(node)).attributedText())
    }

    /// Types `text` as GtkTextView does: one user action that deletes the selection (`replacing`
    /// characters from `offset`), then inserts at the cursor.
    private func type(_ text: String, at offset: Int, replacing length: Int = 0, in node: RenderNode) {
        let buffer = buffer(node)
        var start = GtkTextIter()
        var end = GtkTextIter()
        gtk_text_buffer_get_iter_at_offset(buffer, &start, Int32(offset))
        gtk_text_buffer_get_iter_at_offset(buffer, &end, Int32(offset + length))
        gtk_text_buffer_select_range(buffer, &start, &end)
        gtk_text_buffer_begin_user_action(buffer)
        gtk_text_buffer_delete_selection(buffer, 1, 1)
        gtk_text_buffer_insert_interactive_at_cursor(buffer, text, -1, 1)
        gtk_text_buffer_end_user_action(buffer)
    }

    func testMarkdownIsStyledText() throws {
        let source = "# Title\n\nSome **bold**, `code` and [a link](https://example.com)."
        let node = try render(##""markdown": "# Title\n\nSome **bold**, `code` and [a link](https://example.com).""##)
        XCTAssertEqual(TextEditor.bufferText(buffer(node)), "TitleSome bold, code and a link.", "inline styles only, blocks run together, as on macOS")
        XCTAssertEqual(runs(node), runs(MarkdownText.attributedString(markdown: source)))
        XCTAssertEqual(runs(node), [
            Run(text: "TitleSome "), Run(text: "bold", style: .bold), Run(text: ", "), Run(text: "code", style: .code),
            Run(text: " and "), Run(text: "a link", link: "https://example.com"), Run(text: "."),
        ])
    }

    func testTypedTextTakesTheStyleAroundItAsOnMacOS() throws {
        let node = try render(#""markdown": "**Bold** start and *it* [link](https://e.com)", "valueChangeActionID": "test.edited""#)
        type("X", at: 2, in: node)
        type("Y", at: 5, in: node)
        type("A", at: 0, in: node)
        XCTAssertEqual(runs(node).first, Run(text: "ABoXldY", style: .bold), "inside, after, and at the start before a bold word")
        XCTAssertEqual(fired.count, 3, "each keystroke is an edit")
        XCTAssertEqual(runs(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1]?.value as? AttributedString ?? AttributedString()),
                       runs(node), "the value is the styled text")

        let text = TextEditor.bufferText(buffer(node)) as NSString
        let link = text.range(of: "link")
        type("W", at: link.location + link.length, in: node)
        type("V", at: link.location + 2, in: node)
        XCTAssertEqual(Array(runs(node).suffix(2)), [Run(text: "liVnk", link: "https://e.com"), Run(text: "W")],
                       "a link goes on inside it, not after its end")

        type("N", at: 0, replacing: 7, in: node)
        type("\n", at: 1, in: node)
        XCTAssertEqual(runs(node).first, Run(text: "N\n", style: .bold), "typed over a selection: the style of its first character; a new line too")
        let italic = (TextEditor.bufferText(buffer(node)) as NSString).range(of: " start")
        type("M", at: italic.location, replacing: 9, in: node)
        XCTAssertEqual(runs(node)[1], Run(text: "Md "), "a selection starting in plain text gives plain text")
    }

    func testAHostValueIsReadAsMarkdown() throws {
        let node = try render(#""markdown": "plain", "placeholder": "Notes""#)
        ActionUIModel.shared.setElementValueFromString(windowUUID: windowUUID, viewID: 1, value: "**now** bold", contentType: "markdown")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(runs(node), [Run(text: "now", style: .bold), Run(text: " bold")])
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "*x*")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(runs(node), [Run(text: "x", style: .italic)], "a String value is markdown, as in SwiftUI's attributed editor")
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_widget_get_visible(try placeholder(node)), 1, "empty: the placeholder shows")
    }

    func testShowingTheValueIsNotUndoable() throws {
        let node = try render(#""markdown": "**Bold** start [link](https://e.com) end", "valueChangeActionID": "test.edited""#)
        XCTAssertEqual(gtk_text_buffer_get_can_undo(buffer(node)), 0, "as gtk_text_buffer_set_text in the plain editor")
        let shown = runs(node)
        type("X", at: 2, in: node)
        gtk_text_buffer_undo(buffer(node))
        XCTAssertEqual(runs(node), shown, "undo takes the typing back")
        gtk_text_buffer_undo(buffer(node))
        XCTAssertEqual(runs(node), shown, "and nothing of the shown text")
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
