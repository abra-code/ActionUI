// Sources/Elements/Table+WinUI.swift
/*
 Table on WinUI: a header row over Windows' ListView, as greedy as the List (it shares a stack like a
 Color), following the Linux renderer (Table+Adwaita.swift) and Apple's Table. One row per content row
 (setElementRows), all of them shown; a column shows that column of each row (empty when the row is
 shorter) as one line at the leading edge, cut short with an ellipsis, as a macOS Table cell.

 - Columns: widths are the ideal widths (100 when missing); the column with the largest takes the
   room left (each of them, when several have it), as the Apple renderer's columns do; a minWidth
   above the ideal widens the column to it. Short of room, those columns give it back down to their
   minWidths (default the smaller of 10 and the ideal); past that the row is cut at the table's edge.
   The header row (the titles, a 1 point line at each column's trailing edge, then a 1 point line
   under them) lines up with the rows' cells; columnHeadersVisibility hidden hides it.
 - Resizing: dragging a column's trailing edge in the header (within 4 points of it, where the resize
   cursor shows) sets its width, as on Linux: no narrower than its minWidth, and no wider than its
   ideal width unless it fills (Apple gives such a column that maximum). The column then keeps that
   width, as a Windows list's columns do: it no longer takes the room left or gives it back, and the
   columns that fill and were not dragged take the difference. A change of the columns forgets the
   widths set.
 - Selection: a row the user selects becomes the value (its columns) and fires actionID (Core
   RowSelection), a deselect (Ctrl+click) too; a host's value selects its row and fires nothing; a
   rows change keeps the selection on its row (Core). A double click or Return makes the row the
   value and fires doubleClickActionID with its index, after actionID when the selection changes.
 - Rows are made as they come into view (the ListView's element source, as the List's), so a Table
   of thousands of rows makes tens; each row is named for accessibility tools by its columns.

 Cells, by the column's columnTypes entry (Text when none), as on Linux:
 - Text: one line at the leading edge, cut short with an ellipsis.
 - Button: the text as its title, or an image read as dataInterpretation says when that is set; a
   click fires the entry's actionID with the column as viewPartID and the context actionContext names
   (the title, the row's index, the column's index, or {"row", "column"}). A click does not select
   the row.
 - Image: the text read as dataInterpretation says, as a List's Image cell shows it.
 - AsyncImage: the image the text names, loaded without blocking and scaled to fit the cell (24
   points tall); nothing until it has loaded, and when it cannot be.
 - Toggle: a checkbox (or a switch, by style) showing the text as a Bool; a user toggle writes "true"
   or "false" into the cell, keeps the selection where it was, and fires the entry's actionID with the
   column as viewPartID and the row's index as context (Core Table.commitCellToggle); disabledColumn's
   text, read the same way, disables it.

 Not yet: the toggle button style (a checkbox for now); a toggled row is made again, so its toggle
 loses the keyboard focus; WinUI's CheckBox keeps its 120 point minimum width, so a click beside the
 box in a wide column toggles it; a spinner in an AsyncImage cell while it loads; the inherited buttonStyle on Button cells;
 scrollContentBackground; a double click on a header's edge fitting the column to its cells, as
 Windows' lists do; the resize cursor while a drag leaves the edge (as a split view's divider).
*/

import Dispatch
import CWinUI

/// A Table's columns: their titles and widths, shared by the header and every row.
@MainActor final class TableColumns {
    var titles: [String] = []
    var ideals: [Int] = []
    var minimums: [Int] = []
    /// The columns that take the room left: those with the largest ideal width as given.
    var fills: [Bool] = []
    /// The widths for the last width laid out.
    private(set) var widths: [Int] = []
    /// The widths the user set by dragging, by column: such a column keeps its width.
    var userWidths: [Int: Int] = [:]
    /// Where the ListView puts a row's content from its edge (its item's padding), measured once rows
    /// exist: the header's cells start there too.
    var inset = 0.0

    var count: Int { titles.count }

    /// The widths for a row `available` wide: the ideals, the room left to the widest (each of them),
    /// or taken from them down to their minimums.
    @discardableResult
    func layOut(available: Double) -> Bool {
        var result = ideals.indices.map { userWidths[$0] ?? ideals[$0] }
        let flexible = ideals.indices.filter { fills.indices.contains($0) && fills[$0] && userWidths[$0] == nil }
        var left = StackSolver.length(available) - result.reduce(0, +)
        if left > 0 {
            for (position, index) in flexible.enumerated() {
                // The remainder to the first, so the widths add up.
                let share = left / flexible.count + (position < left % flexible.count ? 1 : 0)
                result[index] += share
            }
        } else {
            for index in flexible where left < 0 {
                let give = min(result[index] - minimums[index], -left)
                result[index] -= give
                left += give
            }
        }
        let changed = result != widths
        widths = result
        return changed
    }

