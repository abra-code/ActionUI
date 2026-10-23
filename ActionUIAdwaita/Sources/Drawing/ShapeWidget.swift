// Sources/Drawing/ShapeWidget.swift
/*
 The widget that draws the shape elements (Rectangle, RoundedRectangle, Circle, Ellipse, Capsule):
 a GtkWidget subclass that fills or strokes one outline in its allocation, with GTK's path API.
 Its size is that of Color (greedy in both axes, 10 x 10 naturally, no minimum), as SwiftUI sizes a
 shape like a Color. It sits alone in a container that is the element's widget: ModifierBox puts
 the foregroundStyle color on the element's widget, and the shape's own color must win over it and
 can refer to it (secondary is the foreground at an opacity), as in SwiftUI. Two classes setting
 color on one widget would leave the winner to the stylesheet's order.

 - The outline fits the allocation as SwiftUI's shapes do: a Circle is the largest circle centered
   in it, a Capsule's ends are half its shorter side, a RoundedRectangle's radius is at most half
   its shorter side (SwiftUI clamps it), an Ellipse touches all four sides.
 - The paint is the fill style, else the stroke style, else the foreground color (SwiftUI fills an
   unstyled shape with the foreground style). The style is the widget's CSS color, so named styles,
   foregroundStyle on an ancestor and dark mode resolve as for text; the snapshot reads it with
   gtk_widget_get_color.
 - A stroke is centered on the outline, half of it outside the allocation, as SwiftUI's stroke is.
 - Continuous corners (cornerStyle or style "continuous") are drawn circular: GTK has no
   superellipse, and the difference is a few pixels near the corners.
 - A Circle stroked wider than its diameter keeps a hole in the middle (GSK strokes it so), where
   SwiftUI covers the whole disc.
*/

import CAdwaita

nonisolated(unsafe) private var shapeWidgetType: GType = 0
private let shapeStateKey = AttachKey<ShapeState>("actionui-shape-state")

/// The outline a shape element draws, fitted to the widget's allocation.
enum ShapeOutline: Equatable {
    case rectangle
    case roundedRectangle(radius: Double)
    case circle
    case ellipse
    case capsule
}

/// What one shape widget draws.
struct ShapeDrawing: Equatable {
    var outline = ShapeOutline.rectangle
    /// nil: filled.
    var strokeWidth: Double?
}

@MainActor private final class ShapeState {
    var drawing = ShapeDrawing()
}

@MainActor
enum ShapeWidget {
    /// The element's widget: a container holding the shape widget.
    static func make() -> WidgetPointer {
        let widget = makeContainer(layoutType: gtk_bin_layout_get_type())
        let shape: WidgetPointer = typed(OpaquePointer(g_object_new_with_properties(widgetType(), 0, nil, nil)!))
        attach(ShapeState(), to: shape, key: shapeStateKey)
        gtk_widget_set_parent(shape, widget)
        gtk_widget_set_hexpand(widget, 1)
        gtk_widget_set_vexpand(widget, 1)
        return widget
    }

    /// Makes the widget draw `outline` with the fill style, else the stroke style (at lineWidth),
    /// else the foreground color. Redraws only when something changed.
    static func update(_ widget: WidgetPointer, outline: ShapeOutline, fill: String?, stroke: String?, lineWidth: Double) {
        guard let shape = Gtk.Widget(widget).firstChild?.pointer,
              let state = attached(on: shape, key: shapeStateKey) else { return }
        let fillStyle = fill.flatMap(ShapeStyleSpec.parse)
        let strokeStyle = fillStyle == nil ? stroke.flatMap(ShapeStyleSpec.parse) : nil
        let drawing = ShapeDrawing(outline: outline, strokeWidth: strokeStyle == nil ? nil : max(lineWidth, 0))
        let declarations = (fillStyle ?? strokeStyle).map { ["color: \(ColorCSS.value($0));"] } ?? []
        StyleSheet.shared.apply(declarations, to: shape, slot: "shape")
        if state.drawing != drawing {
            state.drawing = drawing
            gtk_widget_queue_draw(shape)
        }
    }

