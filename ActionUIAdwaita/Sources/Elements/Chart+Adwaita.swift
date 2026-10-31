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
    private static let drawnKinds: Set<ChartMarkKind> = [.BarMark, .RectangleMark, .PointMark, .RuleMark, .LineMark, .AreaMark]

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
            number: { NumberFormatting.string($0, format: .decimal(minFraction: $1, maxFraction: $1)) },
            formatted: { NumberFormatting.string($0, format: $1) },
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
        case let .blend(colors, share):
            return blend(colors.map { ColorRGBA.resolve($0, for: widget) }, at: Float(share))
        }
    }

    // Over premultiplied colors, as GSK's gradients are.
    private func blend(_ colors: [GdkRGBA], at share: Float) -> GdkRGBA {
        guard colors.count > 1 else { return colors.first ?? GdkRGBA() }
        let place = share * Float(colors.count - 1)
        let index = min(Int(place), colors.count - 2)
        let part = place - Float(index), from = colors[index], to = colors[index + 1]
        let alpha = from.alpha + (to.alpha - from.alpha) * part
        guard alpha > 0 else { return GdkRGBA() }
        func mixed(_ a: Float, _ b: Float) -> Float {
            (a * from.alpha + (b * to.alpha - a * from.alpha) * part) / alpha
        }
        return GdkRGBA(red: mixed(from.red, to.red), green: mixed(from.green, to.green), blue: mixed(from.blue, to.blue), alpha: alpha)
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
        case let .bar(rect, shape, corners, ink):
            bar(rect, shape, corners, ink)
        case let .symbol(shape, center, side, ink):
            fill(ChartSymbols.outline(shape, center: center, side: side), ink)
        case let .path(elements, ink, style):
            guard let path = path(elements) else { return }
            stroke(path, ink, style)
            gsk_path_unref(path)
        case let .markedLine(elements, ink, style, symbols):
            markedLine(elements, ink, style, symbols)
        case let .fill(elements, ink):
            fill(elements, ink)
        case let .text(string, position, alignment, ink):
            label(string, position, alignment, ink)
        case let .turnedText(string, center, degrees, ink):
            turnedLabel(string, center, degrees, ink)
        case let .beginPlot(layer):
            beginPlot(layer)
        case let .endPlot(layer):
            if layer.clips { gtk_snapshot_pop(snapshot) }
            if layer.opacity < 1 { gtk_snapshot_pop(snapshot) }
        case let .roundedFill(rect, radius, ink):
            var rounded = roundedRect(rect, radius)
            var color = rgba(ink)
            gtk_snapshot_push_rounded_clip(snapshot, &rounded)
            var bounds = rounded.bounds
            gtk_snapshot_append_color(snapshot, &color, &bounds)
            gtk_snapshot_pop(snapshot)
        case let .border(rect, width, ink):
            var rounded = roundedRect(rect, 0)
            var widths = [Float](repeating: Float(width), count: 4)
            let color = rgba(ink)
            var colors = [color, color, color, color]
            gtk_snapshot_append_border(snapshot, &rounded, &widths, &colors)
        case let .gradientBar(rect, stops, vertical):
            var bounds = graphene_rect_t(origin: graphene_point_t(x: Float(rect.x), y: Float(rect.y)),
                                         size: graphene_size_t(width: Float(rect.width), height: Float(rect.height)))
            var start = bounds.origin
            var end = vertical ? graphene_point_t(x: start.x, y: start.y + bounds.size.height) : graphene_point_t(x: start.x + bounds.size.width, y: start.y)
            let colors = stops.map { GskColorStop(offset: Float($0.offset), color: ColorRGBA.resolve($0.color, for: widget)) }
            gtk_snapshot_append_linear_gradient(snapshot, &bounds, &start, &end, colors, gsize(colors.count))
        }
    }

    private func bar(_ rect: ChartRect, _ shape: ChartRect, _ corners: ChartCorners, _ ink: ChartInk) {
        var bounds = graphene_rect_t(origin: graphene_point_t(x: Float(rect.x), y: Float(rect.y)),
                                     size: graphene_size_t(width: Float(rect.width), height: Float(rect.height)))
        var shapeBounds = graphene_rect_t(origin: graphene_point_t(x: Float(shape.x), y: Float(shape.y)),
                                          size: graphene_size_t(width: Float(shape.width), height: Float(shape.height)))
        func corner(_ radius: Double) -> graphene_size_t { graphene_size_t(width: Float(radius), height: Float(radius)) }
        var topLeading = corner(corners.topLeading), topTrailing = corner(corners.topTrailing)
        var bottomTrailing = corner(corners.bottomTrailing), bottomLeading = corner(corners.bottomLeading)
        var rounded = GskRoundedRect()
        gsk_rounded_rect_init(&rounded, &shapeBounds, &topLeading, &topTrailing, &bottomTrailing, &bottomLeading)
        var color = rgba(ink)
        gtk_snapshot_push_rounded_clip(snapshot, &rounded)
        gtk_snapshot_append_color(snapshot, &color, &bounds)
        gtk_snapshot_pop(snapshot)
    }

    private func roundedRect(_ rect: ChartRect, _ radius: Double) -> GskRoundedRect {
        var bounds = graphene_rect_t(origin: graphene_point_t(x: Float(rect.x), y: Float(rect.y)),
                                     size: graphene_size_t(width: Float(rect.width), height: Float(rect.height)))
        var rounded = GskRoundedRect()
        gsk_rounded_rect_init_from_rect(&rounded, &bounds, Float(radius))
        return rounded
    }

    private func beginPlot(_ layer: ChartPlotLayer) {
        if layer.opacity < 1 {
            gtk_snapshot_push_opacity(snapshot, layer.opacity)
        }
        if layer.clips {
            var rounded = roundedRect(layer.rect, layer.radius)
            gtk_snapshot_push_rounded_clip(snapshot, &rounded)
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
            case .close:
                gsk_path_builder_close(builder)
            }
        }
        return gsk_path_builder_free_to_path(builder)
    }

    private func fill(_ elements: [ChartPathElement], _ ink: ChartInk) {
        guard let path = path(elements) else { return }
        var color = rgba(ink)
        gtk_snapshot_append_fill(snapshot, path, GSK_FILL_RULE_WINDING, &color)
        gsk_path_unref(path)
    }

    // The holes go in a mask over this line alone, so another line still crosses them. An outline
    // is its own mark's line width inside the symbol's box, so a width of 0 leaves just the hole;
    // one of half the box leaves no inside, and the symbol is then solid, in its box however wide
    // the line (measured on macOS 27).
    private func markedLine(_ elements: [ChartPathElement], _ ink: ChartInk, _ style: ChartStroke, _ symbols: [ChartLineSymbol]) {
        func isHollow(_ mark: ChartLineSymbol) -> Bool {
            ChartSymbols.isHollowOnALine(mark.symbol) && mark.lineWidth * 2 < mark.side
        }
        func inner(_ mark: ChartLineSymbol) -> [ChartPathElement] {
            ChartSymbols.outline(mark.symbol, center: mark.center, side: mark.side - mark.lineWidth)
        }
        let hollow = symbols.filter(isHollow)
        let solid = symbols.filter { !isHollow($0) }
        if Float(style.lineWidth) > 0, let line = path(elements) {
            if !hollow.isEmpty, let holes = path(hollow.flatMap(inner)) {
                var opaque = GdkRGBA(red: 0, green: 0, blue: 0, alpha: 1)
                gtk_snapshot_push_mask(snapshot, GSK_MASK_MODE_INVERTED_ALPHA)
                gtk_snapshot_append_fill(snapshot, holes, GSK_FILL_RULE_WINDING, &opaque)
                gtk_snapshot_pop(snapshot)
                stroke(line, ink, style)
                gtk_snapshot_pop(snapshot)
                gsk_path_unref(holes)
            } else {
                stroke(line, ink, style)
            }
            gsk_path_unref(line)
        }
        for (width, marks) in Dictionary(grouping: hollow, by: \.lineWidth).sorted(by: { $0.key < $1.key }) where Float(width) > 0 {
            guard let outlines = path(marks.flatMap(inner)) else { continue }
            stroke(outlines, ink, ChartStroke(lineWidth: width, lineCap: .round, lineJoin: .round))
            gsk_path_unref(outlines)
        }
        if !solid.isEmpty {
            fill(solid.flatMap { ChartSymbols.outline($0.symbol, center: $0.center, side: $0.side) }, ink)
        }
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

    private func turnedLabel(_ string: String, _ center: ChartPoint, _ degrees: Double, _ ink: ChartInk) {
        let size = text.size(string)
        var middle = graphene_point_t(x: Float(center.x), y: Float(center.y))
        var corner = graphene_point_t(x: Float(-size.width / 2), y: Float(-size.height / 2))
        var color = rgba(ink)
        gtk_snapshot_save(snapshot)
        gtk_snapshot_translate(snapshot, &middle)
        gtk_snapshot_rotate(snapshot, Float(degrees))
        gtk_snapshot_translate(snapshot, &corner)
        gtk_snapshot_append_layout(snapshot, text.layout, &color)
        gtk_snapshot_restore(snapshot)
    }

    private func label(_ string: String, _ position: ChartPoint, _ alignment: ChartPoint, _ ink: ChartInk) {
        let size = text.size(string)
        var origin = graphene_point_t(x: Float((position.x - size.width * alignment.x).rounded()),
                                      y: Float((position.y - size.height * alignment.y).rounded()))
        var color = rgba(ink)
        gtk_snapshot_save(snapshot)
        gtk_snapshot_translate(snapshot, &origin)
        gtk_snapshot_append_layout(snapshot, text.layout, &color)
        gtk_snapshot_restore(snapshot)
    }
}
