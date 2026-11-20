// Sources/Layout/LazyRows.swift
/*
 The template form of LazyVStack, LazyHStack, LazyVGrid and LazyHGrid on GTK, made lazily: a row's
 template instance (the template with the row's data, RenderNode.lazyTemplateRowNode) is made only
 when the row comes in or near the part of the container its ScrollView shows, and let go when it
 is far out of view, as SwiftUI's lazy stacks and grids make their rows. A ScrollView of 2000 rows
 opens and scrolls with tens of rows made.

 - Lines: a lazy stack places one row per line along its axis; a lazy grid places as many rows as
   it has tracks (columns of a LazyVGrid, rows of a LazyHGrid) per line, laid out by
   LazyGridLayout. A line is made and let go whole.
 - What is shown: the container follows the nearest GtkScrolledWindow above it that scrolls along
   its axis, through the scrolled window's adjustment (its position and page size) and the
   container's place in the scrolled content. Lines within a page before and after the visible part
   are made; lines more than two pages away are let go, so small scrolls do not make and let go the
   same rows. Outside any such scrolled window every row is made, in the container's sync as the
   eager form makes them.
 - Sizes: a made line is measured (a LazyVStack's row for the stack's width: its height for that
   width; a grid's line as tall as its tallest cell for the tracks' widths); the length of a line
   let go is remembered for that width; a line never made is estimated at the average of the lines
   known. The container is as long as all of them with the spacing between.
 - Anchoring: making lines changes the known lengths and the estimate, so the lines above the
   visible part may become longer or shorter. The scroll position moves by the same amount, so the
   line at the top of the visible part stays where it is; GTK does not do this itself. A change of
   the container's width changes every line's length (a LazyVStack's rows are measured for its
   width): the line at the top and how far into it the visible part started are kept across it too.
 - Rows are made and let go outside GTK's measuring and allocation (GTK forbids changing its
   widget tree there), on a main loop source scheduled by the adjustment's signals, by the
   container's allocation and by its update; the container's size is then queued again.
 - Across its axis the container takes all the room it is offered: a stack aligns each row in it by
   its alignment, a grid shares it among its tracks. It does not expand along its axis (the expand
   flags set here). The rows made at a moment decide neither: only its natural size across is its
   made rows'.
 - Rows are kept by index, as in the eager form (TemplateRows): a row whose data changes is made
   again, rows added at the end are added, rows removed from the end are removed. A row let go
   loses only transient state (keyboard focus, a text selection): its data lives in the content
   rows (a row-bound Toggle writes its row), so it shows the same when made again.
*/

import CAdwaita

let lazyRowsKey = AttachKey<LazyRows>("actionui-lazy-rows")

nonisolated(unsafe) private var lazyRowsLayoutType: GType = 0

/// A lazy stack's or lazy grid's rows in its template form, attached to its container widget (laid
/// out by LazyRows.layoutType).
@MainActor
final class LazyRows {
    /// A line's length along the axis before any line has been measured.
    static let initialEstimate = 20
    /// The page assumed before the scrolled window is laid out.
    static let fallbackPage = 600.0

    let axis: StackAxis
    /// A lazy grid's tracks and alignment (its tracks are across the axis); nil for a lazy stack.
    let grid: LazyGridState?
    /// The container widget, which keeps this object.
    private let widget: WidgetPointer
    private weak var node: RenderNode?
    private var template: (any ActionUIElementBase)?
    /// The content rows.
    private(set) var rows: [[String]] = []
    private(set) var spacing = 0
    private(set) var alignment = StackSolver.Alignment.center
    /// The grid's tracks when the lines were last measured: other tracks give other lines.
    private var gridTracks: [LazyGridTrack] = []
    /// The rows made, by index.
    private(set) var made: [Int: RenderNode] = [:]
    /// Lines' lengths along the axis, by line, measured for `knownCross` across: the made lines'
    /// and those let go since.
    private var known: [Int: Int] = [:]
    private var knownCross = -1
    /// The container's environment when the rows were last updated.
    private var environment = Environment()
    /// The scrolled window followed, its adjustment along the axis (referenced) and the handlers
    /// connected to it.
    private var scroller: WidgetPointer?
    private var adjustment: UnsafeMutablePointer<GtkAdjustment>?
    private var handlers: [gulong] = []
    private var refreshPending = false
    /// Where the visible part started at the last refresh, in the container along its axis: what a
    /// change of width keeps in view.
    private var lastTop: Double?
    /// The line at the top of the visible part before a change of width, and how far into it the
    /// visible part started, to be put back by the next refresh.
    private var pendingAnchor: (index: Int, inside: Int)?

