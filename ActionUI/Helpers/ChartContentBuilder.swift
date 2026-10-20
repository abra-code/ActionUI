// Helpers/ChartContentBuilder.swift
//
// Builds a Chart's marks from its ChartSpec and rows. Mark initializers are generic over
// Plottable with each argument's type fixed at the call site, so every plottable value is
// "opened" into a typed PlottableValue by a switch over its scalar type, nested once per
// argument (a start/end pair opens together, as one type), and the finished mark is type-erased
// to AnyChartContent. The marks form one flat list that the chart emits through a single
// ForEach; erased marks render pixel-identically to typed ones (series join, stacking), and faster.

import Foundation
import SwiftUI
import Charts

// Rows parsed once per (column, type) pair. A nil cell is missing or did not parse. The raw rows
// are kept for text with "$N" references.
struct ChartTypedColumns {
    let rows: [[String]]
    private let cells: [ChartColumnRef: [ChartScalar?]]

    var rowCount: Int { rows.count }

    init(rows: [[String]], refs: [ChartColumnRef]) {
        self.rows = rows
        var cells: [ChartColumnRef: [ChartScalar?]] = [:]
        for ref in refs {
            cells[ref] = rows.map { row in
                guard ref.index < row.count else { return nil }
                return Self.parse(row[ref.index], as: ref.type)
            }
        }
        self.cells = cells
    }

    static func parse(_ cell: String, as type: ChartColumnType) -> ChartScalar? {
        switch type {
        case .string:
            return .string(cell)
        case .number:
            return Double(cell.trimmingCharacters(in: .whitespaces)).map { .number($0) }
        case .integer:
            return Int(cell.trimmingCharacters(in: .whitespaces)).map { .integer($0) }
        case .date:
            return DateHelper.parseDate(from: cell).map { .date($0) }
        }
    }

    func scalar(row: Int, ref: ChartColumnRef) -> ChartScalar? {
        cells[ref]?[row] ?? nil
    }
}

// MARK: - Openers

@MainActor
private protocol PlottableOpener {
    func open<P: Plottable>(_ value: PlottableValue<P>) -> AnyChartContent?
}

@MainActor
private protocol PairOpener {
    func open<P: Plottable>(_ start: PlottableValue<P>, _ end: PlottableValue<P>) -> AnyChartContent?
}

private func plottableValue<P: Plottable>(_ value: P, _ plottable: ChartPlottable) -> PlottableValue<P> {
    .value(plottable.label, value)
}

// Opens one scalar into a typed PlottableValue and hands it to `next`.
@MainActor
private func openScalar(_ scalar: ChartScalar, _ plottable: ChartPlottable, _ next: some PlottableOpener) -> AnyChartContent? {
    switch scalar {
    case .string(let value):
        return next.open(plottableValue(value, plottable))
    case .number(let value):
        return next.open(plottableValue(value, plottable))
    case .integer(let value):
        return next.open(plottableValue(value, plottable))
    case .date(let value):
        if let unit = plottable.unit {
            return next.open(.value(plottable.label, value, unit: unit))
        }
        return next.open(plottableValue(value, plottable))
    }
}

// Opens a start/end pair as one type. The description parser makes both plottables the same type, so
// both scalars have the same case.
@MainActor
private func openScalarPair(_ start: ChartScalar, _ startPlottable: ChartPlottable, _ end: ChartScalar, _ endPlottable: ChartPlottable,
                      _ next: some PairOpener) -> AnyChartContent? {
    switch (start, end) {
    case (.string(let a), .string(let b)):
        return next.open(plottableValue(a, startPlottable), plottableValue(b, endPlottable))
    case (.number(let a), .number(let b)):
        return next.open(plottableValue(a, startPlottable), plottableValue(b, endPlottable))
    case (.integer(let a), .integer(let b)):
        return next.open(plottableValue(a, startPlottable), plottableValue(b, endPlottable))
    case (.date(let a), .date(let b)):
        if let unit = startPlottable.unit ?? endPlottable.unit {
            return next.open(.value(startPlottable.label, a, unit: unit), .value(endPlottable.label, b, unit: unit))
        }
        return next.open(plottableValue(a, startPlottable), plottableValue(b, endPlottable))
    default:
        return nil
    }
}

