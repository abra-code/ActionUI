// Sources/Layout/GridCellsLayout.swift
/*
 LazyVGrid's and LazyHGrid's layout on WinUI, as SwiftUI lays them out and as the Linux renderer
 does (LazyGridLayout.swift there, measured on macOS 27: the lazyvgrid-* and lazyhgrid-* layout
 parity fixtures). Described for LazyVGrid; LazyHGrid is the same with the axes swapped (rows for
 columns).

 - The grid takes all the width it is offered. Its columns are its tracks: a fixed one is its width,
   the flexible ones share what the fixed ones and the spacing between columns (8, SwiftUI's default
   GridItem spacing) leave, each at least 10. The block of columns sits at the grid's alignment
   within its width.
 - Children fill the columns row by row. A child takes its column's width (a child that expands
   across fills it, up to its cap; another takes what it asks for in that width) and its height for
   that width; it sits at the grid's alignment in its column and centered in its row. A row is as tall
   as its tallest child; a child that expands vertically fills the row, up to its cap. Rows are
   `lineSpacing` apart, and the grid is as tall as its rows.

 One GridCellsLayout lays out a whole grid (the children form) or one row of it (the template form's
 rows, made as they come into view: LazyGridLines).
*/

import CWinUI

/// One track: a column of a LazyVGrid, a row of a LazyHGrid.
enum GridTrack: Equatable {
    case fixed(Int)
    case flexible
}

/// How a lazy grid's cells are laid out: its tracks, their alignment and the space between lines.
struct GridConfiguration: Equatable {
    /// True for LazyVGrid: the tracks are columns.
    var vertical = true
    var tracks: [GridTrack] = [.flexible]
    var alignment = StackSolver.Alignment.center
    var lineSpacing = 0

    /// The space between tracks (SwiftUI's default GridItem spacing) and a flexible track's minimum.
    static let trackSpacing = 8
    static let flexibleMinimum = 10

    /// The tracks' sizes in a grid `available` long: fixed ones their size, flexible ones an equal
    /// share of the rest (the first ones a pixel more when it does not divide), each at least 10.
    func trackSizes(available: Int) -> [Int] {
        let gaps = Self.trackSpacing * max(0, tracks.count - 1)
        var fixed = 0
        var flexible = 0
        for track in tracks {
            switch track {
            case .fixed(let size): fixed += size
            case .flexible: flexible += 1
            }
        }
        let rest = max(available - gaps - fixed, flexible * Self.flexibleMinimum)
        var extra = flexible > 0 ? rest % flexible : 0
        return tracks.map { track in
            switch track {
            case .fixed(let size):
                return size
            case .flexible:
                let size = max(Self.flexibleMinimum, rest / flexible + (extra > 0 ? 1 : 0))
                extra -= 1
                return size
            }
        }
    }

    /// The tracks' smallest total length, with the spacing between them.
    var minimumLength: Int {
        tracks.reduce(Self.trackSpacing * max(0, tracks.count - 1)) { total, track in
            if case .fixed(let size) = track { return total + size }
            return total + Self.flexibleMinimum
        }
    }
}

/// Lays out cells in lines of a grid's tracks.
@MainActor
final class GridCellsLayout {
    struct Item {
        let view: WinUIObject
        var expansion: Expansion = []
        var cap: (horizontal: Int?, vertical: Int?) = (nil, nil)
    }

    let panel: LayoutPanel
    private(set) var configuration = GridConfiguration()
    private(set) var items: [Item] = []

    /// Where each cell goes, worked out for one track length (the grid's width, a LazyHGrid's height).
    private struct Plan {
        var trackLength: Int
        var trackSizes: [Int]
        var blockStart: Int
        var lineSizes: [Int]
        /// Each cell's track, line, size along the tracks' axis and across it, and what it asked for
        /// along the tracks' axis in its track.
        var cells: [(track: Int, line: Int, along: Int, across: Int, asked: Int)]
    }

    private var plan: Plan?

    init() throws(WinUIError) {
        panel = try LayoutPanel()
        panel.measure = { [unowned self] available in measure(available) }
        panel.arrange = { [unowned self] finalSize in arrange(finalSize) }
    }

