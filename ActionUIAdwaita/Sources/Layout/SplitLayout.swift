// Sources/Layout/SplitLayout.swift
/*
 HSplitView's and VSplitView's layout on GTK: the panes side by side (or stacked) with a 1 pixel
 divider between each pair, which the user drags, as macOS's split views draw them. GtkPaned holds
 two panes and splits them by their natural sizes, which does not give SwiftUI's layout, so the
 split view is a container of its own.

 Measured on macOS 27 (HSplitView): the panes start as an HStack with no spacing lays them out
 (StackSolver), the dividers 1 point each: flexible panes share the space, panes that are not
 flexible take their natural size, and a split view of such panes hugs them. The first pane's
 frame's ideal size, when it has one, sets the first divider instead (ActionUI's own setter on
 Apple). Each pane's box is placed as a one-child ZStack places it: as long as the pane in the axis
 and the cross axis when it expands, else its natural size, centered.

 - Dragging a divider moves the space between its two panes, within each one's minimum and the
   largest it takes (its natural size, or its frame's maximum when it expands), as NSSplitView
   keeps panes within their constraints. A press counts within 4 pixels of a divider, where the
   pointer shows the resize cursor.
 - Once the user has dragged, the panes keep their sizes, and a change of the split view's size
   goes to the last pane (the content beside a sidebar), then to the ones before it as each
   reaches its minimum or maximum. A change in the panes (one added or removed) lays them out from
   the start again.
*/

import CAdwaita

nonisolated(unsafe) private var splitLayoutType: GType = 0

/// A split view's panes, dividers and sizes, attached to its container.
@MainActor
final class SplitState {
    let orientation: GtkOrientation
    /// The panes' boxes, in order, and the dividers between them.
    private(set) var panes: [WidgetPointer] = []
    private(set) var dividers: [WidgetPointer] = []
    /// The first pane's ideal size in the axis, which sets the first divider.
    var firstIdeal: Int?
    /// The panes' sizes the user set by dragging; nil until then.
    var userSizes: [Int]?
    /// The panes' sizes when last allocated, where the dividers are.
    var allocatedSizes: [Int] = []
    /// The divider being dragged and the panes' sizes when the drag began.
    var drag: (index: Int, start: [Int])?
    var cursorShown = false

    init(orientation: GtkOrientation) {
        self.orientation = orientation
    }

    /// Makes `panes` the split view's panes, in order, with `dividerCount` dividers (one less than the
    /// panes shown, a Group's children counting as panes).
    func setPanes(_ panes: [WidgetPointer], dividerCount: Int, in container: WidgetPointer) {
        if panes.count != self.panes.count || zip(panes, self.panes).contains(where: { $0 != $1 }) {
            userSizes = nil
        }
        self.panes = panes
        setDividerCount(dividerCount, in: container)
        // Pane, divider, pane, ...: the order focus and accessibility follow.
        var previous: WidgetPointer?
        for (index, pane) in panes.enumerated() {
            for widget in [pane] + (index < dividers.count ? [dividers[index]] : []) {
                if gtk_widget_get_parent(widget) != container || gtk_widget_get_prev_sibling(widget) != previous {
                    gtk_widget_insert_after(widget, container, previous)
                }
                previous = widget
            }
        }
    }

    /// Adds or removes dividers to make `count`.
    func setDividerCount(_ count: Int, in container: WidgetPointer) {
        while dividers.count < max(0, count) {
            let divider = gtk_separator_new(orientation == GTK_ORIENTATION_HORIZONTAL ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL)!
            gtk_widget_set_parent(divider, container)
            dividers.append(divider)
        }
        while dividers.count > max(0, count) {
            gtk_widget_unparent(dividers.removeLast())
        }
    }
}

let splitStateKey = AttachKey<SplitState>("actionui-split")

@MainActor
enum SplitLayout {
    /// A divider's thickness, and how far from it a press grabs it.
    static let dividerThickness = 1
    static let grabDistance = 4.0