// The opened arguments of one mark: scalars for its plottable values, plus its spec.
@MainActor
private struct MarkArguments {
    let spec: ChartMarkSpec
    let scalars: [String: ChartScalar]

    func scalar(_ key: String) -> ChartScalar { scalars[key]! }
    func plottable(_ key: String) -> ChartPlottable { spec.values[key]! }
    func point(_ key: String) -> CGFloat? { spec.points[key] }
}

// x + y (BarMark, LineMark, PointMark, AreaMark, RectangleMark) and x + y + series (LineMark, AreaMark).
@MainActor
private struct XYOpener: PlottableOpener {
    let args: MarkArguments
    func open<X: Plottable>(_ x: PlottableValue<X>) -> AnyChartContent? {
        openScalar(args.scalar("y"), args.plottable("y"), XYOpener2(args: args, x: x))
    }
}

@MainActor
private struct XYOpener2<X: Plottable>: PlottableOpener {
    let args: MarkArguments
    let x: PlottableValue<X>
    func open<Y: Plottable>(_ y: PlottableValue<Y>) -> AnyChartContent? {
        let spec = args.spec
        if spec.form == .xySeries {
            return openScalar(args.scalar("series"), args.plottable("series"), SeriesOpener(spec: spec, x: x, y: y))
        }
        switch spec.kind {
        case .BarMark:
            return AnyChartContent(erasing: Charts.BarMark(x: x, y: y, width: spec.width, height: spec.height, stacking: spec.stacking))
        case .LineMark:
            return AnyChartContent(erasing: Charts.LineMark(x: x, y: y))
        case .PointMark:
            return AnyChartContent(erasing: Charts.PointMark(x: x, y: y))
        case .AreaMark:
            return AnyChartContent(erasing: Charts.AreaMark(x: x, y: y, stacking: spec.stacking))
        case .RectangleMark:
            return AnyChartContent(erasing: Charts.RectangleMark(x: x, y: y, width: spec.width, height: spec.height))
        case .RuleMark, .SectorMark:
            return nil
        }
    }
}

@MainActor
private struct SeriesOpener<X: Plottable, Y: Plottable>: PlottableOpener {
    let spec: ChartMarkSpec
    let x: PlottableValue<X>
    let y: PlottableValue<Y>
    func open<S: Plottable>(_ series: PlottableValue<S>) -> AnyChartContent? {
        switch spec.kind {
        case .LineMark:
            return AnyChartContent(erasing: Charts.LineMark(x: x, y: y, series: series))
        case .AreaMark:
            return AnyChartContent(erasing: Charts.AreaMark(x: x, y: y, series: series, stacking: spec.stacking))
        default:
            return nil
        }
    }
}

// SectorMark: the angle with its radii and inset.
@MainActor
private struct SectorOpener: PlottableOpener {
    let args: MarkArguments
    func open<A: Plottable>(_ angle: PlottableValue<A>) -> AnyChartContent? {
        let spec = args.spec
        return AnyChartContent(erasing: Charts.SectorMark(angle: angle, innerRadius: spec.innerRadius, outerRadius: spec.outerRadius,
                                                          angularInset: args.point("angularInset")))
    }
}

// One plottable value with optional points on the other axis.
@MainActor
private struct SingleOpener: PlottableOpener {
    let args: MarkArguments
    func open<P: Plottable>(_ value: PlottableValue<P>) -> AnyChartContent? {
        let spec = args.spec
        switch (spec.form, spec.kind) {
        case (.xPoints, .BarMark):
            return AnyChartContent(erasing: Charts.BarMark(x: value, yStart: args.point("yStart"), yEnd: args.point("yEnd"),
                                                           width: spec.width, stacking: spec.stacking))
        case (.xPoints, .RuleMark):
            return AnyChartContent(erasing: Charts.RuleMark(x: value, yStart: args.point("yStart"), yEnd: args.point("yEnd")))
        case (.xPoints, .PointMark):
            return AnyChartContent(erasing: Charts.PointMark(x: value, y: args.point("y")))
        case (.xPoints, .RectangleMark):
            return AnyChartContent(erasing: Charts.RectangleMark(x: value, yStart: args.point("yStart"), yEnd: args.point("yEnd"),
                                                                 width: spec.width))
        case (.yPoints, .RectangleMark):
            return AnyChartContent(erasing: Charts.RectangleMark(xStart: args.point("xStart"), xEnd: args.point("xEnd"), y: value,
                                                                 height: spec.height))
        case (.yPoints, .BarMark):
            return AnyChartContent(erasing: Charts.BarMark(xStart: args.point("xStart"), xEnd: args.point("xEnd"), y: value,
                                                           height: spec.height, stacking: spec.stacking))
        case (.yPoints, .RuleMark):
            return AnyChartContent(erasing: Charts.RuleMark(xStart: args.point("xStart"), xEnd: args.point("xEnd"), y: value))
        case (.yPoints, .PointMark):
            return AnyChartContent(erasing: Charts.PointMark(x: args.point("x"), y: value))
        default:
            return nil
        }
    }
}

