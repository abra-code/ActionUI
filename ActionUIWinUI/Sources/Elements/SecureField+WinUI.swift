// Sources/Elements/SecureField+WinUI.swift
/*
 SecureField on WinUI: a PasswordBox, which shows dots and tells input methods and accessibility tools
 the text is a password, without a button that shows the text, as macOS's SecureField has none. It
 behaves as TextField does, as on Linux:
 - as wide as it is offered (SwiftUI's SecureField is greedy in width, as TextField is);
 - the text is the value, else the text property (SecureField.initialValue), set only when it differs,
   since setting it moves the caret; WinUI also reports the renderer's own change, a moment later, and
   the report matching the text an update set is skipped, as TextField's is;
 - the placeholder is the prompt, else the title;
 - typing runs Core's TextField.userEditedText (the value, then valueChangeActionID); Return and leaving
   the field run TextField.userSubmitted (actionID), as on macOS and Linux.

 Not yet: textContentType (ignored on macOS too); a title in a Form's label column; an accessible name
 from the title.
*/

import CWinUI

extension SecureField: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .horizontal }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let box = WinUIObject(adopting: actionUIWinUIPasswordBoxCreate()) else {
            throw WinUIError.last("creating a PasswordBox")
        }
        node.state = TextFieldState()
        WinUIEvents.connect(box, actionUIWinUITextBoxOnTextChanged, "a PasswordBox's change") { [weak node, weak box] in
            guard let node, let box, node.isAttached, let text = TextField.currentText(box) else { return }
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
        WinUIEvents.connect(box, actionUIWinUITextBoxOnSubmit, "a PasswordBox's submit") { [weak node] in
            guard let node, node.isAttached else { return }
            TextField.userSubmitted(actionID: Props(node.properties).actionID, viewID: node.element.id,
                                    windowUUID: node.windowModel.windowUUID)
        }
        return box
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        node.applyTextAppearance(to: view, what: "a SecureField")
        let props = Props(node.properties)
        let text = SecureField.initialValue(node.model) as? String ?? props.text
        let placeholder = props.prompt ?? props.title
        let state = node.state as? TextFieldState
        var ok = true
        if TextField.currentText(view) != text {
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
            ActionUIModel.shared.logger.log("SecureField: \(WinUIError.last("showing a SecureField"))", .error)
        }
    }
}
