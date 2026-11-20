// Sources/Layout/LazyRows.swift
/*
 The template form of LazyVStack and LazyHStack on GTK, made lazily: a row's template instance (the
 template with the row's data, RenderNode.lazyTemplateRowNode) is made only when the row comes in
 or near the part of the stack its ScrollView shows, and let go when it is far out of view, as
 SwiftUI's lazy stacks make their rows. A ScrollView of 2000 rows opens and scrolls with tens of
 rows made.

 - What is shown: the stack follows the nearest GtkScrolledWindow above it that scrolls along its
   axis, through the scrolled window's adjustment (its position and page size) and the stack's
   place in the scrolled content. Rows within a page before and after the visible part are made;
   rows more than two pages away are let go, so small scrolls do not make and let go the same rows.
   Outside any such scrolled window every row is made, in the stack's sync as the eager form makes
   them.
 - Sizes: a made row is measured (a LazyVStack's row for the stack's width: its height for that
   width); the length of a row let go is remembered for that width; a row never made is estimated
   at the average of the rows known. The stack is as long as all of them with the spacing between.
 - Anchoring: making rows changes the known lengths and the estimate, so the rows above the visible
   part may become longer or shorter. The scroll position moves by the same amount, so the row at
   the top of the visible part stays where it is; GTK does not do this itself. A change of the
   stack's width changes every row's length (a LazyVStack's rows are measured for its width): the
   row at the top and how far into it the visible part started are kept across it too.
 - Rows are made and let go outside GTK's measuring and allocation (GTK forbids changing its
   widget tree there), on a main loop source scheduled by the adjustment's signals, by the stack's
   allocation and by its update; the stack's size is then queued again.
 - Across its axis the stack takes all the room it is offered and aligns each row in it by its
   alignment; it does not expand along it (StackLayout.setLazy's flags). The rows made at a moment
   decide neither: only its natural size across is its widest made row's.
 - Rows are kept by index, as in the eager form (TemplateRows): a row whose data changes is made
   again, rows added at the end are added, rows removed from the end are removed. A row let go
   loses only transient state (keyboard focus, a text selection): its data lives in the content
   rows (a row-bound Toggle writes its row), so it shows the same when made again.
*/

import CAdwaita

let lazyRowsKey = AttachKey<LazyRows>("actionui-lazy-rows")

nonisolated(unsafe) private var lazyRowsLayoutType: GType = 0

/// A lazy stack's rows in its template form, attached to its container widget (laid out by
/// LazyRows.layoutType).
@MainActor
final class LazyRows {
    /// A row's length along the axis before any row has been measured.
    static let initialEstimate = 20
    /// The page assumed before the scrolled window is laid out.
    static let fallbackPage = 600.0

    let axis: StackAxis
    /// The container widget, which keeps this object.
    private let widget: WidgetPointer
    private weak var node: RenderNode?
    private var template: (any ActionUIElementBase)?
    /// The content rows.
    private(set) var rows: [[String]] = []
    private(set) var spacing = 0
    private(set) var alignment = StackSolver.Alignment.center
    /// The rows made, by index.
    private(set) var made: [Int: RenderNode] = [:]
    /// Rows' lengths along the axis, by index, measured for `knownCross` across: the made rows' and
    /// those let go since.
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
    /// Where the visible part started at the last refresh, in the stack along its axis: what a
    /// change of width keeps in view.
    private var lastTop: Double?
    /// The row at the top of the visible part before a change of width, and how far into it the
    /// visible part started, to be put back by the next refresh.
    private var pendingAnchor: (index: Int, inside: Int)?