    /// A new, empty split view container laid out along `orientation`.
    static func makeSplit(_ orientation: GtkOrientation) -> WidgetPointer {
        let container = makeContainer(layoutType: layoutType())
        let state = SplitState(orientation: orientation)
        attach(state, to: container, key: splitStateKey)
        watchDrags(container, state)
        return container
    }

    // MARK: Sizes (no GTK, so they are tested without a display)

    /// The panes' sizes before the user drags: as an HStack (or VStack) with dividers for spacing
    /// lays them out, the first pane at `firstIdeal` (within its range, and leaving the others
    /// their minimums where it can) when given.
    static func initialSizes(_ panes: [StackChild], available: Int, firstIdeal: Int?) -> [Int] {
        var children = panes
        if let ideal = firstIdeal, var first = children.first {
            let room = available - dividerThickness * (children.count - 1) - children.dropFirst().reduce(0) { $0 + $1.minimum }
            let size = max(first.minimum, min(first.maximum.map { min(ideal, $0) } ?? ideal, room))
            first.minimum = size
            first.maximum = size
            children[0] = first
        }
        return StackSolver.mainSizes(children, available: available, spacing: dividerThickness)
    }

    /// The user's sizes fitted to `available`: the difference goes to the last pane, then to the
    /// ones before it as each reaches its minimum or maximum.
    static func fitted(_ sizes: [Int], _ panes: [StackChild], available: Int) -> [Int] {
        var result = sizes
        var difference = available - StackSolver.length(of: sizes, spacing: dividerThickness)
        for index in result.indices.reversed() where difference != 0 {
            let pane = panes[index]
            let wanted = result[index] + difference
            let size = max(pane.minimum, pane.maximum.map { min(wanted, $0) } ?? wanted)
            difference -= size - result[index]
            result[index] = size
        }
        return result
    }

    /// The sizes after the divider after pane `index` moved `delta` from where it was at `start`:
    /// the two panes beside it trade space, each kept within its range.
    static func dragged(_ start: [Int], _ panes: [StackChild], index: Int, delta: Int) -> [Int] {
        guard index + 1 < start.count else { return start }
        let before = panes[index]
        let after = panes[index + 1]
        // The moves each pane allows: growing the first shrinks the second.
        var lower = before.minimum - start[index]
        var upper = before.maximum.map { $0 - start[index] } ?? Int.max
        lower = max(lower, after.maximum.map { start[index + 1] - $0 } ?? Int.min)
        upper = min(upper, start[index + 1] - after.minimum)
        guard lower <= upper else { return start }
        let move = min(max(delta, lower), upper)
        var result = start
        result[index] += move
        result[index + 1] -= move
        return result
    }

    // MARK: Layout manager