    /// Sets column `index`'s width to `width` as the user dragged it, within its minimum and, unless it
    /// fills, its ideal width; whether that changes it.
    func resize(_ index: Int, to width: Int) -> Bool {
        guard ideals.indices.contains(index), minimums.indices.contains(index) else { return false }
        let fills = self.fills.indices.contains(index) && self.fills[index]
        let allowed = min(max(width, minimums[index]), fills ? StackSolver.maximumLength : ideals[index])
        // Against the width set, not the one laid out: moves can come faster than layout passes, and a
        // move back to the laid-out width must still undo the one before it.
        guard userWidths[index] != allowed else { return false }
        userWidths[index] = allowed
        return true
    }

    /// Column `index`'s start and width in a row (0 past the columns laid out).
    func span(_ index: Int) -> (start: Int, width: Int) {
        guard widths.indices.contains(index) else { return (0, 0) }
        return (widths[..<index].reduce(0, +), widths[index])
    }
}

/// A row of cells (a content row's, or the header's) placed at the columns' widths.
@MainActor final class TableRowLayout {
    /// A cell, and whether it fills its column (a text) or keeps its own size at the column's leading
    /// edge, centered in the row (a button, an image, a toggle).
    struct Cell {
        let view: WinUIObject
        var fills: Bool
        /// The most height it is given (an AsyncImage cell's image, scaled to fit); nil: what it asks.
        var height: Double?
    }

    let panel: LayoutPanel
    let columns: TableColumns
    private(set) var cells: [Cell] = []
    /// Each cell's size from the last measure pass, for arrange.
    private var desired: [ActionUIWinUISize] = []
    /// The header's: its cells start at the rows' inset.
    let isHeader: Bool
    /// The header's: at each column's trailing edge, where a drag resizes the column, its 1 point line
    /// (as a split view's divider, over the cells).
    private(set) var edges: [SplitDivider] = []

    init(columns: TableColumns, cells: [Cell], isHeader: Bool) throws(WinUIError) {
        self.columns = columns
        self.isHeader = isHeader
        panel = try LayoutPanel()
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
        for cell in cells {
            try panel.append(cell.view)
        }
        self.cells = cells
        if isHeader {
            for _ in cells {
                let edge = try SplitDivider(horizontal: true)
                try panel.append(edge.hitArea.object)
                edges.append(edge)
            }
        }
    }

    /// A one-line text cell, cut short with an ellipsis (semibold in the header).
    static func textCell(_ text: String, header: Bool = false) throws(WinUIError) -> Cell {
        guard let cell = WinUIObject(adopting: actionUIWinUITextBlockCreate()) else {
            throw WinUIError.last("making a Table cell")
        }
        var shown = actionUIWinUITextBlockSetText(cell.pointer, text) && actionUIWinUITextBlockSetTrimmed(cell.pointer, true)
        if header {
            shown = shown && actionUIWinUIElementSetFont(cell.pointer, nil, 0, 600)
        }
        if !shown {
            ActionUIModel.shared.logger.log("Table: \(WinUIError.last("showing a cell"))", .error)
        }
        return Cell(view: cell, fills: true)
    }

