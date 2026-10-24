// Sources/Layout/GridLayout.swift
/*
 Grid on GTK: a GtkLayoutManager subclass that lays a container's children out in rows and
 columns, as SwiftUI's Grid does (measured on macOS 27, the grid layout parity fixtures):

 - a column is as wide as its widest cell, and grows when one of its cells grows (to that cell's
   frame maximum; unbounded without one); a row likewise with its cells' heights;
 - the columns share the Grid's width as a stack's children share its length (StackSolver: least
   flexible first, each offered an even share of what is left), with the spacing between them;
   the rows share its height the same way, each cell's height measured at its column's width;
 - each cell takes what a stack child takes of its column's width and its row's height, and is
   aligned in that space by the Grid's alignment;
 - a row shorter than the others leaves its last columns empty; the default spacing is 8;
 - a column or row of Spacers only is placed after the others and gets no default spacing next to
   it, as a Spacer in a stack (StackSolver); one with any other cell is shared as usual;
 - an EmptyView takes no cell (the cells after it in its row move one column back), and a row of
   nothing else takes no row and no spacing.

 The children are the cells in reading order; GridConfiguration says how many each row has.
*/

import CAdwaita

/// A Grid's rows (the number of cells in each), alignment and spacing, attached to its container.
@MainActor
final class GridConfiguration {
    var rowLengths: [Int] = []
    var horizontal: StackSolver.Alignment = .center
    var vertical: StackSolver.Alignment = .center
    var horizontalSpacing = GridLayout.defaultSpacing
    var verticalSpacing = GridLayout.defaultSpacing
    /// The Grid was given no spacing in that axis (SwiftUI's default): none next to a line of
    /// Spacers.
    var horizontalSpacingIsDefault = true
    var verticalSpacingIsDefault = true
}

let gridConfigurationKey = AttachKey<GridConfiguration>("actionui-grid")

nonisolated(unsafe) private var gridLayoutType: GType = 0

@MainActor
enum GridLayout {
    /// SwiftUI's spacing between a Grid's rows and columns when it is given none (measured).
    static let defaultSpacing = 8

    /// A new, empty Grid container.
    static func makeGrid() -> WidgetPointer {
        let widget = makeContainer(layoutType: layoutType())
        attach(GridConfiguration(), to: widget, key: gridConfigurationKey)
        return widget
    }

    static func layoutType() -> GType {
        if gridLayoutType != 0 { return gridLayoutType }
        var info = GTypeInfo()
        info.class_size = guint16(MemoryLayout<GtkLayoutManagerClass>.size)
        info.instance_size = guint16(MemoryLayout<GtkLayoutManager>.size)
        info.class_init = { klass, _ in
            guard let klass else { return }
            let layoutClass = klass.assumingMemoryBound(to: GtkLayoutManagerClass.self)
            layoutClass.pointee.get_request_mode = { _, _ in GTK_SIZE_REQUEST_HEIGHT_FOR_WIDTH }
            layoutClass.pointee.measure = { _, widget, orientation, forSize, minimum, natural, minimumBaseline, naturalBaseline in
                guard let widget else { return }
                let size = MainActor.assumeIsolated { GridLayout.measure(widget, orientation, forSize: Int(forSize)) }
                minimum?.pointee = Int32(clamping: size.minimum)
                natural?.pointee = Int32(clamping: size.natural)
                minimumBaseline?.pointee = -1
                naturalBaseline?.pointee = -1
            }
            layoutClass.pointee.allocate = { _, widget, width, height, _ in
                guard let widget else { return }
                MainActor.assumeIsolated { GridLayout.allocate(widget, width: Int(width), height: Int(height)) }
            }
        }
        gridLayoutType = g_type_register_static(gtk_layout_manager_get_type(), "ActionUIGridLayout", &info, GTypeFlags(0))
        return gridLayoutType
    }

    private static func configuration(_ widget: WidgetPointer) -> GridConfiguration {
        attached(on: widget, key: gridConfigurationKey) ?? GridConfiguration()
    }