// x + yStart/yEnd pair.
@MainActor
private struct XPairOpener: PlottableOpener {
    let args: MarkArguments
    func open<X: Plottable>(_ x: PlottableValue<X>) -> AnyChartContent? {
        openScalarPair(args.scalar("yStart"), args.plottable("yStart"), args.scalar("yEnd"), args.plottable("yEnd"),
                                            XPairOpener2(args: args, x: x))
    }
}

@MainActor
private struct XPairOpener2<X: Plottable>: PairOpener {
    let args: MarkArguments
    let x: PlottableValue<X>
    func open<Y: Plottable>(_ yStart: PlottableValue<Y>, _ yEnd: PlottableValue<Y>) -> AnyChartContent? {
        if args.spec.form == .xPairSeries {
            return openScalar(args.scalar("series"), args.plottable("series"), XPairSeriesOpener(x: x, yStart: yStart, yEnd: yEnd))
        }
        switch args.spec.kind {
        case .BarMark:
            return AnyChartContent(erasing: Charts.BarMark(x: x, yStart: yStart, yEnd: yEnd, width: args.spec.width))
        case .RuleMark:
            return AnyChartContent(erasing: Charts.RuleMark(x: x, yStart: yStart, yEnd: yEnd))
        case .AreaMark:
            return AnyChartContent(erasing: Charts.AreaMark(x: x, yStart: yStart, yEnd: yEnd))
        case .RectangleMark:
            return AnyChartContent(erasing: Charts.RectangleMark(x: x, yStart: yStart, yEnd: yEnd, width: args.spec.width))
        default:
            return nil
        }
    }
}

// AreaMark x + yStart/yEnd + series.
@MainActor
private struct XPairSeriesOpener<X: Plottable, Y: Plottable>: PlottableOpener {
    let x: PlottableValue<X>
    let yStart: PlottableValue<Y>
    let yEnd: PlottableValue<Y>
    func open<S: Plottable>(_ series: PlottableValue<S>) -> AnyChartContent? {
        AnyChartContent(erasing: Charts.AreaMark(x: x, yStart: yStart, yEnd: yEnd, series: series))
    }
}

// xStart/xEnd pair + y.
@MainActor
private struct PairYOpener: PairOpener {
    let args: MarkArguments
    func open<X: Plottable>(_ xStart: PlottableValue<X>, _ xEnd: PlottableValue<X>) -> AnyChartContent? {
        openScalar(args.scalar("y"), args.plottable("y"), PairYOpener2(args: args, xStart: xStart, xEnd: xEnd))
    }
}

@MainActor
private struct PairYOpener2<X: Plottable>: PlottableOpener {
    let args: MarkArguments
    let xStart: PlottableValue<X>
    let xEnd: PlottableValue<X>
    func open<Y: Plottable>(_ y: PlottableValue<Y>) -> AnyChartContent? {
        if args.spec.form == .pairYSeries {
            return openScalar(args.scalar("series"), args.plottable("series"), PairYSeriesOpener(xStart: xStart, xEnd: xEnd, y: y))
        }
        switch args.spec.kind {
        case .BarMark:
            return AnyChartContent(erasing: Charts.BarMark(xStart: xStart, xEnd: xEnd, y: y, height: args.spec.height))
        case .RuleMark:
            return AnyChartContent(erasing: Charts.RuleMark(xStart: xStart, xEnd: xEnd, y: y))
        case .AreaMark:
            return AnyChartContent(erasing: Charts.AreaMark(xStart: xStart, xEnd: xEnd, y: y))
        case .RectangleMark:
            return AnyChartContent(erasing: Charts.RectangleMark(xStart: xStart, xEnd: xEnd, y: y, height: args.spec.height))
        default:
            return nil
        }
    }
}