    func setConfiguration(_ configuration: GridConfiguration) {
        guard configuration != self.configuration else { return }
        self.configuration = configuration
        panel.invalidateLayout()
    }

    func setItems(_ newItems: [Item]) {
        let current = items.map { ObjectIdentifier($0.view) }
        let wanted = newItems.map { ObjectIdentifier($0.view) }
        let changed = items.map(\.expansion.rawValue) != newItems.map(\.expansion.rawValue)
            || !items.elementsEqual(newItems) { $0.cap == $1.cap }
        items = newItems
        if current != wanted {
            do {
                while !panel.children.isEmpty {
                    try panel.remove(at: panel.children.count - 1)
                }
                // In order, so keyboard focus moves through the cells as they are read.
                for item in newItems {
                    try panel.append(item.view)
                }
            } catch {
                ActionUIModel.shared.logger.log("GridCellsLayout: \(error)", .error)
            }
        }
        if current != wanted || changed {
            panel.invalidateLayout()
        }
    }

    // MARK: Layout

    private func along(_ size: ActionUIWinUISize) -> Double { configuration.vertical ? size.width : size.height }
    private func across(_ size: ActionUIWinUISize) -> Double { configuration.vertical ? size.height : size.width }
    private func size(along: Double, across: Double) -> ActionUIWinUISize {
        configuration.vertical ? ActionUIWinUISize(width: along, height: across) : ActionUIWinUISize(width: across, height: along)
    }
    private func expandsAlong(_ item: Item) -> Bool { item.expansion.contains(configuration.vertical ? .horizontal : .vertical) }
    private func expandsAcross(_ item: Item) -> Bool { item.expansion.contains(configuration.vertical ? .vertical : .horizontal) }
    private func capAlong(_ item: Item) -> Int? { configuration.vertical ? item.cap.horizontal : item.cap.vertical }
    private func capAcross(_ item: Item) -> Int? { configuration.vertical ? item.cap.vertical : item.cap.horizontal }

    /// The tracks' length when each flexible track is as long as its longest cell (offered nothing
    /// along the tracks: a LazyVGrid measured for its ideal width).
    private func naturalTrackLength() -> Int {
        let tracks = configuration.tracks
        guard !tracks.isEmpty else { return 0 }
        var longest = [Int](repeating: GridConfiguration.flexibleMinimum, count: tracks.count)
        for (index, item) in items.enumerated() {
            let track = index % tracks.count
            let asked = item.view.measureRequested(size(along: .infinity, across: .infinity))
            longest[track] = max(longest[track], StackSolver.length(along(asked), rounding: .up))
        }
        return zip(tracks, longest).reduce(GridConfiguration.trackSpacing * (tracks.count - 1)) { total, pair in
            if case .fixed(let size) = pair.0 { return total + size }
            return total + pair.1
        }
    }

    private func makePlan(trackLength: Int) -> Plan {
        let sizes = configuration.trackSizes(available: trackLength)
        let block = sizes.reduce(GridConfiguration.trackSpacing * max(0, sizes.count - 1), +)
        let blockStart = max(0, StackSolver.alignedOffset(size: block, block: trackLength, alignment: configuration.alignment))
        var plan = Plan(trackLength: trackLength, trackSizes: sizes, blockStart: blockStart, lineSizes: [], cells: [])
        guard !sizes.isEmpty else { return plan }
        for (index, item) in items.enumerated() {
            let track = index % sizes.count
            let line = index / sizes.count
            let room = sizes[track]
            // What it asks for in its track's length: a wrapping text at most that long, a fixed size
            // its own (it may overflow the track, as a fixed child overflows a stack).
            let asked = item.view.measureRequested(size(along: Double(room), across: .infinity))
            let askedAlong = StackSolver.length(along(asked), rounding: .up)
            let alongSize = expandsAlong(item) ? max(min(room, capAlong(item) ?? room), askedAlong) : askedAlong
            // Its length across for the length it takes along.
            let measured = alongSize == askedAlong ? asked : item.view.measureRequested(size(along: Double(alongSize), across: .infinity))
            let acrossSize = StackSolver.length(across(measured), rounding: .up)
            if line == plan.lineSizes.count {
                plan.lineSizes.append(0)
            }
            plan.lineSizes[line] = max(plan.lineSizes[line], acrossSize)
            plan.cells.append((track, line, alongSize, acrossSize, askedAlong))
        }
        return plan
    }