    /// The cells, row by row. A child that takes no place (gtk_widget_should_layout false: an
    /// EmptyView's box) takes no cell, and a row left without cells is no row, as in SwiftUI
    /// (measured: grid-emptyview-takes-no-cell, grid-emptyview-row-takes-no-row).
    private static func rows(_ widget: WidgetPointer, _ configuration: GridConfiguration) -> [[WidgetPointer]] {
        let children = Gtk.Widget(widget).children.map(\.pointer)
        var rows: [[WidgetPointer]] = []
        var start = 0
        for length in configuration.rowLengths {
            let end = min(start + length, children.count)
            let cells = children[start..<max(start, end)].filter { gtk_widget_should_layout($0) != 0 }
            if !cells.isEmpty {
                rows.append(cells)
            }
            start = max(start, end)
        }
        return rows
    }

    /// A cell as StackSolver sees it in one axis, measured for `forSize` in the other.
    private static func cell(_ child: WidgetPointer, _ orientation: GtkOrientation, forSize: Int = -1) -> (range: StackChild, natural: Int) {
        let size = Gtk.Widget(child).measure(orientation, forSize: forSize)
        var range: StackChild
        if Gtk.Widget(child).expands(orientation) {
            range = .expanding(minimum: size.minimum, cap: LayoutCaps.cap(child, orientation, forSize: forSize))
        } else {
            range = .fixed(minimum: size.minimum, natural: size.natural)
        }
        range.isSpacer = attached(on: child, key: spacerMarkerKey) != nil
        return (range, size.natural)
    }

    /// A line (column or row) from its cells: at least the largest minimum, at most the largest
    /// maximum (unbounded when a cell is), naturally the largest natural size; a Spacer line when
    /// all its cells are Spacers (measured: grid-spacer-mixed-lines shares a line with one Spacer
    /// as usual).
    private static func line(_ cells: [(range: StackChild, natural: Int)]) -> (range: StackChild, natural: Int) {
        let minimum = cells.map(\.range.minimum).max() ?? 0
        let maximums = cells.map(\.range.maximum)
        let maximum: Int? = maximums.contains { $0 == nil } ? nil : (maximums.compactMap { $0 }.max() ?? 0)
        let natural = max(cells.map(\.natural).max() ?? 0, minimum)
        let isSpacer = !cells.isEmpty && cells.allSatisfy(\.range.isSpacer)
        return (StackChild(minimum: minimum, maximum: maximum.map { max($0, minimum) }, isSpacer: isSpacer), natural)
    }

    private static func columns(_ rows: [[WidgetPointer]]) -> [(range: StackChild, natural: Int)] {
        let count = rows.map(\.count).max() ?? 0
        return (0..<count).map { column in
            line(rows.compactMap { column < $0.count ? $0[column] : nil }.map { cell($0, GTK_ORIENTATION_HORIZONTAL) })
        }
    }

    /// The spacing between neighboring columns (`horizontal`) or rows: none next to a line of
    /// Spacers when the Grid was given no spacing in that axis.
    private static func gaps(_ lines: [(range: StackChild, natural: Int)], _ configuration: GridConfiguration,
                             horizontal: Bool) -> [Int] {
        StackSolver.gaps(lines.map(\.range),
                         spacing: horizontal ? configuration.horizontalSpacing : configuration.verticalSpacing,
                         isDefaultSpacing: horizontal ? configuration.horizontalSpacingIsDefault : configuration.verticalSpacingIsDefault)
    }

    /// The columns' widths in a Grid `width` wide, and the spacing between them.
    private static func columnWidths(_ rows: [[WidgetPointer]], _ configuration: GridConfiguration, width: Int)
        -> (widths: [Int], gaps: [Int]) {
        let columns = columns(rows)
        let gaps = gaps(columns, configuration, horizontal: true)
        return (StackSolver.mainSizes(columns.map(\.range), available: width, gaps: gaps), gaps)
    }

    /// Each cell's width in its column.
    private static func cellWidth(_ child: WidgetPointer, column: Int) -> Int {
        cell(child, GTK_ORIENTATION_HORIZONTAL).range.size(offered: column)
    }