    /// The drawing the element's widget shows, for tests.
    static func drawing(of widget: WidgetPointer) -> ShapeDrawing? {
        Gtk.Widget(widget).firstChild.flatMap { attached(on: $0.pointer, key: shapeStateKey)?.drawing }
    }

    private static func snapshot(_ widget: WidgetPointer, _ snapshot: OpaquePointer) {
        guard let drawing = attached(on: widget, key: shapeStateKey)?.drawing else { return }
        let width = Float(gtk_widget_get_width(widget))
        let height = Float(gtk_widget_get_height(widget))
        guard width > 0, height > 0 else { return }
        let builder = gsk_path_builder_new()!
        let rect = graphene_rect_t(origin: graphene_point_t(x: 0, y: 0), size: graphene_size_t(width: width, height: height))
        let shorter = min(width, height)
        switch drawing.outline {
        case .rectangle:
            var bounds = rect
            gsk_path_builder_add_rect(builder, &bounds)
        case .roundedRectangle(let radius):
            // A host can set any number; NaN would pass max(), and infinity clamps like any large one.
            let corner = min(Float(radius.isNaN ? 0 : max(radius, 0)), shorter / 2)
            addRoundedRect(builder, rect, radius: graphene_size_t(width: corner, height: corner))
        case .capsule:
            addRoundedRect(builder, rect, radius: graphene_size_t(width: shorter / 2, height: shorter / 2))
        case .ellipse:
            addRoundedRect(builder, rect, radius: graphene_size_t(width: width / 2, height: height / 2))
        case .circle:
            var center = graphene_point_t(x: width / 2, y: height / 2)
            gsk_path_builder_add_circle(builder, &center, shorter / 2)
        }
        let path = gsk_path_builder_free_to_path(builder)!
        defer { gsk_path_unref(path) }
        var color = GdkRGBA()
        gtk_widget_get_color(widget, &color)
        if let strokeWidth = drawing.strokeWidth {
            guard strokeWidth > 0 else { return }
            let stroke = gsk_stroke_new(Float(strokeWidth))!
            defer { gsk_stroke_free(stroke) }
            gtk_snapshot_append_stroke(snapshot, path, stroke, &color)
        } else {
            gtk_snapshot_append_fill(snapshot, path, GSK_FILL_RULE_WINDING, &color)
        }
    }

    /// A rectangle whose four corners have the same radii; radii of half the sides make an ellipse.
    private static func addRoundedRect(_ builder: OpaquePointer, _ rect: graphene_rect_t, radius: graphene_size_t) {
        var rounded = GskRoundedRect()
        var bounds = rect
        var corner = radius
        gsk_rounded_rect_init(&rounded, &bounds, &corner, &corner, &corner, &corner)
        gsk_path_builder_add_rounded_rect(builder, &rounded)
    }

    private static func widgetType() -> GType {
        if shapeWidgetType != 0 { return shapeWidgetType }
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkWidgetClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkWidget>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            let widgetClass = klass.assumingMemoryBound(to: GtkWidgetClass.self)
            widgetClass.pointee.measure = { _, _, _, minimum, natural, minimumBaseline, naturalBaseline in
                minimum?.pointee = 0
                natural?.pointee = MainActor.assumeIsolated { Color.idealLength }
                minimumBaseline?.pointee = -1
                naturalBaseline?.pointee = -1
            }
            widgetClass.pointee.snapshot = { widget, snapshot in
                guard let widget, let snapshot else { return }
                MainActor.assumeIsolated { ShapeWidget.snapshot(widget, snapshot) }
            }
            gtk_widget_class_set_css_name(widgetClass, "actionui-shape")
        }
        shapeWidgetType = g_type_register_static(gtk_widget_get_type(), "ActionUIShape", &info, GTypeFlags(0))
        return shapeWidgetType
    }
}
