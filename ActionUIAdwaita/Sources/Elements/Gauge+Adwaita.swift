// Sources/Elements/Gauge+Adwaita.swift
/*
 Gauge on GTK, in the form its style has on macOS (measured on macOS 27 with the parity recorder,
 and seen in SwiftUI drawings):
 - no style, and accessoryLinearCapacity: a GtkLevelBar under the title (centered without a style,
   leading for capacity), as wide as it is offered.
 - accessoryLinear: a drawn bar with a dot at the value, as wide as it is offered, 8 points tall; its
   title is not shown, as on macOS.
 - accessoryCircular: a drawn open arc, its gap at the bottom, with a dot at the value and the title
   small in the gap; 58 x 58.
 - accessoryCircularCapacity: a drawn ring filled clockwise from the top, the title large in the
   middle; 58 x 58.
 The drawn forms use the accent color, as GTK's level bar does.

 - The value is the value, else the value property (Gauge.initialValue), shown inside the range.
 - Assistive technologies read the level bar or the drawing as a meter with its value, named after
   the title; a visible title label is left out of the tree, so it is read once.
*/

import CAdwaita

nonisolated(unsafe) private var drawingWidgetType: GType = 0
let gaugeStateKey = AttachKey<GaugeState>("actionui-gauge-state")

/// What a drawn gauge shows, kept on the drawing.
@MainActor final class GaugeState {
    var kind = Gauge.Kind.linear
    var fraction = 0.0
    /// The range and value last written for assistive technologies; nil before the first update.
    var accessibleValue: [Double]?
}

extension Gauge: ActionUIAdwaitaRenderer {
    enum Kind: Int {
        case levelBar = 0, linear, circular, circularCapacity
    }

    /// The side of the circular forms, the drawn bar's height, and the line widths.
    static let circularSide: Int32 = 58
    static let linearHeight: Int32 = 8
    static let circularLineWidth: Float = 6
    /// The gap between the title and the level bar.
    static let titleSpacing: Int32 = 4

    static func widgetKind(_ node: RenderNode) -> Int {
        kind(Props(node.properties).style).rawValue
    }

