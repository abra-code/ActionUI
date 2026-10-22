// Views/TextEditorReadOnlyTests.swift
/*
 A read-only TextEditor keeps its text on Apple: typing into its text view (what a keystroke does,
 NSTextView.insertText) changes neither the text shown nor the value, for plain text and for
 markdown; the text stays selectable. An editable TextEditor takes the typing, as before.
*/

#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import ActionUI

@MainActor
final class TextEditorReadOnlyTests: XCTestCase {
    private var logger: XCTestLogger!
    private var window: NSWindow?
    private var windowUUID: String?

    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .warning)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
    }

    override func tearDown() async throws {
        window?.orderOut(nil)
        window = nil
        windowUUID = nil
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        try await super.tearDown()
    }

    /// The TextEditor shown in a window, its text view, and its view model.
    private func render(_ properties: [String: Any]) throws -> (NSTextView, ViewModel) {
        let document: [String: Any] = ["type": "TextEditor", "id": 1, "properties": properties]
        let windowUUID = UUID().uuidString
        self.windowUUID = windowUUID
        let element = try ActionUIModel.shared.loadDescription(from: document, windowUUID: windowUUID)
        let viewModel = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id])
        let host = NSHostingView(rootView: ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
            .frame(width: 200, height: 80))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 120), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        self.window = window
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        return (try XCTUnwrap(textView(in: host), "no text view"), viewModel)
    }

    private func textView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        return view.subviews.lazy.compactMap { self.textView(in: $0) }.first
    }

    /// What a keystroke does: text inserted at the end.
    private func type(_ text: String, into textView: NSTextView) {
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    }

    func testAReadOnlyTextEditorKeepsItsText() throws {
        let (textView, model) = try render(["text": "Fixed", "readOnly": true])
        type("X", into: textView)
        XCTAssertEqual(textView.string, "Fixed", "the text shown stays")
        XCTAssertNotEqual(model.value as? String, "FixedX", "the value stays")
        XCTAssertTrue(textView.isSelectable, "the text can still be selected and copied")
    }

    /// Undo after an ignored keystroke must not undo it on the text shown again: on macOS 27 that
    /// raised NSRangeException (typing at the end, then Undo). The editor is made again instead.
    func testAReadOnlyTextEditorLeavesNothingToUndo() throws {
        let (textView, _) = try render(["text": "Fixed", "readOnly": true])
        window?.makeFirstResponder(textView)
        type("XYZ", into: textView)
        let shown = try XCTUnwrap(window?.contentView.flatMap { self.textView(in: $0) })
        XCTAssertEqual(shown.string, "Fixed")
        XCTAssertFalse(try XCTUnwrap(shown.undoManager).canUndo, "no ignored typing to undo")
    }

    func testAnEditableTextEditorTakesTheTyping() throws {
        let (textView, model) = try render(["text": "Draft"])
        type("X", into: textView)
        XCTAssertEqual(textView.string, "DraftX")
        XCTAssertEqual(model.value as? String, "DraftX")
    }

    func testAReadOnlyMarkdownTextEditorKeepsItsText() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("the attributed editor is macOS 26 and later") }
        let (textView, model) = try render(["markdown": "**Fixed**", "readOnly": true])
        let before = textView.string
        let valueBefore = model.value.map { "\($0)" }
        type("X", into: textView)
        // The editor is made again after an ignored edit: look for its text view again.
        let shown = try XCTUnwrap(window?.contentView.flatMap { self.textView(in: $0) })
        XCTAssertEqual(shown.string, before)
        XCTAssertEqual(model.value.map { "\($0)" }, valueBefore)
    }

    /// A selection change also sets the attributed editor's content, unchanged: it must not make the
    /// editor again, which would drop the selection.
    func testAReadOnlyMarkdownTextEditorKeepsASelection() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("the attributed editor is macOS 26 and later") }
        let (textView, _) = try render(["markdown": "**Fixed** text", "readOnly": true])
        window?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let shown = try XCTUnwrap(window?.contentView.flatMap { self.textView(in: $0) })
        XCTAssertTrue(shown === textView, "the editor is not made again")
        XCTAssertEqual(shown.selectedRange(), NSRange(location: 0, length: 5))
    }

    /// Read-only is for the user: the host still sets the text.
    func testAHostStillSetsAReadOnlyTextEditor() throws {
        let (textView, _) = try render(["text": "Fixed", "readOnly": true])
        ActionUIModel.shared.setElementValue(windowUUID: try XCTUnwrap(windowUUID), viewID: 1, value: "Changed")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(textView.string, "Changed")
    }

    func testAHostStillSetsAReadOnlyMarkdownTextEditor() throws {
        guard #available(macOS 26.0, *) else { throw XCTSkip("the attributed editor is macOS 26 and later") }
        _ = try render(["markdown": "**Fixed**", "readOnly": true])
        ActionUIModel.shared.setElementValue(windowUUID: try XCTUnwrap(windowUUID), viewID: 1, value: "*Changed*")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let shown = try XCTUnwrap(window?.contentView.flatMap { self.textView(in: $0) })
        XCTAssertEqual(shown.string, "Changed")
    }
}
#endif