    private init(widget: WidgetPointer, node: RenderNode, axis: StackAxis, grid: LazyGridState?) {
        self.widget = widget
        self.node = node
        self.axis = axis
        self.grid = grid
    }

    isolated deinit {
        stopFollowing()
        for row in made.values {
            row.detach()
        }
    }

    /// Whether `node`'s element shows its template (the lazy form) rather than its children.
    static func showsTemplate(_ node: RenderNode) -> Bool {
        node.effectiveElement.subviews?["template"] is any ActionUIElementBase
    }

    /// A new container for a lazy stack's template form, or a lazy grid's with `grid` (attached to
    /// the container too, where the grid's renderer sets its tracks), empty until update.
    static func makeWidget(_ node: RenderNode, axis: StackAxis, grid: LazyGridState? = nil) -> WidgetPointer {
        let widget = makeContainer(layoutType: layoutType())
        let rows = LazyRows(widget: widget, node: node, axis: axis, grid: grid)
        attach(rows, to: widget, key: lazyRowsKey)
        if let grid {
            attach(grid, to: widget, key: lazyGridStateKey)
        }
        // Across the axis it expands whatever its rows do, along it not.
        gtk_widget_set_hexpand(widget, axis == .vertical ? 1 : 0)
        gtk_widget_set_vexpand(widget, axis == .vertical ? 0 : 1)
        connectSignal(widget, "map", .instanceOnly) { [weak rows] in
            rows?.scheduleRefresh()
        }
        connectSignal(widget, "unmap", .instanceOnly) { [weak rows] in
            rows?.stopFollowing()
        }
        return widget
    }

    // MARK: Updating

    /// Takes `node`'s template, content rows, spacing (between lines) and alignment (a stack's; a
    /// grid's is in its state). Runs in the node's sync: rows whose data changed or that went are let
    /// go here, rows are made later (refresh), outside the sync's observation.
    func update(_ node: RenderNode, spacing: Double, alignment: StackSolver.Alignment) {
        self.node = node
        node.syncChildren([], insert: { _, _ in }, remove: { gtk_widget_unparent($0.outerWidget) })
        template = node.effectiveElement.subviews?["template"] as? any ActionUIElementBase
        let newRows = node.model.states["content"] as? [[String]] ?? []
        var changed = false
        let points = StackSolver.length(spacing)
        if points != self.spacing || alignment != self.alignment {
            self.spacing = points
            self.alignment = alignment
            changed = true
        }
        if let grid, grid.tracks != gridTracks {
            // Other tracks put the rows on other lines, of other lengths: every line again.
            gridTracks = grid.tracks
            for (index, row) in made {
                release(index, row)
            }
            known = [:]
            changed = true
        }
        if node.environment != environment {
            environment = node.environment
            for row in made.values {
                SyncScheduler.shared.markDirty(row)
            }
        }
        if newRows != rows {
            for (index, row) in made where index >= newRows.count || newRows[index] != rows[index] {
                release(index, row)
            }
            // A changed row's line keeps its remembered length until it is made again and
            // measured: closer than the estimate, so new data that changes no length keeps the
            // same rows in view (forgotten, the lines above would all take the estimate and the
            // view would move). Lines past the new end go, and a grid's line holding the old or the
            // new end has other rows now: it is measured again.
            let newLineCount = (newRows.count + perLine - 1) / perLine
            for line in known.keys where line >= newLineCount {
                known[line] = nil
            }
            if newRows.count != rows.count {
                for end in [rows.count, newRows.count] where end % perLine != 0 {
                    known[end / perLine] = nil
                }
            }
            rows = newRows
            changed = true
        }
        // Outside a scrolled window every row is made, here as the eager form makes them, so a
        // window that fits its content opens at its size (refresh would make them a turn later).
        if nearestScroller() == nil, template != nil {
            for index in rows.indices where made[index] == nil {
                changed = make(index, inSync: true) || changed
            }
        }
        if changed {
            gtk_widget_queue_resize(widget)
        }
        scheduleRefresh()
    }