    private var offset: Double { isHeader ? columns.inset : 0 }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        var height = 0.0
        desired = []
        for (index, cell) in cells.enumerated() {
            let width = Double(columns.span(index).width)
            var size = cell.view.measure(ActionUIWinUISize(width: width, height: cell.height ?? .infinity))
            if let cap = cell.height {
                size.height = min(size.height, cap)
            }
            desired.append(size)
            height = max(height, size.height)
        }
        // Measured all the same: WinUI arranges only children measured in this pass.
        for edge in edges {
            _ = edge.hitArea.object.measure(ActionUIWinUISize(width: 0, height: 0))
        }
        let width = Double(columns.span(max(columns.count - 1, 0)).start + columns.span(max(columns.count - 1, 0)).width) + offset
        return ActionUIWinUISize(width: available.width.isFinite ? min(width, available.width) : width, height: height)
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        for (index, cell) in cells.enumerated() {
            let span = columns.span(index)
            if !desired.indices.contains(index) {
                cell.view.arrange(ActionUIWinUIRect(x: offset + Double(span.start), y: 0, width: Double(span.width), height: finalSize.height))
            } else {
                // Every cell at its own height, centered in the row: a TextBlock given more height
                // draws its line at the top, above a taller Button's or CheckBox's center.
                let size = desired[index]
                let width = cell.fills ? Double(span.width) : min(size.width, Double(span.width))
                let height = min(size.height, finalSize.height)
                cell.view.arrange(ActionUIWinUIRect(x: offset + Double(span.start), y: (finalSize.height - height) / 2, width: width, height: height))
            }
        }
        // Each edge's line on its column's last point, the drag's hit area around it.
        for (index, edge) in edges.enumerated() {
            let span = columns.span(index)
            let end = offset + Double(span.start + span.width)
            edge.hitArea.object.arrange(ActionUIWinUIRect(x: end - 1 - SplitLayout.grabDistance, y: 0,
                                                          width: 2 * SplitLayout.grabDistance + 1, height: finalSize.height))
        }
    }
}

/// A Table's view: the header row, a line under it, and the ListView of the rows.
@MainActor final class TableLayout {
    let panel: LayoutPanel
    let list: WinUIObject
    let columns = TableColumns()
    private(set) var header: TableRowLayout?
    let line: LayoutPanel
    var headerShown = true
    /// The rows made, for a new layout of their cells when the widths change.
    var rows: [TableRowLayout] = []

    init(list: WinUIObject) throws(WinUIError) {
        self.list = list
        panel = try LayoutPanel()
        line = try LayoutPanel()
        line.measure = { _ in ActionUIWinUISize(width: 0, height: 0) }
        Paint.apply(.theme("DividerStrokeColorDefaultBrush"), ActionUIWinUIBrushBackground, to: line.object, what: "a Table's header line")
        try panel.append(list)
        try panel.append(line.object)
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    /// Shows a header of the columns' titles (none when hidden).
    func setHeader(shown: Bool) {
        headerShown = shown
        do {
            if let header {
                if let index = panel.children.firstIndex(where: { $0 === header.panel.object }) {
                    try panel.remove(at: index)
                }
                self.header = nil
            }
            if shown {
                var cells: [TableRowLayout.Cell] = []
                for title in columns.titles {
                    cells.append(try TableRowLayout.textCell(title, header: true))
                }
                let made = try TableRowLayout(columns: columns, cells: cells, isHeader: true)
                try panel.append(made.panel.object)
                header = made
                for (index, edge) in made.edges.enumerated() {
                    SplitPointer.connect(edge.hitArea.object, relativeTo: made.panel.object, owner: "Table") { [weak self] kind, x, _ in
                        self?.edgeDragged(index, kind, x) ?? false
                    }
                }
            }
        } catch {
            ActionUIModel.shared.logger.log("Table: \(error)", .error)
        }
        panel.invalidateLayout()
    }

    private var headerHeight = 0.0
    /// The drag under way: its column, the column's width and the pointer's position when it started.
    private var drag: (index: Int, start: Int, origin: Double)?

    /// A drag of column `index`'s trailing edge in the header: a press starts it, a move sets the
    /// column's width.
    private func edgeDragged(_ index: Int, _ kind: ActionUIWinUIPointerEventKind, _ x: Double) -> Bool {
        switch kind {
        case ActionUIWinUIPointerPressed:
            guard index < columns.count else { return false }
            drag = (index, columns.span(index).width, x)
            return true
        case ActionUIWinUIPointerMoved:
            guard let drag else { return false }
            let delta = Int((x - drag.origin).rounded())
            if columns.resize(drag.index, to: drag.start + delta) {
                panel.invalidateLayout()
            }
            return true
        default:
            let dragging = drag != nil
            drag = nil
            return dragging
        }
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let width = available.width.isFinite ? available.width : 0
        // The columns fill the row the ListView gives its content (its width less the item's padding on
        // each side, taken as the inset on both), worked out before the header and the rows are measured
        // for them: the Table takes all of the width it is offered.
        if available.width.isFinite, columns.layOut(available: max(width - 2 * columns.inset, 0)) {
            for row in rows {
                row.panel.invalidateLayout()
            }
            header?.panel.invalidateLayout()
        }
        headerHeight = 0
        if let header, headerShown {
            headerHeight = header.panel.object.measure(ActionUIWinUISize(width: width, height: .infinity)).height
        }
        _ = line.object.measure(ActionUIWinUISize(width: 0, height: 0))
        let lineHeight = headerShown ? Double(SplitLayout.dividerThickness) : 0
        let listHeight = available.height.isFinite ? max(available.height - headerHeight - lineHeight, 0) : .infinity
        let listSize = list.measure(ActionUIWinUISize(width: width, height: listHeight))
        // Greedy, as the List: all of a finite offer, else what it needs.
        return ActionUIWinUISize(width: available.width.isFinite ? available.width : listSize.width,
                                 height: available.height.isFinite ? available.height : headerHeight + lineHeight + listSize.height)
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        var y = 0.0
        if let header, headerShown {
            header.panel.object.arrange(ActionUIWinUIRect(x: 0, y: 0, width: finalSize.width, height: headerHeight))
            // Columns wider than the Table are cut at its edge, as the rows are by the ListView.
            if !actionUIWinUIElementSetClipSize(header.panel.object.pointer, finalSize.width, headerHeight) {
                ActionUIModel.shared.logger.log("Table: \(WinUIError.last("clipping the header"))", .error)
            }
            y = headerHeight
            line.object.arrange(ActionUIWinUIRect(x: 0, y: y, width: finalSize.width, height: Double(SplitLayout.dividerThickness)))
            y += Double(SplitLayout.dividerThickness)
        } else {
            line.object.arrange(ActionUIWinUIRect(x: 0, y: 0, width: 0, height: 0))
        }
        list.arrange(ActionUIWinUIRect(x: 0, y: y, width: finalSize.width, height: max(finalSize.height - y, 0)))
        measureInset()
    }

    private var insetPending = false

    /// Where a made row's content starts in the ListView, read once its layout is done (on the next
    /// turn of the main loop); a change lays the header and the rows out again.
    private func measureInset() {
        guard !insetPending, let row = rows.first else { return }
        insetPending = true
        DispatchQueue.main.async { [weak self, weak row] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.insetPending = false
                guard let row else { return }
                var bounds = ActionUIWinUIRect(x: 0, y: 0, width: 0, height: 0)
                guard actionUIWinUIElementBoundsIn(row.panel.object.pointer, self.list.pointer, &bounds),
                      bounds.width > 0, bounds.x >= 0, bounds.x.isFinite, abs(bounds.x - self.columns.inset) >= 0.5 else { return }
                self.columns.inset = bounds.x
                self.panel.invalidateLayout()
                self.header?.panel.invalidateLayout()
            }
        }
    }
}

