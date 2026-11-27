// Sources/Layout/GridLayout.swift
/*
 Grid on WinUI: a panel that lays a Grid's cells out in rows and columns, as SwiftUI's Grid does
 (measured on macOS 27 for the Linux renderer's GridLayout, whose rules this follows):

 - a column is as wide as its widest cell, and grows when one of its cells grows (to that cell's
   frame maximum; unbounded without one); a row likewise with its cells' heights;
 - the columns share the Grid's width as a stack's children share its length (StackSolver: least
   flexible first, each offered an even share of what is left), with the spacing between them; the
   rows share its height the same way, each cell's height measured at its column's width, as on
   Linux;
 - a cell that can be made narrower than it asks for (RenderNode.compression: a Text, which wraps)
   counts in its column from its smallest width (what its box asks for with nothing offered across,
   past WinUI's cap: WinUIObject.measureRequested) to its natural one, so a long Text wraps in a
   narrow Grid instead of widening it; it is measured again at the width its column gets;
 - each cell takes what a stack child takes of its column's width and its row's height, and is
   aligned in that space by the Grid's alignment;
 - a row shorter than the others leaves its last columns empty; the default spacing is 8;
 - a column or row of Spacers only gets no default spacing next to it, as a Spacer in a stack.
*/

import CWinUI

@MainActor final class GridLayout {
    /// SwiftUI's spacing between a Grid's rows and columns when it is given none (measured).
    static let defaultSpacing = 8.0

    /// A cell, beside its WinUI object: how it grows (RenderNode.expansion, caps) and whether it is a
    /// Spacer.
    struct Cell {
        let view: WinUIObject
        var expansion: Expansion = []
        var cap: (horizontal: Int?, vertical: Int?) = (nil, nil)
        /// The axes along which it can be made smaller than it asks for (RenderNode.compression).
        var compressible: Expansion = []
        var isSpacer = false
    }

    let panel: LayoutPanel
    private(set) var rows: [[Cell]] = []
    var horizontal = StackSolver.Alignment.center
    var vertical = StackSolver.Alignment.center
    /// nil: the default spacing (none next to a line of Spacers).
    var horizontalSpacing: Double?
    var verticalSpacing: Double?
    /// Each cell's size when measured unbounded, from the last measure pass (by view).
    private var naturals: [ObjectIdentifier: ActionUIWinUISize] = [:]
    /// A cell's smallest width, for one that can be made narrower (by view).
    private var smallestWidths: [ObjectIdentifier: Double] = [:]
    /// A cell's height at the width its column gets, for one that can be made narrower (by view): the rows' heights.
    private var heightsAtWidth: [ObjectIdentifier: Double] = [:]
    /// The columns' widths from the last measure pass when it was unbounded across (each column's natural
    /// width), else nil. Arranged in exactly that width, the Grid gives each column that width again: shared out
    /// anew, a column that wraps would get less than its natural width, its cells measured for it would ask
    /// for another height, and the layout would never finish (StackLayout.unboundedLengths).
    private var unboundedWidths: [Int]?

