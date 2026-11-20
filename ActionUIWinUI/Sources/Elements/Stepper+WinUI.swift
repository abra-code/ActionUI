// Sources/Elements/Stepper+WinUI.swift
/*
 Stepper on WinUI: its label, 8, then minus and plus (the SF Symbols' Windows outlines) joined into one
 control, [-|+], as a ControlGroup joins its buttons (actionUIWinUIControlSetJoined: rounded only at the
 outer ends, one border between them), as macOS shows a stepper's label before its two arrows in one
 control and the Linux renderer its linked buttons. The buttons have less padding than WinUI's (5, 2, 5, 3, not
 11, 5, 11, 6), about 28 x 24 each, the size of the spin buttons on WinUI's own NumberBox: macOS's
 stepper is one narrow control, and a pair of full-size buttons looked twice as heavy (the Linux
 renderer makes its buttons smaller for the same reason).
 WinUI's NumberBox is not used: it shows the value in an editable field, which SwiftUI's Stepper has
 not, and labelFormat usually shows the value already. As large as it is (measured on macOS 27: it does
 not grow; an empty label keeps its gap).

 - The label is Core's Stepper.labelText: labelFormat with the value in it (NumberPrintf; a format it
   refuses shows the plain value), else the label property, as on Apple and Linux. labelsHidden hides it.
 - A button steps the value by step, kept in the range when there is one, and runs Core's
   Stepper.userSetValue (the value, then actionID with it as context). A button is disabled at its end
   of the range, as SwiftUI disables an arrow there. The label keeps its color when the Stepper is
   disabled, as a Picker's title.

 Not yet: accessible names (the group after its label, the buttons Decrement and Increment, as VoiceOver
 names them); controlSize.
*/

import CWinUI

/// What a Stepper node keeps: its layout, its buttons and their symbols' size.
@MainActor final class StepperState {
    let layout: TitledControlLayout
    let row: ControlRow
    let minus: WinUIObject
    let plus: WinUIObject
    var symbols: [WinUIObject] = []
    var symbolSide = -1.0
    var appliedAppearance: TextAppearance?

    init(layout: TitledControlLayout, row: ControlRow, minus: WinUIObject, plus: WinUIObject) {
        self.layout = layout
        self.row = row
        self.minus = minus
        self.plus = plus
    }
}

extension Stepper: ActionUIWinUIRenderer {
    /// The gap between the two buttons (none: they are joined), and their padding (WinUI's Button has
    /// 11, 5, 11, 6).
    static let buttonSpacing = 0.0
    static let buttonPadding = (leading: 5.0, top: 2.0, trailing: 5.0, bottom: 3.0)

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        var buttons: [WinUIObject] = []
        var symbols: [WinUIObject] = []
        for (name, direction) in [("minus", -1.0), ("plus", 1.0)] {
            guard let button = WinUIObject(adopting: actionUIWinUIButtonCreate()) else {
                throw WinUIError.last("creating a Stepper's button")
            }
            let padding = buttonPadding
            if !actionUIWinUIControlSetPadding(button.pointer, padding.leading, padding.top, padding.trailing, padding.bottom) {
                ActionUIModel.shared.logger.log("Stepper: \(WinUIError.last("setting a button's padding"))", .error)
            }
            // Joined: minus rounded at its leading end, plus at its trailing end, one border between them.
            if !actionUIWinUIControlSetJoined(button.pointer, direction < 0, direction > 0) {
                ActionUIModel.shared.logger.log("Stepper: \(WinUIError.last("joining the buttons"))", .error)
            }
            // The symbol, else (no outline for it, or the shim refused it) "-" or "+".
            var showsSymbol = false
            if let symbol = ImageLayout.makeSymbol(name) {
                if actionUIWinUIButtonSetContent(button.pointer, symbol.pointer) {
                    symbols.append(symbol)
                    showsSymbol = true
                } else {
                    ActionUIModel.shared.logger.log("Stepper: \(WinUIError.last("showing the \(name) symbol"))", .error)
                }
            }
            if !showsSymbol && !actionUIWinUIButtonSetTitle(button.pointer, direction < 0 ? "-" : "+") {
                ActionUIModel.shared.logger.log("Stepper: \(WinUIError.last("titling a button"))", .error)
            }
            WinUIEvents.connect(button, actionUIWinUIButtonOnClick, "a Stepper's button") { [weak node] in
                guard let node, node.isAttached else { return }
                let props = Props(node.properties)
                let value = Stepper.initialValue(node.model) as? Double ?? props.initialValue
                Stepper.userSetValue(stepped(value, by: direction, props), element: node.element, model: node.model,
                                     windowUUID: node.windowModel.windowUUID, props: props)
            }
            buttons.append(button)
        }
        let row = try ControlRow(buttons[0], buttons[1], spacing: buttonSpacing)
        let layout = try TitledControlLayout(control: row.panel.object)
        let state = StepperState(layout: layout, row: row, minus: buttons[0], plus: buttons[1])
        state.symbols = symbols
        node.state = state
        return layout.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? StepperState else { return }
        let props = Props(node.properties)
        let value = Stepper.initialValue(node.model) as? Double ?? props.initialValue
        state.layout.setTitle(labelText(props, value: value))
        state.layout.titleHidden = node.isLabelsHidden
        if state.appliedAppearance != node.textAppearance {
            state.appliedAppearance = node.textAppearance
            node.textAppearance.apply(to: state.layout.title, what: "a Stepper's label")
            for button in [state.minus, state.plus] {
                node.textAppearance.apply(to: button, what: "a Stepper's button")
            }
        }
        let side = ImageLayout.symbolSide(node, scale: nil)
        if side != state.symbolSide {
            state.symbolSide = side
            for symbol in state.symbols where !actionUIWinUISymbolSetSize(symbol.pointer, side) {
                ActionUIModel.shared.logger.log("Stepper: \(WinUIError.last("sizing a symbol"))", .error)
            }
            state.layout.panel.invalidateLayout()
        }
        node.applyAccessibilityHidden(to: state.layout.title)
        // The view is the layout's panel (no Control): the buttons are enabled here, each off at its end of
        // the range.
        let enabled = !(node.isDisabled || node.isHidden)
        for (button, direction) in [(state.minus, -1.0), (state.plus, 1.0)] {
            node.applyAccessibilityHidden(to: button)
            let atEnd = props.range.map { direction < 0 ? value <= $0.lowerBound : value >= $0.upperBound } ?? false
            if !actionUIWinUIElementSetEnabled(button.pointer, enabled && !atEnd) {
                ActionUIModel.shared.logger.log("Stepper: \(WinUIError.last("enabling a button"))", .error)
            }
        }
    }

    /// One step from `value` in `direction` (-1 or 1), kept in the range when there is one, as on Linux.
    static func stepped(_ value: Double, by direction: Double, _ props: Props) -> Double {
        let next = value + direction * props.step
        guard let range = props.range else { return next }
        return Swift.min(Swift.max(next, range.lowerBound), range.upperBound)
    }
}
