// Sources/Elements/Slider+Adwaita.swift
/*
 Slider on GTK: a horizontal GtkScale over the range, without the value drawn beside it, as
 SwiftUI's Slider shows none. It takes the width it is offered and only its own height (measured on
 macOS 27: beside a filling Color in a 400-point HStack each got 200; it is 16 points tall there,
 GTK's scale is taller).

 - The position is the value, else the value property (Slider.initialValue); GTK shows a value
   outside the range at the nearer end.
 - With a step, a position the user drags to snaps to the nearest step from the minimum, as
   SwiftUI's Slider(value:in:step:) does; the arrow keys move by the step.
 - Moving it runs Core's Slider.userSetValue (the value, then valueChangeActionID); an update fires
   nothing.
*/

import CAdwaita

extension Slider: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let scale = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 0, 1, 0.01)!
        gtk_scale_set_draw_value(typed(scale), 0)
        gtk_widget_set_hexpand(scale, 1)
        // Lines up beside its middle, as macOS lines up a Slider's title (Baselines).
        attach(TextLineMarker(.centered), to: scale, key: textLineMarkerKey)
        let snapBack = SnapBack()
        connectUserSignal(scale, "value-changed", .instanceOnly) { [weak node] in
            guard let node else { return }
            let range: UnsafeMutablePointer<GtkRange> = typed(scale)
            let position = gtk_range_get_value(range)
            if let pending = snapBack.position {
                snapBack.position = nil
                if position == pending { return }
            }
            let props = Props(node.properties)
            let snapped = snap(position, props)
            Slider.userSetValue(snapped, element: node.element, model: node.model, windowUUID: node.windowUUID, props: props)
            if snapped != position {
                // Emits value-changed again, after this handler returns (GtkAdjustment's signal does
                // not recurse, GLib restarts the emission), so outside any UpdateGuard. That run
                // must not store the position again: the action may have set another value (an
                // in-process handler does so synchronously), and storing would overwrite it and
                // fire the action a second time.
                snapBack.position = snapped
                gtk_range_set_value(range, snapped)
            }
        }
        return scale
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        let range: UnsafeMutablePointer<GtkRange> = typed(widget)
        let adjustment = gtk_range_get_adjustment(range)!
        if gtk_adjustment_get_lower(adjustment) != props.min || gtk_adjustment_get_upper(adjustment) != props.max {
            gtk_range_set_range(range, props.min, props.max)
        }
        // The arrow keys move by the step, else by a hundredth of the range; Page Up and Down by a
        // tenth.
        let span = props.max - props.min
        let step = props.step ?? span / 100
        let page = Swift.max(step, span / 10)
        if gtk_adjustment_get_step_increment(adjustment) != step || gtk_adjustment_get_page_increment(adjustment) != page {
            gtk_range_set_increments(range, step, page)
        }
        let position = Slider.initialValue(node.model) as? Double ?? props.initialValue
        if gtk_range_get_value(range) != position {
            gtk_range_set_value(range, position)
        }
        let parts = ControlSizeCSS.slider(node.environment.controlSize)
        ControlSizeCSS.applyPart(parts.scale, to: widget)
        ControlSizeCSS.applyPart(parts.knob, to: widget, selector: "{} > trough > slider", slot: "controlSizeKnob")
    }

    static var defaultExpansion: Expansion { .horizontal }

    /// The position the value-changed handler snapped the scale to, until the value-changed that
    /// snapping emits arrives.
    @MainActor final class SnapBack {
        var position: Double?
    }

    /// The step position nearest `position`: min + n * step, the values SwiftUI documents as valid
    /// ("the distance between each valid value"), so the last one is below max when the range is
    /// no multiple of the step (0...10 by 4 stops at 8). `position` itself without a step.
    static func snap(_ position: Double, _ props: Props) -> Double {
        guard let step = props.step, step > 0 else { return position }
        // A whole number of steps can divide to just under it (0.3 / 0.1 is 2.9999999999999996).
        let lastStep = ((props.max - props.min) / step + 1e-9).rounded(.down)
        let steps = Swift.min(Swift.max(((position - props.min) / step).rounded(), 0), lastStep)
        return props.min + steps * step
    }
}