// AreaMark xStart/xEnd + y + series.
@MainActor
private struct PairYSeriesOpener<X: Plottable, Y: Plottable>: PlottableOpener {
    let xStart: PlottableValue<X>
    let xEnd: PlottableValue<X>
    let y: PlottableValue<Y>
    func open<S: Plottable>(_ series: PlottableValue<S>) -> AnyChartContent? {
        AnyChartContent(erasing: Charts.AreaMark(xStart: xStart, xEnd: xEnd, y: y, series: series))
    }
}

// RectangleMark xStart/xEnd + yStart/yEnd.
@MainActor
private struct PairPairOpener: PairOpener {
    let args: MarkArguments
    func open<X: Plottable>(_ xStart: PlottableValue<X>, _ xEnd: PlottableValue<X>) -> AnyChartContent? {
        openScalarPair(args.scalar("yStart"), args.plottable("yStart"), args.scalar("yEnd"), args.plottable("yEnd"),
                       PairPairOpener2(xStart: xStart, xEnd: xEnd))
    }
}

@MainActor
private struct PairPairOpener2<X: Plottable>: PairOpener {
    let xStart: PlottableValue<X>
    let xEnd: PlottableValue<X>
    func open<Y: Plottable>(_ yStart: PlottableValue<Y>, _ yEnd: PlottableValue<Y>) -> AnyChartContent? {
        AnyChartContent(erasing: Charts.RectangleMark(xStart: xStart, xEnd: xEnd, yStart: yStart, yEnd: yEnd))
    }
}

// A pair with optional points on the other axis.
@MainActor
private struct PairPointsOpener: PairOpener {
    let args: MarkArguments
    func open<P: Plottable>(_ start: PlottableValue<P>, _ end: PlottableValue<P>) -> AnyChartContent? {
        switch (args.spec.form, args.spec.kind) {
        case (.pointsPair, .BarMark):
            return AnyChartContent(erasing: Charts.BarMark(xStart: args.point("xStart"), xEnd: args.point("xEnd"), yStart: start, yEnd: end))
        case (.pointsPair, .RuleMark):
            return AnyChartContent(erasing: Charts.RuleMark(x: args.point("x"), yStart: start, yEnd: end))
        case (.pairPoints, .BarMark):
            return AnyChartContent(erasing: Charts.BarMark(xStart: start, xEnd: end, yStart: args.point("yStart"), yEnd: args.point("yEnd")))
        case (.pairPoints, .RuleMark):
            return AnyChartContent(erasing: Charts.RuleMark(xStart: start, xEnd: end, y: args.point("y")))
        case (.pointsPair, .RectangleMark):
            return AnyChartContent(erasing: Charts.RectangleMark(xStart: args.point("xStart"), xEnd: args.point("xEnd"), yStart: start, yEnd: end))
        case (.pairPoints, .RectangleMark):
            return AnyChartContent(erasing: Charts.RectangleMark(xStart: start, xEnd: end, yStart: args.point("yStart"), yEnd: args.point("yEnd")))
        default:
            return nil
        }
    }
}

// Modifiers that take a plottable value are applied after erasure, each re-erasing.
@MainActor
private struct ByModifierOpener: PlottableOpener {
    let content: AnyChartContent
    let modifier: ChartMarkModifier
    func open<P: Plottable>(_ value: PlottableValue<P>) -> AnyChartContent? {
        switch modifier {
        case .foregroundStyleBy:
            return AnyChartContent(erasing: content.foregroundStyle(by: value))
        case .symbolBy:
            return AnyChartContent(erasing: content.symbol(by: value))
        case .symbolSizeBy:
            return AnyChartContent(erasing: content.symbolSize(by: value))
        case .lineStyleBy:
            return AnyChartContent(erasing: content.lineStyle(by: value))
        case .position(_, let axis, let span):
            return AnyChartContent(erasing: content.position(by: value, axis: axis, span: span))
        default:
            return content
        }
    }
}

// MARK: - Builder

