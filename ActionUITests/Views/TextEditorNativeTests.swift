// Views/TextEditorNativeTests.swift
/*
 The native TextEditor on macOS ("implementation": "native"): an NSTextView that shows the value,
 appends text that extends it to its storage instead of replacing the text, replaces any other
 value, takes typing into the value (firing valueChangeActionID), keeps read-only and disabled
 text out of reach of typing, takes its font and color from the element's properties, and keeps no
 undo across a change the host makes. Without the property, or with markdown, the SwiftUI editor
 draws the element.
*/

#if os(macOS)
import XCTest
import SwiftUI
import AppKit
@testable import ActionUI

@MainActor
final class TextEditorNativeTests: XCTestCase {
    private var logger: XCTestLogger!
    private var window: NSWindow?
    private var windowUUID = ""

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
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        try await super.tearDown()
    }

    /// The TextEditor shown in a window, its text view, and its view model.
    private func render(_ properties: [String: Any], native: Bool = true) throws -> (NSTextView, ViewModel) {
        var properties = properties
        if native {
            properties["implementation"] = "native"
        }
        let document: [String: Any] = ["type": "TextEditor", "id": 1, "properties": properties]
        windowUUID = UUID().uuidString
        let element = try ActionUIModel.shared.loadDescription(from: document, windowUUID: windowUUID)
        let viewModel = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id])
        let host = NSHostingView(rootView: ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
            .frame(width: 300, height: 120))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 160), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        self.window = window
        settle()
        return (try XCTUnwrap(textView(in: host), "no text view"), viewModel)
    }

    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    }

    private func textView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView { return textView }
        return view.subviews.lazy.compactMap { self.textView(in: $0) }.first
    }

    /// What a keystroke does: text inserted at the end.
    private func type(_ text: String, into textView: NSTextView) {
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        settle()
    }

    /// Records the text storage's edits, in the storage's characters.
    private final class EditRecorder: NSObject, NSTextStorageDelegate {
        var ranges: [NSRange] = []

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            if editedMask.contains(.editedCharacters) {
                ranges.append(editedRange)
            }
        }
    }

    /// The ranges of the text storage's character edits while `body` runs.
    private func editedRanges(of textView: NSTextView, during body: () -> Void) throws -> [NSRange] {
        let storage = try XCTUnwrap(textView.textStorage)
        let recorder = EditRecorder()
        let previous = storage.delegate
        storage.delegate = recorder
        defer { storage.delegate = previous }
        body()
        return recorder.ranges
    }

    // MARK: - Which editor

    /// The native editor is the scroll view's own text view; SwiftUI's TextEditor uses a subclass.
    func testTheImplementationPropertyChoosesTheEditor() throws {
        let (native, _) = try render(["text": "A"])
        XCTAssertTrue(Swift.type(of: native) == NSTextView.self, "native: a plain NSTextView, got \(Swift.type(of: native))")
        window?.orderOut(nil)
        let (swiftUI, _) = try render(["text": "A"], native: false)
        XCTAssertFalse(Swift.type(of: swiftUI) == NSTextView.self, "default: SwiftUI's own text view")
    }

    func testMarkdownTakesTheDefaultEditor() throws {
        let (textView, _) = try render(["markdown": "**A**"])
        XCTAssertFalse(Swift.type(of: textView) == NSTextView.self)
    }

    // MARK: - The text

    func testItShowsTheInitialText() throws {
        let (textView, model) = try render(["text": "Hello"])
        XCTAssertEqual(textView.string, "Hello")
        XCTAssertEqual(model.value as? String, "Hello")
    }

    func testAppendingAppendsOnlyTheNewText() throws {
        let (textView, model) = try render(["text": "Hello", "readOnly": true])
        let ranges = try editedRanges(of: textView) {
            XCTAssertTrue(ActionUIModel.shared.appendElementText(windowUUID: windowUUID, viewID: 1, text: ", world"))
            settle()
        }
        XCTAssertEqual(textView.string, "Hello, world")
        XCTAssertEqual(model.value as? String, "Hello, world")
        XCTAssertEqual(ranges, [NSRange(location: 5, length: 7)], "one edit, at the end, of the new text")
    }

    /// A whole value that starts with the text shown is an append as well.
    func testAValueThatExtendsTheTextIsAppended() throws {
        let (textView, _) = try render(["text": "ab"])
        let ranges = try editedRanges(of: textView) {
            ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "abcd")
            settle()
        }
        XCTAssertEqual(textView.string, "abcd")
        XCTAssertEqual(ranges, [NSRange(location: 2, length: 2)])
    }

    func testAnyOtherValueReplacesTheText() throws {
        let (textView, _) = try render(["text": "abcd"])
        let ranges = try editedRanges(of: textView) {
            ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "xy")
            settle()
        }
        XCTAssertEqual(textView.string, "xy")
        XCTAssertEqual(ranges.last, NSRange(location: 0, length: 2))
    }

    /// The piece starts at a Unicode scalar boundary that is not a character boundary: a combining
    /// accent after "e" must be appended as itself, with nothing of the "e" again.
    func testAppendingACombiningMarkAppendsOnlyTheMark() throws {
        let (textView, model) = try render(["text": "caf" + "e"])
        ActionUIModel.shared.appendElementText(windowUUID: windowUUID, viewID: 1, text: "\u{0301}!")
        settle()
        XCTAssertEqual(textView.string.unicodeScalars.count, 6)
        XCTAssertEqual(textView.string, "caf" + "e\u{0301}!")
        XCTAssertEqual(model.value as? String, "caf" + "e\u{0301}!")
    }

    func testAppendedTextHasTheEditorsFontAndColor() throws {
        let (textView, _) = try render(["text": "", "font": ["name": "Monaco", "size": 10], "foregroundStyle": "#FF0000"])
        ActionUIModel.shared.appendElementText(windowUUID: windowUUID, viewID: 1, text: "out")
        settle()
        let storage = try XCTUnwrap(textView.textStorage)
        let font = try XCTUnwrap(storage.attribute(.font, at: 1, effectiveRange: nil) as? NSFont)
        XCTAssertEqual(font.fontName, "Monaco")
        XCTAssertEqual(font.pointSize, 10)
        let color = try XCTUnwrap((storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB))
        XCTAssertEqual(color.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(color.greenComponent, 0, accuracy: 0.01)
    }

    func testAMissingNamedFontFallsBackToItsDesign() throws {
        let (textView, _) = try render(["text": "x", "font": ["name": "NoSuchFont-ActionUI", "size": 11, "design": "monospaced"]])
        let font = try XCTUnwrap(textView.font)
        XCTAssertEqual(font.pointSize, 11)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.monoSpace), "monospaced: \(font.fontName)")
    }

    func testWithoutAFontTheTextIsTheBodyFont() throws {
        let (textView, _) = try render(["text": "x"])
        XCTAssertEqual(textView.font?.pointSize, NSFont.preferredFont(forTextStyle: .body).pointSize)
    }

    func testAHiddenScrollContentBackgroundDrawsNoBackground() throws {
        let (shown, _) = try render(["text": "x"])
        XCTAssertTrue(shown.drawsBackground)
        window?.orderOut(nil)
        let (hidden, _) = try render(["text": "x", "scrollContentBackground": "hidden"])
        XCTAssertFalse(hidden.drawsBackground)
        XCTAssertFalse(try XCTUnwrap(hidden.enclosingScrollView).drawsBackground)
    }

    // MARK: - The user

    func testTypingSetsTheValueAndFiresTheValueChangeAction() throws {
        var fired: [Int] = []
        ActionUIModel.shared.registerActionHandler(for: "edited") { _, _, viewID, _, _ in fired.append(viewID) }
        let (textView, model) = try render(["text": "Draft", "valueChangeActionID": "edited"])
        type("X", into: textView)
        XCTAssertEqual(model.value as? String, "DraftX")
        XCTAssertEqual(textView.string, "DraftX")
        XCTAssertEqual(fired, [1])
    }

    /// A host append after typing goes to the end of what was typed.
    func testAnAppendAfterTypingFollowsTheTypedText() throws {
        let (textView, model) = try render(["text": "a"])
        type("b", into: textView)
        ActionUIModel.shared.appendElementText(windowUUID: windowUUID, viewID: 1, text: "c")
        settle()
        XCTAssertEqual(textView.string, "abc")
        XCTAssertEqual(model.value as? String, "abc")
    }

    func testReadOnlyTextIsSelectableButNotEditable() throws {
        let (textView, model) = try render(["text": "Fixed", "readOnly": true])
        XCTAssertFalse(textView.isEditable)
        XCTAssertTrue(textView.isSelectable)
        type("X", into: textView)
        XCTAssertEqual(textView.string, "Fixed")
        XCTAssertEqual(model.value as? String, "Fixed")
    }

    func testDisabledTextIsNeitherSelectableNorEditable() throws {
        let (textView, _) = try render(["text": "Off", "disabled": true])
        XCTAssertFalse(textView.isEditable)
        XCTAssertFalse(textView.isSelectable)
    }

    /// Undo after the host changed the text would apply the typing's undo to text it no longer
    /// matches: the host's change clears the editor's undo, and only the editor's.
    func testAHostChangeLeavesNothingToUndo() throws {
        let (textView, _) = try render(["text": "a"])
        window?.makeFirstResponder(textView)
        type("b", into: textView)
        XCTAssertTrue(try XCTUnwrap(textView.undoManager).canUndo, "typing can be undone")
        XCTAssertFalse(textView.undoManager === window?.undoManager, "the editor has its own undo")
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "new")
        settle()
        XCTAssertFalse(try XCTUnwrap(textView.undoManager).canUndo)
    }

    /// Undo and Redo change the text without textDidChange; the value follows them anyway.
    func testUndoAndRedoSetTheValue() throws {
        var fired = 0
        ActionUIModel.shared.registerActionHandler(for: "edited") { _, _, _, _, _ in fired += 1 }
        let (textView, model) = try render(["text": "a", "valueChangeActionID": "edited"])
        window?.makeFirstResponder(textView)
        type("b", into: textView)
        let undoManager = try XCTUnwrap(textView.undoManager)
        undoManager.undo()
        settle()
        XCTAssertEqual(textView.string, "a")
        XCTAssertEqual(model.value as? String, "a")
        undoManager.redo()
        settle()
        XCTAssertEqual(textView.string, "ab")
        XCTAssertEqual(model.value as? String, "ab")
        XCTAssertEqual(fired, 3, "typing, Undo and Redo")
    }

    /// Typing after a host append is undone alone, and the value follows.
    func testUndoAfterAnAppendUndoesOnlyTheLaterTyping() throws {
        let (textView, model) = try render(["text": "a"])
        window?.makeFirstResponder(textView)
        type("b", into: textView)
        ActionUIModel.shared.appendElementText(windowUUID: windowUUID, viewID: 1, text: "XYZ")
        settle()
        type("d", into: textView)
        try XCTUnwrap(textView.undoManager).undo()
        settle()
        XCTAssertEqual(textView.string, "abXYZ")
        XCTAssertEqual(model.value as? String, "abXYZ")
    }
}
#endif
