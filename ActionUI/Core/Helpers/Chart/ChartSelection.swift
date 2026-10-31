// Core/Helpers/Chart/ChartSelection.swift
//
// Chart selection: what a description declares (chartXSelection, chartYSelection,
// chartAngleSelection), and the selection as the element's value (a JSON string).

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

enum ChartSelectionMode: String {
    case value, range
}

/// What a description declares, with the type of each selected axis.
struct ChartSelectionSpec: Equatable {
    /// The plotted value that reads the selection, outside a ForEach.
    static let reference = "$selection"

    var x: ChartSelectionMode?
    var y: ChartSelectionMode?
    var angle = false
    var xType: ChartColumnType?
    var yType: ChartColumnType?
    var angleType: ChartColumnType?
    // A date axis whose first mark has a unit of a day or coarser prints its selection as a
    // calendar day; any other date axis prints a local date and time, as DatePicker does.
    var xDateOnly = false
    var yDateOnly = false

    var isEmpty: Bool { x == nil && y == nil && !angle }
}

/// One axis's selection: a value, or a range for "range" mode.
enum ChartSelectionPart: Equatable {
    case value(ChartScalar)
    case range(ChartScalar, ChartScalar)
}

/// The selection a chart holds, decoded from and encoded to the element's JSON value.
struct ChartSelection: Equatable {
    var x: ChartSelectionPart?
    var y: ChartSelectionPart?
    var angle: Double?
    // The 0-based row of the selected sector; resolved when the user selects, kept as given when
    // a host sets the value.
    var row: Int?

    var isEmpty: Bool { x == nil && y == nil && angle == nil }

    /// Decodes `value` for `spec`. A part that does not fit the spec (no such selection
    /// declared, or a value of another type) is left out, so it reads as nothing selected.
    static func decode(_ value: String?, spec: ChartSelectionSpec) -> ChartSelection {
        var selection = ChartSelection()
        guard let value, !value.isEmpty, !spec.isEmpty,
              let object = (try? ActionUIJSON.value(from: value)) as? [String: Any] else {
            return selection
        }
        selection.x = part(object["x"], mode: spec.x, type: spec.xType)
        selection.y = part(object["y"], mode: spec.y, type: spec.yType)
        if spec.angle, let number = JSONNumber.plain(object["angle"]), number.isFinite {
            selection.angle = number
            if let row = JSONNumber.plain(object["row"]), let whole = Int(exactly: row), whole >= 0 {
                selection.row = whole
            }
        }
        return selection
    }

    /// The JSON value, keys sorted; "" when nothing is selected.
    func encode(spec: ChartSelectionSpec) -> String {
        var object: [String: Any] = [:]
        if let x, let json = Self.json(x, dateOnly: spec.xDateOnly) { object["x"] = json }
        if let y, let json = Self.json(y, dateOnly: spec.yDateOnly) { object["y"] = json }
        if let angle {
            object["angle"] = angle
            if let row { object["row"] = row }
        }
        guard !object.isEmpty, let text = try? JSONValue(any: object)?.text(sortedKeys: true, escapingSlashes: false) else {
            return ""
        }
        return text
    }

    private static func part(_ raw: Any?, mode: ChartSelectionMode?, type: ChartColumnType?) -> ChartSelectionPart? {
        guard let raw, let mode, let type else { return nil }
        switch mode {
        case .value:
            return scalar(raw, type: type).map { .value($0) }
        case .range:
            guard let pair = raw as? [Any], pair.count == 2,
                  let start = scalar(pair[0], type: type), let end = scalar(pair[1], type: type),
                  ordered(start, end) else { return nil }
            return .range(start, end)
        }
    }

    /// A JSON value as a scalar of `type`: a string, a number that is not a boolean, a whole
    /// number in Int's range, or an ISO 8601 date string. Also reads a scroll position.
    static func scalar(_ raw: Any, type: ChartColumnType) -> ChartScalar? {
        switch type {
        case .string:
            return (raw as? String).map { .string($0) }
        case .number:
            return JSONNumber.plain(raw).flatMap { $0.isFinite ? .number($0) : nil }
        case .integer:
            return JSONNumber.plain(raw).flatMap { Int(exactly: $0) }.map { .integer($0) }
        case .date:
            return (raw as? String).flatMap(DateHelper.parseDate(from:)).map { .date($0) }
        }
    }

    private static func ordered(_ start: ChartScalar, _ end: ChartScalar) -> Bool {
        switch (start, end) {
        case (.string(let a), .string(let b)): return a <= b
        case (.number(let a), .number(let b)): return a <= b
        case (.integer(let a), .integer(let b)): return a <= b
        case (.date(let a), .date(let b)): return a <= b
        default: return false
        }
    }

    private static func json(_ part: ChartSelectionPart, dateOnly: Bool) -> Any? {
        switch part {
        case .value(let scalar):
            return json(scalar, dateOnly: dateOnly)
        case .range(let start, let end):
            guard let a = json(start, dateOnly: dateOnly), let b = json(end, dateOnly: dateOnly) else { return nil }
            return [a, b]
        }
    }

    private static func json(_ scalar: ChartScalar, dateOnly: Bool) -> Any? {
        switch scalar {
        case .string(let text): return text
        case .number(let number): return number.isFinite ? number : nil
        case .integer(let integer): return integer
        case .date(let date): return dateOnly ? DateHelper.formatDate(from: date) : DateHelper.formatDateTime(from: date)
        }
    }
}
