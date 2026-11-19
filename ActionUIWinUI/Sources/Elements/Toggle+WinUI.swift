// Sources/Elements/Toggle+WinUI.swift
/*
 Toggle on WinUI: a CheckBox with the title beside it, as macOS shows a Toggle by default; style
 "switch" is a ToggleSwitch with the title beside the switch. On is the value, else the isOn
 property, else off (Toggle.initialValue), as on Apple and Linux.

 - The user's change runs Core's Toggle.userSetValue (the value, then actionID with the new state),
   as on Linux. A CheckBox reports only the user's clicks; a ToggleSwitch also reports the
   renderer's own changes, which userSetValue ignores (the value already holds them).
 - The style is read when the element is made (a later change of style keeps the first control).

 Not yet: style "button", the title hidden by labelsHidden, controlSize, a Toggle in a template
 row (Linux writes the row's column).
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
            return toggle
        }
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? ToggleState else { return }
        node.applyTextAppearance(to: view, what: "a Toggle")
        let props = Props(node.properties)
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

    private static func userToggled(_ node: RenderNode, on: Bool) {
        Toggle.userSetValue(on, element: node.element, model: node.model, windowUUID: node.windowModel.windowUUID,
                            props: Props(node.properties))
    }
}

/// What a Toggle node keeps: its control's kind and the title it shows (nil before the first update).
@MainActor final class ToggleState {
    let kind: Toggle.Kind
    var title: String?

    init(kind: Toggle.Kind) {
        self.kind = kind
    }
}
