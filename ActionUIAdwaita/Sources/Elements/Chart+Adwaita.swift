// Sources/Elements/Chart+Adwaita.swift
/*
 Chart on GTK: a widget that draws what Drawing/ChartLayout.swift lays out with GTK's snapshot API
 (GSK paths and strokes, Pango text). Greedy in both axes with Color's size, as Canvas is.

 The description is stored cleaned (Core/Elements/Chart.swift), and its warnings were logged then,
 so it parses without a logger here. Marks are read when the description or the rows change; the
 layout runs at each draw, which GTK asks for only when the size, the theme or the chart changed.

 Axis text is the theme's text color and 0.8 of its size, near Swift Charts' caption2 next to body
 text. Numbers and dates are written in the user's locale (NumberFormatting, DateFormatting).

 Selection (chartXSelection, chartYSelection, chartAngleSelection), as Swift Charts on macOS takes
 it: a value or an angle follows the pointer while it is over the plot, and goes when the pointer
 leaves; a range is a drag across the plot, from where it started to where it is, and goes when the
 button is released. On a touchscreen a value follows the finger while it touches, as on iOS. The
 selection is the element's value (ChartSelection's JSON); a change by the user fires
 valueChangeActionID at once ("continuous", or a cleared selection) or once the selection has
 rested 150 ms ("settled", the default), and a value the host sets fires nothing. The marks that
 read "$selection" are drawn from the value (ChartMarkResolver), at each change. ChartSelectionHit
 reads a place as a value, from where the last draw put the plot.

 Annotations (ChartAnnotations): each is the element in its "content" shown with its mark's row, as
 a template row is (RenderNode.templateRowNode: its controls act with the chart's id and the row as
 viewPartID, -1 outside a ForEach), a child widget of the chart placed beside its mark at each
 allocation and drawn over the marks. A view is kept while its mark's row is the same; past 1000
 annotations the chart draws its marks without them, with a warning, as on Apple.

 Scrolling (chartScrollableAxes; ChartLayout+Scroll): the scroll wheel and the touchpad move the
 window, a vertical wheel the horizontal window when only that axis scrolls, as GTK's scrolled
 windows do; on a touchscreen a drag across the plot moves it, and there it does not select. A
 window held at its end passes the scroll on to what holds the chart. Its place is kept on the
 widget, not in the value, as chartScrollPosition sets only where it starts; a new description
 that scrolls otherwise starts it again.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

nonisolated(unsafe) private var chartWidgetType: GType = 0
nonisolated(unsafe) private var chartParentClass: UnsafeMutablePointer<GObjectClass>?
private let chartStateKey = AttachKey<ChartState>("actionui-chart")

/// What a chart draws, kept on its widget.
@MainActor private final class ChartState {
    var spec = ChartSpec()
    var marks = ChartResolvedMarks()
    /// Where the last draw put the plot and how its axes ran, for reading a place as a value.
    var geometry = ChartGeometry()
    weak var node: RenderNode?
    /// Where a drag that selects a range started, in the widget, and whether it has moved: a click
    /// that does not move selects no range.
    var dragStart: ChartPoint?
    var dragMoved = false
    /// A "settled" action waiting for the selection to rest.
    var settleSource: guint = 0
    /// The leading edges of the scrolling axes' windows (ChartScrollWindow), nil until the first
    /// draw places them; and the scrolling they were placed for.
    var scroll: (x: Double?, y: Double?) = (nil, nil)
    var scrollSpec = ChartScrollSpec()
    /// The windows' leading edges when a touch pan started.
    var panStart: (x: Double?, y: Double?)?
    /// The annotation views, by what they show (kept while that stays the same), and each drawn
    /// mark's, by instance and ordinal.
    var annotationNodes: [String: [RenderNode]] = [:]
    var annotationsByMark: [Int: [RenderNode]] = [:]
    var annotationsDropped = false
    /// The last layout, for the size it was made at; nil when the chart changed since.
    var laidOut: (width: Double, height: Double, primitives: [ChartPrimitive], geometry: ChartGeometry)?

    isolated deinit {
        if settleSource != 0 {
            g_source_remove(settleSource)
        }
    }
}

extension Chart: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let widget: WidgetPointer = typed(OpaquePointer(g_object_new_with_properties(widgetType(), 0, nil, nil)!))
        gtk_widget_set_hexpand(widget, 1)
        gtk_widget_set_vexpand(widget, 1)
        let state = ChartState()
        state.node = node
        attach(state, to: widget, key: chartStateKey)
        watchSelection(widget, state)
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
        if state.spec.scroll != state.scrollSpec {
            state.scrollSpec = state.spec.scroll
            state.scroll = (nil, nil)
        }
        let selection = ChartSelection.decode(node.model.value as? String, spec: state.spec.selection)
        state.marks = ChartMarkResolver.resolve(state.spec, rows: rows, selection: selection)
        report(state, viewID: node.element.id)
        syncAnnotations(widget, node, state)
        state.laidOut = nil
        gtk_widget_queue_allocate(widget)
        gtk_widget_queue_draw(widget)
    }

    /// Swift Charts' limit, past which a chart draws its marks without annotations (ChartRenderCache).
    static let maxAnnotations = 1000

    /// Makes a view for each annotation of the marks, keeping the ones that show the same thing.
    private static func syncAnnotations(_ widget: WidgetPointer, _ node: RenderNode, _ state: ChartState) {
        var wanted: [(instance: Int, spec: ChartAnnotationSpec, key: String, row: Int, cells: [String])] = []
        for (index, instance) in state.marks.instances.enumerated() {
            var ordinal = 0
            for modifier in instance.mark.modifiers {
                guard case .annotation(let spec) = modifier else { continue }
                // As on Apple (ChartContentBuilder): one that reads no row gets none, and -1 as its row.
                let row = spec.readsRows ? instance.row ?? -1 : -1
                let cells = spec.readsRows ? instance.annotationRow : []
                // Template ids are numbered alike in every annotation, so the content itself is
                // compared too, when a view is reused.
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
        var unused = state.annotationNodes
        var kept: [String: [RenderNode]] = [:]
        var byMark: [Int: [RenderNode]] = [:]
        for item in wanted {
            let annotation: RenderNode
            if let index = unused[item.key]?.firstIndex(where: { ($0.element as? ActionUIElement) == item.spec.content }) {
                annotation = unused[item.key]!.remove(at: index)
            } else {
                annotation = node.templateRowNode(item.spec.content, row: item.cells, rowIndex: item.row)
                gtk_widget_set_parent(annotation.outerWidget, widget)
            }
            kept[item.key, default: []].append(annotation)
            byMark[item.instance, default: []].append(annotation)
        }
        for old in unused.values.joined() {
            gtk_widget_unparent(old.outerWidget)
            old.detach()
        }
        state.annotationNodes = kept
        state.annotationsByMark = byMark
    }

    /// The layout at the widget's size, made again only after the chart changed or the size did.
    private static func layout(_ widget: WidgetPointer, _ state: ChartState, width: Double, height: Double)
        -> (primitives: [ChartPrimitive], geometry: ChartGeometry) {
        if let cached = state.laidOut, cached.width == width, cached.height == height {
            return (cached.primitives, cached.geometry)
        }
        let text = ChartAxisText(widget: widget)
        let metrics = ChartTextMetrics(
            size: { text.size($0) },
            number: { NumberFormatting.string($0, format: .decimal(minFraction: $1, maxFraction: $1)) },
            formatted: { NumberFormatting.string($0, format: $1) },
            date: { DateFormatting.string($0, skeleton: $1) })
        let (primitives, geometry) = ChartLayout.laidOut(state.spec, marks: state.marks, width: width, height: height, metrics: metrics,
                                                         scroll: state.scroll)
        state.geometry = geometry
        state.scroll = (geometry.xScroll?.leading, geometry.yScroll?.leading)
        state.laidOut = (width, height, primitives, geometry)
        return (primitives, geometry)
    }

    /// Where annotation views are seen: anywhere, past the chart's edges too, as Swift Charts draws
    /// them (checked on macOS 27 in a window: a label above a full bar and one beside a rule's end
    /// drew over what is around the chart); along a scrolling axis only the plot, where the marks
    /// stop, so the views of marks out of the window go with them.
    private static func annotationRoom(_ geometry: ChartGeometry) -> ChartRect {
        let reach = 100_000.0
        var room = ChartRect(x: -reach, y: -reach, width: geometry.chart.width + 2 * reach, height: geometry.chart.height + 2 * reach)
        if geometry.xScroll != nil { (room.x, room.width) = (geometry.plot.x, geometry.plot.width) }
        if geometry.yScroll != nil { (room.y, room.height) = (geometry.plot.y, geometry.plot.height) }
        return room
    }

    /// Lays the chart out and places each annotation view beside its mark; a view whose mark is not
    /// drawn, or that falls outside the room views are seen in, is hidden (child-visible: no resize
    /// is queued from here, and it is neither drawn nor picked).
    private static func allocate(_ widget: WidgetPointer, width: Int32, height: Int32) {
        guard let state = attached(on: widget, key: chartStateKey) else { return }
        // Made again at every allocation: a font or text scale change queues one at the same size.
        state.laidOut = nil
        let geometry = layout(widget, state, width: Double(width), height: Double(height)).geometry
        let room = annotationRoom(geometry)
        var placed = Set<ObjectIdentifier>()
        for frame in geometry.annotations {
            guard let views = state.annotationsByMark[frame.instance], frame.ordinal < views.count else { continue }
            let view = views[frame.ordinal]
            let specs = state.marks.instances[frame.instance].mark.modifiers.compactMap { modifier -> ChartAnnotationSpec? in
                if case .annotation(let spec) = modifier { return spec }
                return nil
            }
            guard frame.ordinal < specs.count else { continue }
            let box = view.outerWidget!
            var minimum: Int32 = 0, natural: Int32 = 0
            gtk_widget_measure(box, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &natural, nil, nil)
            let childWidth = natural
            gtk_widget_measure(box, GTK_ORIENTATION_VERTICAL, childWidth, &minimum, &natural, nil, nil)
            let rect = ChartAnnotationPlacement.place(specs[frame.ordinal], frame: frame.frame, center: frame.center,
                                                      size: ChartSize(width: Double(childWidth), height: Double(natural)),
                                                      plot: geometry.plot, chart: geometry.chart)
            guard rect.x < room.x + room.width, rect.x + rect.width > room.x,
                  rect.y < room.y + room.height, rect.y + rect.height > room.y else { continue }
            gtk_widget_set_child_visible(box, 1)
            var origin = graphene_point_t(x: Float(rect.x.rounded()), y: Float(rect.y.rounded()))
            gtk_widget_allocate(box, childWidth, natural, -1, gsk_transform_translate(nil, &origin))
            placed.insert(ObjectIdentifier(view))
        }
        for view in state.annotationNodes.values.joined() where !placed.contains(ObjectIdentifier(view)) {
            gtk_widget_set_child_visible(view.outerWidget, 0)
        }
    }

    static var defaultExpansion: Expansion { .both }

    /// Named by what its marks say; a label on the chart itself comes first (ModifierBox).
    static func defaultAccessibleLabel(_ node: RenderNode) -> String? {
        attached(on: node.widget, key: chartStateKey)?.marks.accessibleName
    }

    private static func report(_ state: ChartState, viewID: Int) {
        let logger = ActionUIModel.shared.logger
        if state.marks.skippedRows > 0, let first = state.marks.firstSkip {
            let place = first.inlineData ? "row \(first.row + 1) of a ForEach's data" : "row \(first.row + 1)"
            logger.log("Chart \(viewID): skipped \(state.marks.skippedRows) row(s) with a cell that does not parse; first: \(place), column \(first.column + 1) is not a \(first.type.rawValue)", .warning)
        }
    }

    private static func snapshot(_ widget: WidgetPointer, _ snapshot: OpaquePointer) {
        guard let state = attached(on: widget, key: chartStateKey) else { return }
        let width = Double(gtk_widget_get_width(widget)), height = Double(gtk_widget_get_height(widget))
        guard width > 0, height > 0 else { return }
        let text = ChartAxisText(widget: widget)
        let (primitives, geometry) = layout(widget, state, width: width, height: height)
        var foreground = GdkRGBA()
        gtk_widget_get_color(widget, &foreground)
        let drawing = ChartDrawing(widget: widget, snapshot: snapshot, foreground: foreground, text: text)
        for primitive in primitives {
            drawing.draw(primitive)
        }
        // The annotations, over the marks, cut off only where a scrolling axis's window ends.
        let room = annotationRoom(geometry)
        var clip = graphene_rect_t(origin: graphene_point_t(x: Float(room.x), y: Float(room.y)),
                                   size: graphene_size_t(width: Float(room.width), height: Float(room.height)))
        gtk_snapshot_push_clip(snapshot, &clip)
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            gtk_widget_snapshot_child(widget, current, snapshot)
            child = gtk_widget_get_next_sibling(current)
        }
        gtk_snapshot_pop(snapshot)
    }

    // MARK: Selection

    /// The settle time of a "settled" selection action (Apple's ChartSelectionBinder.settleDelay).
    static let settleMilliseconds: UInt32 = 150

    private static func watchSelection(_ widget: WidgetPointer, _ state: ChartState) {
        let motion = gtk_event_controller_motion_new()!
        connectPoint(UnsafeMutableRawPointer(motion), "motion") { [weak state] x, y in
            guard let state else { return }
            hover(state, at: ChartPoint(x: x, y: y))
        }
        connectSignal(UnsafeMutableRawPointer(motion), "leave", .instanceOnly) { [weak state] in
            guard let state, state.dragStart == nil else { return }
            clearValues(state)
        }
        gtk_widget_add_controller(widget, motion)

        let scroller = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES)!
        connectScroll(UnsafeMutableRawPointer(scroller)) { [weak state] dx, dy in
            guard let state else { return false }
            // A wheel's step is GtkScrolledWindow's: the length shown to the power of 2/3.
            let wheel = gtk_event_controller_scroll_get_unit(scroller) == GDK_SCROLL_UNIT_WHEEL
            return scrolled(widget, state, dx: dx, dy: dy, wheel: wheel)
        }
        gtk_widget_add_controller(widget, scroller)

        let drag = gtk_gesture_drag_new()!
        gtk_gesture_single_set_button(drag, 1)
        connectPoint(UnsafeMutableRawPointer(drag), "drag-begin") { [weak state] x, y in
            guard let state else { return }
            // A touch on a scrolling chart moves its window.
            if isTouch(drag), state.geometry.xScroll != nil || state.geometry.yScroll != nil {
                gtk_gesture_set_state(drag, GTK_EVENT_SEQUENCE_CLAIMED)
                state.panStart = state.scroll
                return
            }
            let spec = state.spec.selection
            let selectsRange = spec.x == .range || spec.y == .range
            // Only a chart that selects takes the drag; another leaves it to what holds the chart.
            guard selectsRange || (isTouch(drag) && !spec.isEmpty) else {
                gtk_gesture_set_state(drag, GTK_EVENT_SEQUENCE_DENIED)
                return
            }
            gtk_gesture_set_state(drag, GTK_EVENT_SEQUENCE_CLAIMED)
            let start = ChartPoint(x: x, y: y)
            state.dragStart = start
            state.dragMoved = false
            // A touch shows the values under the finger at once; a range waits for the drag to move.
            if isTouch(drag) {
                write(state) { setValues(&$0, state, at: start) }
            }
        }
        connectPoint(UnsafeMutableRawPointer(drag), "drag-update") { [weak state] dx, dy in
            guard let state else { return }
            if let start = state.panStart {
                pan(widget, state, from: start, dx: dx, dy: dy)
                return
            }
            guard let start = state.dragStart, dx != 0 || dy != 0 || state.dragMoved else { return }
            state.dragMoved = true
            dragged(state, from: start, to: ChartPoint(x: start.x + dx, y: start.y + dy), touch: isTouch(drag))
        }
        connectPoint(UnsafeMutableRawPointer(drag), "drag-end") { [weak state] _, _ in
            guard let state else { return }
            if state.panStart != nil {
                state.panStart = nil
                return
            }
            guard state.dragStart != nil else { return }
            state.dragStart = nil
            let touch = isTouch(drag)
            // A click that did not move selected no range: there is nothing to clear.
            guard state.dragMoved || touch else { return }
            write(state) { selection in
                let spec = state.spec.selection
                if spec.x == .range || (touch && spec.x == .value) { selection.x = nil }
                if spec.y == .range || (touch && spec.y == .value) { selection.y = nil }
                if touch && spec.angle {
                    selection.angle = nil
                    selection.row = nil
                }
            }
        }
        gtk_widget_add_controller(widget, drag)
    }

    /// A scroll by (dx, dy), in points or in wheel steps: moves the windows of the axes that scroll.
    /// Returns whether a window moved; one held at its end leaves the scroll to what holds the chart.
    private static func scrolled(_ widget: WidgetPointer, _ state: ChartState, dx: Double, dy: Double, wheel: Bool) -> Bool {
        let geometry = state.geometry
        guard geometry.xScroll != nil || geometry.yScroll != nil else { return false }
        var dx = dx, dy = dy
        // Only the horizontal axis scrolls: a vertical wheel or swipe moves it.
        if geometry.yScroll == nil, dx == 0 {
            (dx, dy) = (dy, 0)
        }
        if wheel {
            dx *= pow(geometry.plot.width, 2.0 / 3)
            dy *= pow(geometry.plot.height, 2.0 / 3)
        }
        return move(widget, state, from: state.scroll, dx: dx, dy: dy)
    }

    /// A touch pan by (dx, dy) points from where the windows were when it began: the content follows
    /// the finger.
    private static func pan(_ widget: WidgetPointer, _ state: ChartState, from start: (x: Double?, y: Double?), dx: Double, dy: Double) {
        _ = move(widget, state, from: start, dx: -dx, dy: -dy)
    }

    /// Moves the windows `dx` points toward the trailing edge and `dy` points down from `start`.
    private static func move(_ widget: WidgetPointer, _ state: ChartState, from start: (x: Double?, y: Double?), dx: Double, dy: Double) -> Bool {
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
        state.laidOut = nil
        // Allocated again, so the annotations move with the window.
        gtk_widget_queue_allocate(widget)
        gtk_widget_queue_draw(widget)
        return true
    }

    private static func isTouch(_ gesture: OpaquePointer) -> Bool {
        guard let device = gtk_event_controller_get_current_event_device(gesture) else { return false }
        return gdk_device_get_source(device) == GDK_SOURCE_TOUCHSCREEN
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

    /// A drag from `start` to `end`: the range it covers on an axis that selects a range, and on a
    /// touchscreen the values under the finger.
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

    /// Applies `change` to the selection the value holds, stores it when it differs, and fires the
    /// action as selectionActionTiming says. The sync the new value causes draws the marks that
    /// read it.
    private static func write(_ state: ChartState, _ change: (inout ChartSelection) -> Void) {
        // Only the user's input selects: a signal GTK emits while a renderer applies the model (a
        // leave as a host hides the chart under the pointer) writes nothing.
        guard !UpdateGuard.isApplying, let node = state.node, !state.spec.selection.isEmpty else { return }
        let spec = state.spec.selection
        let before = node.model.value as? String ?? ""
        var selection = ChartSelection.decode(before, spec: spec)
        change(&selection)
        let after = selection.encode(spec: spec)
        guard after != before else { return }
        node.model.value = after
        let props = Props(node.properties)
        guard let actionID = props.valueChangeActionID else { return }
        if state.settleSource != 0 {
            g_source_remove(state.settleSource)
            state.settleSource = 0
        }
        let windowUUID = node.windowUUID
        let viewID = node.element.id
        let fire = { ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: viewID, viewPartID: 0) }
        if props.selectionActionTiming == .continuous || after.isEmpty {
            fire()
            return
        }
        state.settleSource = runAfter(milliseconds: settleMilliseconds) { [weak state] in
            state?.settleSource = 0
            fire()
        }
    }

    private static func widgetType() -> GType {
        if chartWidgetType != 0 { return chartWidgetType }
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkWidgetClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkWidget>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            chartParentClass = g_type_class_peek_parent(klass)?.assumingMemoryBound(to: GObjectClass.self)
            // The annotation views are children: they go when the chart does.
            klass.assumingMemoryBound(to: GObjectClass.self).pointee.dispose = { object in
                guard let object else { return }
                let widget: WidgetPointer = typed(object)
                while let child = gtk_widget_get_first_child(widget) {
                    gtk_widget_unparent(child)
                }
                chartParentClass?.pointee.dispose?(object)
            }
            let widgetClass = klass.assumingMemoryBound(to: GtkWidgetClass.self)
            widgetClass.pointee.size_allocate = { widget, width, height, _ in
                guard let widget else { return }
                MainActor.assumeIsolated { Chart.allocate(widget, width: width, height: height) }
            }
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
        chartWidgetType = g_type_register_static(gtk_widget_get_type(), "ActionUIChart", &info, GTypeFlags(rawValue: 0))
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
        case let .beginEffect(effect):
            beginEffect(effect)
        case let .endEffect(effect):
            if effect.shadow != nil { gtk_snapshot_pop(snapshot) }
            if effect.blur > 0 { gtk_snapshot_pop(snapshot) }
            if effect.opacity < 1 { gtk_snapshot_pop(snapshot) }
            gtk_snapshot_restore(snapshot)
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

    private func beginEffect(_ effect: ChartMarkEffect) {
        gtk_snapshot_save(snapshot)
        var offset = graphene_point_t(x: Float(effect.offset.x), y: Float(effect.offset.y))
        gtk_snapshot_translate(snapshot, &offset)
        if effect.opacity < 1 {
            gtk_snapshot_push_opacity(snapshot, effect.opacity)
        }
        if effect.blur > 0 {
            // GSK's blur radius is twice the deviation, SwiftUI's is the deviation.
            gtk_snapshot_push_blur(snapshot, Double(CanvasFilter.radius(effect.blur * 2)))
        }
        if let shadow = effect.shadow {
            var node = GskShadow(color: shadow.color.map { ColorRGBA.resolve($0, for: widget) } ?? ModifierBox.defaultShadowColor,
                                 dx: Float(shadow.x), dy: Float(shadow.y), radius: CanvasFilter.radius(shadow.radius * 2))
            gtk_snapshot_push_shadow(snapshot, &node, 1)
        }
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
