// Sources/Layout/LazyGridLayout.swift
/*
 LazyVGrid's and LazyHGrid's layout on GTK, as SwiftUI lays them out (measured on macOS 27: the
 lazyvgrid-* and lazyhgrid-* layout parity fixtures). Described for LazyVGrid; LazyHGrid is the
 same with the axes swapped (rows for columns, the grid as tall as it is offered).

 - The grid takes all the width it is offered. Its columns are its tracks: a fixed one is its
   width, the flexible ones share what the fixed ones and the spacing between columns (8, SwiftUI's
   default GridItem spacing) leave, each at least 10. The block of columns sits at the grid's
   alignment within its width.
 - Children fill the columns row by row. A child takes its column's width clamped to its range (a
   flexible one fills it) and its height for that width; it sits at the grid's alignment across
   its column and centered in its row. A row is as tall as its tallest child at its natural height;
   a child that expands vertically then fills the row, up to its cap. Rows are `spacing` apart, and
   the grid is as tall as its rows.
 - Every child is laid out, none lazily: GTK lays out a thousand rows quickly (the List's check).
*/

import CAdwaita

nonisolated(unsafe) private var lazyGridLayoutType: GType = 0

/// One track (a column of a LazyVGrid, a row of a LazyHGrid).
enum LazyGridTrack: Equatable {
    case fixed(Int)
    case flexible
}

/// A lazy grid's configuration and children, attached to its container.
@MainActor
final class LazyGridState {
    /// True for LazyVGrid: the tracks are columns.
    let vertical: Bool
    var tracks: [LazyGridTrack] = [.flexible]
    var alignment = StackSolver.Alignment.center
    /// The space between lines (rows of a LazyVGrid).
    var lineSpacing = 0
    /// The children's boxes, in order.
    var items: [WidgetPointer] = []
    /// The template instances, in template mode.
    let templateRows = TemplateRows()

    init(vertical: Bool) {
        self.vertical = vertical
    }

    var trackAxis: GtkOrientation { vertical ? GTK_ORIENTATION_HORIZONTAL : GTK_ORIENTATION_VERTICAL }
    var lineAxis: GtkOrientation { vertical ? GTK_ORIENTATION_VERTICAL : GTK_ORIENTATION_HORIZONTAL }
}

let lazyGridStateKey = AttachKey<LazyGridState>("actionui-lazy-grid")

@MainActor
enum LazyGridLayout {
    /// The space between tracks (SwiftUI's default GridItem spacing) and a flexible track's minimum.
    static let trackSpacing = 8
    static let flexibleMinimum = 10

    /// A new, empty grid container; `vertical` for a LazyVGrid.
    static func makeGrid(vertical: Bool) -> WidgetPointer {
        let widget = makeContainer(layoutType: layoutType())
        attach(LazyGridState(vertical: vertical), to: widget, key: lazyGridStateKey)
        // Greedy along the tracks' axis only, whatever the children (GTK would take their expand).
        gtk_widget_set_hexpand(widget, vertical ? 1 : 0)
        gtk_widget_set_vexpand(widget, vertical ? 0 : 1)
        return widget
    }

    // MARK: Sizes (no GTK, so they are tested without a display)

    /// The tracks' sizes in a grid `available` long: fixed ones their size, flexible ones an equal
    /// share of the rest (the first ones a pixel more when it does not divide), each at least 10.
    static func trackSizes(_ tracks: [LazyGridTrack], available: Int) -> [Int] {
        let gaps = trackSpacing * max(0, tracks.count - 1)
        var fixed = 0
        var flexible = 0
        for track in tracks {
            switch track {
            case .fixed(let size): fixed += size
            case .flexible: flexible += 1
            }
        }
        let rest = max(available - gaps - fixed, flexible * flexibleMinimum)
        var extra = flexible > 0 ? rest % flexible : 0
        return tracks.map { track in
            switch track {
            case .fixed(let size):
                return size
            case .flexible:
                let size = max(flexibleMinimum, rest / flexible + (extra > 0 ? 1 : 0))
                extra -= 1
                return size
            }
        }
    }

    /// The tracks' smallest total length, with the spacing between them.
    static func minimumLength(_ tracks: [LazyGridTrack]) -> Int {
        tracks.reduce(trackSpacing * max(0, tracks.count - 1)) { total, track in
            if case .fixed(let size) = track { return total + size }
            return total + flexibleMinimum
        }
    }

    // MARK: Layout manager