    /// Makes and lets go of rows soon, on the main loop, outside GTK's layout.
    func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        runAfter(milliseconds: 0) { [weak self] in
            self?.refresh()
        }
    }

    /// Makes the lines in or near the visible part of the container and lets go of those far from
    /// it (every row outside a scrolled window), keeping the top visible line in place.
    func refresh() {
        refreshPending = false
        guard let node, node.isAttached, template != nil else { return }
        follow(nearestScroller())
        guard let adjustment else {
            var added = false
            for index in rows.indices where made[index] == nil {
                added = make(index) || added
            }
            if added {
                gtk_widget_queue_resize(widget)
            }
            return
        }
        let cross = allocatedCross
        // Before the scrolled window is laid out its page is 0: a window's height is assumed.
        let pageSize = gtk_adjustment_get_page_size(adjustment)
        let page = pageSize > 0 ? pageSize : Self.fallbackPage
        if let pending = pendingAnchor {
            pendingAnchor = nil
            restore(pending, cross: cross, adjustment: adjustment)
        }
        // The visible part in the container's coordinates along its axis.
        let top = gtk_adjustment_get_value(adjustment) - (contentOffset ?? 0)
        lastTop = top
        let anchor = top > 0 ? row(at: Int(top), cross: cross) : nil
        let anchorOffset = anchor.map { offset(of: $0, cross: cross) }
        var changed = false
        // Made lines change the estimate, and so which lines are near: a few rounds settle it.
        for _ in 0..<4 {
            let wanted = lineRange(from: top - page, to: top + 2 * page, cross: cross)
            var added = false
            for line in wanted where !isMade(line) {
                added = makeLine(line) || added
            }
            changed = changed || added
            if !added { break }
        }
        let kept = lineRange(from: top - 2 * page, to: top + 3 * page, cross: cross)
        for (index, row) in made where !kept.contains(index / perLine) {
            release(index, row)
            changed = true
        }
        guard changed else { return }
        if let anchor, let anchorOffset {
            let shift = Double(offset(of: anchor, cross: cross) - anchorOffset)
            if shift != 0 {
                scroll(adjustment, to: gtk_adjustment_get_value(adjustment) + shift)
                lastTop = gtk_adjustment_get_value(adjustment) - (contentOffset ?? 0)
            }
        }
        gtk_widget_queue_resize(widget)
    }

    /// Scrolls to `value`, raising the adjustment's upper bound when it is below what that needs:
    /// the viewport sets it only at its next allocation, and GTK would clamp the value to it.
    private func scroll(_ adjustment: UnsafeMutablePointer<GtkAdjustment>, to value: Double) {
        let upper = max(gtk_adjustment_get_upper(adjustment), value + gtk_adjustment_get_page_size(adjustment))
        gtk_adjustment_configure(adjustment, value, gtk_adjustment_get_lower(adjustment), upper,
                                 gtk_adjustment_get_step_increment(adjustment),
                                 gtk_adjustment_get_page_increment(adjustment),
                                 gtk_adjustment_get_page_size(adjustment))
    }

    /// Scrolls so the visible part starts in line `anchor.index` as far into it as before a change
    /// of width (at most to the end of the line and the gap after it, which row(at:) counts as the
    /// line's).
    private func restore(_ anchor: (index: Int, inside: Int), cross: Int, adjustment: UnsafeMutablePointer<GtkAdjustment>) {
        guard anchor.index < lineCount else { return }
        let starts = offsets(cross: cross)
        let inside = min(anchor.inside, max(starts[anchor.index + 1] - starts[anchor.index] - 1, 0))
        let value = (contentOffset ?? 0) + Double(starts[anchor.index] + inside)
        if value != gtk_adjustment_get_value(adjustment) {
            scroll(adjustment, to: value)
        }
    }

    /// Makes line `line`'s rows not made yet and remembers the line's length. False when none
    /// could be made.
    private func makeLine(_ line: Int) -> Bool {
        var added = false
        for index in rowIndices(of: line) where made[index] == nil {
            added = make(index) || added
        }
        guard added else { return false }
        let cross = allocatedCross
        let key = lengthKey(cross)
        if key != knownCross {
            known = [:]
            knownCross = key
        }
        known[line] = lineLength(line, cross: trackLength(cross))
        return true
    }

    /// Makes row `index`'s instance, places its box among the made rows in row order and syncs it.
    /// In the node's sync (`inSync`) the instance is synced right after that sync instead, as a new
    /// child is. False when it cannot be made.
    private func make(_ index: Int, inSync: Bool = false) -> Bool {
        guard let node, let template, rows.indices.contains(index) else { return false }
        let instance = inSync ? node.templateRowNode(template, row: rows[index], rowIndex: index)
                              : node.lazyTemplateRowNode(template, row: rows[index], rowIndex: index)
        let next = made.keys.filter { $0 > index }.min().flatMap { made[$0]?.outerWidget }
        if let next {
            gtk_widget_insert_before(instance.outerWidget, widget, next)
        } else {
            gtk_widget_insert_before(instance.outerWidget, widget, nil)
        }
        made[index] = instance
        if !inSync {
            instance.sync()
        }
        return true
    }

    /// Takes row `index`'s instance out and lets it go; its line's length stays known.
    private func release(_ index: Int, _ row: RenderNode) {
        gtk_widget_unparent(row.outerWidget)
        row.detach()
        made[index] = nil
    }

    // MARK: Lines

    /// The rows per line: 1 in a stack, a grid's tracks.
    private var perLine: Int {
        grid.map { max($0.tracks.count, 1) } ?? 1
    }

    private var lineCount: Int {
        (rows.count + perLine - 1) / perLine
    }

    private func rowIndices(of line: Int) -> Range<Int> {
        (line * perLine)..<min((line + 1) * perLine, rows.count)
    }

    private func isMade(_ line: Int) -> Bool {
        rowIndices(of: line).allSatisfy { made[$0] != nil }
    }

    /// The boxes of line `line`'s made rows, in row order.
    private func madeBoxes(of line: Int) -> [WidgetPointer] {
        rowIndices(of: line).compactMap { made[$0]?.outerWidget }
    }

    /// The made lines, by line.
    private var madeLines: Set<Int> {
        Set(made.keys.map { $0 / perLine })
    }

    // MARK: Following the scrolled window

    /// The nearest scrolled window above the container that scrolls along its axis through a
    /// viewport.
    private func nearestScroller() -> WidgetPointer? {
        let orientation = mainOrientation
        var current = gtk_widget_get_parent(widget)
        while let candidate = current {
            if Gtk.Widget(candidate).isA(gtk_scrolled_window_get_type()),
               let child = gtk_scrolled_window_get_child(OpaquePointer(candidate)),
               Gtk.Widget(child).isA(gtk_viewport_get_type()) {
                var horizontal = GTK_POLICY_NEVER
                var vertical = GTK_POLICY_NEVER
                gtk_scrolled_window_get_policy(OpaquePointer(candidate), &horizontal, &vertical)
                let policy = orientation == GTK_ORIENTATION_VERTICAL ? vertical : horizontal
                if policy != GTK_POLICY_NEVER {
                    return candidate
                }
            }
            current = gtk_widget_get_parent(candidate)
        }
        return nil
    }

    /// Follows `scroller`'s adjustment along the axis (none: stops following). Also while the
    /// container is not shown (a tab not selected): it then makes the rows of the scrolled window's
    /// first pages, not all of them.
    private func follow(_ scroller: WidgetPointer?) {
        guard let scroller else {
            stopFollowing()
            return
        }
        let window = OpaquePointer(scroller)
        guard let current = axis == .vertical ? gtk_scrolled_window_get_vadjustment(window)
                                              : gtk_scrolled_window_get_hadjustment(window) else {
            stopFollowing()
            return
        }
        if scroller == self.scroller && current == adjustment { return }
        stopFollowing()
        self.scroller = scroller
        g_object_ref(current)
        adjustment = current
        let object = UnsafeMutableRawPointer(current)
        for signal in ["value-changed", "changed"] {
            handlers.append(connectSignal(object, signal, .instanceOnly) { [weak self] in
                self?.scheduleRefresh()
            })
        }
    }

    /// Disconnects from the adjustment followed.
    func stopFollowing() {
        if let adjustment {
            for handler in handlers {
                g_signal_handler_disconnect(UnsafeMutableRawPointer(adjustment), handler)
            }
            g_object_unref(adjustment)
        }
        handlers = []
        adjustment = nil
        scroller = nil
    }

    /// Where the container starts along its axis in the scrolled content (the viewport's child),
    /// nil when it is not laid out there.
    var contentOffset: Double? {
        guard let scroller, let viewport = gtk_scrolled_window_get_child(OpaquePointer(scroller)),
              let content = gtk_viewport_get_child(OpaquePointer(viewport)) else { return nil }
        var origin = graphene_point_t(x: 0, y: 0)
        var point = graphene_point_t(x: 0, y: 0)
        guard gtk_widget_compute_point(widget, content, &origin, &point) != 0 else { return nil }
        return Double(axis == .vertical ? point.y : point.x)
    }

    // MARK: Lengths

    private var mainOrientation: GtkOrientation {
        axis == .vertical ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL
    }

    private var crossOrientation: GtkOrientation {
        axis == .vertical ? GTK_ORIENTATION_HORIZONTAL : GTK_ORIENTATION_VERTICAL
    }

    /// The container's allocated size across its axis; -1 before it is allocated.
    var allocatedCross: Int {
        let size = Int(axis == .vertical ? gtk_widget_get_width(widget) : gtk_widget_get_height(widget))
        return size > 0 ? size : -1
    }

    /// What a line's length along the axis depends on across it: a LazyVStack's row's height depends
    /// on its width and a grid's line on its tracks' sizes; a LazyHStack's column's width on nothing.
    private func lengthKey(_ cross: Int) -> Int {
        axis == .vertical || grid != nil ? cross : -1
    }

    /// A stack's row's size across a stack `cross` across (-1: not given): what a stack's child
    /// takes when offered that (all of it, to its cap, when it expands); a LazyHStack's column's
    /// height for its width `length`.
    private func crossSize(of row: WidgetPointer, cross: Int, length: Int = -1) -> Int {
        let forSize = axis == .vertical ? -1 : length
        let size = Gtk.Widget(row).measure(crossOrientation, forSize: forSize)
        guard cross >= 0 else { return max(size.natural, size.minimum) }
        let child: StackChild
        if Gtk.Widget(row).expands(crossOrientation) {
            child = .expanding(minimum: size.minimum, cap: LayoutCaps.cap(row, crossOrientation, forSize: forSize))
        } else {
            child = .fixed(minimum: size.minimum, natural: size.natural)
        }
        return child.size(offered: cross)
    }

    /// A stack's row's natural length along the axis in a stack `cross` across (a LazyVStack's
    /// row's height for the width it gets there).
    private func length(of row: WidgetPointer, cross: Int) -> Int {
        let forSize = axis == .vertical ? crossSize(of: row, cross: cross) : -1
        let size = Gtk.Widget(row).measure(mainOrientation, forSize: forSize)
        return max(size.natural, size.minimum)
    }

    /// What a grid's lines are measured for in a container `cross` across: `cross`, or without one
    /// (-1) the tracks' natural length for all the made rows, as the eager grid takes for all its
    /// children (not each line's own). A stack's: `cross`.
    private func trackLength(_ cross: Int) -> Int {
        guard let grid, cross < 0 else { return cross }
        return LazyGridLayout.naturalTrackLength(grid, items: madeGridBoxes)
    }

    /// The made rows' boxes in row order, those laid out only, as the eager grid's items.
    private var madeGridBoxes: [WidgetPointer] {
        made.sorted { $0.key < $1.key }.map { $0.value.outerWidget! }.filter { gtk_widget_should_layout($0) != 0 }
    }

    /// Line `line`'s length along the axis in a container `cross` across (for a grid, trackLength's
    /// result), from its made rows: a stack's row's natural length, a grid line's tallest cell
    /// (LazyGridLayout).
    private func lineLength(_ line: Int, cross: Int) -> Int {
        let boxes = madeBoxes(of: line)
        if let grid {
            return LazyGridLayout.lineLength(grid, items: boxes, trackLength: cross)
        }
        return boxes.first.map { length(of: $0, cross: cross) } ?? 0
    }

    /// The lines' lengths known in a container `cross` across, by line (the made lines measured
    /// now, the others remembered for that size), and the estimate for the rest: their average.
    private func lengths(cross: Int) -> (known: [Int: Int], estimate: Int) {
        var lengths = lengthKey(cross) == knownCross ? known : [:]
        let across = trackLength(cross)
        for line in madeLines {
            lengths[line] = lineLength(line, cross: across)
        }
        guard !lengths.isEmpty else { return (lengths, Self.initialEstimate) }
        let total = lengths.values.reduce(0, +)
        return (lengths, (total + lengths.count / 2) / lengths.count)
    }

    /// Where each line starts along the axis in a container `cross` across, and the container's
    /// whole length (the last element).
    private func offsets(cross: Int) -> [Int] {
        let (lengths, estimate) = self.lengths(cross: cross)
        let count = lineCount
        var result: [Int] = []
        result.reserveCapacity(count + 1)
        var position = 0
        for line in 0..<count {
            result.append(position)
            position += (lengths[line] ?? estimate) + (line + 1 < count ? spacing : 0)
        }
        result.append(position)
        return result
    }

    /// Where line `index` starts (a stack's row) in a container `cross` across.
    func offset(of index: Int, cross: Int) -> Int {
        offsets(cross: cross)[index]
    }

    /// The line at `position` along the axis (the last one past the end; a stack's row); nil
    /// without rows.
    func row(at position: Int, cross: Int) -> Int? {
        guard lineCount > 0 else { return nil }
        return line(at: position, starts: offsets(cross: cross))
    }

    /// The line at `position` among lines starting at `starts` (offsets), of at least one line.
    private func line(at position: Int, starts: [Int]) -> Int {
        let count = lineCount
        var index = 0
        while index + 1 < count && starts[index + 1] <= position {
            index += 1
        }
        return index
    }

    /// The lines that reach into [from, to) along the axis.
    private func lineRange(from: Double, to: Double, cross: Int) -> Range<Int> {
        let starts = offsets(cross: cross)
        let count = lineCount
        var first = count
        var last = count
        for line in 0..<count {
            if first == count, Double(starts[line + 1]) > from {
                first = line
            }
            if Double(starts[line]) >= to {
                last = line
                break
            }
        }
        return first..<max(first, last)
    }

    // MARK: Layout

    static func layoutType() -> GType {
        if lazyRowsLayoutType != 0 { return lazyRowsLayoutType }
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkLayoutManagerClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkLayoutManager>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            let layoutClass = klass.assumingMemoryBound(to: GtkLayoutManagerClass.self)
            // A LazyHGrid's lines are widths for its height, as the eager grid's.
            layoutClass.pointee.get_request_mode = { _, widget in
                MainActor.assumeIsolated {
                    let rows = widget.flatMap { attached(on: $0, key: lazyRowsKey) }
                    return rows?.grid != nil && rows?.axis == .horizontal ? GTK_SIZE_REQUEST_WIDTH_FOR_HEIGHT : GTK_SIZE_REQUEST_HEIGHT_FOR_WIDTH
                }
            }
            layoutClass.pointee.measure = { _, widget, orientation, forSize, minimum, natural, minimumBaseline, naturalBaseline in
                guard let widget else { return }
                let size = MainActor.assumeIsolated {
                    attached(on: widget, key: lazyRowsKey)?.measure(orientation, forSize: Int(forSize)) ?? (minimum: 0, natural: 0)
                }
                minimum?.pointee = Int32(clamping: size.minimum)
                natural?.pointee = Int32(clamping: size.natural)
                minimumBaseline?.pointee = -1
                naturalBaseline?.pointee = -1
            }
            layoutClass.pointee.allocate = { _, widget, width, height, _ in
                guard let widget else { return }
                MainActor.assumeIsolated {
                    attached(on: widget, key: lazyRowsKey)?.allocate(width: Int(width), height: Int(height))
                }
            }
        }
        lazyRowsLayoutType = g_type_register_static(gtk_layout_manager_get_type(), "ActionUILazyRowsLayout", &info, GTypeFlags(rawValue: 0))
        return lazyRowsLayoutType
    }

    /// Along the axis: every line's length and the spacing, known or estimated; it cannot be made
    /// smaller. Across: a stack's nothing at least (it takes what it is offered), its widest made
    /// row at best; a grid's its tracks' smallest length at least, at best the length its made rows
    /// give its flexible tracks.
    private func measure(_ orientation: GtkOrientation, forSize: Int) -> (minimum: Int, natural: Int) {
        if orientation == mainOrientation {
            // A LazyVStack's height and a grid's line length are for a size across; a LazyHStack's
            // width is for none.
            let cross = lengthKey(forSize)
            let length = offsets(cross: cross).last ?? 0
            return (length, length)
        }
        if let grid {
            return (LazyGridLayout.minimumLength(grid.tracks), LazyGridLayout.naturalTrackLength(grid, items: madeGridBoxes))
        }
        var widest = 0
        for row in made.values {
            let length = axis == .vertical ? -1 : self.length(of: row.outerWidget, cross: -1)
            widest = max(widest, crossSize(of: row.outerWidget, cross: -1, length: length))
        }
        return (0, widest)
    }

    /// Places the made lines at their offsets (a stack's row aligned across the stack, a grid's
    /// cells in their tracks), and remembers their lengths for this size. A change of size or place
    /// may bring other lines into view: refresh.
    private func allocate(width: Int, height: Int) {
        let cross = axis == .vertical ? width : height
        let key = lengthKey(cross)
        if key != knownCross {
            // The line at the top before the change, from the lengths for the old width; the next
            // refresh puts it back (the scroll position cannot change during allocation). Kept
            // when an earlier change was not put back yet.
            if pendingAnchor == nil, adjustment != nil, knownCross >= 0, let top = lastTop, top > 0, lineCount > 0 {
                let starts = offsets(cross: knownCross)
                let index = line(at: Int(top), starts: starts)
                pendingAnchor = (index, Int(top) - starts[index])
            }
            known = [:]
            knownCross = key
        }
        let starts = offsets(cross: cross)
        for line in madeLines.sorted() {
            let length = lineLength(line, cross: cross)
            known[line] = length
            if let grid {
                LazyGridLayout.allocateLine(grid, items: madeBoxes(of: line), trackLength: cross,
                                            lineStart: starts[line], lineLength: length)
                continue
            }
            guard let box = madeBoxes(of: line).first else { continue }
            let across = crossSize(of: box, cross: cross, length: length)
            let block = max(across, cross)
            let place = StackSolver.centeredStart(length: block, available: cross)
                + StackSolver.alignedOffset(size: across, block: block, alignment: alignment)
            let x = axis == .vertical ? place : starts[line]
            let y = axis == .vertical ? starts[line] : place
            var origin = graphene_point_t(x: Float(x), y: Float(y))
            let size = axis == .vertical ? (across, length) : (length, across)
            gtk_widget_allocate(box, Int32(clamping: size.0), Int32(clamping: size.1), -1, gsk_transform_translate(nil, &origin))
        }
        scheduleRefresh()
    }
}
