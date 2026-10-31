// Sources/Drawing/ChartMarkInstances.swift
/*
 What a chart's entries come to over its rows: one instance per drawn mark, with its plotted values
 read, following Apple's ChartContentBuilder. A mark in a ForEach is drawn once per row, a ForEach
 with its own data over those rows, and a row with a cell that does not parse is skipped whole. A
 mark that reads the selection ("$selection") is not drawn: Linux has no chart selection yet.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct ChartMarkInstance {
    let mark: ChartMarkSpec
    /// Plotted values by initializer label (x, y, xStart, ...).
    let values: [String: ChartScalar]
    /// The series a {"by"} foreground style puts it in, unless a style nearer the mark sets its color.
    let styleKey: String?
    /// The same for a {"by"} symbol and line style.
    let symbolKey: String?
    let lineStyleKey: String?
    /// What joins it to other lines or areas: its series and the {"by"} styles it wears: of color,
    /// line and symbol on a line, of color alone on an area. Marks that share this are one line, in
    /// the style of the first. A {"by"} that a style nearer the mark replaces, a symbol's size and a
    /// position do not split a line (measured on macOS 27).
    let seriesKey: String
}

struct ChartResolvedMarks {
    var instances: [ChartMarkInstance] = []
    /// Rows with a cell that did not parse, and the first such cell.
    var skippedRows = 0
    var firstSkip: (row: Int, column: Int, type: ChartColumnType, inlineData: Bool)?
}

struct ChartMarkResolver {
    private var columns: ChartTypedColumns
    private var inlineData = false
    private var result = ChartResolvedMarks()

    static func resolve(_ spec: ChartSpec, rows: [[String]]) -> ChartResolvedMarks {
        var resolver = ChartMarkResolver(columns: ChartTypedColumns(rows: rows, refs: spec.referencedColumns))
        resolver.append(spec.content)
        return resolver.result
    }

    private init(columns: ChartTypedColumns) {
        self.columns = columns
    }

    private mutating func append(_ entries: [ChartEntry]) {
        for entry in entries {
            switch entry {
            case .mark(let mark):
                if let instance = instance(mark, row: nil) {
                    result.instances.append(instance)
                }
            case .plot(let children):
                append(children)
            case .forEach(let children, let data):
                let chartRows = columns
                if let data {
                    columns = ChartTypedColumns(rows: data, refs: ChartSpec.referencedColumns(in: children))
                    inlineData = true
                }
                appendRows(children)
                columns = chartRows
                inlineData = false
            }
        }
    }

    private mutating func appendRows(_ entries: [ChartEntry]) {
        var rowInstances: [ChartMarkInstance] = []
        for row in 0..<columns.rowCount {
            rowInstances.removeAll(keepingCapacity: true)
            if appendRow(entries, row: row, into: &rowInstances) {
                result.instances.append(contentsOf: rowInstances)
            } else {
                result.skippedRows += 1
            }
        }
    }

    // One row's marks; false as soon as one cannot be read.
    private mutating func appendRow(_ entries: [ChartEntry], row: Int, into instances: inout [ChartMarkInstance]) -> Bool {
        for entry in entries {
            switch entry {
            case .mark(let mark):
                guard let instance = instance(mark, row: row) else { return false }
                instances.append(instance)
            case .plot(let children):
                guard appendRow(children, row: row, into: &instances) else { return false }
            case .forEach:
                return false
            }
        }
        return true
    }

    private mutating func read(_ plottable: ChartPlottable, row: Int?) -> ChartScalar? {
        switch plottable.source {
        case .literal(let scalar):
            return scalar
        case .selection:
            return nil
        case .column(let index):
            guard let row else { return nil }
            let value = columns.scalar(row: row, ref: ChartColumnRef(index: index, type: plottable.type))
            if value == nil, result.firstSkip == nil {
                result.firstSkip = (row, index, plottable.type, inlineData)
            }
            return value
        }
    }

    private mutating func instance(_ mark: ChartMarkSpec, row: Int?) -> ChartMarkInstance? {
        var values: [String: ChartScalar] = [:]
        for (key, plottable) in mark.values {
            guard let scalar = read(plottable, row: row) else { return nil }
            values[key] = scalar
        }
        var styleKey: String?
        var symbolKey: String?
        var lineStyleKey: String?
        var seriesParts = values["series"].map { [Self.key($0)] } ?? [""]
        // The mark's own modifiers come first, a Plot's after them, and the first of each kind wins.
        var styled = false, lined = false, marked = false
        for modifier in mark.modifiers {
            switch modifier {
            case .foregroundStyle: styled = true
            case .lineStyle: lined = true
            case .symbol: marked = true
            default: break
            }
            guard let plottable = modifier.plottable else { continue }
            guard let scalar = read(plottable, row: row) else { return nil }
            switch modifier {
            case .foregroundStyleBy where !styled:
                styleKey = Self.key(scalar)
                seriesParts.append(Self.key(scalar))
                styled = true
            case .lineStyleBy where !lined:
                lineStyleKey = Self.key(scalar)
                if mark.kind != .AreaMark { seriesParts.append(Self.key(scalar)) }
                lined = true
            case .symbolBy where !marked:
                symbolKey = Self.key(scalar)
                if mark.kind != .AreaMark { seriesParts.append(Self.key(scalar)) }
                marked = true
            default:
                break
            }
        }
        return ChartMarkInstance(mark: mark, values: values, styleKey: styleKey, symbolKey: symbolKey, lineStyleKey: lineStyleKey,
                                 seriesKey: seriesParts.joined(separator: "\u{1F}"))
    }

    private static func key(_ scalar: ChartScalar) -> String {
        switch scalar {
        case .string(let text): return text
        case .number(let number): return String(number)
        case .integer(let number): return String(number)
        case .date(let date): return String(date.timeIntervalSinceReferenceDate)
        }
    }
}
