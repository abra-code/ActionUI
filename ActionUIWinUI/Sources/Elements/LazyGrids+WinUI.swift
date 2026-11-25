// Sources/Elements/LazyGrids+WinUI.swift
/*
 LazyVGrid and LazyHGrid on WinUI: their children, or one template instance per content row
 (setElementRows; the template shown with the row's data, as on Apple and Linux), flowing into the
 declared columns (rows for LazyHGrid) as GridCellsLayout lays them out: a column with a numeric
 "minimum" is that wide, one with "flexible": true shares the rest. spacing is the space between rows
 (columns for LazyHGrid); alignment places the block of tracks in the grid and each child in its cell.
 The grid takes all the room it is offered along its tracks (a LazyVGrid all the width), as on macOS.

 - The children form lays out every child at once (GridCellsLayout), as on Linux.
 - The template form is lazy (LazyGridLines): an ItemsRepeater shows one item per line of the grid (a
   row of a LazyVGrid, a column of a LazyHGrid) and asks for a line's element only when the line comes
   in or near the part its ScrollView shows; the line is its rows' template instances laid out by
   GridCellsLayout. A line far out of view is let go, its instances with it. Lines are kept by their
   content: a line whose rows' data changes is made again, lines are added at and removed from the
   end; a change in the number of tracks makes every line again. The form is chosen when the grid is
   made (a template in the ActionUI JSON).

 Each line of the template form is laid out on its own, for the same length along the tracks (the
 grid's width), so the columns line up; a flexible column's ideal width (a LazyVGrid in a row that
 offers no width) is its line's longest cell's, where the children form takes the whole grid's.
*/

import CWinUI

/// A lazy grid's template form: its repeater of lines, the rows it shows and the lines made.
@MainActor
final class LazyGridLines: RepeaterSource {
    private(set) var repeater: WinUIObject!
    private weak var node: RenderNode?
    private var template: (any ActionUIElementBase)?
    private var rows: [[String]] = []
    private(set) var configuration: GridConfiguration
    private var lineSpacing = -1
    /// The lines made: each one's instances and layout.
    private var made: [(instances: [RenderNode], cells: GridCellsLayout)] = []

    init(node: RenderNode, vertical: Bool) throws(WinUIError) {
        self.node = node
        configuration = GridConfiguration(vertical: vertical)
        repeater = try makeRepeater(vertical: vertical, source: self, what: "a lazy grid")
    }

    /// The rows of each line: the content rows `tracks` at a time.
    private static func lines(_ rows: [[String]], tracks: Int) -> [[[String]]] {
        guard tracks > 0 else { return [] }
        return stride(from: 0, to: rows.count, by: tracks).map { Array(rows[$0..<min($0 + tracks, rows.count)]) }
    }

    /// Makes the repeater's items the lines of the content rows, laid out by `newConfiguration`.
    func update(template: (any ActionUIElementBase)?, rows newRows: [[String]], configuration newConfiguration: GridConfiguration) {
        self.template = template
        let oldLines = Self.lines(rows, tracks: configuration.tracks.count)
        // The lines are the repeater's items; the space between them is its spacing.
        var lineConfiguration = newConfiguration
        lineConfiguration.lineSpacing = 0
        let tracksChanged = newConfiguration.tracks.count != configuration.tracks.count
        if lineConfiguration != configuration {
            configuration = lineConfiguration
            for line in made {
                line.cells.setConfiguration(lineConfiguration)
            }
        }
        if newConfiguration.lineSpacing != lineSpacing {
            if actionUIWinUIRepeaterSetSpacing(repeater.pointer, Double(newConfiguration.lineSpacing)) {
                lineSpacing = newConfiguration.lineSpacing
            } else {
                ActionUIModel.shared.logger.log("LazyGridLines: \(WinUIError.last("setting the spacing"))", .error)
            }
        }
        // The rows first: the repeater may ask for an element as soon as its items change.
        rows = newRows
        let newLines = Self.lines(newRows, tracks: configuration.tracks.count)
        for index in 0..<min(oldLines.count, newLines.count) where tracksChanged || oldLines[index] != newLines[index] {
            if !actionUIWinUIRepeaterReplace(repeater.pointer, Int32(index)) {
                ActionUIModel.shared.logger.log("LazyGridLines: \(WinUIError.last("changing a line"))", .error)
            }
        }
        if newLines.count < oldLines.count, !actionUIWinUIRepeaterTruncate(repeater.pointer, Int32(newLines.count)) {
            ActionUIModel.shared.logger.log("LazyGridLines: \(WinUIError.last("removing lines"))", .error)
        }
        for _ in oldLines.count..<max(oldLines.count, newLines.count) {
            if !actionUIWinUIRepeaterAppend(repeater.pointer) {
                ActionUIModel.shared.logger.log("LazyGridLines: \(WinUIError.last("adding a line"))", .error)
                // The lines the repeater has: the next update adds the others.
                let count = max(Int(actionUIWinUIRepeaterCount(repeater.pointer)), 0)
                rows = Array(newRows.prefix(count * configuration.tracks.count))
                break
            }
        }
    }