    init() throws(WinUIError) {
        panel = try LayoutPanel()
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    /// Makes the panel hold `newRows`' cells in reading order; asks for a new layout when they changed.
    func setRows(_ newRows: [[Cell]]) {
        let current = rows.flatMap { $0 }.map { ObjectIdentifier($0.view) }
        let wanted = newRows.flatMap { $0 }.map { ObjectIdentifier($0.view) }
        let shapeChanged = rows.map(\.count) != newRows.map(\.count)
            || rows.flatMap { $0 }.map(\.expansion.rawValue) != newRows.flatMap { $0 }.map(\.expansion.rawValue)
            || rows.flatMap { $0 }.map(\.compressible.rawValue) != newRows.flatMap { $0 }.map(\.compressible.rawValue)
            || !rows.flatMap({ $0 }).elementsEqual(newRows.flatMap { $0 }) { $0.cap == $1.cap }
        rows = newRows
        if current != wanted {
            do {
                while !panel.children.isEmpty {
                    try panel.remove(at: panel.children.count - 1)
                }
                for cell in newRows.flatMap({ $0 }) {
                    try panel.append(cell.view)
                }
            } catch {
                ActionUIModel.shared.logger.log("GridLayout: \(error)", .error)
            }
        }
        if current != wanted || shapeChanged {
            panel.invalidateLayout()
        }
    }

    func invalidate() {
        panel.invalidateLayout()
    }

    // MARK: Lines

    /// A cell as StackSolver sees it in one axis, from its natural size.
    private func child(_ cell: Cell, horizontal: Bool) -> StackChild {
        let key = ObjectIdentifier(cell.view)
        let size = naturals[key] ?? ActionUIWinUISize(width: 0, height: 0)
        let natural = horizontal ? size.width : (heightsAtWidth[key] ?? size.height)
        let length = StackSolver.length(natural, rounding: .up)
        let expands = cell.expansion.contains(horizontal ? .horizontal : .vertical)
        // Across, a cell that wraps can be as narrow as its smallest width.
        let smallest = horizontal ? smallestWidths[key].map { min(StackSolver.length($0, rounding: .up), length) } : nil
        var child: StackChild = expands ? .expanding(minimum: smallest ?? length, cap: horizontal ? cell.cap.horizontal : cell.cap.vertical)
                                        : .fixed(minimum: smallest ?? length, natural: length)
        child.isSpacer = cell.isSpacer
        return child
    }

    /// A line (column or row) from its cells: at least the largest minimum, at most the largest maximum
    /// (unbounded when a cell is); a Spacer line when all its cells are Spacers.
    private func line(_ cells: [StackChild]) -> StackChild {
        let minimum = cells.map(\.minimum).max() ?? 0
        let maximums = cells.map(\.maximum)
        let maximum: Int? = maximums.contains { $0 == nil } ? nil : (maximums.compactMap { $0 }.max() ?? 0)
        return StackChild(minimum: minimum, maximum: maximum.map { max($0, minimum) },
                          isSpacer: !cells.isEmpty && cells.allSatisfy(\.isSpacer))
    }

    private func columns() -> [StackChild] {
        let count = rows.map(\.count).max() ?? 0
        return (0..<count).map { column in
            line(rows.compactMap { column < $0.count ? child($0[column], horizontal: true) : nil })
        }
    }

    private func rowLines() -> [StackChild] {
        rows.map { row in line(row.map { child($0, horizontal: false) }) }
    }

    private func gaps(_ lines: [StackChild], horizontal: Bool) -> [Int] {
        let spacing = horizontal ? horizontalSpacing : verticalSpacing
        return StackSolver.gaps(lines, spacing: StackSolver.length(spacing ?? Self.defaultSpacing), isDefaultSpacing: spacing == nil)
    }

    /// The lines' sizes in `available` (infinite: `naturals`, else each at its least).
    private func sizes(_ lines: [StackChild], gaps: [Int], available: Double, naturals: [Int]? = nil) -> [Int] {
        available.isFinite ? StackSolver.mainSizes(lines, available: StackSolver.length(available), gaps: gaps)
            : naturals ?? lines.map(\.minimum)
    }

    /// Each column's natural width: its widest cell's, unwrapped (a cell that expands at its least, as before).
    private func columnNaturals() -> [Int] {
        let count = rows.map(\.count).max() ?? 0
        return (0..<count).map { column in
            rows.compactMap { row -> Int? in
                guard column < row.count else { return nil }
                let cell = row[column]
                let width = naturals[ObjectIdentifier(cell.view)]?.width ?? 0
                return StackSolver.length(width, rounding: .up)
            }.max() ?? 0
        }
    }

    /// Measures each cell that wraps at the width its column gets of `widths`, for the rows' heights.
    private func measureAtWidths(_ widths: [Int]) {
        heightsAtWidth = [:]
        for row in rows {
            for (column, cell) in row.enumerated() where column < widths.count && cell.compressible.contains(.horizontal) {
                let width = child(cell, horizontal: true).size(offered: widths[column])
                heightsAtWidth[ObjectIdentifier(cell.view)] =
                    cell.view.measureRequested(ActionUIWinUISize(width: Double(width), height: .infinity)).height
            }
        }
    }

    // MARK: Layout

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        naturals = [:]
        smallestWidths = [:]
        heightsAtWidth = [:]
        for cell in rows.flatMap({ $0 }) {
            let key = ObjectIdentifier(cell.view)
            naturals[key] = cell.view.measureRequested(ActionUIWinUISize(width: .infinity, height: .infinity))
            if cell.compressible.contains(.horizontal) {
                smallestWidths[key] = cell.view.measureRequested(ActionUIWinUISize(width: 0, height: .infinity)).width
            }
        }
        let columns = columns()
        let columnGaps = gaps(columns, horizontal: true)
        let widths = sizes(columns, gaps: columnGaps, available: available.width, naturals: columnNaturals())
        unboundedWidths = available.width.isFinite ? nil : widths
        // The rows' heights at those widths: a Text made narrower is taller.
        measureAtWidths(widths)
        let rowLines = rowLines()
        let rowGaps = gaps(rowLines, horizontal: false)
        let heights = sizes(rowLines, gaps: rowGaps, available: available.height)
        return ActionUIWinUISize(width: Double(StackSolver.length(of: widths, gaps: columnGaps)),
                                 height: Double(StackSolver.length(of: heights, gaps: rowGaps)))
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        guard !rows.isEmpty else { return }
        let columns = columns()
        let columnGaps = gaps(columns, horizontal: true)
        let width = StackSolver.length(finalSize.width)
        let height = StackSolver.length(finalSize.height)
        var widths = StackSolver.mainSizes(columns, available: width, gaps: columnGaps)
        if let natural = unboundedWidths, natural.count == widths.count, StackSolver.length(of: natural, gaps: columnGaps) == width {
            widths = natural
        }
        // Each cell that wraps measured again at the width it gets, which arrange gives it.
        measureAtWidths(widths)
        let rowLines = rowLines()
        let rowGaps = gaps(rowLines, horizontal: false)
        let heights = StackSolver.mainSizes(rowLines, available: height, gaps: rowGaps)
        // The block of rows and columns, centered when the Grid is given more than it takes.
        var y = StackSolver.centeredStart(length: StackSolver.length(of: heights, gaps: rowGaps), available: height)
        let left = StackSolver.centeredStart(length: StackSolver.length(of: widths, gaps: columnGaps), available: width)
        for (rowIndex, row) in rows.enumerated() {
            var x = left
            for (column, cell) in row.enumerated() {
                let cellWidth = child(cell, horizontal: true).size(offered: widths[column])
                let cellHeight = child(cell, horizontal: false).size(offered: heights[rowIndex])
                cell.view.arrange(ActionUIWinUIRect(
                    x: Double(x + StackSolver.alignedOffset(size: cellWidth, block: widths[column], alignment: horizontal)),
                    y: Double(y + StackSolver.alignedOffset(size: cellHeight, block: heights[rowIndex], alignment: vertical)),
                    width: Double(cellWidth), height: Double(cellHeight)))
                x += widths[column] + (column < columnGaps.count ? columnGaps[column] : 0)
            }
            y += heights[rowIndex] + (rowIndex < rowGaps.count ? rowGaps[rowIndex] : 0)
        }
    }
}