    private init(widget: WidgetPointer, node: RenderNode, axis: StackAxis) {
        self.widget = widget
        self.node = node
        self.axis = axis
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

    /// A new container for a lazy stack's template form, empty until update.
    static func makeWidget(_ node: RenderNode, axis: StackAxis) -> WidgetPointer {
        let widget = makeContainer(layoutType: layoutType())
        let rows = LazyRows(widget: widget, node: node, axis: axis)
        attach(rows, to: widget, key: lazyRowsKey)
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

    /// Takes `node`'s template, content rows, spacing and alignment. Runs in the node's sync: rows
    /// whose data changed or that went are let go here, rows are made later (refresh), outside the
    /// sync's observation.
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
            // A changed row keeps its remembered length until it is made again and measured: closer
            // than the estimate, so new data that changes no length keeps the same rows in view
            // (forgotten, the rows above would all take the estimate and the view would move).
            for index in known.keys where index >= newRows.count {
                known[index] = nil
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

    /// Makes the rows in or near the visible part of the stack and lets go of those far from it
    /// (every row outside a scrolled window), keeping the top visible row in place.
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
        // The visible part in the stack's coordinates along its axis.
        let top = gtk_adjustment_get_value(adjustment) - (contentOffset ?? 0)
        lastTop = top
        let anchor = top > 0 ? row(at: Int(top), cross: cross) : nil
        let anchorOffset = anchor.map { offset(of: $0, cross: cross) }
        var changed = false
        // Made rows change the estimate, and so which rows are near: a few rounds settle it.
        for _ in 0..<4 {
            let wanted = rowRange(from: top - page, to: top + 2 * page, cross: cross)
            var added = false
            for index in wanted where made[index] == nil {
                added = make(index) || added
            }
            changed = changed || added
            if !added { break }
        }
        let kept = rowRange(from: top - 2 * page, to: top + 3 * page, cross: cross)
        for (index, row) in made where !kept.contains(index) {
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

    /// Scrolls so the visible part starts in row `anchor.index` as far into it as before a change
    /// of width (at most to the end of the row and the gap after it, which row(at:) counts as the
    /// row's).
    private func restore(_ anchor: (index: Int, inside: Int), cross: Int, adjustment: UnsafeMutablePointer<GtkAdjustment>) {
        guard rows.indices.contains(anchor.index) else { return }
        let starts = offsets(cross: cross)
        let inside = min(anchor.inside, max(starts[anchor.index + 1] - starts[anchor.index] - 1, 0))
        let value = (contentOffset ?? 0) + Double(starts[anchor.index] + inside)
        if value != gtk_adjustment_get_value(adjustment) {
            scroll(adjustment, to: value)
        }
    }

    /// Makes row `index`'s instance, places its box among the made rows in row order, syncs it and
    /// remembers its length. In the node's sync (`inSync`) the instance is synced right after that
    /// sync instead, as a new child is, and its length is found at the next allocation. False when
    /// it cannot be made.
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
        if inSync { return true }
        instance.sync()
        let cross = allocatedCross
        let key = lengthKey(cross)
        if key != knownCross {
            known = [:]
            knownCross = key
        }
        known[index] = length(of: instance.outerWidget, cross: cross)
        return true
    }

    /// Takes row `index`'s instance out and lets it go; its length stays known.
    private func release(_ index: Int, _ row: RenderNode) {
        gtk_widget_unparent(row.outerWidget)
        row.detach()
        made[index] = nil
    }

    // MARK: Following the scrolled window

    /// The nearest scrolled window above the stack that scrolls along its axis through a viewport.
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

    /// Follows `scroller`'s adjustment along the axis (none: stops following). Also while the stack
    /// is not shown (a tab not selected): it then makes the rows of the scrolled window's first
    /// pages, not all of them.
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

    /// Where the stack starts along its axis in the scrolled content (the viewport's child), nil
    /// when it is not laid out there.
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

    /// The stack's allocated size across its axis; -1 before it is allocated.
    var allocatedCross: Int {
        let size = Int(axis == .vertical ? gtk_widget_get_width(widget) : gtk_widget_get_height(widget))
        return size > 0 ? size : -1
    }

    /// What a row's length along the axis depends on across it: a LazyVStack's row's height depends
    /// on its width, a LazyHStack's column's width on nothing.
    private func lengthKey(_ cross: Int) -> Int {
        axis == .vertical ? cross : -1
    }

    /// A row's size across a stack `cross` across (-1: not given): what a stack's child takes when
    /// offered that (all of it, to its cap, when it expands); a LazyHStack's column's height for its
    /// width `length`.
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

    /// A row's natural length along the axis in a stack `cross` across (a LazyVStack's row's height
    /// for the width it gets there).
    private func length(of row: WidgetPointer, cross: Int) -> Int {
        let forSize = axis == .vertical ? crossSize(of: row, cross: cross) : -1
        let size = Gtk.Widget(row).measure(mainOrientation, forSize: forSize)
        return max(size.natural, size.minimum)
    }

    /// The rows' lengths known in a stack `cross` across, by index (the made rows measured now, the
    /// others remembered for that size), and the estimate for the rest: their average.
    private func lengths(cross: Int) -> (known: [Int: Int], estimate: Int) {
        var lengths = lengthKey(cross) == knownCross ? known : [:]
        for (index, row) in made {
            lengths[index] = length(of: row.outerWidget, cross: cross)
        }
        guard !lengths.isEmpty else { return (lengths, Self.initialEstimate) }
        let total = lengths.values.reduce(0, +)
        return (lengths, (total + lengths.count / 2) / lengths.count)
    }

    /// Where each row starts along the axis in a stack `cross` across, and the stack's whole
    /// length (the last element).
    private func offsets(cross: Int) -> [Int] {
        let (lengths, estimate) = self.lengths(cross: cross)
        var result: [Int] = []
        result.reserveCapacity(rows.count + 1)
        var position = 0
        for index in rows.indices {
            result.append(position)
            position += (lengths[index] ?? estimate) + (index + 1 < rows.count ? spacing : 0)
        }
        result.append(position)
        return result
    }

    func offset(of index: Int, cross: Int) -> Int {
        offsets(cross: cross)[index]
    }

    /// The row at `position` along the axis (the last one past the end); nil without rows.
    func row(at position: Int, cross: Int) -> Int? {
        guard !rows.isEmpty else { return nil }
        return row(at: position, starts: offsets(cross: cross))
    }

    /// The row at `position` among rows starting at `starts` (offsets), of at least one row.
    private func row(at position: Int, starts: [Int]) -> Int {
        var index = 0
        while index + 1 < rows.count && starts[index + 1] <= position {
            index += 1
        }
        return index
    }

    /// The rows that reach into [from, to) along the axis.
    private func rowRange(from: Double, to: Double, cross: Int) -> Range<Int> {
        let starts = offsets(cross: cross)
        var first = rows.count
        var last = rows.count
        for index in rows.indices {
            if first == rows.count, Double(starts[index + 1]) > from {
                first = index
            }
            if Double(starts[index]) >= to {
                last = index
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
            layoutClass.pointee.get_request_mode = { _, _ in GTK_SIZE_REQUEST_HEIGHT_FOR_WIDTH }
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

    /// Along the axis: every row's length and the spacing, known or estimated; it cannot be made
    /// smaller. Across: nothing at least (it takes what it is offered), its widest made row at
    /// best.
    private func measure(_ orientation: GtkOrientation, forSize: Int) -> (minimum: Int, natural: Int) {
        if orientation == mainOrientation {
            // A LazyVStack's height is for a width; a LazyHStack's width is for no height.
            let cross = axis == .vertical ? forSize : -1
            let length = offsets(cross: cross).last ?? 0
            return (length, length)
        }
        var widest = 0
        for row in made.values {
            let length = axis == .vertical ? -1 : self.length(of: row.outerWidget, cross: -1)
            widest = max(widest, crossSize(of: row.outerWidget, cross: -1, length: length))
        }
        return (0, widest)
    }

    /// Places the made rows at their offsets, each aligned across the stack, and remembers their
    /// lengths for this size. A change of size or place may bring other rows into view: refresh.
    private func allocate(width: Int, height: Int) {
        let cross = axis == .vertical ? width : height
        let key = lengthKey(cross)
        if key != knownCross {
            // The row at the top before the change, from the lengths for the old width; the next
            // refresh puts it back (the scroll position cannot change during allocation). Kept
            // when an earlier change was not put back yet.
            if pendingAnchor == nil, adjustment != nil, knownCross >= 0, let top = lastTop, top > 0, !rows.isEmpty {
                let starts = offsets(cross: knownCross)
                let index = row(at: Int(top), starts: starts)
                pendingAnchor = (index, Int(top) - starts[index])
            }
            known = [:]
            knownCross = key
        }
        let starts = offsets(cross: cross)
        for (index, row) in made.sorted(by: { $0.key < $1.key }) {
            let box = row.outerWidget!
            let length = self.length(of: box, cross: cross)
            known[index] = length
            let across = crossSize(of: box, cross: cross, length: length)
            let block = max(across, cross)
            let place = StackSolver.centeredStart(length: block, available: cross)
                + StackSolver.alignedOffset(size: across, block: block, alignment: alignment)
            let x = axis == .vertical ? place : starts[index]
            let y = axis == .vertical ? starts[index] : place
            var origin = graphene_point_t(x: Float(x), y: Float(y))
            let size = axis == .vertical ? (across, length) : (length, across)
            gtk_widget_allocate(box, Int32(clamping: size.0), Int32(clamping: size.1), -1, gsk_transform_translate(nil, &origin))
        }
        scheduleRefresh()
    }
}