    static func kind(_ style: Props.Style?) -> Kind {
        switch style {
        case nil, .accessoryLinearCapacity?: return .levelBar
        case .accessoryLinear?: return .linear
        case .accessoryCircular?: return .circular
        case .accessoryCircularCapacity?: return .circularCapacity
        }
    }

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let kind = Kind(rawValue: node.widgetKind) ?? .levelBar
        // Left out of the accessibility tree: the meter carries the title as its name. Made only for
        // a form that shows it (a floating label never added to a parent leaks).
        func makeTitle() -> WidgetPointer {
            newWidget(gtk_label_get_type(), accessibleRole: GTK_ACCESSIBLE_ROLE_PRESENTATION)
        }
        switch kind {
        case .levelBar:
            let title = makeTitle()
            let box = gtk_box_new(GTK_ORIENTATION_VERTICAL, titleSpacing)!
            let bar = gtk_level_bar_new()!
            // One color for any value: no low, high and full offsets.
            for offset in [GTK_LEVEL_BAR_OFFSET_LOW, GTK_LEVEL_BAR_OFFSET_HIGH, GTK_LEVEL_BAR_OFFSET_FULL] {
                gtk_level_bar_remove_offset_value(OpaquePointer(bar), offset)
            }
            gtk_widget_set_hexpand(bar, 1)
            gtk_box_append(typed(box), title)
            gtk_box_append(typed(box), bar)
            return box
        case .linear:
            let drawing = makeDrawing(kind)
            gtk_widget_set_hexpand(drawing, 1)
            return drawing
        case .circular, .circularCapacity:
            let overlay = gtk_overlay_new()!
            let title = makeTitle()
            let drawing = makeDrawing(kind)
            gtk_widget_set_size_request(drawing, circularSide, circularSide)
            gtk_overlay_set_child(OpaquePointer(overlay), drawing)
            gtk_widget_set_halign(title, GTK_ALIGN_CENTER)
            gtk_widget_set_valign(title, kind == .circular ? GTK_ALIGN_END : GTK_ALIGN_CENTER)
            gtk_widget_add_css_class(title, kind == .circular ? "caption" : "title-4")
            gtk_label_set_ellipsize(opaque(title), PANGO_ELLIPSIZE_END)
            gtk_label_set_max_width_chars(opaque(title), kind == .circular ? 6 : 4)
            gtk_overlay_add_overlay(OpaquePointer(overlay), title)
            return overlay
        }
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let props = Props(node.properties)
        let kind = Kind(rawValue: node.widgetKind) ?? .levelBar
        let value = Gauge.initialValue(node.model) as? Double ?? props.initialValue
        let shown = Swift.min(Swift.max(value, props.min), props.max)
        let span = props.max - props.min
        let fraction = span > 0 ? (shown - props.min) / span : 0
        let meter = accessibleWidget(widget)
        if let title = titleLabel(widget) {
            let text = props.title ?? ""
            if swiftString(gtk_label_get_text(opaque(title))) != text {
                gtk_label_set_text(opaque(title), text)
            }
            let visible: gboolean = props.title == nil ? 0 : 1
            if gtk_widget_get_visible(title) != visible {
                gtk_widget_set_visible(title, visible)
            }
            let xalign: Float = props.style == nil ? 0.5 : 0
            if kind == .levelBar, gtk_label_get_xalign(opaque(title)) != xalign {
                gtk_label_set_xalign(opaque(title), xalign)
            }
        }
        if kind == .levelBar {
            // GtkLevelBar refuses a negative minimum (a CRITICAL, and it keeps 0): a range below 0
            // is moved to start at 0, and assistive technologies get the gauge's own numbers,
            // written after the bar's (rewriting equal values sends nothing).
            let shift = props.min < 0 ? -props.min : 0
            let bar = OpaquePointer(meter)
            if gtk_level_bar_get_min_value(bar) != props.min + shift || gtk_level_bar_get_max_value(bar) != props.max + shift {
                gtk_level_bar_set_min_value(bar, props.min + shift)
                gtk_level_bar_set_max_value(bar, props.max + shift)
            }
            if gtk_level_bar_get_value(bar) != shown + shift {
                gtk_level_bar_set_value(bar, shown + shift)
            }
            setAccessibleValue(meter, min: props.min, max: props.max, now: shown)
        } else if let state = attached(on: meter, key: gaugeStateKey) {
            if state.fraction != fraction {
                state.fraction = fraction
                gtk_widget_queue_draw(meter)
            }
            let accessible = [props.min, props.max, shown]
            if state.accessibleValue != accessible {
                state.accessibleValue = accessible
                setAccessibleValue(meter, min: props.min, max: props.max, now: shown)
            }
        }
    }

    /// The level bar or the drawing, which assistive technologies read.
    static func accessibleWidget(_ widget: WidgetPointer) -> WidgetPointer {
        if attached(on: widget, key: gaugeStateKey) != nil {
            return widget
        }
        if g_type_check_instance_is_a(UnsafeMutablePointer<GTypeInstance>(OpaquePointer(widget)), gtk_overlay_get_type()) != 0 {
            return gtk_overlay_get_child(OpaquePointer(widget)) ?? widget
        }
        return gtk_widget_get_last_child(widget) ?? widget
    }

    /// Named after its title.
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        Props(node.properties).title
    }

    /// The title label: above a level bar, over a circular drawing; nil for the drawn bar.
    private static func titleLabel(_ widget: WidgetPointer) -> WidgetPointer? {
        if attached(on: widget, key: gaugeStateKey) != nil {
            return nil
        }
        if g_type_check_instance_is_a(UnsafeMutablePointer<GTypeInstance>(OpaquePointer(widget)), gtk_overlay_get_type()) != 0 {
            return gtk_widget_get_last_child(widget)
        }
        return gtk_widget_get_first_child(widget)
    }

    private static func makeDrawing(_ kind: Kind) -> WidgetPointer {
        let drawing: WidgetPointer = typed(OpaquePointer(g_object_new_with_properties(drawingType(), 0, nil, nil)!))
        let state = GaugeState()
        state.kind = kind
        attach(state, to: drawing, key: gaugeStateKey)
        StyleSheet.shared.apply(["color: var(--accent-color);"], to: drawing, slot: "gaugeColor")
        return drawing
    }

    private static func draw(_ widget: WidgetPointer, _ snapshot: OpaquePointer) {
        guard let state = attached(on: widget, key: gaugeStateKey) else { return }
        switch state.kind {
        case .circular:
            // An open arc of three quarters, its gap centered at the bottom.
            RingDrawing.draw(widget, snapshot, lineWidth: circularLineWidth, start: 0.75 * Float.pi, sweep: 1.5 * Float.pi,
                             fraction: state.fraction, marker: true)
        case .circularCapacity:
            RingDrawing.draw(widget, snapshot, lineWidth: circularLineWidth, start: -Float.pi / 2, sweep: 2 * Float.pi,
                             fraction: state.fraction, marker: false)
        case .linear:
            drawLinear(widget, snapshot, state.fraction)
        case .levelBar:
            break
        }
    }

    /// A rounded bar across the width: a faint track, the fraction in the color, and a dot at the
    /// value.
    private static func drawLinear(_ widget: WidgetPointer, _ snapshot: OpaquePointer, _ fraction: Double) {
        let width = Float(gtk_widget_get_width(widget))
        let height = Float(gtk_widget_get_height(widget))
        let thickness = Float(linearHeight) / 2
        guard width > thickness * 2 else { return }
        var color = GdkRGBA()
        gtk_widget_get_color(widget, &color)
        var track = color
        track.alpha *= 0.2
        let y = height / 2
        let left = thickness
        let right = width - thickness
        let end = left + (right - left) * Float(Swift.min(Swift.max(fraction, 0), 1))
        let stroke = gsk_stroke_new(thickness)!
        defer { gsk_stroke_free(stroke) }
        gsk_stroke_set_line_cap(stroke, GSK_LINE_CAP_ROUND)
        for (from, to, paint) in [(left, right, track), (left, end, color)] where to > from {
            var paint = paint
            let builder = gsk_path_builder_new()!
            gsk_path_builder_move_to(builder, from, y)
            gsk_path_builder_line_to(builder, to, y)
            let path = gsk_path_builder_free_to_path(builder)!
            gtk_snapshot_append_stroke(snapshot, path, stroke, &paint)
            gsk_path_unref(path)
        }
        var dot = graphene_point_t(x: end, y: y)
        let builder = gsk_path_builder_new()!
        gsk_path_builder_add_circle(builder, &dot, Float(linearHeight) / 2)
        let path = gsk_path_builder_free_to_path(builder)!
        gtk_snapshot_append_fill(snapshot, path, GSK_FILL_RULE_WINDING, &color)
        gsk_path_unref(path)
    }

    /// A GtkWidget subclass that draws a gauge, a meter for assistive technologies. Its natural size
    /// is the drawn bar's height (the circular forms set their size).
    private static func drawingType() -> GType {
        if drawingWidgetType != 0 { return drawingWidgetType }
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkWidgetClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkWidget>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            let widgetClass = klass.assumingMemoryBound(to: GtkWidgetClass.self)
            widgetClass.pointee.measure = { _, orientation, _, minimum, natural, minimumBaseline, naturalBaseline in
                let length: Int32 = orientation == GTK_ORIENTATION_VERTICAL ? 8 : 16
                minimum?.pointee = length
                natural?.pointee = length
                minimumBaseline?.pointee = -1
                naturalBaseline?.pointee = -1
            }
            widgetClass.pointee.snapshot = { widget, snapshot in
                guard let widget, let snapshot else { return }
                MainActor.assumeIsolated { Gauge.draw(widget, snapshot) }
            }
            gtk_widget_class_set_css_name(widgetClass, "actionui-gauge")
            gtk_widget_class_set_accessible_role(widgetClass, GTK_ACCESSIBLE_ROLE_METER)
        }
        drawingWidgetType = g_type_register_static(gtk_widget_get_type(), "ActionUIGauge", &info, GTypeFlags(0))
        return drawingWidgetType
    }
}
