// Helpers/ChartContentBuilder.swift
//
// Builds a Chart's marks from its ChartSpec and rows. Mark initializers are generic over
// Plottable with each argument's type fixed at the call site, so every plottable value is
// "opened" into a typed PlottableValue by a switch over its scalar type, nested once per
// argument, and the finished mark is type-erased to AnyChartContent. The marks form one flat
// list that the chart emits through a single ForEach; erased marks render pixel-identically to
// typed ones (series join, stacking), and faster.

import Foundation
import SwiftUI
import Charts

// Rows parsed once per (column, type) pair. A nil cell is missing or did not parse.
struct ChartTypedColumns {
    let rowCount: Int
    private let cells: [ChartColumnRef: [ChartScalar?]]

    init(rows: [[String]], refs: [ChartColumnRef]) {
        rowCount = rows.count
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

@MainActor
private protocol PlottableOpener {
    func open<P: Plottable>(_ value: PlottableValue<P>) -> AnyChartContent
}

// Opens one scalar into a typed PlottableValue and hands it to `next`.
@MainActor
private func withPlottable(_ scalar: ChartScalar, _ plottable: ChartPlottable, _ next: some PlottableOpener) -> AnyChartContent {
    switch scalar {
    case .string(let value):
        return next.open(.value(plottable.label, value))
    case .number(let value):
        return next.open(.value(plottable.label, value))
    case .integer(let value):
        return next.open(.value(plottable.label, value))
    case .date(let value):
        if let unit = plottable.unit {
            return next.open(.value(plottable.label, value, unit: unit))
        }
        return next.open(.value(plottable.label, value))
    }
}

// x+y marks: open x, then y inside, then the initializer with both concrete types.
@MainActor
private struct XOpener: PlottableOpener {
    let kind: ChartMarkKind
    let y: ChartScalar
    let yPlottable: ChartPlottable

    func open<X: Plottable>(_ x: PlottableValue<X>) -> AnyChartContent {
        withPlottable(y, yPlottable, YOpener(kind: kind, x: x))
    }
}

@MainActor
private struct YOpener<X: Plottable>: PlottableOpener {
    let kind: ChartMarkKind
    let x: PlottableValue<X>

    func open<Y: Plottable>(_ y: PlottableValue<Y>) -> AnyChartContent {
        switch kind {
        case .BarMark:
            return AnyChartContent(erasing: Charts.BarMark(x: x, y: y))
        case .LineMark:
            return AnyChartContent(erasing: Charts.LineMark(x: x, y: y))
        }
    }
}

@MainActor
private struct ForegroundByOpener: PlottableOpener {
    let content: AnyChartContent
    func open<P: Plottable>(_ value: PlottableValue<P>) -> AnyChartContent {
        AnyChartContent(erasing: content.foregroundStyle(by: value))
    }
}

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
        guard let x = resolve(spec.x, row: row), let y = resolve(spec.y, row: row) else { return nil }
        var content = withPlottable(x, spec.x, XOpener(kind: spec.kind, y: y, yPlottable: spec.y))
        if let by = spec.foregroundBy {
            guard let scalar = resolve(by, row: row) else { return nil }
            content = withPlottable(scalar, by, ForegroundByOpener(content: content))
        }
        if let color = spec.foregroundColor {
            content = AnyChartContent(erasing: content.foregroundStyle(color))
        }
        return content
    }
}