    /// The rows, each cell measured at its width in a column of `widths` (nil: no width given).
    private static func rowLines(_ rows: [[WidgetPointer]], widths: [Int]?) -> [(range: StackChild, natural: Int)] {
        rows.map { row in
            line(row.enumerated().map { column, child in
                let forSize = widths.map { cellWidth(child, column: $0[column]) } ?? -1
                return cell(child, GTK_ORIENTATION_VERTICAL, forSize: forSize)
            })
        }
    }

    /// The columns (`orientation` horizontal) or the rows, the rows' cells measured at their
    /// widths in a Grid `forSize` wide (-1: no width given), and the spacing between them.
    private static func lines(_ rows: [[WidgetPointer]], _ configuration: GridConfiguration, _ orientation: GtkOrientation,
                              forSize: Int) -> (lines: [(range: StackChild, natural: Int)], gaps: [Int]) {
        if orientation == GTK_ORIENTATION_HORIZONTAL {
            let columns = columns(rows)
            return (columns, gaps(columns, configuration, horizontal: true))
        }
        // Height for width: the cells' heights at the widths their columns get.
        let widths = forSize >= 0 ? columnWidths(rows, configuration, width: forSize).widths : nil
        let lines = rowLines(rows, widths: widths)
        return (lines, gaps(lines, configuration, horizontal: false))
    }

    private static func measure(_ widget: WidgetPointer, _ orientation: GtkOrientation, forSize: Int) -> (minimum: Int, natural: Int) {
        let configuration = configuration(widget)
        let (lines, gaps) = lines(rows(widget, configuration), configuration, orientation, forSize: forSize)
        let spacing = gaps.reduce(0, +)
        return (lines.map(\.range.minimum).reduce(spacing, +), lines.map(\.natural).reduce(spacing, +))
    }

    private static func allocate(_ widget: WidgetPointer, width: Int, height: Int) {
        let configuration = configuration(widget)
        let rows = rows(widget, configuration)
        guard !rows.isEmpty else { return }
        let (widths, columnGaps) = columnWidths(rows, configuration, width: width)
        let rowLines = rowLines(rows, widths: widths)
        let rowGaps = gaps(rowLines, configuration, horizontal: false)
        let heights = StackSolver.mainSizes(rowLines.map(\.range), available: height, gaps: rowGaps)
        // The block of rows and columns, centered when the Grid is given more than it takes.
        var y = StackSolver.centeredStart(length: StackSolver.length(of: heights, gaps: rowGaps), available: height)
        let left = StackSolver.centeredStart(length: StackSolver.length(of: widths, gaps: columnGaps), available: width)
        for (rowIndex, row) in rows.enumerated() {
            var x = left
            for (column, child) in row.enumerated() {
                let cellWidth = cellWidth(child, column: widths[column])
                let cellHeight = cell(child, GTK_ORIENTATION_VERTICAL, forSize: cellWidth).range.size(offered: heights[rowIndex])
                var origin = graphene_point_t(
                    x: Float(x + StackSolver.alignedOffset(size: cellWidth, block: widths[column], alignment: configuration.horizontal)),
                    y: Float(y + StackSolver.alignedOffset(size: cellHeight, block: heights[rowIndex], alignment: configuration.vertical)))
                gtk_widget_allocate(child, Int32(clamping: cellWidth), Int32(clamping: cellHeight), -1,
                                    gsk_transform_translate(nil, &origin))
                x += widths[column] + (column < columnGaps.count ? columnGaps[column] : 0)
            }
            y += heights[rowIndex] + (rowIndex < rowGaps.count ? rowGaps[rowIndex] : 0)
        }
    }

    /// The largest size the Grid takes in `orientation` when it expands (LayoutCaps.cap): its
    /// columns' or rows' largest sizes plus the spacing; nil when one is unbounded. A height is for
    /// `forSize` wide (-1: no width given).
    static func cap(_ widget: WidgetPointer, _ orientation: GtkOrientation, forSize: Int) -> Int? {
        let configuration = configuration(widget)
        let (lines, gaps) = lines(rows(widget, configuration), configuration, orientation, forSize: forSize)
        var total = gaps.reduce(0, +)
        for line in lines {
            guard let maximum = line.range.maximum else { return nil }
            total += maximum
        }
        return total
    }
}