    static func layoutType() -> GType {
        if lazyGridLayoutType != 0 { return lazyGridLayoutType }
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkLayoutManagerClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkLayoutManager>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            let layoutClass = klass.assumingMemoryBound(to: GtkLayoutManagerClass.self)
            layoutClass.pointee.get_request_mode = { _, widget in
                MainActor.assumeIsolated {
                    let vertical = widget.flatMap { attached(on: $0, key: lazyGridStateKey) }?.vertical ?? true
                    return vertical ? GTK_SIZE_REQUEST_HEIGHT_FOR_WIDTH : GTK_SIZE_REQUEST_WIDTH_FOR_HEIGHT
                }
            }
            layoutClass.pointee.measure = { _, widget, orientation, forSize, minimum, natural, minimumBaseline, naturalBaseline in
                guard let widget else { return }
                let size = MainActor.assumeIsolated { LazyGridLayout.measure(widget, orientation, forSize: Int(forSize)) }
                minimum?.pointee = Int32(clamping: size.minimum)
                natural?.pointee = Int32(clamping: size.natural)
                minimumBaseline?.pointee = -1
                naturalBaseline?.pointee = -1
            }
            layoutClass.pointee.allocate = { _, widget, width, height, _ in
                guard let widget else { return }
                MainActor.assumeIsolated { LazyGridLayout.allocate(widget, width: Int(width), height: Int(height)) }
            }
        }
        lazyGridLayoutType = g_type_register_static(gtk_layout_manager_get_type(), "ActionUILazyGridLayout", &info, GTypeFlags(0))
        return lazyGridLayoutType
    }

    /// Where every child goes for a grid `trackLength` long across its tracks.
    private struct Plan {
        var trackSizes: [Int]
        var blockStart: Int
        var lineSizes: [Int]
        /// Each shown child's track, line, size along the tracks' axis, and measured size across it.
        var cells: [(item: WidgetPointer, track: Int, line: Int, along: Int, across: (minimum: Int, natural: Int))]
    }

    private static func shownItems(_ state: LazyGridState) -> [WidgetPointer] {
        state.items.filter { gtk_widget_should_layout($0) != 0 }
    }

    private static func plan(_ state: LazyGridState, trackLength: Int) -> Plan {
        let sizes = trackSizes(state.tracks, available: trackLength)
        let block = sizes.reduce(trackSpacing * max(0, sizes.count - 1), +)
        let blockStart = max(0, StackSolver.alignedOffset(size: block, block: trackLength, alignment: state.alignment))
        var plan = Plan(trackSizes: sizes, blockStart: blockStart, lineSizes: [], cells: [])
        guard !sizes.isEmpty else { return plan }
        for (index, item) in shownItems(state).enumerated() {
            let track = index % sizes.count
            let line = index / sizes.count
            let measured = Gtk.Widget(item).measure(state.trackAxis)
            let range: StackChild = Gtk.Widget(item).expands(state.trackAxis)
                ? .expanding(minimum: measured.minimum, cap: LayoutCaps.cap(item, state.trackAxis))
                : .fixed(minimum: measured.minimum, natural: measured.natural)
            let along = range.size(offered: sizes[track])
            let measuredAcross = Gtk.Widget(item).measure(state.lineAxis, forSize: along)
            let across = (minimum: measuredAcross.minimum, natural: measuredAcross.natural)
            if line == plan.lineSizes.count {
                plan.lineSizes.append(0)
            }
            plan.lineSizes[line] = max(plan.lineSizes[line], across.natural, across.minimum)
            plan.cells.append((item, track, line, along, across))
        }
        return plan
    }

    private static func lineLength(_ plan: Plan, _ state: LazyGridState) -> Int {
        plan.lineSizes.reduce(state.lineSpacing * max(0, plan.lineSizes.count - 1), +)
    }

    private static func measure(_ widget: WidgetPointer, _ orientation: GtkOrientation, forSize: Int) -> (minimum: Int, natural: Int) {
        guard let state = attached(on: widget, key: lazyGridStateKey) else { return (0, 0) }
        let natural = naturalTrackLength(state)
        if orientation == state.trackAxis {
            return (minimumLength(state.tracks), natural)
        }
        let length = lineLength(plan(state, trackLength: forSize >= 0 ? forSize : natural), state)
        return (length, length)
    }

    /// The tracks' length when each flexible track is as long as its widest child.
    private static func naturalTrackLength(_ state: LazyGridState) -> Int {
        guard !state.tracks.isEmpty else { return 0 }
        var widest = [Int](repeating: flexibleMinimum, count: state.tracks.count)
        for (index, item) in shownItems(state).enumerated() {
            let track = index % state.tracks.count
            widest[track] = max(widest[track], Gtk.Widget(item).measure(state.trackAxis).natural)
        }
        return zip(state.tracks, widest).reduce(trackSpacing * (state.tracks.count - 1)) { total, pair in
            if case .fixed(let size) = pair.0 { return total + size }
            return total + pair.1
        }
    }

    private static func allocate(_ widget: WidgetPointer, width: Int, height: Int) {
        guard let state = attached(on: widget, key: lazyGridStateKey) else { return }
        let trackLength = state.vertical ? width : height
        let plan = plan(state, trackLength: trackLength)
        // A grid without tracks places no child, and GTK refuses to draw one never allocated.
        for item in shownItems(state) {
            gtk_widget_set_child_visible(item, plan.trackSizes.isEmpty ? 0 : 1)
        }
        var trackStarts: [Int] = []
        var position = plan.blockStart
        for size in plan.trackSizes {
            trackStarts.append(position)
            position += size + trackSpacing
        }
        var lineStarts: [Int] = []
        position = 0
        for size in plan.lineSizes {
            lineStarts.append(position)
            position += size + state.lineSpacing
        }
        for cell in plan.cells {
            // Offered its line's size: one that expands across fills it, up to its cap.
            let range: StackChild = Gtk.Widget(cell.item).expands(state.lineAxis)
                ? .expanding(minimum: cell.across.minimum, cap: LayoutCaps.cap(cell.item, state.lineAxis, forSize: cell.along))
                : .fixed(minimum: cell.across.minimum, natural: cell.across.natural)
            let acrossSize = range.size(offered: plan.lineSizes[cell.line])
            let along = trackStarts[cell.track] + StackSolver.alignedOffset(size: cell.along, block: plan.trackSizes[cell.track], alignment: state.alignment)
            let across = lineStarts[cell.line] + StackSolver.centeredStart(length: acrossSize, available: plan.lineSizes[cell.line])
            var origin = state.vertical ? graphene_point_t(x: Float(along), y: Float(across)) : graphene_point_t(x: Float(across), y: Float(along))
            gtk_widget_allocate(cell.item, Int32(clamping: state.vertical ? cell.along : acrossSize),
                                Int32(clamping: state.vertical ? acrossSize : cell.along), -1, gsk_transform_translate(nil, &origin))
        }
    }
}
