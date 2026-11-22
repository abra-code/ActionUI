// Sources/Elements/Chart+WinUI.swift
/*
 Chart on WinUI: what ChartLayout (ActionUIRendererShared, shared with the Linux renderer) lays out,
 drawn with Direct2D into a bitmap at the window's scale (the shim's Drawing API, as Canvas draws)
 and shown by a WinUI Image that fills the chart. Greedy in both axes with Color's ideal size, as
 Canvas is. Drawn again when the chart, the rows or the value change, when its size or the window's
 scale changes, and when the theme turns light or dark.

 The description is stored cleaned (Core/Elements/Chart.swift), and its warnings were logged then, so
 it parses without a logger here. Marks are read when the description, the rows or the value change.

 As the Linux renderer draws (Chart+Adwaita.swift):
 - Axis text is the theme's text color at 0.8 of the body size (14 points on Windows), in WinUI's text
   font (Segoe UI Variable).
 - A bar's rectangle is cut to its shape's rounded corners; a line's hollow symbols cut their holes out
   of that line alone; an effect (opacity, blur, shadow, offset) and a plot layer's opacity apply to
   what they hold as one group, as GSK's pushes do (Direct2D layers here).
 - Dates are the user's short date and time (Windows' own formats for the locale, as Linux's GLib
   fallback writes %x and %R); numbers are plain digits with a period, rounded to the axis's fraction
   digits (Linux's fallback without ICU).

 Selection (chartXSelection, chartYSelection, chartAngleSelection) and scrolling (chartScrollableAxes)
 as the Linux renderer takes them: a mouse or a pen selects a value or an angle by hovering and a range
 by dragging; a finger selects under it while it is down, and pans a chart that scrolls; the wheel and a
 touchpad move the scrolling axes' windows, a notch being the length shown to the power of 2/3, and leave
 the wheel to what holds the chart once a window is held at its end. The selection is the element's
 value (ChartSelection's JSON); a change by the user fires valueChangeActionID at once ("continuous", or
 a cleared selection) or once it has rested 150 ms ("settled").

 Annotations (annotation on a mark) as the Linux renderer places them: each a view of its own (a
 template row of the chart, made once and kept while the mark shows the same thing), placed beside its
 mark by ChartAnnotationPlacement in a layer over the marks, seen past the chart's edges as Swift Charts
 draws them, and along a scrolling axis only within the plot. Past 1000 annotations the marks are drawn
 without them, as Swift Charts does.

 Accessibility tools read the chart as its image, named by what its marks say (their accessibilityLabel
 and accessibilityValue), as on Linux, unless the chart has an accessibilityLabel of its own.

 Not yet: numbers in the user's locale (ICU, which Windows has as icu.dll, as Linux uses its ICU), the
 first weekday of the user's locale for week ticks.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
// cos, sin: FoundationEssentials does not bring the C math library on Windows.
#if canImport(Darwin)
import Darwin
#elseif os(Windows)
import ucrt
#endif
import CWinUI
// DispatchQueue: FoundationEssentials does not bring Dispatch on Windows.
import Dispatch

/// What a chart keeps: its layout and image, what it draws, and what it drew for.
@MainActor final class ChartState {
    let fill: FillLayout
    let image: WinUIObject
    var spec = ChartSpec()
    var marks = ChartResolvedMarks()
    /// Where the last drawing put the plot and how its axes ran.
    var geometry = ChartGeometry()
    /// The leading edges of the scrolling axes' windows, nil until the first drawing places them, and
    /// the scrolling they were placed for.
    var scroll: (x: Double?, y: Double?) = (nil, nil)
    var scrollSpec = ChartScrollSpec()
    var drawnSize: ActionUIWinUISize?
    var drawnScale: Double?
    var needsDrawing = true
    /// The annotation views: a layer over the image, as large as it, and in it the room where they are
    /// seen (the plot along a scrolling axis, clipped there; else the whole layer, unclipped).
    let annotationLayer: LayoutPanel
    let annotationRoom: LayoutPanel
    /// Each annotation's view by what it shows (reused while that stays), and by mark, in order.
    var annotations: [String: [ChartAnnotationView]] = [:]
    var annotationsByMark: [Int: [ChartAnnotationView]] = [:]
    var annotationsDropped = false
    /// Where the room's (0, 0) is in the chart's coordinates, and its clip (nil: none), from the layer's
    /// last arrange.
    var roomOrigin = ChartPoint(x: 0, y: 0)
    var roomClip: ActionUIWinUISize?
    /// The sizes the views asked for at the room's last measure.
    var annotationSizes: [ObjectIdentifier: ActionUIWinUISize] = [:]
    /// The node the user's selection is written to.
    weak var node: RenderNode?
    /// A press the chart took: where it went down, whether it moved, and whether a finger made it. A
    /// press that selects a range or a touch's values has `dragStart`; a finger's pan of a scrolling chart
    /// has `panStart`, the windows' leading edges when it began.
    var pressPoint: ChartPoint?
    var dragStart: ChartPoint?
    var dragMoved = false
    var dragTouch = false
    var panStart: (x: Double?, y: Double?)?
    /// Counts the writes of the selection: a "settled" action fires only when no later write came.
    var selectionWrites = 0

    init(fill: FillLayout, image: WinUIObject, annotationLayer: LayoutPanel, annotationRoom: LayoutPanel) {
        self.annotationLayer = annotationLayer
        self.annotationRoom = annotationRoom
        self.fill = fill
        self.image = image
    }
}

extension Chart: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .both }

    /// What accessibility tools read as the chart: its image (they do not see ActionUI's own panels).
    static func accessibleObject(_ view: WinUIObject, _ node: RenderNode) -> WinUIObject {
        (node.state as? ChartState)?.image ?? view
    }

    /// Named by what its marks say (their accessibilityLabel and accessibilityValue, the first 100 marks),
    /// as the Linux renderer names its chart; an accessibilityLabel on the chart itself comes first.
    static func defaultAccessibleName(_ node: RenderNode) -> String? {
        (node.state as? ChartState)?.marks.accessibleName
    }

    /// Swift Charts' axis text next to body text (caption2), as the Linux renderer sizes it.
    static let axisFontSize = 14.0 * 0.8

    /// How far the chart's image reaches past the chart on every side: one line of axis text. The layout
    /// draws some text outside the chart's bounds, as Swift Charts does (the top y label, centered on the
    /// top gridline, reaches half a line above the chart; a label at a plot's end may pass its side).
    /// A multiple of 4 points, so it is whole pixels at every scale Windows offers (steps of 25%): the
    /// layout rounds the image's place and size to pixels, and the chart's (0, 0) stays on the panel's.
    static let overflowMargin: Double = {
        var width = 0.0, height = 0.0
        guard actionUIWinUIMeasureText("0", axisFontSize, 400, &width, &height), height.isFinite, height > 0 else {
            return 16
        }
        return (height / 4).rounded(.up) * 4
    }()

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let image = WinUIObject(adopting: actionUIWinUIImageCreate()) else {
            throw WinUIError.last("creating a Chart's image")
        }
        let fill = try FillLayout(child: image)
        // The image reaches past the chart (overflowMargin) for the text drawn outside it; that margin takes no
        // pointer input from what is around the chart: the chart's own panel takes the input.
        fill.childOutset = overflowMargin
        if !actionUIWinUIElementSetHitTestVisible(image.pointer, false) {
            ActionUIModel.shared.logger.log("Chart: \(WinUIError.last("letting the pointer through a chart's image"))", .error)
        }
        // A panel takes the pointer only where something is drawn in it unless it has a background: the whole chart
        // takes it (its hover, help and tap).
        var clear = ActionUIWinUIColor(red: 0, green: 0, blue: 0, alpha: 0)
        if !actionUIWinUIElementSetBrush(fill.panel.object.pointer, ActionUIWinUIBrushBackground, &clear, nil) {
            ActionUIModel.shared.logger.log("Chart: \(WinUIError.last("giving a chart's panel a background"))", .error)
        }
        // The annotation layer over the marks, the room in it.
        let room = try LayoutPanel()
        let layer = try LayoutPanel()
        try layer.append(room.object)
        try fill.panel.append(layer.object)
        let state = ChartState(fill: fill, image: image, annotationLayer: layer, annotationRoom: room)
        layer.measure = { [weak state] available in
            _ = state?.annotationRoom.object.measure(available)
            return ActionUIWinUISize(width: 0, height: 0)
        }
        layer.arrange = { [weak state] size in
            guard let state else { return }
            arrangeAnnotationLayer(state, size: size)
        }
        room.measure = { [weak state] _ in
            guard let state else { return ActionUIWinUISize(width: 0, height: 0) }
            // Each view at the size it asks for, as Linux measures its natural size.
            let unbounded = ActionUIWinUISize(width: .infinity, height: .infinity)
            var sizes: [ObjectIdentifier: ActionUIWinUISize] = [:]
            for view in state.annotations.values.joined() {
                sizes[ObjectIdentifier(view)] = view.holder.object.measureRequested(unbounded)
            }
            state.annotationSizes = sizes
            return ActionUIWinUISize(width: 0, height: 0)
        }
        room.arrange = { [weak state] _ in
            guard let state else { return }
            placeAnnotations(state)
        }
        state.node = node
        node.state = state
        ChartInput.connect(fill.panel.object) { [weak state] input in
            guard let state else { return false }
            return Chart.input(state, input)
        }
        fill.arranged = { [weak state] size in
            guard let state else { return }
            drawIfNeeded(state, size: size)
        }
        // The axes and the text are the theme's text color: drawn again in the new theme.
        WinUIEvents.connect(fill.panel.object, actionUIWinUIElementOnActualThemeChanged, "a Chart's theme") { [weak state] in
            guard let state else { return }
            state.needsDrawing = true
            state.fill.panel.invalidateLayout()
        }
        return fill.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? ChartState else { return }
        let description = node.properties["chart"] as? [String: Any] ?? [:]
        let rows = node.model.states["content"] as? [[String]] ?? []
        state.spec = ChartDescription.parse(description, logger: nil).spec
        if state.spec.scroll != state.scrollSpec {
            state.scrollSpec = state.spec.scroll
            state.scroll = (nil, nil)
        }
        let selection = ChartSelection.decode(node.model.value as? String, spec: state.spec.selection)
        state.marks = ChartMarkResolver.resolve(state.spec, rows: rows, selection: selection)
        report(state, viewID: node.element.id)
        syncAnnotations(node, state)
        state.needsDrawing = true
        if let size = state.drawnSize {
            drawIfNeeded(state, size: size)
        }
    }

    private static func report(_ state: ChartState, viewID: Int) {
        let logger = ActionUIModel.shared.logger
        if state.marks.skippedRows > 0, let first = state.marks.firstSkip {
            let place = first.inlineData ? "row \(first.row + 1) of a ForEach's data" : "row \(first.row + 1)"
            logger.log("Chart \(viewID): skipped \(state.marks.skippedRows) row(s) with a cell that does not parse; first: \(place), column \(first.column + 1) is not a \(first.type.rawValue)", .warning)
        }
    }

    /// Lays the chart out and draws it for `size` when it, the size or the window's scale changed
    /// since the last drawing.
    private static func drawIfNeeded(_ state: ChartState, size: ActionUIWinUISize) {
        let scale = actionUIWinUIElementRasterizationScale(state.image.pointer)
        // Within a hundredth of a point: the annotation layer asks with its own size less the margins, which
        // at a fractional scale can differ from the chart's in the last bits (WinUI's sizes are floats,
        // rounded to pixels), and would draw the chart again.
        let sameSize = state.drawnSize.map { abs($0.width - size.width) < 0.01 && abs($0.height - size.height) < 0.01 } ?? false
        guard state.needsDrawing || !sameSize || state.drawnScale != scale else { return }
        state.needsDrawing = false
        state.drawnSize = size
        state.drawnScale = scale
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return }
        let text = ChartAxisText()
        let metrics = ChartTextMetrics(
            size: { text.size($0) },
            number: { ChartFormatting.number($0, digits: $1...$1) },
            formatted: { ChartFormatting.number($0, format: $1) },
            date: { ChartFormatting.date($0, skeleton: $1) })
        let (primitives, geometry) = ChartLayout.laidOut(state.spec, marks: state.marks, width: size.width, height: size.height,
                                                         metrics: metrics, scroll: state.scroll)
        state.geometry = geometry
        // The views follow the new layout; the layer places the room again, whose frame and clip along a
        // scrolling axis are the plot's, which new data (wider axis labels) can move at the same size.
        if !state.annotations.isEmpty {
            state.annotationRoom.invalidateLayout()
            state.annotationLayer.invalidateLayout()
        }
        state.scroll = (geometry.xScroll?.leading, geometry.yScroll?.leading)
        // The chart's points from (margin, margin) in an image as much larger on every side.
        let margin = overflowMargin
        guard let drawing = actionUIWinUIDrawingBegin(size.width + 2 * margin, size.height + 2 * margin, scale) else {
            ActionUIModel.shared.logger.log("Chart: \(WinUIError.last("starting a drawing of \(size.width) x \(size.height)"))", .error)
            return
        }
        let painter = ChartDrawing(drawing: drawing, text: text, foreground: actionUIWinUIThemeTextColor(),
                                   origin: ChartPoint(x: margin, y: margin))
        for primitive in primitives {
            painter.draw(primitive)
        }
        painter.finish()
        if !actionUIWinUIDrawingFinish(drawing, state.image.pointer) {
            ActionUIModel.shared.logger.log("Chart: \(WinUIError.last("showing the drawing"))", .error)
        }
    }

    // MARK: Annotations

    /// Swift Charts' limit, past which a chart draws its marks without annotations (ChartRenderCache).
    static let maxAnnotations = 1000

    /// Makes a view for each annotation of the marks, keeping the ones that show the same thing (as the
    /// Linux renderer: by the annotation's place on its mark, its content and the row it reads).
    private static func syncAnnotations(_ node: RenderNode, _ state: ChartState) {
        var wanted: [(instance: Int, spec: ChartAnnotationSpec, key: String, row: Int, cells: [String])] = []
        for (index, instance) in state.marks.instances.enumerated() {
            var ordinal = 0
            for modifier in instance.mark.modifiers {
                guard case .annotation(let spec) = modifier else { continue }
                // As on Apple (ChartContentBuilder): one that reads no row gets none, and -1 as its row.
                let row = spec.readsRows ? instance.row ?? -1 : -1
                let cells = spec.readsRows ? instance.annotationRow : []
                // Template ids are numbered alike in every annotation, so the content itself is compared
                // too, when a view is reused.
                let key = "\(ordinal)\u{1F}\(spec.content.id)\u{1F}\(row)\u{1F}" + cells.joined(separator: "\u{1F}")
                wanted.append((index, spec, key, row, cells))
                ordinal += 1
            }
        }
        if wanted.count > maxAnnotations {
            if !state.annotationsDropped {
                ActionUIModel.shared.logger.log("Chart \(node.element.id): \(wanted.count) annotations (more than \(maxAnnotations)); drawing the marks without them", .warning)
            }
            state.annotationsDropped = true
            wanted = []
        } else {
            state.annotationsDropped = false
        }
        var unused = state.annotations
        var kept: [String: [ChartAnnotationView]] = [:]
        var byMark: [Int: [ChartAnnotationView]] = [:]
        for item in wanted {
            let view: ChartAnnotationView
            if let index = unused[item.key]?.firstIndex(where: { ($0.node.element as? ActionUIElement) == item.spec.content }) {
                view = unused[item.key]!.remove(at: index)
            } else {
                let annotation = node.templateRowNode(item.spec.content, row: item.cells, rowIndex: item.row)
                guard let content = annotation.outerView else {
                    node.releaseTemplateNode(annotation)
                    continue
                }
                do {
                    view = try ChartAnnotationView(node: annotation, view: content)
                    try state.annotationRoom.append(view.holder.object)
                } catch {
                    ActionUIModel.shared.logger.log("Chart \(node.element.id): \(error)", .error)
                    node.releaseTemplateNode(annotation)
                    continue
                }
            }
            kept[item.key, default: []].append(view)
            byMark[item.instance, default: []].append(view)
        }
        for old in unused.values.joined() {
            if let index = state.annotationRoom.children.firstIndex(where: { $0 === old.holder.object }) {
                do {
                    try state.annotationRoom.remove(at: index)
                } catch {
                    ActionUIModel.shared.logger.log("Chart \(node.element.id): \(error)", .error)
                }
            }
            node.releaseTemplateNode(old.node)
        }
        state.annotations = kept
        state.annotationsByMark = byMark
        state.annotationRoom.invalidateLayout()
    }

    /// The annotation layer, as large as the image (the chart and overflowMargin around it): lays the chart
    /// out for its size first, then places the room where views are seen.
    private static func arrangeAnnotationLayer(_ state: ChartState, size: ActionUIWinUISize) {
        let margin = overflowMargin
        let chartSize = ActionUIWinUISize(width: size.width - 2 * margin, height: size.height - 2 * margin)
        drawIfNeeded(state, size: chartSize)
        // Seen anywhere, past the chart's edges too, as Swift Charts draws them (Linux measured it on macOS
        // 27); along a scrolling axis only the plot, where the marks stop.
        let geometry = state.geometry
        var frame = ActionUIWinUIRect(x: 0, y: 0, width: size.width, height: size.height)
        var clipped = false
        if geometry.xScroll != nil {
            (frame.x, frame.width) = (geometry.plot.x + margin, geometry.plot.width)
            clipped = true
        }
        if geometry.yScroll != nil {
            (frame.y, frame.height) = (geometry.plot.y + margin, geometry.plot.height)
            clipped = true
        }
        state.roomOrigin = ChartPoint(x: frame.x - margin, y: frame.y - margin)
        let clip = clipped ? ActionUIWinUISize(width: frame.width, height: frame.height) : nil
        if clip?.width != state.roomClip?.width || clip?.height != state.roomClip?.height {
            state.roomClip = clip
            if !actionUIWinUIElementSetClipSize(state.annotationRoom.object.pointer, clip?.width ?? -1, clip?.height ?? -1) {
                ActionUIModel.shared.logger.log("Chart: \(WinUIError.last("clipping a chart's annotations"))", .error)
            }
        }
        state.annotationRoom.object.arrange(frame)
    }

    /// Places each annotation view beside its mark; one whose mark is not drawn, or that falls outside the
    /// room, is hidden (neither drawn nor taking the pointer).
    private static func placeAnnotations(_ state: ChartState) {
        let geometry = state.geometry
        var room = ChartRect(x: -100_000, y: -100_000, width: geometry.chart.width + 200_000, height: geometry.chart.height + 200_000)
        if geometry.xScroll != nil { (room.x, room.width) = (geometry.plot.x, geometry.plot.width) }
        if geometry.yScroll != nil { (room.y, room.height) = (geometry.plot.y, geometry.plot.height) }
        var placed = Set<ObjectIdentifier>()
        for frame in geometry.annotations {
            guard let views = state.annotationsByMark[frame.instance], frame.ordinal < views.count,
                  frame.instance < state.marks.instances.count else { continue }
            let view = views[frame.ordinal]
            let specs = state.marks.instances[frame.instance].mark.modifiers.compactMap { modifier -> ChartAnnotationSpec? in
                if case .annotation(let spec) = modifier { return spec }
                return nil
            }
            guard frame.ordinal < specs.count, let size = state.annotationSizes[ObjectIdentifier(view)] else { continue }
            let rect = ChartAnnotationPlacement.place(specs[frame.ordinal], frame: frame.frame, center: frame.center,
                                                      size: ChartSize(width: size.width, height: size.height),
                                                      plot: geometry.plot, chart: geometry.chart)
            guard rect.x < room.x + room.width, rect.x + rect.width > room.x,
                  rect.y < room.y + room.height, rect.y + rect.height > room.y else { continue }
            view.holder.object.arrange(ActionUIWinUIRect(x: (rect.x - state.roomOrigin.x).rounded(), y: (rect.y - state.roomOrigin.y).rounded(),
                                                         width: size.width, height: size.height))
            view.show(true)
            placed.insert(ObjectIdentifier(view))
        }
        for view in state.annotations.values.joined() where !placed.contains(ObjectIdentifier(view)) {
            view.holder.object.arrange(ActionUIWinUIRect(x: 0, y: 0, width: 0, height: 0))
            view.show(false)
        }
    }

    // MARK: Selection and scrolling

    /// The settle time of a "settled" selection action (Apple's ChartSelectionBinder.settleDelay).
    static let settleMilliseconds = 150

    /// The pointer's input over the chart, as the Linux renderer takes it: a mouse or a pen selects values
    /// by hovering and a range by dragging; a finger selects under it while it is down, and pans a chart
    /// that scrolls; the wheel and a touchpad scroll. Returns whether the chart took the event.
    static func input(_ state: ChartState, _ input: ActionUIWinUIPointerInput) -> Bool {
        let point = ChartPoint(x: input.x, y: input.y)
        switch input.kind {
        case ActionUIWinUIPointerInputPressed:
            return pressed(state, at: point, touch: input.touch)
        case ActionUIWinUIPointerInputMoved:
            if let start = state.panStart, let origin = state.pressPoint {
                pan(state, from: start, dx: point.x - origin.x, dy: point.y - origin.y)
                return true
            }
            // A mouse or a pen: the values follow it, during a drag too.
            if !input.touch {
                hover(state, at: point)
            }
            guard let start = state.dragStart else { return false }
            if point.x != start.x || point.y != start.y || state.dragMoved {
                state.dragMoved = true
                dragged(state, from: start, to: point, touch: state.dragTouch)
            }
            return true
        case ActionUIWinUIPointerInputReleased:
            let took = ended(state)
            // A leave during the press was not acted on, and Windows may not report it again after the
            // release: a mouse or a pen let go outside the chart clears what follows it.
            if took, !input.touch, let size = state.drawnSize,
               point.x < 0 || point.y < 0 || point.x > size.width || point.y > size.height {
                clearValues(state)
            }
            return took
        case ActionUIWinUIPointerInputCanceled:
            // After a release Windows reports the capture's end too: nothing is held then.
            _ = ended(state)
            return false
        case ActionUIWinUIPointerInputExited:
            guard state.dragStart == nil, state.panStart == nil else { return false }
            clearValues(state)
            return false
        case ActionUIWinUIPointerInputWheel:
            return scrolled(state, dx: input.wheelX, dy: input.wheelY)
        default:
            return false
        }
    }

    private static func pressed(_ state: ChartState, at point: ChartPoint, touch: Bool) -> Bool {
        // One press at a time: a second finger is not taken while the first holds the chart (Windows does not
        // say here which pointer a move is from).
        guard state.pressPoint == nil else { return false }
        // A finger on a scrolling chart moves its window.
        if touch, state.geometry.xScroll != nil || state.geometry.yScroll != nil {
            state.panStart = state.scroll
            state.pressPoint = point
            return true
        }
        let spec = state.spec.selection
        let selectsRange = spec.x == .range || spec.y == .range
        // Only a chart that selects takes the press; another leaves it to what holds the chart.
        guard selectsRange || (touch && !spec.isEmpty) else { return false }
        state.pressPoint = point
        state.dragStart = point
        state.dragMoved = false
        state.dragTouch = touch
        // A finger shows the values under it at once; a range waits for the drag to move.
        if touch {
            write(state) { setValues(&$0, state, at: point) }
        }
        return true
    }

    /// The press the chart took ended (a release or a cancel): a pan stops; a drag's range and a finger's
    /// values go, as Swift Charts clears them. Returns whether a press was held.
    private static func ended(_ state: ChartState) -> Bool {
        state.pressPoint = nil
        if state.panStart != nil {
            state.panStart = nil
            return true
        }
        guard state.dragStart != nil else { return false }
        state.dragStart = nil
        let touch = state.dragTouch
        // A click that did not move selected no range: there is nothing to clear.
        guard state.dragMoved || touch else { return true }
        write(state) { selection in
            let spec = state.spec.selection
            if spec.x == .range || (touch && spec.x == .value) { selection.x = nil }
            if spec.y == .range || (touch && spec.y == .value) { selection.y = nil }
            if touch && spec.angle {
                selection.angle = nil
                selection.row = nil
            }
        }
        return true
    }

    /// A wheel's turn of (dx, dy) notches: moves the windows of the axes that scroll, a notch being the
    /// length shown to the power of 2/3, as GTK's scrolled window steps (the Linux renderer's rule).
    /// Returns whether a window moved; one held at its end leaves the wheel to what holds the chart.
    private static func scrolled(_ state: ChartState, dx: Double, dy: Double) -> Bool {
        let geometry = state.geometry
        guard geometry.xScroll != nil || geometry.yScroll != nil else { return false }
        var dx = dx, dy = dy
        // Only the horizontal axis scrolls: a vertical wheel moves it.
        if geometry.yScroll == nil, dx == 0 {
            (dx, dy) = (dy, 0)
        }
        dx *= pow(geometry.plot.width, 2.0 / 3)
        dy *= pow(geometry.plot.height, 2.0 / 3)
        return move(state, from: state.scroll, dx: dx, dy: dy)
    }

    /// A finger's pan by (dx, dy) points from where the windows were when it began: the content follows
    /// the finger.
    private static func pan(_ state: ChartState, from start: (x: Double?, y: Double?), dx: Double, dy: Double) {
        _ = move(state, from: start, dx: -dx, dy: -dy)
    }

    /// Moves the windows `dx` points toward the trailing edge and `dy` points down from `start`, and draws
    /// the chart again.
    private static func move(_ state: ChartState, from start: (x: Double?, y: Double?), dx: Double, dy: Double) -> Bool {
        let geometry = state.geometry
        var next = state.scroll
        // Down the plot: lower numbers on a rising axis (points per unit below 0), later bands and dates.
        if let window = geometry.xScroll, let leading = start.x, window.pointsPerUnit != 0 {
            next.x = window.held(leading + dx / window.pointsPerUnit)
        }
        if let window = geometry.yScroll, let leading = start.y, window.pointsPerUnit != 0 {
            next.y = window.held(leading + dy / window.pointsPerUnit)
        }
        guard next.x != state.scroll.x || next.y != state.scroll.y else { return false }
        state.scroll = next
        state.needsDrawing = true
        if let size = state.drawnSize {
            drawIfNeeded(state, size: size)
        }
        return true
    }

    /// The pointer over the chart: the values and the angle selected by value follow it.
    private static func hover(_ state: ChartState, at point: ChartPoint) {
        let spec = state.spec.selection
        guard spec.x == .value || spec.y == .value || spec.angle else { return }
        write(state) { selection in
            setValues(&selection, state, at: point)
        }
    }

    private static func setValues(_ selection: inout ChartSelection, _ state: ChartState, at point: ChartPoint) {
        let spec = state.spec.selection
        let geometry = state.geometry
        if spec.x == .value {
            selection.x = ChartSelectionHit.value(at: point, .horizontal, type: spec.xType, geometry: geometry).map { .value($0) }
        }
        if spec.y == .value {
            selection.y = ChartSelectionHit.value(at: point, .vertical, type: spec.yType, geometry: geometry).map { .value($0) }
        }
        if spec.angle {
            let hit = ChartSelectionHit.angle(at: point, marks: state.marks, type: spec.angleType, geometry: geometry)
            selection.angle = hit?.angle
            selection.row = hit?.row
        }
    }

    /// A drag from `start` to `end`: the range it covers on an axis that selects a range, and for a finger
    /// the values under it.
    private static func dragged(_ state: ChartState, from start: ChartPoint, to end: ChartPoint, touch: Bool) {
        let spec = state.spec.selection
        write(state) { selection in
            if spec.x == .range {
                selection.x = ChartSelectionHit.range(from: start, to: end, .horizontal, type: spec.xType, geometry: state.geometry)
            }
            if spec.y == .range {
                selection.y = ChartSelectionHit.range(from: start, to: end, .vertical, type: spec.yType, geometry: state.geometry)
            }
            if touch {
                setValues(&selection, state, at: end)
            }
        }
    }

    /// The pointer left the chart: what follows it goes.
    private static func clearValues(_ state: ChartState) {
        let spec = state.spec.selection
        write(state) { selection in
            if spec.x == .value { selection.x = nil }
            if spec.y == .value { selection.y = nil }
            if spec.angle {
                selection.angle = nil
                selection.row = nil
            }
        }
    }

    /// Applies `change` to the selection the value holds, stores it when it differs, and fires the action
    /// as selectionActionTiming says. The sync the new value causes draws the marks that read it.
    private static func write(_ state: ChartState, _ change: (inout ChartSelection) -> Void) {
        guard let node = state.node, node.isAttached, !state.spec.selection.isEmpty else { return }
        let spec = state.spec.selection
        let before = node.model.value as? String ?? ""
        var selection = ChartSelection.decode(before, spec: spec)
        change(&selection)
        let after = selection.encode(spec: spec)
        guard after != before else { return }
        node.model.value = after
        state.selectionWrites += 1
        let props = Props(node.properties)
        guard let actionID = props.valueChangeActionID else { return }
        let windowUUID = node.windowModel.windowUUID
        let viewID = node.element.id
        let origin = LinkTrust.origin(node)
        let fire = { ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: viewID, viewPartID: 0, origin: origin) }
        if props.selectionActionTiming == .continuous || after.isEmpty {
            fire()
            return
        }
        let count = state.selectionWrites
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(settleMilliseconds)) { [weak state] in
            MainActor.assumeIsolated {
                guard let state, state.selectionWrites == count, state.node?.isAttached == true else { return }
                fire()
            }
        }
    }
}

/// Swift closures as a chart's pointer input handler (actionUIWinUIElementOnPointerInput), held by the
/// shim as WinUIEvents' handlers are.
@MainActor private final class ChartInputBox {
    let action: @MainActor (ActionUIWinUIPointerInput) -> Bool

    init(_ action: @escaping @MainActor (ActionUIWinUIPointerInput) -> Bool) {
        self.action = action
    }
}

private let fireChartInput: ActionUIWinUIPointerInputCallback = { context, input in
    guard let context, let input else { return false }
    let box = Unmanaged<ChartInputBox>.fromOpaque(context).takeUnretainedValue()
    let event = input.pointee
    return MainActor.assumeIsolated {
        box.action(event)
    }
}

private let releaseChartInput: ActionUIWinUICallback = { context in
    guard let context else { return }
    Unmanaged<ChartInputBox>.fromOpaque(context).release()
}

@MainActor enum ChartInput {
    /// Reports `element`'s pointer input to `action`, in its own coordinates.
    static func connect(_ element: WinUIObject, _ action: @escaping @MainActor (ActionUIWinUIPointerInput) -> Bool) {
        let context = Unmanaged.passRetained(ChartInputBox(action)).toOpaque()
        // On failure the shim has already called releaseChartInput.
        if !actionUIWinUIElementOnPointerInput(element.pointer, element.pointer, fireChartInput, context, releaseChartInput) {
            ActionUIModel.shared.logger.log("Chart: \(WinUIError.last("watching the pointer's input"))", .error)
        }
    }
}

/// One annotation's view, in a panel of its own that the chart shows or hides without touching the view
/// (its own opacity, its clip).
@MainActor final class ChartAnnotationView {
    let node: RenderNode
    let holder: LayoutPanel
    private var shown = true

    init(node: RenderNode, view: WinUIObject) throws(WinUIError) {
        self.node = node
        let panel = try LayoutPanel()
        try panel.append(view)
        panel.measure = { [unowned panel] available in
            panel.children.first?.measureRequested(available) ?? ActionUIWinUISize(width: 0, height: 0)
        }
        panel.arrange = { [unowned panel] size in
            panel.children.first?.arrange(ActionUIWinUIRect(x: 0, y: 0, width: size.width, height: size.height))
        }
        holder = panel
    }

    /// Shows the view, or hides it from the eye and the pointer.
    func show(_ visible: Bool) {
        guard visible != shown else { return }
        shown = visible
        if !actionUIWinUIElementSetOpacity(holder.object.pointer, visible ? 1 : 0)
            || !actionUIWinUIElementSetHitTestVisible(holder.object.pointer, visible) {
            ActionUIModel.shared.logger.log("Chart: \(WinUIError.last("showing or hiding an annotation"))", .error)
        }
    }
}

/// The axis font's measurements, kept for one drawing (a label is measured by the layout and again
/// when it is drawn).
@MainActor final class ChartAxisText {
    private var sizes: [String: ChartSize] = [:]

    func size(_ text: String) -> ChartSize {
        if let known = sizes[text] {
            return known
        }
        var width = 0.0, height = 0.0
        if !actionUIWinUIMeasureText(text, Chart.axisFontSize, 400, &width, &height) {
            width = 0
            height = 0
        }
        let size = ChartSize(width: width, height: height)
        sizes[text] = size
        return size
    }
}

/// Numbers and dates on a chart's axes, until the user's locale formats them (ICU): numbers as plain
/// digits with a period (Linux's fallback without ICU), dates in Windows' own short forms for the user's
/// locale.
@MainActor enum ChartFormatting {
    /// The fraction digits a format shows, as Linux's NumberFormatting takes them.
    private static func fractionDigits(_ format: NumberFormatSpec) -> ClosedRange<Int>? {
        switch format {
        case .integer:
            return 0...0
        case .decimal(let minimum, let maximum), .percent(let minimum, let maximum):
            return NumberFormatSpec.fractionRange(minFraction: minimum, maxFraction: maximum) ?? 0...6
        case .currency(_, let minimum, let maximum):
            return NumberFormatSpec.fractionRange(minFraction: minimum, maxFraction: maximum)
        }
    }

    static func number(_ value: Double, format: NumberFormatSpec) -> String {
        let digits = fractionDigits(format) ?? 2...2
        let shown: String
        switch format {
        case .percent: shown = number(value * 100, digits: digits) + "%"
        case .currency(let code, _, _): shown = code + " " + number(value, digits: digits)
        default: shown = number(value, digits: digits)
        }
        return shown
    }

    /// `value` rounded to `digits.upperBound` fraction digits (an exact half to even, as the C library's
    /// %.*f rounds it), the trailing zeros past `digits.lowerBound` left out, with a period. A value too
    /// large to keep that many digits in 64 bits shows zeros in its last places (a double that large has
    /// no digits there); one past 64 bits is in Swift's own form.
    static func number(_ value: Double, digits: ClosedRange<Int>) -> String {
        guard value.isFinite else { return String(value) }
        func power(_ count: Int) -> Double {
            var result = 1.0
            for _ in 0..<count { result *= 10 }
            return result
        }
        let wanted = min(max(digits.upperBound, 0), 15)
        var places = wanted
        while places > 0, abs(value) * power(places) >= 9.0e15 {
            places -= 1
        }
        let scaled = (abs(value) * power(places)).rounded(.toNearestOrEven)
        guard scaled < 1.8e19 else { return String(value) }
        let whole = UInt64(scaled)
        let unit = UInt64(power(places))
        var text = String(whole / unit)
        var fraction = places > 0 ? String(whole % unit) : ""
        fraction = String(repeating: "0", count: places - fraction.count) + fraction + String(repeating: "0", count: wanted - places)
        while fraction.count > max(digits.lowerBound, 0), fraction.last == "0" {
            fraction.removeLast()
        }
        if !fraction.isEmpty {
            text += "." + fraction
        }
        return value < 0 && whole != 0 ? "-" + text : text
    }

    /// The skeleton's date and time fields as the user's short date and time (hours and minutes).
    static func date(_ date: Date, skeleton: String) -> String {
        let hasDate = skeleton.contains { "GyYuUQqMLwWdDFgEec".contains($0) }
        let hasTime = skeleton.contains { "jJCahHkKmsSA".contains($0) }
        guard let text = actionUIWinUICopyLocalDateText(date.timeIntervalSince1970, hasDate || !hasTime, hasTime) else {
            return ""
        }
        defer { actionUIWinUIFreeString(text) }
        return String(cString: text)
    }
}

/// Draws the primitives of one chart into a drawing.
@MainActor private final class ChartDrawing {
    let drawing: OpaquePointer
    let text: ChartAxisText
    let foreground: ActionUIWinUIColor
    /// The translation of what is drawn now (the effects' offsets), and what each open effect or plot
    /// layer pushed: how many layers to end.
    private var offsets: [ChartPoint]
    private var effectLayers: [Int] = []
    private var plotLayers: [Int] = []
    private var failed = false

    /// `origin`: where the chart's (0, 0) is in the drawing.
    init(drawing: OpaquePointer, text: ChartAxisText, foreground: ActionUIWinUIColor, origin: ChartPoint) {
        offsets = [origin]
        self.drawing = drawing
        self.text = text
        self.foreground = foreground
    }

    /// Ends what a layout left open, and logs the first failure of the drawing.
    func finish() {
        for count in (effectLayers + plotLayers).reversed() {
            for _ in 0..<count { _ = actionUIWinUIDrawingEndLayer(drawing) }
        }
        effectLayers = []
        plotLayers = []
    }

    private func check(_ done: Bool, _ what: String) {
        if !done, !failed {
            failed = true
            ActionUIModel.shared.logger.log("Chart: \(WinUIError.last(what))", .error)
        }
    }

    // MARK: Colors

    private func color(_ ink: ChartInk) -> ActionUIWinUIColor {
        switch ink {
        case .color(let color):
            return ColorRGBA.resolve(color)
        case .text(let opacity):
            var color = foreground
            color.alpha *= opacity
            return color
        case let .blend(colors, share):
            return blend(colors.map(ColorRGBA.resolve), at: share)
        }
    }

    // Over premultiplied colors, as the Linux renderer (GSK's gradients) blends them.
    private func blend(_ colors: [ActionUIWinUIColor], at share: Double) -> ActionUIWinUIColor {
        guard colors.count > 1 else { return colors.first ?? ActionUIWinUIColor(red: 0, green: 0, blue: 0, alpha: 0) }
        let place = share * Double(colors.count - 1)
        let index = min(max(Int(place), 0), colors.count - 2)
        let part = place - Double(index), from = colors[index], to = colors[index + 1]
        let alpha = from.alpha + (to.alpha - from.alpha) * part
        guard alpha > 0 else { return ActionUIWinUIColor(red: 0, green: 0, blue: 0, alpha: 0) }
        func mixed(_ a: Double, _ b: Double) -> Double {
            (a * from.alpha + (b * to.alpha - a * from.alpha) * part) / alpha
        }
        return ActionUIWinUIColor(red: mixed(from.red, to.red), green: mixed(from.green, to.green), blue: mixed(from.blue, to.blue),
                                  alpha: alpha)
    }

    // MARK: Paths

    /// Starts a path under the current offset; false when the drawing refused it.
    private func begin(rotation degrees: Double = 0, around center: ChartPoint? = nil) -> Bool {
        let offset = offsets.last!
        guard let center, degrees != 0 else {
            return actionUIWinUIDrawingSetTransform(drawing, 1, 0, 0, 1, offset.x, offset.y)
        }
        let radians = degrees * Double.pi / 180
        let cosine = cos(radians), sine = sin(radians)
        // Rotated about `center` (clockwise for positive degrees, y down), then offset.
        let tx = center.x - cosine * center.x + sine * center.y + offset.x
        let ty = center.y - sine * center.x - cosine * center.y + offset.y
        return actionUIWinUIDrawingSetTransform(drawing, cosine, sine, -sine, cosine, tx, ty)
    }

    private func send(_ elements: [ChartPathElement]) -> Bool {
        var sent = true
        for element in elements {
            switch element {
            case .move(let point):
                sent = actionUIWinUIDrawingMoveTo(drawing, point.x, point.y) && sent
            case .line(let point):
                sent = actionUIWinUIDrawingLineTo(drawing, point.x, point.y) && sent
            case let .curve(first, second, end):
                sent = actionUIWinUIDrawingCubicTo(drawing, first.x, first.y, second.x, second.y, end.x, end.y) && sent
            case .close:
                sent = actionUIWinUIDrawingClose(drawing) && sent
            }
        }
        return sent
    }

    private func fill(_ elements: [ChartPathElement], _ ink: ChartInk) {
        guard !elements.isEmpty else { return }
        check(begin() && send(elements) && actionUIWinUIDrawingFill(drawing, color(ink)), "filling a chart's shape")
    }

    private func stroke(_ elements: [ChartPathElement], _ ink: ChartInk, _ style: ChartStroke) {
        guard !elements.isEmpty, style.lineWidth > 0 else { return }
        let cap: ActionUIWinUILineCap
        switch style.lineCap {
        case .butt: cap = ActionUIWinUILineCapButt
        case .round: cap = ActionUIWinUILineCapRound
        case .square: cap = ActionUIWinUILineCapSquare
        }
        let join: ActionUIWinUILineJoin
        switch style.lineJoin {
        case .miter: join = ActionUIWinUILineJoinMiter
        case .round: join = ActionUIWinUILineJoinRound
        case .bevel: join = ActionUIWinUILineJoinBevel
        }
        let dashes = style.dash.map { max($0, 0) }
        let stroked = begin() && send(elements) && dashes.withUnsafeBufferPointer { buffer in
            actionUIWinUIDrawingStroke(drawing, color(ink), style.lineWidth, cap, join, max(style.miterLimit, 0),
                                       buffer.isEmpty ? nil : buffer.baseAddress, Int32(buffer.count), style.dashPhase)
        }
        check(stroked, "stroking a chart's line")
    }

    private static func rectangle(_ rect: ChartRect) -> [ChartPathElement] {
        [.move(ChartPoint(x: rect.x, y: rect.y)), .line(ChartPoint(x: rect.x + rect.width, y: rect.y)),
         .line(ChartPoint(x: rect.x + rect.width, y: rect.y + rect.height)), .line(ChartPoint(x: rect.x, y: rect.y + rect.height)),
         .close]
    }

    /// A rectangle with its corners rounded by `corners` (circular, each at most half the shorter side),
    /// clockwise on the screen.
    private static func rounded(_ rect: ChartRect, _ corners: ChartCorners) -> [ChartPathElement] {
        let limit = max(min(rect.width, rect.height) / 2, 0)
        let tl = min(max(corners.topLeading, 0), limit), tr = min(max(corners.topTrailing, 0), limit)
        let br = min(max(corners.bottomTrailing, 0), limit), bl = min(max(corners.bottomLeading, 0), limit)
        guard tl > 0 || tr > 0 || br > 0 || bl > 0 else { return rectangle(rect) }
        // A quarter circle as one cubic.
        let k = 0.5522847498
        let left = rect.x, top = rect.y, right = rect.x + rect.width, bottom = rect.y + rect.height
        func point(_ x: Double, _ y: Double) -> ChartPoint { ChartPoint(x: x, y: y) }
        var path: [ChartPathElement] = [.move(point(left + tl, top)), .line(point(right - tr, top))]
        if tr > 0 { path.append(.curve(point(right - tr + tr * k, top), point(right, top + tr - tr * k), point(right, top + tr))) }
        path.append(.line(point(right, bottom - br)))
        if br > 0 { path.append(.curve(point(right, bottom - br + br * k), point(right - br + br * k, bottom), point(right - br, bottom))) }
        path.append(.line(point(left + bl, bottom)))
        if bl > 0 { path.append(.curve(point(left + bl - bl * k, bottom), point(left, bottom - bl + bl * k), point(left, bottom - bl))) }
        path.append(.line(point(left, top + tl)))
        if tl > 0 { path.append(.curve(point(left, top + tl - tl * k), point(left + tl - tl * k, top), point(left + tl, top))) }
        path.append(.close)
        return path
    }

    // MARK: Primitives

    func draw(_ primitive: ChartPrimitive) {
        switch primitive {
        case let .line(from, to, ink, stroke):
            line(from, to, ink, stroke)
        case let .rect(rect, ink):
            fill(Self.rectangle(rect), ink)
        case let .bar(rect, shape, corners, ink):
            bar(rect, shape, corners, ink)
        case let .symbol(shape, center, side, ink):
            fill(ChartSymbols.outline(shape, center: center, side: side), ink)
        case let .path(elements, ink, style):
            stroke(elements, ink, style)
        case let .markedLine(elements, ink, style, symbols):
            markedLine(elements, ink, style, symbols)
        case let .fill(elements, ink):
            fill(elements, ink)
        case let .text(string, position, alignment, ink):
            label(string, position, alignment, ink)
        case let .turnedText(string, center, degrees, ink):
            turnedLabel(string, center, degrees, ink)
        case let .beginEffect(effect):
            beginEffect(effect)
        case .endEffect:
            if let count = effectLayers.popLast() {
                for _ in 0..<count { check(actionUIWinUIDrawingEndLayer(drawing), "ending a chart's effect") }
            }
            if offsets.count > 1 { offsets.removeLast() }
        case let .beginPlot(layer):
            beginPlot(layer)
        case .endPlot:
            if let count = plotLayers.popLast() {
                for _ in 0..<count { check(actionUIWinUIDrawingEndLayer(drawing), "ending a chart's plot") }
            }
        case let .roundedFill(rect, radius, ink):
            fill(Self.rounded(rect, ChartCorners(topLeading: radius, topTrailing: radius, bottomTrailing: radius, bottomLeading: radius)), ink)
        case let .border(rect, width, ink):
            // Inside the rectangle, as GSK draws a border.
            guard width > 0 else { return }
            let inset = ChartRect(x: rect.x + width / 2, y: rect.y + width / 2, width: rect.width - width, height: rect.height - width)
            stroke(Self.rectangle(inset), ink, ChartStroke(lineWidth: width))
        case let .gradientBar(rect, stops, vertical):
            gradient(rect, stops, vertical)
        }
    }

    /// The bar's rectangle cut to its shape's rounded corners: a corner of the rectangle that is the
    /// shape's own is rounded as the shape's; the others are square (a stacked segment between two).
    private func bar(_ rect: ChartRect, _ shape: ChartRect, _ corners: ChartCorners, _ ink: ChartInk) {
        func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.5 }
        let left = near(rect.x, shape.x), right = near(rect.x + rect.width, shape.x + shape.width)
        let top = near(rect.y, shape.y), bottom = near(rect.y + rect.height, shape.y + shape.height)
        let kept = ChartCorners(topLeading: top && left ? corners.topLeading : 0, topTrailing: top && right ? corners.topTrailing : 0,
                                bottomTrailing: bottom && right ? corners.bottomTrailing : 0,
                                bottomLeading: bottom && left ? corners.bottomLeading : 0)
        fill(Self.rounded(rect, kept), ink)
    }

    // A straight line of an odd width sits on the pixel grid, so it stays one crisp pixel (the Linux
    // renderer's rule).
    private func line(_ from: ChartPoint, _ to: ChartPoint, _ ink: ChartInk, _ style: ChartStroke) {
        let odd = max(style.lineWidth.rounded(), 1).truncatingRemainder(dividingBy: 2) == 1
        func snapped(_ value: Double) -> Double {
            odd ? value.rounded(.down) + 0.5 : value.rounded()
        }
        let (x0, x1) = from.x == to.x ? (snapped(from.x), snapped(to.x)) : (from.x, to.x)
        let (y0, y1) = from.y == to.y ? (snapped(from.y), snapped(to.y)) : (from.y, to.y)
        stroke([.move(ChartPoint(x: x0, y: y0)), .line(ChartPoint(x: x1, y: y1))], ink, style)
    }

    // The holes are cut out of this line alone, so another line still crosses them: the line is drawn in
    // a layer clipped to everything but the holes. An outline is its own mark's line width inside the
    // symbol's box, so a width of 0 leaves just the hole; one of half the box leaves no inside, and the
    // symbol is then solid (the Linux renderer's rules, measured on macOS 27).
    private func markedLine(_ elements: [ChartPathElement], _ ink: ChartInk, _ style: ChartStroke, _ symbols: [ChartLineSymbol]) {
        func isHollow(_ mark: ChartLineSymbol) -> Bool {
            ChartSymbols.isHollowOnALine(mark.symbol) && mark.lineWidth * 2 < mark.side
        }
        func inner(_ mark: ChartLineSymbol) -> [ChartPathElement] {
            ChartSymbols.outline(mark.symbol, center: mark.center, side: mark.side - mark.lineWidth)
        }
        let hollow = symbols.filter(isHollow)
        let solid = symbols.filter { !isHollow($0) }
        if style.lineWidth > 0 {
            if hollow.isEmpty {
                stroke(elements, ink, style)
            } else {
                // A rectangle far past the chart, and each hole wound the other way: inside a hole the
                // windings cancel, so the nonzero clip leaves it out. Where two holes overlap they would
                // cancel it twice over and leave the line there, so a clip takes only holes whose boxes
                // do not meet, and the clips of the layer together leave out every hole.
                let reach = 1.0e5
                let outside = Self.rectangle(ChartRect(x: -reach, y: -reach, width: 2 * reach, height: 2 * reach))
                let sign = Self.windingSign(outside)
                var clips: [(boxes: [ChartRect], path: [ChartPathElement])] = []
                for mark in hollow {
                    for figure in Self.figures(inner(mark)) {
                        let box = Self.bounds(figure)
                        let hole = Self.windingSign(figure) == sign ? Self.reversed(figure) : figure
                        if let index = clips.firstIndex(where: { !$0.boxes.contains { Self.overlap($0, box) } }) {
                            clips[index].boxes.append(box)
                            clips[index].path += hole
                        } else {
                            clips.append(([box], outside + hole))
                        }
                    }
                }
                if actionUIWinUIDrawingBeginLayer(drawing) {
                    var clipped = true
                    for clip in clips {
                        clipped = begin() && send(clip.path) && actionUIWinUIDrawingClip(drawing) && clipped
                    }
                    check(clipped, "cutting a chart line's symbols")
                    stroke(elements, ink, style)
                    check(actionUIWinUIDrawingEndLayer(drawing), "ending a chart line's layer")
                } else {
                    check(false, "starting a chart line's layer")
                    stroke(elements, ink, style)
                }
            }
        }
        for (width, marks) in Dictionary(grouping: hollow, by: \.lineWidth).sorted(by: { $0.key < $1.key }) where width > 0 {
            stroke(marks.flatMap(inner), ink, ChartStroke(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        if !solid.isEmpty {
            fill(solid.flatMap { ChartSymbols.outline($0.symbol, center: $0.center, side: $0.side) }, ink)
        }
    }

    /// A path's figures, each from its move to the next.
    private static func figures(_ elements: [ChartPathElement]) -> [[ChartPathElement]] {
        var found: [[ChartPathElement]] = []
        for element in elements {
            if case .move = element {
                found.append([element])
            } else if !found.isEmpty {
                found[found.count - 1].append(element)
            }
        }
        return found
    }

    /// The box around a figure's points and control points (a curve stays inside it).
    private static func bounds(_ figure: [ChartPathElement]) -> ChartRect {
        var points: [ChartPoint] = []
        for element in figure {
            switch element {
            case .move(let point), .line(let point): points.append(point)
            case let .curve(first, second, end): points += [first, second, end]
            case .close: break
            }
        }
        guard let first = points.first else { return ChartRect(x: 0, y: 0, width: 0, height: 0) }
        var left = first.x, top = first.y, right = first.x, bottom = first.y
        for point in points {
            left = min(left, point.x)
            top = min(top, point.y)
            right = max(right, point.x)
            bottom = max(bottom, point.y)
        }
        return ChartRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// Whether two boxes share some area (touching edges do not).
    private static func overlap(_ a: ChartRect, _ b: ChartRect) -> Bool {
        a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height
    }

    /// The sign of a figure's area on the screen (its points and control points as a polygon): which
    /// way it winds.
    private static func windingSign(_ figure: [ChartPathElement]) -> Double {
        var points: [ChartPoint] = []
        for element in figure {
            switch element {
            case .move(let point), .line(let point): points.append(point)
            case let .curve(first, second, end): points += [first, second, end]
            case .close: break
            }
        }
        guard points.count > 2 else { return 0 }
        var area = 0.0
        for index in points.indices {
            let a = points[index], b = points[(index + 1) % points.count]
            area += a.x * b.y - b.x * a.y
        }
        return area < 0 ? -1 : 1
    }

    /// One figure run backwards: the same outline, wound the other way.
    private static func reversed(_ figure: [ChartPathElement]) -> [ChartPathElement] {
        guard case .move(let start) = figure.first else { return figure }
        var segments: [(from: ChartPoint, element: ChartPathElement)] = []
        var current = start
        var closed = false
        for element in figure.dropFirst() {
            switch element {
            case .line(let point):
                segments.append((current, element))
                current = point
            case .curve(_, _, let end):
                segments.append((current, element))
                current = end
            case .close:
                closed = true
            case .move:
                break
            }
        }
        var path: [ChartPathElement] = [.move(current)]
        for (from, element) in segments.reversed() {
            switch element {
            case .line: path.append(.line(from))
            case let .curve(first, second, _): path.append(.curve(second, first, from))
            default: break
            }
        }
        if closed { path.append(.close) }
        return path
    }

    private func gradient(_ rect: ChartRect, _ stops: [ChartGradientStop], _ vertical: Bool) {
        guard !stops.isEmpty else { return }
        let colors = stops.map { ColorRGBA.resolve($0.color) }
        let offsets = stops.map { min(max($0.offset, 0), 1) }
        let end = vertical ? (rect.x, rect.y + rect.height) : (rect.x + rect.width, rect.y)
        let filled = begin() && send(Self.rectangle(rect)) && colors.withUnsafeBufferPointer { colorBuffer in
            offsets.withUnsafeBufferPointer { offsetBuffer in
                actionUIWinUIDrawingFillLinearGradient(drawing, rect.x, rect.y, end.0, end.1, colorBuffer.baseAddress,
                                                       offsetBuffer.baseAddress, Int32(colorBuffer.count))
            }
        }
        check(filled, "filling a chart's gradient")
    }

    // MARK: Text

    private func label(_ string: String, _ position: ChartPoint, _ alignment: ChartPoint, _ ink: ChartInk) {
        let size = text.size(string)
        let x = (position.x - size.width * alignment.x).rounded(), y = (position.y - size.height * alignment.y).rounded()
        check(begin() && actionUIWinUIDrawingText(drawing, string, x, y, 0, Chart.axisFontSize, 400, color(ink)),
              "drawing a chart's text")
    }

    private func turnedLabel(_ string: String, _ center: ChartPoint, _ degrees: Double, _ ink: ChartInk) {
        let size = text.size(string)
        check(begin(rotation: degrees, around: center)
              && actionUIWinUIDrawingText(drawing, string, center.x - size.width / 2, center.y - size.height / 2, 0,
                                          Chart.axisFontSize, 400, color(ink)),
              "drawing a chart's turned text")
    }

    // MARK: Groups

    // An effect is a group: a layer whose opacity and filters (the shadow innermost, then the blur, as
    // the Linux renderer pushes them) apply to an inner layer holding the group's drawing, put over it as
    // one operation. An effect with only an offset needs no layer.
    private func beginEffect(_ effect: ChartMarkEffect) {
        let offset = offsets.last!
        offsets.append(ChartPoint(x: offset.x + effect.offset.x, y: offset.y + effect.offset.y))
        var filters: [ActionUIWinUIDrawingFilter] = []
        if let shadow = effect.shadow {
            let color = shadow.color.map(ColorRGBA.resolve) ?? ActionUIWinUIColor(red: 0, green: 0, blue: 0, alpha: 0.33)
            filters.append(ActionUIWinUIDrawingFilter(kind: ActionUIWinUIDrawingFilterShadow, color: color, radius: shadow.radius,
                                                      x: shadow.x, y: shadow.y))
        }
        if effect.blur > 0 {
            filters.append(ActionUIWinUIDrawingFilter(kind: ActionUIWinUIDrawingFilterBlur,
                                                      color: ActionUIWinUIColor(red: 0, green: 0, blue: 0, alpha: 0),
                                                      radius: effect.blur, x: 0, y: 0))
        }
        guard effect.opacity < 1 || !filters.isEmpty else {
            effectLayers.append(0)
            return
        }
        guard actionUIWinUIDrawingBeginLayer(drawing) else {
            check(false, "starting a chart's effect")
            effectLayers.append(0)
            return
        }
        if effect.opacity < 1 {
            check(actionUIWinUIDrawingSetOpacity(drawing, effect.opacity), "a chart effect's opacity")
        }
        if !filters.isEmpty {
            let set = filters.withUnsafeBufferPointer { buffer in
                actionUIWinUIDrawingSetFilters(drawing, buffer.baseAddress, Int32(buffer.count))
            }
            check(set, "a chart effect's filters")
        }
        if actionUIWinUIDrawingBeginLayer(drawing) {
            effectLayers.append(2)
        } else {
            check(false, "starting a chart's effect")
            effectLayers.append(1)
        }
    }

    // A plot layer clips what it holds to its rounded rectangle and, with an opacity, puts it over the
    // chart as one group (an inner layer, as an effect does).
    private func beginPlot(_ layer: ChartPlotLayer) {
        guard layer.opacity < 1 || layer.clips else {
            plotLayers.append(0)
            return
        }
        guard actionUIWinUIDrawingBeginLayer(drawing) else {
            check(false, "starting a chart's plot")
            plotLayers.append(0)
            return
        }
        var pushed = 1
        if layer.opacity < 1 {
            check(actionUIWinUIDrawingSetOpacity(drawing, layer.opacity), "a chart plot's opacity")
        }
        if layer.clips {
            let radius = layer.radius
            let outline = Self.rounded(layer.rect, ChartCorners(topLeading: radius, topTrailing: radius, bottomTrailing: radius,
                                                                bottomLeading: radius))
            check(begin() && send(outline) && actionUIWinUIDrawingClip(drawing), "clipping a chart's plot")
        }
        if layer.opacity < 1 {
            if actionUIWinUIDrawingBeginLayer(drawing) {
                pushed += 1
            } else {
                check(false, "starting a chart's plot")
            }
        }
        plotLayers.append(pushed)
    }
}
