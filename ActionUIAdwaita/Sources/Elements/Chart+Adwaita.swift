// Sources/Elements/Chart+Adwaita.swift
/*
 Chart on GTK: a widget that draws what Drawing/ChartLayout.swift lays out with GTK's snapshot API
 (GSK paths and strokes, Pango text). Greedy in both axes with Color's size, as Canvas is.

 The description is stored cleaned (Core/Elements/Chart.swift), and its warnings were logged then,
 so it parses without a logger here. Marks are read when the description or the rows change; the
 layout runs at each draw, which GTK asks for only when the size, the theme or the chart changed.

 Axis text is the theme's text color and 0.8 of its size, near Swift Charts' caption2 next to body
 text. Numbers and dates are written in the user's locale (NumberFormatting, DateFormatting).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

nonisolated(unsafe) private var chartWidgetType: GType = 0
private let chartStateKey = AttachKey<ChartState>("actionui-chart")

/// What a chart draws, kept on its widget.
@MainActor private final class ChartState {
    var spec = ChartSpec()
    var marks = ChartResolvedMarks()
    /// The mark kinds already reported as not drawn.
    var reported: Set<ChartMarkKind> = []
}

extension Chart: ActionUIAdwaitaRenderer {
    private static let drawnKinds: Set<ChartMarkKind> = [.BarMark, .PointMark, .RuleMark, .LineMark, .AreaMark]

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let widget: WidgetPointer = typed(OpaquePointer(g_object_new_with_properties(widgetType(), 0, nil, nil)!))
        gtk_widget_set_hexpand(widget, 1)
        gtk_widget_set_vexpand(widget, 1)
        attach(ChartState(), to: widget, key: chartStateKey)
        return widget
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let state = attached(on: widget, key: chartStateKey) else { return }
        let description = node.properties["chart"] as? [String: Any] ?? [:]
        let rows = node.model.states["content"] as? [[String]] ?? []
        if let firstWeekday = DateFormatting.firstWeekday() {
            ChartDates.calendar.firstWeekday = firstWeekday
        }
        state.spec = ChartDescription.parse(description, logger: nil).spec
        state.marks = ChartMarkResolver.resolve(state.spec, rows: rows)
        report(state, viewID: node.element.id)
        gtk_widget_queue_draw(widget)
    }

    static var defaultExpansion: Expansion { .both }

    private static func report(_ state: ChartState, viewID: Int) {
        let logger = ActionUIModel.shared.logger
        if state.marks.skippedRows > 0, let first = state.marks.firstSkip {
            let place = first.inlineData ? "row \(first.row + 1) of a ForEach's data" : "row \(first.row + 1)"
            logger.log("Chart \(viewID): skipped \(state.marks.skippedRows) row(s) with a cell that does not parse; first: \(place), column \(first.column + 1) is not a \(first.type.rawValue)", .warning)
        }
        for instance in state.marks.instances where !drawnKinds.contains(instance.mark.kind) {
            if state.reported.insert(instance.mark.kind).inserted {
                logger.log("Chart \(viewID): \(instance.mark.kind.rawValue) is not drawn on Linux yet", .warning)
            }
        }
    }

    private static func snapshot(_ widget: WidgetPointer, _ snapshot: OpaquePointer) {
        guard let state = attached(on: widget, key: chartStateKey) else { return }
        let width = Double(gtk_widget_get_width(widget)), height = Double(gtk_widget_get_height(widget))
        guard width > 0, height > 0 else { return }
        let text = ChartAxisText(widget: widget)
        let metrics = ChartTextMetrics(
            size: { text.size($0) },
            number: { NumberFormatting.string($0, format: .decimal(minFraction: nil, maxFraction: nil)) },
            date: { DateFormatting.string($0, skeleton: $1) })
        let primitives = ChartLayout.primitives(state.spec, marks: state.marks, width: width, height: height, metrics: metrics)
        var foreground = GdkRGBA()
        gtk_widget_get_color(widget, &foreground)
        let drawing = ChartDrawing(widget: widget, snapshot: snapshot, foreground: foreground, text: text)
        for primitive in primitives {
            drawing.draw(primitive)
        }
    }

    private static func widgetType() -> GType {
        if chartWidgetType != 0 { return chartWidgetType }
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
                MainActor.assumeIsolated { Chart.snapshot(widget, snapshot) }
            }
            gtk_widget_class_set_css_name(widgetClass, "actionui-chart")
            gtk_widget_class_set_accessible_role(widgetClass, GTK_ACCESSIBLE_ROLE_IMG)
        }
        chartWidgetType = g_type_register_static(gtk_widget_get_type(), "ActionUIChart", &info, GTypeFlags(0))
        return chartWidgetType
    }
}

/// One Pango layout in the axis font, reused for every label of a draw.
@MainActor final class ChartAxisText {
    private static let scale = 0.8
    // Unsafe only for deinit, which ends the one reference this draw holds.
    nonisolated(unsafe) let layout: OpaquePointer

    init(widget: WidgetPointer) {
        layout = gtk_widget_create_pango_layout(widget, nil)
        let font = pango_font_description_copy(pango_context_get_font_description(pango_layout_get_context(layout)))
        // GTK's size is absolute, in pixels; setting a plain size would turn it into points.
        pango_font_description_set_absolute_size(font, Double(pango_font_description_get_size(font)) * Self.scale)
        pango_layout_set_font_description(layout, font)
        pango_font_description_free(font)
    }

    deinit {
        g_object_unref(UnsafeMutableRawPointer(layout))
    }

    func size(_ text: String) -> ChartSize {
        pango_layout_set_text(layout, text, -1)
        var width: gint = 0, height: gint = 0
        pango_layout_get_pixel_size(layout, &width, &height)
        return ChartSize(width: Double(width), height: Double(height))
    }
}

/// Draws the primitives of one snapshot.
@MainActor private struct ChartDrawing {
    let widget: WidgetPointer
    let snapshot: OpaquePointer
    let foreground: GdkRGBA
    let text: ChartAxisText

    private func rgba(_ ink: ChartInk) -> GdkRGBA {
        switch ink {
        case .color(let color):
            return ColorRGBA.resolve(color, for: widget)
        case .text(let opacity):
            var color = foreground
            color.alpha *= Float(opacity)
            return color
        }
    }

    func draw(_ primitive: ChartPrimitive) {
        switch primitive {
        case let .line(from, to, ink, stroke):
            line(from, to, ink, stroke)
        case let .rect(rect, ink):
            var color = rgba(ink)
            var bounds = graphene_rect_t(origin: graphene_point_t(x: Float(rect.x), y: Float(rect.y)),
                                         size: graphene_size_t(width: Float(rect.width), height: Float(rect.height)))
            gtk_snapshot_append_color(snapshot, &color, &bounds)
        case let .symbol(shape, center, size, ink):
            symbol(shape, center, size, ink)
        case let .path(elements, ink, style):
            guard let path = path(elements) else { return }
            stroke(path, ink, style)
            gsk_path_unref(path)
        case let .fill(elements, ink):
            guard let path = path(elements) else { return }
            var color = rgba(ink)
            gtk_snapshot_append_fill(snapshot, path, GSK_FILL_RULE_WINDING, &color)
            gsk_path_unref(path)
        case let .text(string, position, alignment):
            label(string, position, alignment)
        }
    }

    private func path(_ elements: [ChartPathElement]) -> OpaquePointer? {
        guard let builder = gsk_path_builder_new() else { return nil }
        for element in elements {
            switch element {
            case .move(let point):
                gsk_path_builder_move_to(builder, Float(point.x), Float(point.y))
            case .line(let point):
                gsk_path_builder_line_to(builder, Float(point.x), Float(point.y))
            case let .curve(first, second, end):
                gsk_path_builder_cubic_to(builder, Float(first.x), Float(first.y), Float(second.x), Float(second.y), Float(end.x), Float(end.y))
            }
        }
        return gsk_path_builder_free_to_path(builder)
    }

    private func stroke(_ path: OpaquePointer, _ ink: ChartInk, _ style: ChartStroke) {
        guard let stroke = gsk_stroke_new(Float(style.lineWidth)) else { return }
        gsk_stroke_set_line_cap(stroke, cap(style.lineCap))
        gsk_stroke_set_line_join(stroke, join(style.lineJoin))
        gsk_stroke_set_miter_limit(stroke, Float(max(style.miterLimit, 0)))
        if !style.dash.isEmpty {
            gsk_stroke_set_dash(stroke, style.dash.map { Float(max($0, 0)) }, gsize(style.dash.count))
            gsk_stroke_set_dash_offset(stroke, Float(style.dashPhase))
        }
        var color = rgba(ink)
        gtk_snapshot_append_stroke(snapshot, path, stroke, &color)
        gsk_stroke_free(stroke)
    }

    private func cap(_ cap: ChartLineCap) -> GskLineCap {
        switch cap {
        case .butt: return GSK_LINE_CAP_BUTT
        case .round: return GSK_LINE_CAP_ROUND
        case .square: return GSK_LINE_CAP_SQUARE
        }
    }

    private func join(_ join: ChartLineJoin) -> GskLineJoin {
        switch join {
        case .miter: return GSK_LINE_JOIN_MITER
        case .round: return GSK_LINE_JOIN_ROUND
        case .bevel: return GSK_LINE_JOIN_BEVEL
        }
    }

    // A straight line of an odd width sits on the pixel grid, so it stays one crisp pixel.
    private func line(_ from: ChartPoint, _ to: ChartPoint, _ ink: ChartInk, _ style: ChartStroke) {
        let odd = max(style.lineWidth.rounded(), 1).truncatingRemainder(dividingBy: 2) == 1
        func snapped(_ value: Double) -> Double {
            odd ? value.rounded(.down) + 0.5 : value.rounded()
        }
        let (x0, x1) = from.x == to.x ? (snapped(from.x), snapped(to.x)) : (from.x, to.x)
        let (y0, y1) = from.y == to.y ? (snapped(from.y), snapped(to.y)) : (from.y, to.y)
        guard let builder = gsk_path_builder_new() else { return }
        gsk_path_builder_move_to(builder, Float(x0), Float(y0))
        gsk_path_builder_line_to(builder, Float(x1), Float(y1))
        guard let path = gsk_path_builder_free_to_path(builder) else { return }
        stroke(path, ink, style)
        gsk_path_unref(path)
    }

    private func symbol(_ shape: ChartSymbol, _ center: ChartPoint, _ size: ChartSize, _ ink: ChartInk) {
        guard let builder = gsk_path_builder_new() else { return }
        let rx = Float(size.width / 2), ry = Float(size.height / 2)
        let x = Float(center.x), y = Float(center.y)
        func polygon(_ points: [(Float, Float)]) {
            for (index, point) in points.enumerated() {
                if index == 0 {
                    gsk_path_builder_move_to(builder, x + point.0 * rx, y + point.1 * ry)
                } else {
                    gsk_path_builder_line_to(builder, x + point.0 * rx, y + point.1 * ry)
                }
            }
            gsk_path_builder_close(builder)
        }
        func spokes(_ points: [(Float, Float)]) {
            for point in points {
                gsk_path_builder_move_to(builder, x - point.0 * rx, y - point.1 * ry)
                gsk_path_builder_line_to(builder, x + point.0 * rx, y + point.1 * ry)
            }
        }
        var strokes = false
        switch shape {
        case .circle:
            var bounds = graphene_rect_t(origin: graphene_point_t(x: x - rx, y: y - ry), size: graphene_size_t(width: rx * 2, height: ry * 2))
            var corners = GskRoundedRect()
            gsk_rounded_rect_init_from_rect(&corners, &bounds, min(rx, ry))
            gsk_path_builder_add_rounded_rect(builder, &corners)
        case .square:
            polygon([(-1, -1), (1, -1), (1, 1), (-1, 1)])
        case .triangle:
            polygon([(0, -1), (1, 1), (-1, 1)])
        case .diamond:
            polygon([(0, -1.3), (1.3, 0), (0, 1.3), (-1.3, 0)])
        case .pentagon:
            polygon([(0, -1), (0.95, -0.31), (0.59, 0.81), (-0.59, 0.81), (-0.95, -0.31)])
        case .plus:
            strokes = true
            spokes([(1, 0), (0, 1)])
        case .cross:
            strokes = true
            spokes([(0.75, 0.75), (0.75, -0.75)])
        case .asterisk:
            strokes = true
            spokes([(0, 1), (0.87, 0.5), (0.87, -0.5)])
        }
        guard let path = gsk_path_builder_free_to_path(builder) else { return }
        if strokes {
            stroke(path, ink, ChartStroke(lineWidth: 1.5))
        } else {
            var color = rgba(ink)
            gtk_snapshot_append_fill(snapshot, path, GSK_FILL_RULE_WINDING, &color)
        }
        gsk_path_unref(path)
    }

    private func label(_ string: String, _ position: ChartPoint, _ alignment: ChartPoint) {
        let size = text.size(string)
        var origin = graphene_point_t(x: Float((position.x - size.width * alignment.x).rounded()),
                                      y: Float((position.y - size.height * alignment.y).rounded()))
        var color = rgba(ChartLayout.labelInk)
        gtk_snapshot_save(snapshot)
        gtk_snapshot_translate(snapshot, &origin)
        gtk_snapshot_append_layout(snapshot, text.layout, &color)
        gtk_snapshot_restore(snapshot)
    }
}
