// Sources/Elements/Slider+WinUI.swift
/*
 Slider on WinUI: Windows' horizontal Slider over the range, without the value shown beside its thumb,
 as SwiftUI's Slider shows none. It takes the width it is offered and its own height, as SwiftUI's and
 the Linux renderer's do.

 - The position is the value, else the value property (Slider.initialValue). A value outside the range
   is shown at the nearer end without being changed, as on Linux (WinUI's Slider would move it and
   report that as a change).
 - With a step, the thumb snaps to the nearest step from the minimum, as SwiftUI's
   Slider(value:in:step:) does (never past the last whole step: on 0 to 10 by 4, at most 8, as
   SwiftUI and Linux stop there), and a tick below marks each step, as macOS draws them (none past 200
   steps, where macOS's run together into a line: WinUI makes an element per tick); the arrow keys
   move by the step (without one, by a hundredth of the range).
 - Moving it runs Core's Slider.userSetValue (the value, then valueChangeActionID). The Slider also
   reports the renderer's own changes, during the call: those are skipped.

 Not yet: an accessible name; the step's snapping of a value a host sets (WinUI shows it on the nearest
 step, the value keeps what the host set); controlSize.
*/

import CWinUI

/// What a Slider node keeps: the range it shows and whether the renderer is setting the Slider.
@MainActor final class SliderState {
    var range: (min: Double, max: Double, step: Double)?
    var applying = false
}

extension Slider: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .horizontal }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let slider = WinUIObject(adopting: actionUIWinUISliderCreate()) else {
            throw WinUIError.last("creating a Slider")
        }
        let state = SliderState()
        node.state = state
        WinUIEvents.connect(slider, actionUIWinUISliderOnValueChanged, "a Slider's value") { [weak node, weak state, weak slider] in
            guard let node, let state, let slider, node.isAttached, !state.applying else { return }
            let props = Props(node.properties)
            let position = actionUIWinUISliderGetValue(slider.pointer)
            let snapped = snap(position, props)
            Slider.userSetValue(snapped, element: node.element, model: node.model, windowUUID: node.windowModel.windowUUID,
                                props: props)
            if snapped != position {
                // The thumb past the last step goes back to it (also when the value already held it).
                SyncScheduler.shared.markDirty(node)
            }
        }
        return slider
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? SliderState else { return }
        let props = Props(node.properties)
        let value = Slider.initialValue(node.model) as? Double ?? props.initialValue
        // The Slider's reports during these calls are the renderer's own.
        state.applying = true
        defer { state.applying = false }
        var ok = true
        let range = (min: props.min, max: props.max, step: props.step ?? 0)
        if state.range.map({ $0 != range }) ?? true {
            ok = actionUIWinUISliderSetRange(view.pointer, range.min, range.max, range.step)
            state.range = ok ? range : nil
        }
        // A value outside the range (or not a number) at the nearer end, without changing the value.
        let shown = value.isNaN ? props.min : Swift.min(Swift.max(value, props.min), props.max)
        if !(ok && actionUIWinUISliderSetValue(view.pointer, shown)) {
            ActionUIModel.shared.logger.log("Slider: \(WinUIError.last("showing a Slider"))", .error)
        }
    }

    /// `position` on the nearest step from the minimum, at most the last whole step, as SwiftUI's
    /// stepped Slider allows (as on Linux); continuous without a step.
    static func snap(_ position: Double, _ props: Props) -> Double {
        guard let step = props.step, step > 0 else { return position }
        // A whole number of steps can divide to just under it (0.3 / 0.1 is 2.9999999999999996).
        let lastStep = ((props.max - props.min) / step + 1e-9).rounded(.down)
        let steps = Swift.min(Swift.max(((position - props.min) / step).rounded(), 0), lastStep)
        return props.min + steps * step
    }
}