@MainActor
struct ChartContentBuilder {
    // The rows being drawn: the chart's, or a ForEach's own data while that ForEach is built.
    private(set) var columns: ChartTypedColumns
    private var drawingInlineData = false
    // Rows with a cell that did not parse, and the first such (row, column) for the warning;
    // `inlineData` when the row is in a ForEach's own data.
    private(set) var skippedRows = 0
    private(set) var firstSkip: (row: Int, column: Int, type: ChartColumnType, inlineData: Bool)?
    // The range of the numbers or dates (as seconds since the reference date) the marks plot on
    // each axis, for the axis stride limit.
    private(set) var xExtent: ClosedRange<Double>?
    private(set) var yExtent: ClosedRange<Double>?
    // The selection that "$selection" values read; marks reading an empty one are not drawn.
    var selection = ChartSelection()
    // Whether to record the categories each axis plots (xCategories, yCategories), for drawing
    // selection marks only at values the chart shows.
    var collectsCategories = false
    private(set) var xCategories: Set<String> = []
    private(set) var yCategories: Set<String> = []
    // Each drawn sector's angle value, in drawing order, with its row (nil outside a ForEach),
    // to find the row an angle selection falls in.
    private(set) var sectorAngles: [(row: Int?, value: Double)] = []
    // Where annotation views are built: the chart's id (the viewID of their actions) and window.
    var viewID = 0
    var windowUUID = ""
    var logger: any ActionUILogger = SilentChartLogger.shared
    // False draws the marks without their annotations (ChartRenderCache.maxAnnotations).
    var drawsAnnotations = true

    private static func widen(_ extent: ClosedRange<Double>?, _ scalar: ChartScalar) -> ClosedRange<Double>? {
        let value: Double
        switch scalar {
        case .number(let number): value = number
        case .integer(let integer): value = Double(integer)
        case .date(let date): value = date.timeIntervalSinceReferenceDate
        case .string: return extent
        }
        // A "nan" or "inf" cell parses as a number; NaN...NaN would stop the app, and Swift
        // Charts draws neither value.
        guard value.isFinite else { return extent }
        guard let extent else { return value...value }
        return min(extent.lowerBound, value)...max(extent.upperBound, value)
    }

    init(columns: ChartTypedColumns) {
        self.columns = columns
    }

    mutating func build(_ entries: [ChartEntry]) -> [AnyChartContent] {
        var output: [AnyChartContent] = []
        for entry in entries {
            append(entry, row: nil, into: &output)
        }
        return output
    }

    private mutating func append(_ entry: ChartEntry, row: Int?, into output: inout [AnyChartContent]) {
        switch entry {
        case .mark(let spec):
            if let content = buildMark(spec, row: row) {
                output.append(content)
            }
        case .plot(let children):
            for child in children {
                append(child, row: row, into: &output)
            }
        case .forEach(let children, let data):
            if let data {
                let chartRows = columns
                columns = ChartTypedColumns(rows: data, refs: ChartSpec.referencedColumns(in: children))
                drawingInlineData = true
                defer {
                    columns = chartRows
                    drawingInlineData = false
                }
                append(.forEach(children, data: nil), row: row, into: &output)
                return
            }
            // A row is drawn whole or not at all: one unparsable cell skips all its marks.
            // A ForEach holds marks and Plots of marks (the description parser refuses a nested ForEach).
            output.reserveCapacity(output.count + columns.rowCount * children.count)
            var rowItems: [AnyChartContent] = []
            for rowIndex in 0..<columns.rowCount {
                rowItems.removeAll(keepingCapacity: true)
                if appendRow(children, row: rowIndex, into: &rowItems) {
                    output.append(contentsOf: rowItems)
                } else {
                    skippedRows += 1
                }
            }
        }
    }

    // Builds one row's marks; false as soon as one cannot be built.
    private mutating func appendRow(_ entries: [ChartEntry], row: Int, into items: inout [AnyChartContent]) -> Bool {
        for entry in entries {
            switch entry {
            case .mark(let spec):
                guard let content = buildMark(spec, row: row) else { return false }
                items.append(content)
            case .plot(let children):
                guard appendRow(children, row: row, into: &items) else { return false }
            case .forEach:
                return false
            }
        }
        return true
    }

    private mutating func resolve(_ plottable: ChartPlottable, row: Int?, key: String = "") -> ChartScalar? {
        switch plottable.source {
        case .literal(let scalar):
            return scalar
        case .selection(let axis):
            switch axis == .horizontal ? selection.x : selection.y {
            case .value(let scalar)?:
                return scalar
            case .range(let start, let end)?:
                return key.hasSuffix("Start") ? start : key.hasSuffix("End") ? end : nil
            case nil:
                return nil
            }
        case .column(let index):
            guard let row else { return nil }
            let value = columns.scalar(row: row, ref: ChartColumnRef(index: index, type: plottable.type))
            if value == nil, firstSkip == nil {
                firstSkip = (row, index, plottable.type, drawingInlineData)
            }
            return value
        }
    }

