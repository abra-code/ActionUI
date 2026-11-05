// Sources/Drawing/ChartMarkInstances.swift
/*
 What a chart's entries come to over its rows: one instance per drawn mark, with its plotted values
 read, following Apple's ChartContentBuilder. A mark in a ForEach is drawn once per row, a ForEach
 with its own data over those rows, and a row with a cell that does not parse is skipped whole.

 A mark that reads the selection ("$selection", outside a ForEach) is drawn only while there is a
 selection it can read, as on Apple: x, xStart and xEnd read the x selection's value, and xStart and
 xEnd a range's start and end (y likewise). A selected category that no other mark plots on that
 axis is not drawn, as it would add a category. Selection marks say nothing in the chart's
 accessible name, which would otherwise change as the pointer moves.
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
    /// The same for a {"by"} symbol, line style and symbol size.
    let symbolKey: String?
    let lineStyleKey: String?
    let sizeKey: String?
    /// Its accessibility label and value for this row, unless hidden or past what a name holds.
    let accessibleText: String?
    /// What a position scale groups it by, one key for a date bin however the dates in it differ,
    /// and the room the group shares. A number or date also has where it falls, a bin from start to end.
    let positionKey: String?
    let positionValue: (start: Double, end: Double)?
    let positionSpan: ChartDimension
    /// The key of the one axis a position can spread it over, with or without a position.
    let positionAxis: String?
    /// A {"by"} over numbers or dates has no series to name: where it falls on its scale instead.
    let colorValue: ChartScalar?
    let lineStyleValue: ChartScalar?
    let sizeValue: ChartScalar?
    /// What joins it to other lines or areas: its series, or without one the {"by"} styles it
    /// wears: of color, line and symbol on a line, of color alone on an area. Marks that share this
    /// are one line, in the style of the first. A {"by"} that a style nearer the mark replaces, a
    /// symbol's size and a position do not split a line (measured on macOS 27).
    let seriesKey: String
    /// The row it was read from (of a ForEach's own data when it has some); nil outside a ForEach.
    let row: Int?
    /// Whether one of its values reads the selection.
    let readsSelection: Bool
    /// The cells of its row, for an annotation that reads them ("$N"); empty when it has none.
    let annotationRow: [String]

    /// A name that takes a slot: a number or date falls along the room instead.
    var positionName: String? { positionValue == nil ? positionKey : nil }
}

struct ChartResolvedMarks {
    fileprivate static let namedMarks = 100

    var instances: [ChartMarkInstance] = []
    /// Rows with a cell that did not parse, and the first such cell.
    var skippedRows = 0
    var firstSkip: (row: Int, column: Int, type: ChartColumnType, inlineData: Bool)?
    /// The text of the first marks with any, which a name is made of; no more is worked out.
    fileprivate(set) var said: [String] = []

    /// What the marks say, as one name for the chart: GTK has no accessible object for a mark. Nil
    /// if none says anything, and a name stops at some marks, as a name is read out whole.
    var accessibleName: String? {
        said.isEmpty ? nil : said.joined(separator: "; ")
    }
}

struct ChartMarkResolver {
    private var columns: ChartTypedColumns
    private var inlineData = false
    private var result = ChartResolvedMarks()
    private let selection: ChartSelection

    static func resolve(_ spec: ChartSpec, rows: [[String]], selection: ChartSelection = ChartSelection()) -> ChartResolvedMarks {
        var resolver = ChartMarkResolver(columns: ChartTypedColumns(rows: rows, refs: spec.referencedColumns), selection: selection)
        resolver.append(spec.content)
        resolver.dropUnplottedSelections()
        return resolver.result
    }

    private init(columns: ChartTypedColumns, selection: ChartSelection) {
        self.columns = columns
        self.selection = selection
    }

    private static let xKeys: Set<String> = ["x", "xStart", "xEnd"]
    private static let yKeys: Set<String> = ["y", "yStart", "yEnd"]

    /// Drops a selection mark at a category that no other mark plots on its axis.
    private mutating func dropUnplottedSelections() {
        guard result.instances.contains(where: \.readsSelection) else { return }
        var categories = (x: Set<String>(), y: Set<String>())
        for instance in result.instances where !instance.readsSelection {
            for (key, value) in instance.values {
                guard case .string(let name) = value else { continue }
                if Self.xKeys.contains(key) { categories.x.insert(name) }
                if Self.yKeys.contains(key) { categories.y.insert(name) }
            }
        }
        result.instances.removeAll { instance in
            guard instance.readsSelection else { return false }
            return instance.mark.values.contains { key, plottable in
                guard case .selection = plottable.source, case .string(let name)? = instance.values[key] else { return false }
                return Self.xKeys.contains(key) ? !categories.x.contains(name) : !categories.y.contains(name)
            }
        }
    }

    private mutating func append(_ entries: [ChartEntry]) {
        for entry in entries {
            switch entry {
            case .mark(let mark):
                if let instance = instance(mark, row: nil) {
                    keep(instance)
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
                rowInstances.forEach { keep($0) }
            } else {
                result.skippedRows += 1
            }
        }
    }

    private mutating func keep(_ instance: ChartMarkInstance) {
        result.instances.append(instance)
        if !instance.readsSelection, let text = instance.accessibleText, result.said.count < ChartResolvedMarks.namedMarks {
            result.said.append(text)
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

    private mutating func read(_ plottable: ChartPlottable, row: Int?, key: String = "") -> ChartScalar? {
        switch plottable.source {
        case .literal(let scalar):
            return scalar
        case .selection(let axis):
            switch axis == .horizontal ? selection.x : selection.y {
            case .value(let value)?:
                return value
            case .range(let start, let end)?:
                return key.hasSuffix("Start") ? start : key.hasSuffix("End") ? end : nil
            case nil:
                return nil
            }
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
        var readsSelection = false
        for (key, plottable) in mark.values {
            guard let scalar = read(plottable, row: row, key: key) else { return nil }
            values[key] = scalar
            if case .selection = plottable.source { readsSelection = true }
        }
        var styleKey: String?
        var symbolKey: String?
        var lineStyleKey: String?
        var sizeKey: String?
        var positionKey: String?
        var positionValue: (start: Double, end: Double)?
        var positionSpan = ChartDimension.automatic
        let positionAxis = Self.positionAxis(values)
        var colorValue: ChartScalar?
        var lineStyleValue: ChartScalar?
        var sizeValue: ChartScalar?
        let series = values["series"]
        var seriesParts = series.map { [Self.key($0)] } ?? [""]
        // The mark's own modifiers come first, a Plot's after them, and the first of each kind wins.
        var styled = false, lined = false, marked = false, sized = false
        for modifier in mark.modifiers {
            switch modifier {
            case .foregroundStyle: styled = true
            case .lineStyle: lined = true
            case .symbol: marked = true
            case .symbolArea, .symbolSize: sized = true
            default: break
            }
            guard let plottable = modifier.plottable else { continue }
            guard let scalar = read(plottable, row: row) else { return nil }
            switch modifier {
            case .foregroundStyleBy where !styled:
                if case .string(let name) = scalar { styleKey = name } else { colorValue = scalar }
                if series == nil { seriesParts.append(Self.key(scalar)) }
                styled = true
            case .lineStyleBy where !lined:
                if case .string(let name) = scalar { lineStyleKey = name } else { lineStyleValue = scalar }
                if series == nil, mark.kind != .AreaMark { seriesParts.append(Self.key(scalar)) }
                lined = true
            case .symbolBy where !marked:
                if case .string(let name) = scalar { symbolKey = name }
                if series == nil, mark.kind != .AreaMark { seriesParts.append(Self.key(scalar)) }
                marked = true
            case .symbolSizeBy where !sized:
                if case .string(let name) = scalar { sizeKey = name } else { sizeValue = scalar }
                sized = true
            case .position(_, let axis, let span) where positionKey == nil && Self.spreads(axis, over: positionAxis):
                if case .string(let name) = scalar {
                    positionKey = name
                } else if let place = Self.positionPlace(scalar, unit: plottable.unit) {
                    (positionKey, positionValue) = (place.key, (place.start, place.end))
                } else {
                    continue
                }
                positionSpan = span
            default:
                break
            }
        }
        return ChartMarkInstance(mark: mark, values: values, styleKey: styleKey, symbolKey: symbolKey, lineStyleKey: lineStyleKey, sizeKey: sizeKey,
                                 accessibleText: result.said.count < ChartResolvedMarks.namedMarks ? accessibleText(mark, row: row) : nil,
                                 positionKey: positionKey, positionValue: positionValue, positionSpan: positionSpan, positionAxis: positionAxis,
                                 colorValue: colorValue, lineStyleValue: lineStyleValue, sizeValue: sizeValue,
                                 seriesKey: seriesParts.joined(separator: "\u{1F}"), row: row, readsSelection: readsSelection,
                                 annotationRow: annotationRow(mark, row: row))
    }

    /// The row's cells when one of the mark's annotations reads them.
    private func annotationRow(_ mark: ChartMarkSpec, row: Int?) -> [String] {
        guard let row, row < columns.rows.count else { return [] }
        let reads = mark.modifiers.contains { modifier in
            if case .annotation(let annotation) = modifier { return annotation.readsRows }
            return false
        }
        return reads ? columns.rows[row] : []
    }

    private func text(_ text: ChartText, row: Int?) -> String {
        switch text {
        case .literal(let string):
            return string
        case .perRow(let template):
            guard let row else { return template }
            return TemplateHelper.substituteString(template, row: columns.rows[row])
        }
    }

    // Backward, so the modifier nearest the mark is the one that stays.
    private func accessibleText(_ mark: ChartMarkSpec, row: Int?) -> String? {
        var label: ChartText?, value: ChartText?, hidden = false
        for modifier in mark.modifiers.reversed() {
            switch modifier {
            case .accessibilityLabel(let given): label = given
            case .accessibilityValue(let given): value = given
            case .accessibilityHidden(let given): hidden = given
            default: break
            }
        }
        guard !hidden, label != nil || value != nil else { return nil }
        let said = [label, value].compactMap { $0.map { text($0, row: row) } }.filter { !$0.isEmpty }
        return said.isEmpty ? nil : said.joined(separator: ", ")
    }

    // The one axis a position can spread a mark over, a start counting as its axis: x with bands or
    // dates, or y with them beside something on x, or x between two numbers. A mark on one axis
    // alone has none, unless that is x with bands or dates (measured on macOS 27).
    private static func positionAxis(_ values: [String: ChartScalar]) -> String? {
        func hasBands(_ scalar: ChartScalar?) -> Bool {
            switch scalar {
            case .string?, .date?: return true
            default: return false
            }
        }
        let x = values["x"] ?? values["xStart"], y = values["y"] ?? values["yStart"]
        if hasBands(x) { return "x" }
        if x == nil { return nil }
        if hasBands(y) { return "y" }
        return y == nil ? nil : "x"
    }

    // An axis named against the one a mark has changes nothing, and leaves a Plot's position to
    // apply (measured on macOS 27).
    private static func spreads(_ axis: ChartAxis?, over key: String?) -> Bool {
        switch axis {
        case .horizontal?: return key == "x"
        case .vertical?: return key == "y"
        case nil: return key != nil
        }
    }

    // A number, or a date at its bin, which ends where the bin does. Nil for one that is no number.
    private static func positionPlace(_ scalar: ChartScalar, unit: Calendar.Component?) -> (key: String, start: Double, end: Double)? {
        switch scalar {
        case .string:
            return nil
        case .number(let number):
            return number.isFinite ? (String(number), number, number) : nil
        case .integer(let number):
            return (String(Double(number)), Double(number), Double(number))
        case .date(let date):
            let bin = ChartDates.bin(date, unit)
            let start = bin.start.timeIntervalSinceReferenceDate
            return (String(start), start, bin.end.timeIntervalSinceReferenceDate)
        }
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
