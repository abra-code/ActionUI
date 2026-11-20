// Sources/Elements/Table+WinUI.swift
/*
 Table on WinUI: a header row over Windows' ListView, as greedy as the List (it shares a stack like a
 Color), following the Linux renderer (Table+Adwaita.swift) and Apple's Table. One row per content row
 (setElementRows), all of them shown; a column shows that column of each row (empty when the row is
 shorter) as one line at the leading edge, cut short with an ellipsis, as a macOS Table cell.

 - Columns: widths are the ideal widths (100 when missing); the column with the largest takes the
   room left (each of them, when several have it), as the Apple renderer's columns do; a minWidth
   above the ideal widens the column to it. Short of room, those columns give it back down to their
   minWidths (default the smaller of 10 and the ideal); past that the row is cut at the table's edge. The header row (the titles, then a 1 point line)
   lines up with the rows' cells; columnHeadersVisibility hidden hides it.
 - Selection: a row the user selects becomes the value (its columns) and fires actionID (Core
   RowSelection), a deselect (Ctrl+click) too; a host's value selects its row and fires nothing; a
   rows change keeps the selection on its row (Core). A double click or Return makes the row the
   value and fires doubleClickActionID with its index, after actionID when the selection changes.
 - Rows are made as they come into view (the ListView's element source, as the List's), so a Table
   of thousands of rows makes tens; each row is named for accessibility tools by its columns.

 Not yet: the Button, Image, AsyncImage and Toggle cells (their text is shown, logged once per kind);
 resizing a column by dragging its header's edge; scrollContentBackground.
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
    /// Where the ListView puts a row's content from its edge (its item's padding), measured once rows
    /// exist: the header's cells start there too.
    var inset = 0.0

    var count: Int { titles.count }

    /// The widths for a row `available` wide: the ideals, the room left to the widest (each of them),
    /// or taken from them down to their minimums.
    @discardableResult
    func layOut(available: Double) -> Bool {
        var result = ideals
        let flexible = ideals.indices.filter { fills.indices.contains($0) && fills[$0] }
        var left = StackSolver.length(available) - ideals.reduce(0, +)
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

    /// Column `index`'s start and width in a row (0 past the columns laid out).
    func span(_ index: Int) -> (start: Int, width: Int) {
        guard widths.indices.contains(index) else { return (0, 0) }
        return (widths[..<index].reduce(0, +), widths[index])
    }
}

/// A row of cells (a content row's, or the header's) placed at the columns' widths.
@MainActor final class TableRowLayout {
    let panel: LayoutPanel
    let columns: TableColumns
    private(set) var cells: [WinUIObject] = []
    /// The header's: its cells start at the rows' inset.
    let isHeader: Bool

    init(columns: TableColumns, texts: [String], isHeader: Bool) throws(WinUIError) {
        self.columns = columns
        self.isHeader = isHeader
        panel = try LayoutPanel()
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
        for text in texts {
            guard let cell = WinUIObject(adopting: actionUIWinUITextBlockCreate()) else {
                throw WinUIError.last("making a Table cell")
            }
            var shown = actionUIWinUITextBlockSetText(cell.pointer, text) && actionUIWinUITextBlockSetTrimmed(cell.pointer, true)
            if isHeader {
                shown = shown && actionUIWinUIElementSetFont(cell.pointer, nil, 0, 600)
            }
            if !shown {
                ActionUIModel.shared.logger.log("Table: \(WinUIError.last("showing a cell"))", .error)
            }
            try panel.append(cell)
            cells.append(cell)
        }
    }

    private var offset: Double { isHeader ? columns.inset : 0 }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        var height = 0.0
        for (index, cell) in cells.enumerated() {
            let width = Double(columns.span(index).width)
            height = max(height, cell.measure(ActionUIWinUISize(width: width, height: .infinity)).height)
        }
        let width = Double(columns.span(max(columns.count - 1, 0)).start + columns.span(max(columns.count - 1, 0)).width) + offset
        return ActionUIWinUISize(width: available.width.isFinite ? min(width, available.width) : width, height: height)
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        for (index, cell) in cells.enumerated() {
            let span = columns.span(index)
            cell.arrange(ActionUIWinUIRect(x: offset + Double(span.start), y: 0, width: Double(span.width), height: finalSize.height))
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
                let made = try TableRowLayout(columns: columns, texts: columns.titles, isHeader: true)
                try panel.append(made.panel.object)
                header = made
            }
        } catch {
            ActionUIModel.shared.logger.log("Table: \(error)", .error)
        }
        panel.invalidateLayout()
    }

    private var headerHeight = 0.0

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
    /// The cell kinds shown as text for now, logged once each.
    var reportedTypes: Set<String> = []

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
        for (index, type) in props.columnTypes.enumerated() where index < titles.count && type.viewType != .text {
            if state.reportedTypes.insert(type.viewType.rawValue).inserted {
                ActionUIModel.shared.logger.log("Table: \(type.viewType.rawValue) cells are shown as their text on Windows for now", .warning)
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
        for index in 0..<min(old.count, rows.count) where old[index] != rows[index] {
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

    /// What accessibility tools name a row by: its columns in order, as VoiceOver reads a row's cells.
    private static func rowLabel(_ row: [String]) -> String {
        row.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The ListView shows row `index`: its cells (each column of the row, empty past its end).
    fileprivate static func makeRow(_ node: RenderNode, _ index: Int) -> OpaquePointer? {
        guard node.isAttached, let state = node.state as? TableState, state.sourceRows.indices.contains(index) else { return nil }
        let row = state.sourceRows[index]
        let columns = state.layout.columns
        let texts = (0..<columns.count).map { $0 < row.count ? row[$0] : "" }
        do {
            let made = try TableRowLayout(columns: columns, texts: texts, isHeader: false)
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