    private mutating func buildMark(_ spec: ChartMarkSpec, row: Int?) -> AnyChartContent? {
        var scalars: [String: ChartScalar] = [:]
        for (key, plottable) in spec.values {
            guard let scalar = resolve(plottable, row: row, key: key) else { return nil }
            scalars[key] = scalar
        }
        // A normalized stack spans 0...1 on its stacked axis whatever the values: the numeric x
        // axis when y is not numeric (or the x-only bar form), else the y axis.
        var normalizedAxis: Axis?
        if spec.stacking == .normalized, spec.kind == .BarMark || spec.kind == .AreaMark {
            let numeric: (String) -> Bool = { key in
                switch scalars[key] {
                case .number?, .integer?: return true
                default: return false
                }
            }
            normalizedAxis = spec.form == .xPoints || (numeric("x") && !numeric("y")) ? .horizontal : .vertical
            if normalizedAxis == .horizontal { xExtent = Self.widen(Self.widen(xExtent, .number(0)), .number(1)) }
            else { yExtent = Self.widen(Self.widen(yExtent, .number(0)), .number(1)) }
        }
        for (key, scalar) in scalars {
            switch key {
            case "x", "xStart", "xEnd":
                if normalizedAxis != .horizontal { xExtent = Self.widen(xExtent, scalar) }
                if collectsCategories, case .string(let category) = scalar { xCategories.insert(category) }
            case "y", "yStart", "yEnd":
                if normalizedAxis != .vertical { yExtent = Self.widen(yExtent, scalar) }
                if collectsCategories, case .string(let category) = scalar { yCategories.insert(category) }
            default: break
            }
        }
        let args = MarkArguments(spec: spec, scalars: scalars)
        let built: AnyChartContent?
        switch spec.form {
        case .xy, .xySeries:
            built = openScalar(args.scalar("x"), args.plottable("x"), XYOpener(args: args))
        case .xPoints:
            built = openScalar(args.scalar("x"), args.plottable("x"), SingleOpener(args: args))
        case .yPoints:
            built = openScalar(args.scalar("y"), args.plottable("y"), SingleOpener(args: args))
        case .xPair:
            built = openScalar(args.scalar("x"), args.plottable("x"), XPairOpener(args: args))
        case .pairY:
            built = openScalarPair(args.scalar("xStart"), args.plottable("xStart"),
                                                        args.scalar("xEnd"), args.plottable("xEnd"), PairYOpener(args: args))
        case .pointsPair:
            built = openScalarPair(args.scalar("yStart"), args.plottable("yStart"),
                                                        args.scalar("yEnd"), args.plottable("yEnd"), PairPointsOpener(args: args))
        case .pairPoints:
            built = openScalarPair(args.scalar("xStart"), args.plottable("xStart"),
                                                        args.scalar("xEnd"), args.plottable("xEnd"), PairPointsOpener(args: args))
        case .xPairSeries:
            built = openScalar(args.scalar("x"), args.plottable("x"), XPairOpener(args: args))
        case .pairYSeries:
            built = openScalarPair(args.scalar("xStart"), args.plottable("xStart"),
                                   args.scalar("xEnd"), args.plottable("xEnd"), PairYOpener(args: args))
        case .pairPair:
            built = openScalarPair(args.scalar("xStart"), args.plottable("xStart"),
                                   args.scalar("xEnd"), args.plottable("xEnd"), PairPairOpener(args: args))
        case .pointsOnly:
            built = AnyChartContent(erasing: Charts.RectangleMark(xStart: args.point("xStart"), xEnd: args.point("xEnd"),
                                                                  yStart: args.point("yStart"), yEnd: args.point("yEnd")))
        case .angle:
            built = openScalar(args.scalar("angle"), args.plottable("angle"), SectorOpener(args: args))
        }
        guard var content = built else { return nil }
        for modifier in spec.modifiers {
            guard let modified = apply(modifier, to: content, row: row) else { return nil }
            content = modified
        }
        if spec.kind == .SectorMark {
            switch scalars["angle"] {
            case .number(let value)?: sectorAngles.append((row, value))
            case .integer(let value)?: sectorAngles.append((row, Double(value)))
            default: break
            }
        }
        return content
    }

