// Sources/Drawing/RingDrawing.swift
/*
 A ring or an open arc that shows a fraction, drawn in a widget's snapshot: a faint track over the
 whole sweep, the fraction of it in the widget's CSS color, and optionally a dot where the fraction
 ends. ProgressView's circular style and Gauge's circular styles draw with it.

 Angles are in radians, clockwise from the positive x axis (GTK's y points down): -pi/2 is the top.
*/

import CAdwaita

enum RingDrawing {
    /// Draws into `snapshot` the ring of `widget`, centered in it and as large as fits: the track
    /// from `start` through `sweep`, then `fraction` (0...1) of it, `lineWidth` wide, and with
    /// `marker` a dot at the end of the fraction.
    @MainActor
    static func draw(_ widget: WidgetPointer, _ snapshot: OpaquePointer, lineWidth: Float,
                     start: Float, sweep: Float, fraction: Double, marker: Bool) {
        let width = Float(gtk_widget_get_width(widget))
        let height = Float(gtk_widget_get_height(widget))
        let side = Swift.min(width, height)
        guard side > lineWidth * 2 else { return }
        let center = graphene_point_t(x: width / 2, y: height / 2)
        let radius = (side - lineWidth * (marker ? 2 : 1)) / 2
        var color = GdkRGBA()
        gtk_widget_get_color(widget, &color)
        let stroke = gsk_stroke_new(lineWidth)!
        defer { gsk_stroke_free(stroke) }
        gsk_stroke_set_line_cap(stroke, GSK_LINE_CAP_ROUND)

        var track = color
        track.alpha *= 0.2
        if let path = arc(center, radius, start: start, sweep: sweep) {
            gtk_snapshot_append_stroke(snapshot, path, stroke, &track)
            gsk_path_unref(path)
        }
        let filled = Float(Swift.min(Swift.max(fraction, 0), 1)) * sweep
        if let path = arc(center, radius, start: start, sweep: filled) {
            gtk_snapshot_append_stroke(snapshot, path, stroke, &color)
            gsk_path_unref(path)
        }
        if marker {
            let end = start + filled
            var dot = graphene_point_t(x: center.x + radius * cosf(end), y: center.y + radius * sinf(end))
            let builder = gsk_path_builder_new()!
            gsk_path_builder_add_circle(builder, &dot, lineWidth)
            let path = gsk_path_builder_free_to_path(builder)!
            gtk_snapshot_append_fill(snapshot, path, GSK_FILL_RULE_WINDING, &color)
            gsk_path_unref(path)
        }
    }

    /// The arc around `center` from `start` clockwise through `sweep`, nil when `sweep` is not
    /// positive. The caller unrefs the path. Within a hair of a full turn it is the circle: an arc
    /// that ends where it starts draws nothing.
    static func arc(_ center: graphene_point_t, _ radius: Float, start: Float, sweep: Float) -> OpaquePointer? {
        guard sweep > 0 else { return nil }
        let builder = gsk_path_builder_new()!
        if sweep >= 2 * Float.pi * (1 - 1e-6) {
            var point = center
            gsk_path_builder_add_circle(builder, &point, radius)
        } else {
            let end = start + sweep
            gsk_path_builder_move_to(builder, center.x + radius * cosf(start), center.y + radius * sinf(start))
            gsk_path_builder_svg_arc_to(builder, radius, radius, 0, sweep > Float.pi ? 1 : 0, 1,
                                        center.x + radius * cosf(end), center.y + radius * sinf(end))
        }
        return gsk_path_builder_free_to_path(builder)
    }
}