    static func layoutType() -> GType {
        if splitLayoutType != 0 { return splitLayoutType }
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkLayoutManagerClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkLayoutManager>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            let layoutClass = klass.assumingMemoryBound(to: GtkLayoutManagerClass.self)
            // Height for width either way, as the stacks: a VSplitView's panes' heights depend on
            // their widths, as a VStack's do.
            layoutClass.pointee.get_request_mode = { _, _ in GTK_SIZE_REQUEST_HEIGHT_FOR_WIDTH }
            layoutClass.pointee.measure = { _, widget, orientation, forSize, minimum, natural, minimumBaseline, naturalBaseline in
                guard let widget else { return }
                let size = MainActor.assumeIsolated { SplitLayout.measure(widget, orientation, forSize: Int(forSize)) }
                minimum?.pointee = Int32(clamping: size.minimum)
                natural?.pointee = Int32(clamping: size.natural)
                minimumBaseline?.pointee = -1
                naturalBaseline?.pointee = -1
            }
            layoutClass.pointee.allocate = { _, widget, width, height, _ in
                guard let widget else { return }
                MainActor.assumeIsolated { SplitLayout.allocate(widget, width: Int(width), height: Int(height)) }
            }
        }
        splitLayoutType = g_type_register_static(gtk_layout_manager_get_type(), "ActionUISplitLayout", &info, GTypeFlags(0))
        return splitLayoutType
    }

    /// A pane as StackSolver sees it in the axis, measured for `forSize` across (-1: none).
    private static func stackChild(_ pane: WidgetPointer, _ axis: GtkOrientation, forSize: Int = -1) -> StackChild {
        let size = Gtk.Widget(pane).measure(axis, forSize: forSize)
        return Gtk.Widget(pane).expands(axis)
            ? .expanding(minimum: size.minimum, cap: LayoutCaps.cap(pane, axis, forSize: forSize))
            : .fixed(minimum: size.minimum, natural: size.natural)
    }

    private static func cross(_ axis: GtkOrientation) -> GtkOrientation {
        axis == GTK_ORIENTATION_HORIZONTAL ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL
    }

    /// The panes the layout places: a Group's children are panes of their own, as on macOS; an
    /// EmptyView's box (not visible) is no pane and gets no divider.
    static func shownPanes(_ state: SplitState) -> [WidgetPointer] {
        state.panes.flatMap { pane -> [WidgetPointer] in
            if let group = Group.widget(inBox: pane) {
                return layoutChildren(group).filter(Group.takesPlace)
            }
            return gtk_widget_should_layout(pane) != 0 ? [pane] : []
        }
    }

    /// A pane's size across a split view `breadth` across (-1: none given, its natural size), as a
    /// one-child ZStack sizes its child, measured for `forSize` along the axis.
    private static func acrossSize(_ pane: WidgetPointer, _ axis: GtkOrientation, breadth: Int, forSize: Int = -1) -> Int {
        let orientation = cross(axis)
        let size = Gtk.Widget(pane).measure(orientation, forSize: forSize)
        guard breadth >= 0 else { return size.natural }
        let range: StackChild = Gtk.Widget(pane).expands(orientation)
            ? .expanding(minimum: size.minimum, cap: LayoutCaps.cap(pane, orientation, forSize: forSize))
            : .fixed(minimum: size.minimum, natural: size.natural)
        return range.size(offered: breadth)
    }

    /// The panes as StackSolver sees them along the axis in a split view `breadth` across, and the
    /// width each is measured for: a VSplitView's panes' heights are for the widths they get (height
    /// for width); an HSplitView's widths need no height (-1).
    private static func axisChildren(_ panes: [WidgetPointer], _ axis: GtkOrientation, breadth: Int) -> (children: [StackChild], forSizes: [Int]) {
        let forSizes = panes.map { axis == GTK_ORIENTATION_VERTICAL && breadth >= 0 ? acrossSize($0, axis, breadth: breadth) : -1 }
        return (zip(panes, forSizes).map { stackChild($0, axis, forSize: $1) }, forSizes)
    }

    /// The panes' sizes in the axis for a split view `available` long.
    private static func sizes(_ state: SplitState, _ panes: [StackChild], available: Int) -> [Int] {
        if let user = state.userSizes, user.count == panes.count {
            return fitted(user, panes, available: available)
        }
        return initialSizes(panes, available: available, firstIdeal: state.firstIdeal)
    }

    /// How long a pane is along the axis in its share `size`: all of it where it expands, else at
    /// most its natural size (`child`'s maximum), as a one-child ZStack places its child.
    private static func along(_ child: StackChild, size: Int) -> Int {
        child.maximum.map { min(size, $0) } ?? size
    }

    private static func measure(_ widget: WidgetPointer, _ orientation: GtkOrientation, forSize: Int) -> (minimum: Int, natural: Int) {
        guard let state = attached(on: widget, key: splitStateKey) else { return (0, 0) }
        let panes = shownPanes(state)
        guard !panes.isEmpty else { return (0, 0) }
        let axis = state.orientation
        let gaps = dividerThickness * (panes.count - 1)
        if orientation == axis {
            // A VSplitView's height for `forSize` wide: each pane's height for the width it gets.
            let forSizes = panes.map { orientation == GTK_ORIENTATION_VERTICAL && forSize >= 0 ? acrossSize($0, axis, breadth: forSize) : -1 }
            let measured = zip(panes, forSizes).map { Gtk.Widget($0).measure(axis, forSize: $1) }
            return (measured.reduce(gaps) { $0 + $1.minimum }, measured.reduce(gaps) { $0 + $1.natural })
        }
        // Across: the widest (tallest) pane; an HSplitView's each measured at the width it gets
        // for `forSize` wide.
        var lengths = panes.map { _ in -1 }
        if orientation == GTK_ORIENTATION_VERTICAL, forSize >= 0 {
            let children = axisChildren(panes, axis, breadth: -1).children
            lengths = zip(children, sizes(state, children, available: forSize)).map { along($0, size: $1) }
        }
        var result = (minimum: 0, natural: 0)
        for (pane, length) in zip(panes, lengths) {
            let size = Gtk.Widget(pane).measure(orientation, forSize: length)
            result = (max(result.minimum, size.minimum), max(result.natural, size.natural))
        }
        return result
    }

    private static func allocate(_ widget: WidgetPointer, width: Int, height: Int) {
        guard let state = attached(on: widget, key: splitStateKey) else { return }
        // A Group's box spans the split view, so its child boxes are placed in the split's coordinates.
        Group.allocateGroups(in: widget, width: width, height: height)
        let panes = shownPanes(state)
        if panes.count - 1 > state.dividers.count {
            // A Group gained children without the split view updating: the dividers come next turn.
            _ = runAfter(milliseconds: 0) { [weak state] in
                guard let state else { return }
                state.setDividerCount(shownPanes(state).count - 1, in: widget)
                gtk_widget_queue_resize(widget)
            }
        }
        // The dividers between shown panes; the others are not drawn.
        for (index, divider) in state.dividers.enumerated() {
            gtk_widget_set_child_visible(divider, index < panes.count - 1 ? 1 : 0)
        }
        guard !panes.isEmpty else {
            state.allocatedSizes = []
            return
        }
        let axis = state.orientation
        let horizontal = axis == GTK_ORIENTATION_HORIZONTAL
        let length = horizontal ? width : height
        let breadth = horizontal ? height : width
        let (children, forSizes) = axisChildren(panes, axis, breadth: breadth)
        let lengths = sizes(state, children, available: length)
        state.allocatedSizes = lengths
        var position = 0
        for (index, pane) in panes.enumerated() {
            let size = lengths[index]
            // As a one-child ZStack places its child: all of the pane where it expands, else its
            // natural size, centered.
            let along = along(children[index], size: size)
            let across = horizontal ? acrossSize(pane, axis, breadth: breadth, forSize: along) : forSizes[index]
            let alongStart = position + StackSolver.centeredStart(length: along, available: size)
            let acrossStart = StackSolver.centeredStart(length: across, available: breadth)
            place(pane, along: alongStart, across: acrossStart, length: along, breadth: across, horizontal: horizontal)
            position += size
            if index < panes.count - 1, index < state.dividers.count {
                let divider = state.dividers[index]
                // Measured first, as GTK expects of an allocated widget.
                _ = Gtk.Widget(divider).measure(axis)
                place(divider, along: position, across: 0, length: dividerThickness, breadth: breadth, horizontal: horizontal)
                position += dividerThickness
            }
        }
    }

    private static func place(_ child: WidgetPointer, along: Int, across: Int, length: Int, breadth: Int, horizontal: Bool) {
        var origin = horizontal ? graphene_point_t(x: Float(along), y: Float(across)) : graphene_point_t(x: Float(across), y: Float(along))
        gtk_widget_allocate(child, Int32(clamping: horizontal ? length : breadth), Int32(clamping: horizontal ? breadth : length), -1,
                            gsk_transform_translate(nil, &origin))
    }

    // MARK: Dragging

    /// The divider within grabDistance of `point` (along the axis), if any.
    static func divider(at point: Double, _ state: SplitState) -> Int? {
        var position = 0
        for (index, size) in state.allocatedSizes.dropLast().enumerated() {
            position += size
            let center = Double(position) + Double(dividerThickness) / 2
            if abs(point - center) <= grabDistance { return index }
            position += dividerThickness
        }
        return nil
    }

    /// Moves the divider being dragged `delta` from where it was when the drag began.
    static func moveDivider(_ container: WidgetPointer, _ state: SplitState, delta: Int) {
        guard let drag = state.drag else { return }
        let breadth = state.orientation == GTK_ORIENTATION_HORIZONTAL ? gtk_widget_get_height(container) : gtk_widget_get_width(container)
        let panes = axisChildren(shownPanes(state), state.orientation, breadth: Int(breadth)).children
        guard drag.start.count == panes.count else { return }
        state.userSizes = dragged(drag.start, panes, index: drag.index, delta: delta)
        // A resize, not only an allocation: an HSplitView's height for its width depends on its
        // panes' widths (wrapping text), and GTK keeps the measurements until a resize.
        gtk_widget_queue_resize(container)
    }

    /// Shows the resize cursor on the split view, or takes it away.
    private static func showCursor(_ container: WidgetPointer, _ state: SplitState, _ shown: Bool) {
        guard shown != state.cursorShown else { return }
        state.cursorShown = shown
        let name = state.orientation == GTK_ORIENTATION_HORIZONTAL ? "col-resize" : "row-resize"
        gtk_widget_set_cursor_from_name(container, shown ? name : nil)
    }

    /// A drag gesture that moves the divider pressed (seen before the panes see the press) and a
    /// motion controller that shows the resize cursor near a divider.
    private static func watchDrags(_ container: WidgetPointer, _ state: SplitState) {
        let horizontal = state.orientation == GTK_ORIENTATION_HORIZONTAL
        let drag = gtk_gesture_drag_new()!
        gtk_gesture_single_set_button(drag, 1)
        gtk_event_controller_set_propagation_phase(drag, GTK_PHASE_CAPTURE)
        connectPoint(UnsafeMutableRawPointer(drag), "drag-begin") { [weak state] x, y in
            guard let state else { return }
            if let index = divider(at: horizontal ? x : y, state) {
                state.drag = (index, state.allocatedSizes)
                gtk_gesture_set_state(drag, GTK_EVENT_SEQUENCE_CLAIMED)
            } else {
                gtk_gesture_set_state(drag, GTK_EVENT_SEQUENCE_DENIED)
            }
        }
        connectPoint(UnsafeMutableRawPointer(drag), "drag-update") { [weak state] dx, dy in
            guard let state else { return }
            moveDivider(container, state, delta: Int((horizontal ? dx : dy).rounded()))
        }
        connectPoint(UnsafeMutableRawPointer(drag), "drag-end") { [weak state] dx, dy in
            guard let state else { return }
            let dragging = state.drag != nil
            state.drag = nil
            // Released away from a divider (a pane at its limit): no motion may follow to take
            // the cursor away.
            var x = 0.0
            var y = 0.0
            if dragging, gtk_gesture_drag_get_start_point(drag, &x, &y) != 0 {
                showCursor(container, state, divider(at: horizontal ? x + dx : y + dy, state) != nil)
            }
        }
        gtk_widget_add_controller(container, drag)

        let motion = gtk_event_controller_motion_new()!
        connectPoint(UnsafeMutableRawPointer(motion), "motion") { [weak state] x, y in
            guard let state else { return }
            showCursor(container, state, state.drag != nil || divider(at: horizontal ? x : y, state) != nil)
        }
        connectSignal(UnsafeMutableRawPointer(motion), "leave", .instanceOnly) { [weak state] in
            guard let state, state.drag == nil else { return }
            showCursor(container, state, false)
        }
        gtk_widget_add_controller(container, motion)
    }
}