    private mutating func apply(_ modifier: ChartMarkModifier, to content: AnyChartContent, row: Int?) -> AnyChartContent? {
        if let plottable = modifier.plottable {
            guard let scalar = resolve(plottable, row: row) else { return nil }
            return openScalar(scalar, plottable, ByModifierOpener(content: content, modifier: modifier))
        }
        switch modifier {
        case .foregroundStyle(let color):
            return AnyChartContent(erasing: content.foregroundStyle(color))
        case .symbol(let shape):
            return AnyChartContent(erasing: content.symbol(shape))
        case .symbolArea(let area):
            return AnyChartContent(erasing: content.symbolSize(area))
        case .symbolSize(let size):
            return AnyChartContent(erasing: content.symbolSize(size))
        case .lineStyle(let style):
            return AnyChartContent(erasing: content.lineStyle(style))
        case .interpolationMethod(let method):
            return AnyChartContent(erasing: content.interpolationMethod(method))
        case .cornerRadius(let radius, let style):
            return AnyChartContent(erasing: content.cornerRadius(radius, style: style))
        case .opacity(let value):
            return AnyChartContent(erasing: content.opacity(value))
        case .zIndex(let value):
            return AnyChartContent(erasing: content.zIndex(value))
        case .offset(let offset):
            switch offset {
            case .xy(let x, let y):
                return AnyChartContent(erasing: content.offset(x: x, y: y))
            case .xYRange(let x, let yStart, let yEnd):
                return AnyChartContent(erasing: content.offset(x: x, yStart: yStart, yEnd: yEnd))
            case .xRangeY(let xStart, let xEnd, let y):
                return AnyChartContent(erasing: content.offset(xStart: xStart, xEnd: xEnd, y: y))
            case .ranges(let xStart, let xEnd, let yStart, let yEnd):
                return AnyChartContent(erasing: content.offset(xStart: xStart, xEnd: xEnd, yStart: yStart, yEnd: yEnd))
            }
        case .blur(let radius):
            return AnyChartContent(erasing: content.blur(radius: radius))
        case .shadow(let color, let radius, let x, let y):
            if let color {
                return AnyChartContent(erasing: content.shadow(color: color, radius: radius, x: x, y: y))
            }
            return AnyChartContent(erasing: content.shadow(radius: radius, x: x, y: y))
        case .alignsMarkStylesWithPlotArea(let aligns):
            return AnyChartContent(erasing: content.alignsMarkStylesWithPlotArea(aligns))
        case .accessibilityLabel(let text):
            return AnyChartContent(erasing: content.accessibilityLabel(resolve(text, row: row)))
        case .accessibilityValue(let text):
            return AnyChartContent(erasing: content.accessibilityValue(resolve(text, row: row)))
        case .accessibilityIdentifier(let text):
            return AnyChartContent(erasing: content.accessibilityIdentifier(resolve(text, row: row)))
        case .accessibilityHidden(let hidden):
            return AnyChartContent(erasing: content.accessibilityHidden(hidden))
        case .annotation(let annotation):
            guard drawsAnnotations else { return content }
            // A template row's instance: the row (empty outside a ForEach) substituted, and its
            // actions carrying the chart's id and the row's index (-1 outside a ForEach).
            let read = annotation.readsRows ? row : nil
            let view = TemplateHelper.buildTemplateView(template: annotation.content, row: read.map { columns.rows[$0] } ?? [],
                                                        rowIndex: read ?? -1, parentID: viewID, windowUUID: windowUUID,
                                                        logger: logger)
            return AnyChartContent(erasing: content.annotation(position: annotation.position, alignment: annotation.alignment,
                                                               spacing: annotation.spacing,
                                                               overflowResolution: annotation.overflow) { view })
        case .foregroundStyleBy, .symbolBy, .symbolSizeBy, .lineStyleBy, .position:
            return content // handled above
        }
    }

    private func resolve(_ text: ChartText, row: Int?) -> String {
        switch text {
        case .literal(let string):
            return string
        case .perRow(let template):
            guard let row else { return template }
            return TemplateHelper.substituteString(template, row: columns.rows[row])
        }
    }
}
