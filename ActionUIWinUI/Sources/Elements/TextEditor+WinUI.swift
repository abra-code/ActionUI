// Sources/Elements/TextEditor+WinUI.swift
/*
 TextEditor on WinUI: a TextBox of several lines (Return starts a line, lines wrap at words, a
 vertical scroll bar when the text is taller than the box), as large as it is offered in both axes
 (as SwiftUI's TextEditor is, measured on macOS 27, and on Linux).

 - The text is the value, else the text property, else the markdown property (TextEditor.initialValue;
   an AttributedString value shows its characters); an update sets it only when it differs, since
   setting it moves the caret.
 - Typing runs Core's TextField.userEditedText (the value, then valueChangeActionID), as every text
   entry does. WinUI also reports the renderer's own text changes, a moment later: the report that
   matches the text an update set is skipped, as TextField's is.
 - A TextBox keeps each line break as "\r" (one set as "\n" or "\r\n" too); its text is read with
   "\n" for each, as the value has on macOS and Linux, and compared so for an update.
 - readOnly makes the text not editable; it can still be selected, scrolled and copied.
 - The placeholder is WinUI's placeholder text, shown while the text is empty.
 - implementation "native" changes nothing: the TextBox is Windows' own editor.

 Not yet: the markdown property's styles (the markdown shows as plain text, and typing makes the value
 a String); appending text (appendElementText) sets the whole text again; an accessible name from the
 placeholder; a title line for a Form's label column.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CWinUI

extension TextEditor: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .both }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let box = WinUIObject(adopting: actionUIWinUITextBoxCreate()) else {
            throw WinUIError.last("creating a TextBox")
        }
        guard actionUIWinUITextBoxSetMultiline(box.pointer) else {
            throw WinUIError.last("making a TextBox of several lines")
        }
        node.state = TextFieldState()
        WinUIEvents.connect(box, actionUIWinUITextBoxOnTextChanged, "a TextEditor's text change") { [weak node, weak box] in
            guard let node, let box, node.isAttached, let text = editorText(box) else { return }
            // The report of an update's own change, not the user's (see TextField).
            if let state = node.state as? TextFieldState, let pending = state.pendingSet {
                state.pendingSet = nil
                if text == pending {
                    return
                }
            }
            TextField.userEditedText(text, valueChangeActionID: Props(node.properties).valueChangeActionID, viewID: node.element.id,
                                     model: node.model, windowUUID: node.windowModel.windowUUID)
        }
        return box
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        node.applyTextAppearance(to: view, what: "a TextEditor")
        let props = Props(node.properties)
        let text = TextEditor.initialValue(node.model) as? String ?? ""
        let placeholder = props.placeholder ?? ""
        let state = node.state as? TextFieldState
        var ok = true
        let wanted = lineFeeds(text)
        if editorText(view) != wanted {
            ok = actionUIWinUITextBoxSetText(view.pointer, text)
            if ok {
                state?.pendingSet = wanted
            }
        }
        let placed = state?.placeholder == placeholder || actionUIWinUITextBoxSetPlaceholder(view.pointer, placeholder)
        if placed {
            state?.placeholder = placeholder
        }
        let readOnly = actionUIWinUITextBoxSetReadOnly(view.pointer, props.readOnly)
        if !(ok && placed && readOnly) {
            ActionUIModel.shared.logger.log("TextEditor: \(WinUIError.last("showing a TextEditor"))", .error)
        }
    }

    /// The box's text with "\n" for each line break; nil when the shim could not read it.
    static func editorText(_ box: WinUIObject) -> String? {
        TextField.currentText(box).map(lineFeeds)
    }

    /// `text` with "\n" for each "\r\n" and each lone "\r".
    static func lineFeeds(_ text: String) -> String {
        guard text.unicodeScalars.contains("\r") else { return text }
        var scalars = String.UnicodeScalarView()
        var afterReturn = false
        for scalar in text.unicodeScalars {
            if scalar == "\n" && afterReturn {
                afterReturn = false
                continue
            }
            afterReturn = scalar == "\r"
            scalars.append(afterReturn ? "\n" : scalar)
        }
        return String(scalars)
    }
}