    /// The repeater asks for line `index`: its rows' instances, made and synced now (a layout pass is
    /// under way), laid out in one line of the grid.
    func make(_ index: Int) -> OpaquePointer? {
        let tracks = configuration.tracks.count
        guard let node, node.isAttached, let template, tracks > 0, index >= 0, index * tracks < rows.count else { return nil }
        let rowIndices = (index * tracks)..<min((index + 1) * tracks, rows.count)
        let instances = rowIndices.map { row in node.templateRowNode(template, row: rows[row], rowIndex: row) }
        for instance in instances {
            instance.sync()
        }
        do {
            let cells = try GridCellsLayout()
            cells.setConfiguration(configuration)
            cells.setItems(instances.compactMap { instance in
                instance.outerView.map { GridCellsLayout.Item(view: $0, expansion: instance.expansion, cap: instance.caps) }
            })
            made.append((instances, cells))
            return cells.panel.object.pointer
        } catch {
            ActionUIModel.shared.logger.log("LazyGridLines: \(error)", .error)
            for instance in instances {
                node.releaseTemplateNode(instance)
            }
            return nil
        }
    }

    /// The repeater no longer shows `element`: its line's instances leave the tree.
    func recycle(_ element: OpaquePointer) {
        guard let position = made.firstIndex(where: { actionUIWinUIObjectIsSame($0.cells.panel.object.pointer, element) }) else { return }
        let line = made.remove(at: position)
        for instance in line.instances {
            node?.releaseTemplateNode(instance)
        }
    }
}

/// What both lazy grids share.
@MainActor
enum LazyGrids {
    static func track(_ size: Double?) -> GridTrack {
        size.map { .fixed(StackSolver.length($0)) } ?? .flexible
    }

    /// The grid's view: a repeater of lines for a grid whose ActionUI JSON gives it a template, else a
    /// layout of all its children.
    static func makeView(_ node: RenderNode, vertical: Bool) throws(WinUIError) -> WinUIObject {
        if node.element.subviews?["template"] is any ActionUIElementBase {
            let lines = try LazyGridLines(node: node, vertical: vertical)
            node.state = lines
            return lines.repeater
        }
        let cells = try GridCellsLayout()
        node.state = cells
        return cells.panel.object
    }

    /// Shows the children or the content rows with `configuration`.
    static func update(_ node: RenderNode, configuration: GridConfiguration) {
        if let lines = node.state as? LazyGridLines {
            let template = node.effectiveElement.subviews?["template"] as? any ActionUIElementBase
            lines.update(template: template, rows: template == nil ? [] : node.model.states["content"] as? [[String]] ?? [],
                         configuration: configuration)
        } else if let cells = node.state as? GridCellsLayout {
            cells.setConfiguration(configuration)
            // One that takes no place (an EmptyView, a Link with no URL) takes no cell, as in SwiftUI's grids (measured on macOS 27 for Grid).
            cells.setItems(node.syncChildren(node.subviews("children")).compactMap { child in
                guard !child.takesNoPlace, let view = child.outerView else { return nil }
                return GridCellsLayout.Item(view: view, expansion: child.expansion, cap: child.caps)
            })
        }
    }
}

extension LazyVGrid: ActionUIWinUIRenderer {
    /// All the width it is offered, whatever its children.
    static var defaultExpansion: Expansion { .horizontal }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        try LazyGrids.makeView(node, vertical: true)
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        let props = Props(node.properties)
        let alignment: StackSolver.Alignment
        switch props.alignment {
        case .leading: alignment = .start
        case .center: alignment = .center
        case .trailing: alignment = .end
        }
        let tracks = props.columns.map { column -> GridTrack in
            switch column {
            case .fixed(let size): return LazyGrids.track(size)
            case .flexible: return .flexible
            }
        }
        LazyGrids.update(node, configuration: GridConfiguration(vertical: true, tracks: tracks, alignment: alignment,
                                                                lineSpacing: StackSolver.length(props.spacing)))
    }
}

extension LazyHGrid: ActionUIWinUIRenderer {
    /// All the height it is offered, whatever its children.
    static var defaultExpansion: Expansion { .vertical }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        try LazyGrids.makeView(node, vertical: false)
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        let props = Props(node.properties)
        let alignment: StackSolver.Alignment
        switch props.alignment {
        case .top: alignment = .start
        case .center: alignment = .center
        case .bottom: alignment = .end
        }
        let tracks = props.rows.map { row -> GridTrack in
            switch row {
            case .fixed(let size): return LazyGrids.track(size)
            case .flexible: return .flexible
            }
        }
        LazyGrids.update(node, configuration: GridConfiguration(vertical: false, tracks: tracks, alignment: alignment,
                                                                lineSpacing: StackSolver.length(props.spacing)))
    }
}
