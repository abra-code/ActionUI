// Sources/Layout/GridLayout.swift
/*
 Grid on WinUI: a panel that lays a Grid's cells out in rows and columns, as SwiftUI's Grid does
 (measured on macOS 27 for the Linux renderer's GridLayout, whose rules this follows):

 - a column is as wide as its widest cell, and grows when one of its cells grows (to that cell's
   frame maximum; unbounded without one); a row likewise with its cells' heights;
 - the columns share the Grid's width as a stack's children share its length (StackSolver: least
   flexible first, each offered an even share of what is left), with the spacing between them; the
   rows share its height the same way;
 - each cell takes what a stack child takes of its column's width and its row's height, and is
   aligned in that space by the Grid's alignment;
 - a row shorter than the others leaves its last columns empty; the default spacing is 8;
 - a column or row of Spacers only gets no default spacing next to it, as a Spacer in a stack.

 Not yet: a cell's height for its column's width (a wrapping Text is measured at its one line).
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
        let size = naturals[ObjectIdentifier(cell.view)] ?? ActionUIWinUISize(width: 0, height: 0)
        let length = StackSolver.length(horizontal ? size.width : size.height, rounding: .up)
        let expands = cell.expansion.contains(horizontal ? .horizontal : .vertical)
        var child: StackChild = expands ? .expanding(minimum: length, cap: horizontal ? cell.cap.horizontal : cell.cap.vertical)
                                        : .fixed(minimum: length, natural: length)
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

    /// The lines' sizes in `available` (infinite: each at its least).
    private func sizes(_ lines: [StackChild], gaps: [Int], available: Double) -> [Int] {
        available.isFinite ? StackSolver.mainSizes(lines, available: StackSolver.length(available), gaps: gaps) : lines.map(\.minimum)
    }

    // MARK: Layout

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        naturals = [:]
        for cell in rows.flatMap({ $0 }) {
            naturals[ObjectIdentifier(cell.view)] = cell.view.measureRequested(ActionUIWinUISize(width: .infinity, height: .infinity))
        }
        let columns = columns()
        let rowLines = rowLines()
        let columnGaps = gaps(columns, horizontal: true)
        let rowGaps = gaps(rowLines, horizontal: false)
        let widths = sizes(columns, gaps: columnGaps, available: available.width)
        let heights = sizes(rowLines, gaps: rowGaps, available: available.height)
        return ActionUIWinUISize(width: Double(StackSolver.length(of: widths, gaps: columnGaps)),
                                 height: Double(StackSolver.length(of: heights, gaps: rowGaps)))
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        guard !rows.isEmpty else { return }
        let columns = columns()
        let rowLines = rowLines()
        let columnGaps = gaps(columns, horizontal: true)
        let rowGaps = gaps(rowLines, horizontal: false)
        let width = StackSolver.length(finalSize.width)
        let height = StackSolver.length(finalSize.height)
        let widths = StackSolver.mainSizes(columns, available: width, gaps: columnGaps)
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
