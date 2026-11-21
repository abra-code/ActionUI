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

 - In a Form (a row of it or of its Sections), the title stands before the field in the Form's label
   column (FormColumn) and the field fills the rest of the row, as macOS and Linux lay it out; the
   placeholder is then the prompt alone. An empty title makes a column of 0 (the field starts 8 in), as
   on Linux (measured on macOS); a title labelsHidden hides makes it a row without a title. Being in a
   Form is read when the element is made.

 Not yet: axis vertical (several lines), number formats, textContentType; Preview's UI Automation
 operations reach a field in a Form only through its layout (none does yet). Leaving the field is
 WinUI's LostFocus; whether it also comes when the window is deactivated or a context menu opens
 (Linux submits only when the focus moves to another control) is to be measured on a desktop.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CWinUI

extension TextField: ActionUIWinUIRenderer {
    /// The title, as SwiftUI names the control after it (the control has no title of its own: in a
    /// Form it is the separate text in the label column).
    static func defaultAccessibleName(_ node: RenderNode) -> String? {
        Props(node.properties).title
    }

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
        return try inFormLayout(node, box)
    }

    /// The field in a Form: its title before it, in the label column (TextFieldState.layout); else the
    /// field itself.
    static func inFormLayout(_ node: RenderNode, _ box: WinUIObject) throws(WinUIError) -> WinUIObject {
        guard FormColumn.isRow(node) else { return box }
        let layout = try TitledControlLayout(control: box)
        layout.controlFills = true
        (node.state as? TextFieldState)?.layout = layout
        return layout.panel.object
    }

    /// The title of a field in a Form (`layout`): shown in the label column (an empty one 0 wide), none
    /// when labelsHidden hides it.
    static func showFormTitle(_ layout: TitledControlLayout, _ title: String, _ node: RenderNode) {
        layout.setTitle(title)
        layout.titleHidden = node.isLabelsHidden
        node.textAppearance.apply(to: layout.title, what: "a field's title")
        node.applyAccessibilityHidden(to: layout.title)
        // RenderNode applies both to the view, which is the layout's panel (no Control, no
        // automation peer): the field gets them here.
        node.applyAccessibilityHidden(to: layout.control)
        if !actionUIWinUIElementSetEnabled(layout.control.pointer, !(node.isDisabled || node.isHidden)) {
            ActionUIModel.shared.logger.log("TextField: \(WinUIError.last("enabling a field"))", .error)
        }
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        let props = Props(node.properties)
        let state = node.state as? TextFieldState
        // In a Form the view is the layout; the field is its control.
        let view = state?.layout?.control ?? view
        node.applyTextAppearance(to: view, what: "a TextField")
        let text = node.model.value as? String ?? props.initialValue
        var placeholder = props.prompt ?? props.title
        if let layout = state?.layout {
            showFormTitle(layout, props.title, node)
            placeholder = props.prompt ?? ""
        }
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
@MainActor final class TextFieldState: TitledControlHolder {
    var placeholder: String?
    var pendingSet: String?
    /// A TextField or SecureField in a Form: its title before it, in the Form's label column.
    var layout: TitledControlLayout?
    var titledControl: WinUIObject? { layout?.control }
}
