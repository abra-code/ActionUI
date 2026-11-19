// Sources/Elements/TextField+WinUI.swift
/*
 TextField on WinUI: a TextBox, as wide as it is offered (SwiftUI's TextField is greedy in width:
 defaultExpansion horizontal), as on Linux.

 - The text is the value, else the text property (Props.initialValue); an update sets it only when
   it differs, since setting the text moves the caret.
 - The placeholder is the prompt, else the title: macOS shows the title inside the field when there
   is no prompt.
 - Typing runs Core's TextField.userEditedText (the value, then valueChangeActionID); Return and
   leaving the field run TextField.userSubmitted (actionID), as on macOS and Linux. WinUI also
   reports the renderer's own text changes, a moment later: the report that matches the text an
   update set is skipped, so a late one cannot write an older text over a newer value (the program
   setting the value again before WinUI reported the first change).

 Not yet: axis vertical (several lines), number formats, textContentType, a title in a Form's label
 column. Leaving the field is WinUI's LostFocus; whether it also comes when the window is
 deactivated or a context menu opens (Linux submits only when the focus moves to another control)
 is to be measured on a desktop.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CWinUI

extension TextField: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .horizontal }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let box = WinUIObject(adopting: actionUIWinUITextBoxCreate()) else {
            throw WinUIError.last("creating a TextBox")
        }
        node.state = TextFieldState()
        WinUIEvents.connect(box, actionUIWinUITextBoxOnTextChanged, "a TextBox's text change") { [weak node, weak box] in
            guard let node, let box, node.isAttached, let text = currentText(box) else { return }
            // The report of an update's own change (WinUI reports it later, maybe merged with a
            // second one: the text is then the last set): not the user's.
            if let state = node.state as? TextFieldState, let pending = state.pendingSet {
                state.pendingSet = nil
                if text == pending {
                    return
                }
            }
            TextField.userEditedText(text, element: node.element, model: node.model, windowUUID: node.windowModel.windowUUID,
                                     props: Props(node.properties))
        }
        WinUIEvents.connect(box, actionUIWinUITextBoxOnSubmit, "a TextBox's submit") { [weak node] in
            guard let node, node.isAttached else { return }
            TextField.userSubmitted(element: node.element, windowUUID: node.windowModel.windowUUID, props: Props(node.properties))
        }
        return box
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        node.applyTextAppearance(to: view, what: "a TextField")
        let props = Props(node.properties)
        let text = node.model.value as? String ?? props.initialValue
        let placeholder = props.prompt ?? props.title
        let state = node.state as? TextFieldState
        // Set only when it differs (the shim compares too): setting it moves the caret, and WinUI
        // reports the change, which the handler then knows to skip.
        var ok = true
        if currentText(view) != text {
            ok = actionUIWinUITextBoxSetText(view.pointer, text)
            if ok {
                state?.pendingSet = text
            }
        }
        let placed = state?.placeholder == placeholder || actionUIWinUITextBoxSetPlaceholder(view.pointer, placeholder)
        if placed {
            state?.placeholder = placeholder
        }
        if !(ok && placed) {
            ActionUIModel.shared.logger.log("TextField: \(WinUIError.last("showing a TextField"))", .error)
        }
    }

    /// The box's text now; nil when the shim could not read it.
    static func currentText(_ box: WinUIObject) -> String? {
        guard let copy = actionUIWinUITextBoxCopyText(box.pointer) else { return nil }
        defer { actionUIWinUIFreeString(copy) }
        return String(cString: copy)
    }
}

/// What a TextField node keeps: the placeholder shown (nil before the first update) and the text an
/// update set whose change WinUI has not reported yet.
@MainActor final class TextFieldState {
    var placeholder: String?
    var pendingSet: String?
}
