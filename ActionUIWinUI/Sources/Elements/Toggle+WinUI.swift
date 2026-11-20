// Sources/Elements/Toggle+WinUI.swift
/*
 Toggle on WinUI: a CheckBox with the title beside it, as macOS shows a Toggle by default; style
 "switch" is a ToggleSwitch with the title beside the switch. On is the value, else the isOn
 property, else off (Toggle.initialValue), as on Apple and Linux.

 - The user's change runs Core's Toggle.userSetValue (the value, then actionID with the new state),
   as on Linux. A CheckBox reports only the user's clicks; a ToggleSwitch also reports the
   renderer's own changes, which userSetValue ignores (the value already holds them).
 - In a template row (a List's), the row holds the state, as on Apple and Linux: the user's change
   is written into the row's column that isOn names ("$1") and actionID fires with the row's index
   (Core TemplateHelper); the container then shows the row again. Without a single column the
   Toggle only shows the row, and turns back.
 - In a Form (a row of it or of its Sections), a switch's title stands before it in the Form's label
   column (FormColumn), as macOS and Linux lay it out, rather than after it as WinUI's ToggleSwitch
   shows it elsewhere (owner's decision); labelsHidden hides it there. A checkbox's title stays beside
   its box, in the content column (measured on macOS).
 - The style is read when the element is made (a later change of style keeps the first control), and
   so is being in a Form.

 Not yet: style "button"; the title hidden by labelsHidden outside a Form; an accessible name for a
 switch in a Form (its text is the label column's); controlSize.
*/

import CWinUI

extension Toggle: ActionUIWinUIRenderer {
    /// The control each style is shown with.
    enum Kind {
        case checkBox, toggleSwitch
    }

    /// The kind for the element's style; read without tracking, at creation.
    static func kind(_ node: RenderNode) -> Kind {
        let style = UntrackedReads.perform { Props(node.properties).style }
        return style == .switch ? .toggleSwitch : .checkBox
    }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        let kind = kind(node)
        node.state = ToggleState(kind: kind)
        switch kind {
        case .checkBox:
            guard let box = WinUIObject(adopting: actionUIWinUICheckBoxCreate()) else {
                throw WinUIError.last("creating a CheckBox")
            }
            WinUIEvents.connect(box, actionUIWinUICheckBoxOnClick, "a CheckBox's click") { [weak node, weak box] in
                guard let node, let box, node.isAttached else { return }
                userToggled(node, on: actionUIWinUICheckBoxIsChecked(box.pointer))
            }
            return box
        case .toggleSwitch:
            guard let toggle = WinUIObject(adopting: actionUIWinUIToggleSwitchCreate()) else {
                throw WinUIError.last("creating a ToggleSwitch")
            }
            WinUIEvents.connect(toggle, actionUIWinUIToggleSwitchOnToggled, "a ToggleSwitch's toggle") { [weak node, weak toggle] in
                guard let node, let toggle, node.isAttached else { return }
                userToggled(node, on: actionUIWinUIToggleSwitchIsOn(toggle.pointer))
            }
            guard FormColumn.isRow(node) else { return toggle }
            // In a Form: the title in the label column, the switch without one.
            guard actionUIWinUIToggleSwitchSetTitle(toggle.pointer, nil) else {
                throw WinUIError.last("taking a ToggleSwitch's title away")
            }
            let layout = try TitledControlLayout(control: toggle)
            (node.state as? ToggleState)?.layout = layout
            return layout.panel.object
        }
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? ToggleState else { return }
        let props = Props(node.properties)
        if let layout = state.layout {
            updateInForm(layout, node, props)
            return
        }
        node.applyTextAppearance(to: view, what: "a Toggle")
        let on = Toggle.initialValue(node.model) as? Bool ?? false
        // Both are set even when the other fails: a title the shim refused must not hide the state.
        let titled: Bool
        let shown: Bool
        switch state.kind {
        case .checkBox:
            titled = state.title == props.title || actionUIWinUICheckBoxSetTitle(view.pointer, props.title)
            shown = actionUIWinUICheckBoxSetChecked(view.pointer, on)
        case .toggleSwitch:
            titled = state.title == props.title || actionUIWinUIToggleSwitchSetTitle(view.pointer, props.title)
            shown = actionUIWinUIToggleSwitchSetOn(view.pointer, on)
        }
        if titled {
            state.title = props.title
        }
        if !(titled && shown) {
            ActionUIModel.shared.logger.log("Toggle: \(WinUIError.last("showing a Toggle"))", .error)
        }
    }

    /// A switch in a Form: its title in the label column, the switch enabled here (the view is the
    /// layout's panel, no Control), its title keeping its color when disabled, as a Picker's.
    private static func updateInForm(_ layout: TitledControlLayout, _ node: RenderNode, _ props: Props) {
        layout.setTitle(props.title)
        layout.titleHidden = node.isLabelsHidden
        node.applyTextAppearance(to: layout.title, what: "a Toggle's title")
        node.applyAccessibilityHidden(to: layout.title)
        node.applyAccessibilityHidden(to: layout.control)
        let enabled = !(node.isDisabled || node.isHidden)
        let on = Toggle.initialValue(node.model) as? Bool ?? false
        if !(actionUIWinUIElementSetEnabled(layout.control.pointer, enabled) && actionUIWinUIToggleSwitchSetOn(layout.control.pointer, on)) {
            ActionUIModel.shared.logger.log("Toggle: \(WinUIError.last("showing a Toggle in a Form"))", .error)
        }
    }

    private static func userToggled(_ node: RenderNode, on: Bool) {
        let props = Props(node.properties)
        let windowUUID = node.windowModel.windowUUID
        guard let context = node.model.templateContext else {
            Toggle.userSetValue(on, element: node.element, model: node.model, windowUUID: windowUUID, props: props)
            return
        }
        // A ToggleSwitch also reports the renderer's own change (a new row's control set to the row's
        // state, or one turned back): the state the row already shows, not the user's toggle.
        guard on != (Toggle.initialValue(node.model) as? Bool ?? false) else { return }
        let column = TemplateHelper.singleColumnIndex(node.element.properties["isOn"])
        if column == nil {
            TemplateHelper.warnOnce("Toggle isOn in a template must be a single column reference such as \"$1\" to keep its state; this Toggle is display-only", logger: ActionUIModel.shared.logger)
        }
        let taken = TemplateHelper.commitRowToggle(on, context: context, column: column, actionID: props.actionID,
                                                   windowUUID: windowUUID)
        if !taken {
            // The control shows the row's state again.
            SyncScheduler.shared.markDirty(node)
        }
    }
}

/// What a Toggle node keeps: its control's kind and the title it shows (nil before the first update).
@MainActor final class ToggleState {
    let kind: Toggle.Kind
    var title: String?
    /// A switch in a Form: its title before it, in the Form's label column.
    var layout: TitledControlLayout?

    init(kind: Toggle.Kind) {
        self.kind = kind
    }
}