    /// `plan` (the measure pass's) for a grid `trackLength` long, measuring no child: the tracks are
    /// sized and placed for that length, a cell that expands along them takes its new track (up to its
    /// cap, at least what it asked for), and every cell keeps its size across and every line its size.
    /// A child measured during arrange for another size than in the measure pass (a Color's desired
    /// size follows the offer) invalidates the grid's measure, which measures it back, and WinUI's
    /// layout never settles: a grid measured with nothing offered along its tracks (a LazyHGrid in a
    /// VStack, a LazyVGrid in an HStack) is arranged in the length its stack gives it.
    private func replanned(_ plan: Plan, trackLength: Int) -> Plan {
        let sizes = configuration.trackSizes(available: trackLength)
        guard sizes.count == plan.trackSizes.count else { return makePlan(trackLength: trackLength) }
        let block = sizes.reduce(GridConfiguration.trackSpacing * max(0, sizes.count - 1), +)
        var replanned = plan
        replanned.trackLength = trackLength
        replanned.trackSizes = sizes
        replanned.blockStart = max(0, StackSolver.alignedOffset(size: block, block: trackLength, alignment: configuration.alignment))
        for (index, item) in zip(replanned.cells.indices, items) where expandsAlong(item) {
            let cell = replanned.cells[index]
            let room = sizes[cell.track]
            replanned.cells[index].along = max(min(room, capAlong(item) ?? room), cell.asked)
        }
        return replanned
    }

    private func measure(_ available: ActionUIWinUISize) -> ActionUIWinUISize {
        let offered = along(available)
        let trackLength = offered.isFinite ? max(StackSolver.length(offered), configuration.minimumLength) : naturalTrackLength()
        let plan = makePlan(trackLength: trackLength)
        self.plan = plan
        let length = plan.lineSizes.reduce(configuration.lineSpacing * max(0, plan.lineSizes.count - 1), +)
        return size(along: Double(trackLength), across: Double(length))
    }

    private func arrange(_ finalSize: ActionUIWinUISize) {
        let trackLength = StackSolver.length(along(finalSize))
        // Arranged at another length than measured (a parent that gives more than it offered): the
        // cells are placed for it, without measuring them again (replanned).
        let plan: Plan
        if let measured = self.plan {
            plan = measured.trackLength == trackLength ? measured : replanned(measured, trackLength: trackLength)
        } else {
            plan = makePlan(trackLength: trackLength)
        }
        self.plan = plan
        // A grid without tracks shows no cell (its columns changed to none): its children are placed
        // nowhere rather than left where they were, as Linux hides them.
        guard !plan.trackSizes.isEmpty else {
            for item in items {
                item.view.arrange(ActionUIWinUIRect(x: 0, y: 0, width: 0, height: 0))
            }
            return
        }
        var trackStarts: [Int] = []
        var position = plan.blockStart
        for size in plan.trackSizes {
            trackStarts.append(position)
            position += size + GridConfiguration.trackSpacing
        }
        var lineStarts: [Int] = []
        position = 0
        for size in plan.lineSizes {
            lineStarts.append(position)
            position += size + configuration.lineSpacing
        }
        for (item, cell) in zip(items, plan.cells) {
            let lineSize = plan.lineSizes[cell.line]
            // One that expands across fills its line, up to its cap.
            let acrossSize = expandsAcross(item) ? max(min(lineSize, capAcross(item) ?? lineSize), cell.across) : cell.across
            let alongStart = trackStarts[cell.track]
                + StackSolver.alignedOffset(size: cell.along, block: plan.trackSizes[cell.track], alignment: configuration.alignment)
            let acrossStart = lineStarts[cell.line] + StackSolver.centeredStart(length: acrossSize, available: lineSize)
            let frame = configuration.vertical
                ? ActionUIWinUIRect(x: Double(alongStart), y: Double(acrossStart), width: Double(cell.along), height: Double(acrossSize))
                : ActionUIWinUIRect(x: Double(acrossStart), y: Double(alongStart), width: Double(acrossSize), height: Double(cell.along))
            item.view.arrange(frame)
        }
    }
}