/// What a Table shows, kept in its node's state.
@MainActor final class TableState {
    let layout: TableLayout
    /// The content as drawn, and the rows as given to the element source.
    var drawnRows: [[String]] = []
    var sourceRows: [[String]] = []
    /// The columns the header and the rows were made for: a change makes them again.
    var shownColumns: (titles: [String], ideals: [Int], minimums: [Int], fills: [Bool], headerShown: Bool)?
    /// The rows made (in or near view): each one's element.
    var made: [TableRowLayout] = []
    /// The row the renderer last selected: a selection event reporting it is the renderer's own.
    var shownIndex: Int32 = -1
    /// The columns' cell types the rows were made with: a change makes them again.
    var shownCellKinds: [String]?
    /// Rows a user toggled: made again at the next update even when their data did not change (a host
    /// that put the cell back shows its value again).
    var staleRows: Set<Int> = []

    init(layout: TableLayout) {
        self.layout = layout
    }
}

extension Table: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .both }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let list = WinUIObject(adopting: actionUIWinUIListCreate()) else {
            throw WinUIError.last("creating a Table's ListView")
        }
        let layout = try TableLayout(list: list)
        let state = TableState(layout: layout)
        node.state = state
        WinUIEvents.connect(list, actionUIWinUIListOnSelectionChanged, "a Table's selection") { [weak node, weak state, weak list] in
            guard let node, let state, let list, node.isAttached else { return }
            let index = actionUIWinUIListGetSelectedIndex(list.pointer)
            guard index != state.shownIndex else { return }
            state.shownIndex = index
            userSelected(node, state, index: index >= 0 ? Int(index) : nil)
        }
        WinUIEvents.connect(list, actionUIWinUIListOnActivated, "a Table's activation") { [weak node, weak state, weak list] in
            guard let node, let state, let list, node.isAttached else { return }
            let index = actionUIWinUIListGetSelectedIndex(list.pointer)
            userActivated(node, state, index: index >= 0 ? Int(index) : nil)
        }
        let box = TableSourceBox()
        box.node = node
        if !actionUIWinUIListSetElementSource(list.pointer, makeTableRow, recycleTableRow, Unmanaged.passRetained(box).toOpaque(),
                                              releaseTableSourceBox) {
            ActionUIModel.shared.logger.log("Table: \(WinUIError.last("registering the rows' source"))", .error)
        }
        if !actionUIWinUIListSetSelectable(list.pointer, true) || !actionUIWinUIListUseElementSource(list.pointer, true) {
            ActionUIModel.shared.logger.log("Table: \(WinUIError.last("showing rows as they come into view"))", .error)
        }
        return layout.panel.object
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? TableState else { return }
        let props = Props(node.properties)
        let layout = state.layout
        let list = layout.list
        // The columns, as the Apple and Linux renderers resolve them: the ideals 100 when missing, the
        // minimums the smaller of 10 and the ideal when missing, an ideal raised to its minimum; the
        // columns with the largest ideal as given fill.
        let titles = props.columns
        // Within StackSolver.maximumLength, so the widths' sum cannot overflow.
        let given = titles.indices.map { index in min((props.widths?[safe: index]).map { Int($0) } ?? 100, StackSolver.maximumLength) }
        let minimums = titles.indices.map { index in
            min(max((props.minWidths?[safe: index]).map { Int($0) } ?? min(10, given[index]), 0), StackSolver.maximumLength)
        }
        let ideals = titles.indices.map { index in max(given[index], minimums[index]) }
        let largest = given.max()
        let fills = given.map { $0 == largest }
        let headerShown = props.columnHeadersVisibility != .hidden
        let columns = (titles, ideals, minimums, fills, headerShown)
        if state.shownColumns.map({ $0 != columns }) ?? true {
            // Widths the user set stay while only the header's visibility changes.
            if state.shownColumns.map({ ($0.titles, $0.ideals, $0.minimums, $0.fills) != (titles, ideals, minimums, fills) }) ?? true {
                layout.columns.userWidths = [:]
            }
            state.shownColumns = columns
            layout.columns.titles = titles
            layout.columns.ideals = ideals
            layout.columns.minimums = minimums
            layout.columns.fills = fills
            layout.setHeader(shown: headerShown)
            // Every row made again for the new columns.
            for index in state.sourceRows.indices {
                state.shownIndex = -1
                if !actionUIWinUIListSourceReplace(list.pointer, Int32(index), rowLabel(state.sourceRows[index])) {
                    ActionUIModel.shared.logger.log("Table: \(WinUIError.last("changing a row"))", .error)
                }
            }
            layout.panel.invalidateLayout()
        }
        // A change of the columns' types (or of an Image cell's symbol size) makes every row again.
        let cellKinds = props.columnTypes.map { "\($0.viewType.rawValue) \($0.dataInterpretation?.rawValue ?? "") \($0.toggleStyle.rawValue) \($0.actionID ?? "") \($0.actionContext.rawValue) \($0.disabledColumn ?? 0)" }
            + ["\(ImageLayout.symbolSide(node, scale: nil))"]
        if cellKinds != state.shownCellKinds {
            let remake = state.shownCellKinds != nil
            state.shownCellKinds = cellKinds
            for index in state.sourceRows.indices where remake {
                state.shownIndex = -1
                if !actionUIWinUIListSourceReplace(list.pointer, Int32(index), rowLabel(state.sourceRows[index])) {
                    ActionUIModel.shared.logger.log("Table: \(WinUIError.last("changing a row"))", .error)
                }
            }
        }
        let rows = node.model.states["content"] as? [[String]] ?? []
        state.drawnRows = rows
        showRows(list, state, rows)
        select(list, state, RowSelection.selectedIndex(value: node.model.value, in: rows))
    }

    /// Makes the element source show `rows`: a row whose data changes is made again, rows are added at
    /// and removed from the end.
    private static func showRows(_ list: WinUIObject, _ state: TableState, _ rows: [[String]]) {
        let old = state.sourceRows
        // The rows first: the ListView may ask for an element as soon as they change.
        state.sourceRows = rows
        let stale = state.staleRows
        state.staleRows = []
        for index in 0..<min(old.count, rows.count) where old[index] != rows[index] || stale.contains(index) {
            state.shownIndex = -1
            if !actionUIWinUIListSourceReplace(list.pointer, Int32(index), rowLabel(rows[index])) {
                ActionUIModel.shared.logger.log("Table: \(WinUIError.last("changing a row"))", .error)
            }
        }
        if rows.count < old.count {
            state.shownIndex = -1
            if !actionUIWinUIListSourceTruncate(list.pointer, Int32(rows.count)) {
                ActionUIModel.shared.logger.log("Table: \(WinUIError.last("removing rows"))", .error)
            }
        } else if rows.count > old.count {
            for row in rows[old.count...] where !actionUIWinUIListSourceAppend(list.pointer, rowLabel(row)) {
                ActionUIModel.shared.logger.log("Table: \(WinUIError.last("adding rows"))", .error)
                state.sourceRows = Array(rows.prefix(max(Int(actionUIWinUIListSourceCount(list.pointer)), 0)))
                break
            }
        }
    }

    // MARK: Cells

    /// The cell of `type` showing `text` (row `rowIndex`'s column `column`): a text, a Button, an
    /// Image, an AsyncImage or a Toggle, as on Linux and Apple.
    private static func cell(_ type: Props.ColumnType, text: String, row: [String], rowIndex: Int, column: Int,
                             _ node: RenderNode, _ state: TableState) throws(WinUIError) -> TableRowLayout.Cell {
        switch type.viewType {
        case .text:
            return try TableRowLayout.textCell(text)
        case .button:
            guard let button = WinUIObject(adopting: actionUIWinUIButtonCreate()) else {
                throw WinUIError.last("making a Button cell")
            }
            // The text as its title, or an image read as dataInterpretation says when that is set.
            var shown: Bool
            if let interpretation = type.dataInterpretation, let image = imageCell(text, interpretation, node) {
                shown = actionUIWinUIButtonSetContent(button.pointer, image.pointer)
            } else {
                shown = actionUIWinUIButtonSetTitle(button.pointer, text)
            }
            if !shown {
                ActionUIModel.shared.logger.log("Table: \(WinUIError.last("showing a Button cell"))", .error)
            }
            // A row whose data changes is made again: the row index and text stay this button's.
            WinUIEvents.connect(button, actionUIWinUIButtonOnClick, "a Table's Button cell") { [weak node] in
                guard let node, node.isAttached, let actionID = type.actionID else { return }
                let context: Any
                switch type.actionContext {
                case .title: context = text
                case .rowIndex: context = rowIndex
                case .columnIndex: context = column
                case .rowColumnIndex: context = ["row": rowIndex, "column": column]
                }
                ActionUIModel.shared.actionHandler(actionID, windowUUID: node.windowModel.windowUUID, viewID: node.element.id,
                                                   viewPartID: column, context: context)
            }
            return TableRowLayout.Cell(view: button, fills: false)
        case .image:
            guard let image = imageCell(text, type.dataInterpretation ?? .systemName, node) else {
                // An image the shim has no symbol for shows nothing, as Image does.
                return try TableRowLayout.textCell("")
            }
            return TableRowLayout.Cell(view: image, fills: false)
        case .asyncImage:
            return try asyncImageCell(text)
        case .toggle:
            return try toggleCell(type, text: text, row: row, rowIndex: rowIndex, column: column, node, state)
        }
    }

    /// An Image cell: the text read as `interpretation` says, as a List's Image cell shows it.
    private static func imageCell(_ text: String, _ interpretation: Props.DataInterpretation, _ node: RenderNode) -> WinUIObject? {
        let listInterpretation = List.Props.DataInterpretation(rawValue: interpretation.rawValue) ?? .systemName
        return List.imageCell(text, ListState.RowCell(type: .image, interpretation: listInterpretation,
                                                      symbolSide: ImageLayout.symbolSide(node, scale: nil)))
    }

    /// An AsyncImage cell: the image the text names, loaded without blocking and scaled to fit the cell
    /// (WinUI's Image, as AsyncImage loads it); nothing until it loads, and when it cannot.
    private static func asyncImageCell(_ text: String) throws(WinUIError) -> TableRowLayout.Cell {
        guard let image = WinUIObject(adopting: actionUIWinUIImageCreate()) else {
            throw WinUIError.last("making an AsyncImage cell")
        }
        if Link.destination(text) == .absolute {
            if !actionUIWinUIImageSetURL(image.pointer, text) || !actionUIWinUIImageSetStretch(image.pointer, ActionUIWinUIImageStretchFit) {
                ActionUIModel.shared.logger.log("Table: \(WinUIError.last("loading \(text)"))", .warning)
            }
        }
        // As tall as a text row, scaled to fit (the row layout measures it within 24 points).
        return TableRowLayout.Cell(view: image, fills: false, height: 24)
    }

    /// A Toggle cell: a checkbox (or a switch, by style; a toggle button is a checkbox for now) showing
    /// the text as a Bool; a user toggle writes "true" or "false" into the cell and fires the entry's
    /// actionID (Core Table.commitCellToggle); disabledColumn's text, read the same way, disables it.
    private static func toggleCell(_ type: Props.ColumnType, text: String, row: [String], rowIndex: Int, column: Int,
                                   _ node: RenderNode, _ state: TableState) throws(WinUIError) -> TableRowLayout.Cell {
        let isOn = TemplateHelper.rowBool(text) ?? false
        let enabled = !isCellDisabled(disabledColumn: type.disabledColumn, row: row)
        let toggled: @MainActor (Bool) -> Void = { [weak node, weak state] on in
            guard let node, let state, node.isAttached, state.drawnRows.indices.contains(rowIndex) else { return }
            // Made again at the next update from what the rows hold then.
            state.staleRows.insert(rowIndex)
            let taken = commitCellToggle(on, drawnRow: state.drawnRows[rowIndex], rowIndex: rowIndex, column: column,
                                         actionID: type.actionID, windowUUID: node.windowModel.windowUUID, viewID: node.element.id)
            if !taken {
                // The row is gone: the next update shows the rows' state again.
                SyncScheduler.shared.markDirty(node)
            }
        }
        let view: WinUIObject
        if type.toggleStyle == .switch {
            guard let toggle = WinUIObject(adopting: actionUIWinUIToggleSwitchCreate()) else {
                throw WinUIError.last("making a Toggle cell")
            }
            // Set before the handler: the switch reports a setter's change as it reports the user's.
            if !actionUIWinUIToggleSwitchSetTitle(toggle.pointer, nil) || !actionUIWinUIToggleSwitchSetOn(toggle.pointer, isOn) {
                ActionUIModel.shared.logger.log("Table: \(WinUIError.last("showing a Toggle cell"))", .error)
            }
            // The value last shown or reported, not the made one: a second user toggle back to it before
            // the row is made again (or when a handler put the rows back) is the user's too.
            var shownOn = isOn
            WinUIEvents.connect(toggle, actionUIWinUIToggleSwitchOnToggled, "a Table's Toggle cell") { [weak toggle] in
                guard let toggle else { return }
                let on = actionUIWinUIToggleSwitchIsOn(toggle.pointer)
                guard on != shownOn else { return }
                shownOn = on
                toggled(on)
            }
            view = toggle
        } else {
            guard let box = WinUIObject(adopting: actionUIWinUICheckBoxCreate()) else {
                throw WinUIError.last("making a Toggle cell")
            }
            if !actionUIWinUICheckBoxSetChecked(box.pointer, isOn) {
                ActionUIModel.shared.logger.log("Table: \(WinUIError.last("showing a Toggle cell"))", .error)
            }
            WinUIEvents.connect(box, actionUIWinUICheckBoxOnClick, "a Table's Toggle cell") { [weak box] in
                guard let box else { return }
                toggled(actionUIWinUICheckBoxIsChecked(box.pointer))
            }
            view = box
        }
        if !actionUIWinUIElementSetEnabled(view.pointer, enabled) {
            ActionUIModel.shared.logger.log("Table: \(WinUIError.last("enabling a Toggle cell"))", .error)
        }
        return TableRowLayout.Cell(view: view, fills: false)
    }

    /// What accessibility tools name a row by: its columns in order, as VoiceOver reads a row's cells.
    private static func rowLabel(_ row: [String]) -> String {
        row.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The ListView shows row `index`: its cells (each column of the row, empty past its end).
    fileprivate static func makeRow(_ node: RenderNode, _ index: Int) -> OpaquePointer? {
        guard node.isAttached, let state = node.state as? TableState, state.sourceRows.indices.contains(index) else { return nil }
        let row = state.sourceRows[index]
        let columns = state.layout.columns
        let types = Props(node.properties).columnTypes
        do {
            var cells: [TableRowLayout.Cell] = []
            for column in 0..<columns.count {
                let text = column < row.count ? row[column] : ""
                let type = column < types.count ? types[column] : Props.ColumnType([:])
                cells.append(try cell(type, text: text, row: row, rowIndex: index, column: column, node, state))
            }
            let made = try TableRowLayout(columns: columns, cells: cells, isHeader: false)
            if !actionUIWinUIElementSetAlignment(made.panel.object.pointer, ActionUIWinUIAlignStart, ActionUIWinUIAlignCenter) {
                ActionUIModel.shared.logger.log("Table: \(WinUIError.last("placing a row"))", .error)
            }
            state.made.append(made)
            state.layout.rows = state.made
            return made.panel.object.pointer
        } catch {
            ActionUIModel.shared.logger.log("Table: \(error)", .error)
            return nil
        }
    }

    /// The ListView recycled a row's container: its cells are let go.
    fileprivate static func recycleRow(_ node: RenderNode, _ element: OpaquePointer) {
        guard let state = node.state as? TableState,
              let position = state.made.firstIndex(where: { actionUIWinUIObjectIsSame($0.panel.object.pointer, element) }) else { return }
        state.made.remove(at: position)
        state.layout.rows = state.made
    }

    /// Shows `index` (nil: none) as the selected row, remembering it as the renderer's own.
    private static func select(_ list: WinUIObject, _ state: TableState, _ index: Int?) {
        let wanted = Int32(index.flatMap { $0 < state.sourceRows.count ? $0 : nil } ?? -1)
        state.shownIndex = wanted
        if !actionUIWinUIListSetSelectedIndex(list.pointer, wanted) {
            ActionUIModel.shared.logger.log("Table: \(WinUIError.last("selecting a row"))", .error)
        }
        state.shownIndex = actionUIWinUIListGetSelectedIndex(list.pointer)
    }

    /// The user selected row `index` (nil: a deselect).
    private static func userSelected(_ node: RenderNode, _ state: TableState, index: Int?) {
        guard let clicked = RowSelection.clickedRow(index: index, in: state.drawnRows) else { return }
        RowSelection.commitRowSelection(clicked, drawnRows: state.drawnRows, model: node.model, actionID: Props(node.properties).actionID,
                                        windowUUID: node.windowModel.windowUUID, viewID: node.element.id)
    }

    /// A double click or Return on a row: the row becomes the value and doubleClickActionID fires with
    /// its index; when that changes the selection, actionID fires first (as on Linux).
    private static func userActivated(_ node: RenderNode, _ state: TableState, index: Int?) {
        let props = Props(node.properties)
        guard let doubleClickActionID = props.doubleClickActionID, let index, state.drawnRows.indices.contains(index) else { return }
        let current = node.model.states["content"] as? [[String]] ?? []
        let row = ActionUIModel.reconciledSelection(state.drawnRows[index], from: state.drawnRows, to: current)
        let changed = (node.model.value as? [String] ?? []) != row
        node.model.value = row
        let windowUUID = node.windowModel.windowUUID
        if changed, let actionID = props.actionID {
            ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: node.element.id, viewPartID: 0)
        }
        ActionUIModel.shared.actionHandler(doubleClickActionID, windowUUID: windowUUID, viewID: node.element.id, viewPartID: 0,
                                           context: index)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// The element source's callback context: a weak reference to the Table's node.
@MainActor private final class TableSourceBox {
    weak var node: RenderNode?
}

private func tableSourceBox(_ context: UnsafeMutableRawPointer?) -> TableSourceBox? {
    context.map { Unmanaged<TableSourceBox>.fromOpaque($0).takeUnretainedValue() }
}

// The element's address crosses the main actor's closure as a number (a pointer is not Sendable).
private let makeTableRow: ActionUIWinUIRepeaterMake = { context, index in
    let box = tableSourceBox(context)
    let address = MainActor.assumeIsolated {
        UInt(bitPattern: box?.node.flatMap { Table.makeRow($0, Int(index)) })
    }
    return OpaquePointer(bitPattern: address)
}

private let recycleTableRow: ActionUIWinUIRepeaterRecycle = { context, element in
    let box = tableSourceBox(context)
    let address = UInt(bitPattern: element)
    MainActor.assumeIsolated {
        guard let node = box?.node, let element = OpaquePointer(bitPattern: address) else { return }
        Table.recycleRow(node, element)
    }
}

private let releaseTableSourceBox: ActionUIWinUICallback = { context in
    guard let context else { return }
    Unmanaged<TableSourceBox>.fromOpaque(context).release()
}
