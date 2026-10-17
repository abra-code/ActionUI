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

// Opens a start/end pair as one type. Validation makes both plottables the same type, so both
// scalars have the same case.
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

// x + y (BarMark, LineMark, PointMark) and x + y + series (LineMark).
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
            return openScalar(args.scalar("series"), args.plottable("series"), SeriesOpener(x: x, y: y))
        }
        switch spec.kind {
        case .BarMark:
            return AnyChartContent(erasing: Charts.BarMark(x: x, y: y, width: spec.width, height: spec.height, stacking: spec.stacking))
        case .LineMark:
            return AnyChartContent(erasing: Charts.LineMark(x: x, y: y))
        case .PointMark:
            return AnyChartContent(erasing: Charts.PointMark(x: x, y: y))
        case .RuleMark:
            return nil
        }
    }
}

@MainActor
private struct SeriesOpener<X: Plottable, Y: Plottable>: PlottableOpener {
    let x: PlottableValue<X>
    let y: PlottableValue<Y>
    func open<S: Plottable>(_ series: PlottableValue<S>) -> AnyChartContent? {
        AnyChartContent(erasing: Charts.LineMark(x: x, y: y, series: series))
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
        switch args.spec.kind {
        case .BarMark:
            return AnyChartContent(erasing: Charts.BarMark(x: x, yStart: yStart, yEnd: yEnd, width: args.spec.width))
        case .RuleMark:
            return AnyChartContent(erasing: Charts.RuleMark(x: x, yStart: yStart, yEnd: yEnd))
        default:
            return nil
        }
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
        switch args.spec.kind {
        case .BarMark:
            return AnyChartContent(erasing: Charts.BarMark(xStart: xStart, xEnd: xEnd, y: y, height: args.spec.height))
        case .RuleMark:
            return AnyChartContent(erasing: Charts.RuleMark(xStart: xStart, xEnd: xEnd, y: y))
        default:
            return nil
        }
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
    let columns: ChartTypedColumns
    // Rows with a cell that did not parse, and the first such (row, column) for the warning.
    private(set) var skippedRows = 0
    private(set) var firstSkip: (row: Int, column: Int, type: ChartColumnType)?

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
        case .forEach(let children):
            // A row is drawn whole or not at all: one unparsable cell skips all its marks.
            // A ForEach holds only marks (validation refuses a nested ForEach).
            output.reserveCapacity(output.count + columns.rowCount * children.count)
            var rowItems: [AnyChartContent] = []
            for rowIndex in 0..<columns.rowCount {
                rowItems.removeAll(keepingCapacity: true)
                for child in children {
                    guard case .mark(let spec) = child, let content = buildMark(spec, row: rowIndex) else { break }
                    rowItems.append(content)
                }
                if rowItems.count == children.count {
                    output.append(contentsOf: rowItems)
                } else {
                    skippedRows += 1
                }
            }
        }
    }

    private mutating func resolve(_ plottable: ChartPlottable, row: Int?) -> ChartScalar? {
        switch plottable.source {
        case .literal(let scalar):
            return scalar
        case .column(let index):
            guard let row else { return nil }
            let value = columns.scalar(row: row, ref: ChartColumnRef(index: index, type: plottable.type))
            if value == nil, firstSkip == nil {
                firstSkip = (row, index, plottable.type)
            }
            return value
        }
    }

    private mutating func buildMark(_ spec: ChartMarkSpec, row: Int?) -> AnyChartContent? {
        var scalars: [String: ChartScalar] = [:]
        for (key, plottable) in spec.values {
            guard let scalar = resolve(plottable, row: row) else { return nil }
            scalars[key] = scalar
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
        }
        guard var content = built else { return nil }
        for modifier in spec.modifiers {
            guard let modified = apply(modifier, to: content, row: row) else { return nil }
            content = modified
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
