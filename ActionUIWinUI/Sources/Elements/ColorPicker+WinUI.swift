// Sources/Elements/ColorPicker+WinUI.swift
/*
 ColorPicker on WinUI: its title, 8, then a button showing a swatch of the color, which opens a flyout
 with WinUI's own ColorPicker (a spectrum, sliders and an opacity slider), as macOS shows a color well
 after the title that opens the color panel and the Linux renderer a color button that opens GTK's
 chooser. As large as it is (measured on macOS 27: it does not grow in either axis).

 - The color is the value, else the selectedColor property, else clear (Core's ColorPicker.initialValue).
   The picker offers opacity, as SwiftUI's ColorPicker does by default.
 - Picking a color runs Core's ColorPicker.userPicked (the value as sRGB components, then actionID); an
   update fires nothing (WinUI reports the renderer's own change as it reports the user's: the color
   the renderer last set is ignored). The picker reports every step of a drag, as GTK's chooser reports
   only the chosen color; each step is a pick.
 - labelsHidden hides the title; it still names the button for accessibility tools, which read the
   button and not the title beside it. In a Form the title is in the label column (FormLabeledLayout).
 - The swatch shows a translucent color over the button's background (no checkerboard).
*/

import CWinUI

/// What a ColorPicker node keeps: its layout and the color it last showed.
@MainActor final class ColorPickerState {
    let layout: TitledControlLayout
    /// The color the renderer last set, in the picker's steps of 1/255: a change event reporting it is
    /// the renderer's own.
    var shownColor: [Int]?
    var accessibleName: String?
    var appliedAppearance: TextAppearance?

    init(layout: TitledControlLayout) {
        self.layout = layout
    }
}

extension ColorPicker: ActionUIWinUIRenderer {
    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let button = WinUIObject(adopting: actionUIWinUIColorButtonCreate()) else {
            throw WinUIError.last("creating a ColorPicker's button")
        }
        let layout = try TitledControlLayout(control: button)
        let state = ColorPickerState(layout: layout)
        node.state = state
        WinUIEvents.connect(button, actionUIWinUIColorButtonOnColorChanged, "a ColorPicker's color") { [weak node, weak state, weak button] in
            guard let node, let state, let button, node.isAttached else { return }
            var color = ActionUIWinUIColor(red: 0, green: 0, blue: 0, alpha: 0)
            guard actionUIWinUIColorButtonGetColor(button.pointer, &color) else {
                ActionUIModel.shared.logger.log("ColorPicker: \(WinUIError.last("reading the picked color"))", .error)
                return
            }
            let steps = steps(color)
            guard steps != state.shownColor else { return }
            state.shownColor = steps
            ColorPicker.userPicked(.rgba(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha),
                                   element: node.element, model: node.model, windowUUID: node.windowModel.windowUUID,
                                   props: Props(node.properties))
        }
        return layout.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? ColorPickerState else { return }
        let layout = state.layout
        let props = Props(node.properties)
        layout.setTitle(props.title)
        layout.titleHidden = node.isLabelsHidden
        if state.appliedAppearance != node.textAppearance {
            state.appliedAppearance = node.textAppearance
            node.textAppearance.apply(to: layout.title, what: "a ColorPicker's title")
        }
        // The button is named after the title, also when labelsHidden hides it, as in SwiftUI; with no
        // title, the button's own name ("Color").
        let name = props.title.isEmpty ? "Color" : props.title
        if state.accessibleName != name {
            if actionUIWinUIElementSetAccessibleName(layout.control.pointer, name) {
                state.accessibleName = name
            } else {
                ActionUIModel.shared.logger.log("ColorPicker: \(WinUIError.last("naming the button"))", .error)
            }
        }
        // Read by the button; the title beside it is not read again.
        if !actionUIWinUIElementSetAccessibilityHidden(layout.title.pointer, true) {
            ActionUIModel.shared.logger.log("ColorPicker: \(WinUIError.last("hiding the title from accessibility tools"))", .error)
        }
        node.applyAccessibilityHidden(to: layout.control)
        // RenderNode enables the view, which is the layout's panel (no Control): the button is enabled here.
        if !actionUIWinUIElementSetEnabled(layout.control.pointer, !(node.isDisabled || node.isHidden)) {
            ActionUIModel.shared.logger.log("ColorPicker: \(WinUIError.last("enabling the button"))", .error)
        }
        let color = ColorRGBA.resolve(ColorPicker.initialValue(node.model) as? ColorSpec ?? .named(.clear))
        let wanted = steps(color)
        if wanted != state.shownColor {
            // Before the call, whose event can come at once.
            state.shownColor = wanted
            if !actionUIWinUIColorButtonSetColor(layout.control.pointer, color) {
                ActionUIModel.shared.logger.log("ColorPicker: \(WinUIError.last("showing the color"))", .error)
                // What it shows: the next update tries again, and the user's pick of `color` is not taken
                // for the renderer's own.
                var shown = ActionUIWinUIColor(red: 0, green: 0, blue: 0, alpha: 0)
                state.shownColor = actionUIWinUIColorButtonGetColor(layout.control.pointer, &shown) ? steps(shown) : nil
            }
        }
    }

    /// `color` in the picker's steps (0...255 for each of red, green, blue and alpha); a part that is not
    /// finite is 0, as the shim takes it (Int(_:) would trap on NaN).
    private static func steps(_ color: ActionUIWinUIColor) -> [Int] {
        [color.red, color.green, color.blue, color.alpha].map { $0.isFinite ? Int((min(max($0, 0), 1) * 255).rounded()) : 0 }
    }
}
