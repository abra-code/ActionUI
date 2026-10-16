// Helpers/ChartDescription.swift
//
// Parses a Chart element's `chart` description (see Views/Chart.swift) into a typed ChartSpec.
// The same parse serves validation, which keeps the cleaned JSON and logs what it dropped, and
// the renderer, which re-parses the already-clean JSON without a logger. Cleaning is idempotent:
// parsing the cleaned JSON again drops nothing.

import Foundation
import SwiftUI
import Charts

enum ChartColumnType: String {
    case string, number, integer, date
}

enum ChartScalar: Equatable {
    case string(String)
    case number(Double)
    case integer(Int)
    case date(Date)
}

// A plottable value: `.value(label, value)` with a column reference resolved to its 0-based
// index, or a literal.
struct ChartPlottable {
    enum Source {
        case column(Int)
        case literal(ChartScalar)
    }
    let label: String
    let source: Source
    let type: ChartColumnType
    let unit: Calendar.Component?
}

enum ChartMarkKind: String {
    case BarMark, LineMark
}

struct ChartMarkSpec {
    let kind: ChartMarkKind
    let x: ChartPlottable
    let y: ChartPlottable
    let foregroundColor: SwiftUI.Color?
    let foregroundBy: ChartPlottable?
}

indirect enum ChartEntry {
    case mark(ChartMarkSpec)
    case forEach([ChartEntry])
}

struct ChartAxisSpec {
    var domain: ForwardingDomain = .automatic
    var visibility: Visibility = .automatic
    var label: String?
}

struct ChartSpec {
    var columnCount = 0
    var content: [ChartEntry] = []
    var x = ChartAxisSpec()
    var y = ChartAxisSpec()
    var legendVisibility: Visibility = .automatic
    var legendPosition: AnnotationPosition = .automatic

    // Every (column, type) pair the marks read, so the rows are parsed once per pair.
    var referencedColumns: [ChartColumnRef] {
        var refs: [ChartColumnRef] = []
        func visit(_ entries: [ChartEntry]) {
            for entry in entries {
                switch entry {
                case .forEach(let children):
                    visit(children)
                case .mark(let mark):
                    for value in [mark.x, mark.y] + (mark.foregroundBy.map { [$0] } ?? []) {
                        if case .column(let index) = value.source {
                            let ref = ChartColumnRef(index: index, type: value.type)
                            if !refs.contains(ref) { refs.append(ref) }
                        }
                    }
                }
            }
        }
        visit(content)
        return refs
    }
}

struct ChartColumnRef: Hashable {
    let index: Int
    let type: ChartColumnType
}

enum ChartDescription {
    static let supportedKeys: Set<String> = [
        "columns", "data", "content", "chartXScale", "chartYScale", "chartXAxis", "chartYAxis",
        "chartXAxisLabel", "chartYAxisLabel", "chartLegend",
    ]

    private struct Column {
        let name: String?
        let type: ChartColumnType?
        // A column given by bare name ("platform") is a string column.
        let isBareName: Bool

        var effectiveType: ChartColumnType? { type ?? (isBareName ? .string : nil) }
    }

    /// Parses `description`. Returns the cleaned JSON (unsupported or invalid parts removed,
    /// `data` kept when it has the right shape) and the typed spec built from it.
    static func parse(_ description: [String: Any], logger: (any ActionUILogger)?) -> (cleaned: [String: Any], spec: ChartSpec) {
        var cleaned: [String: Any] = [:]
        var spec = ChartSpec()

        for key in description.keys where !supportedKeys.contains(key) {
            logger?.log("Chart: '\(key)' is not supported in a chart description; ignoring", .warning)
        }

        let columns = parseColumns(description["columns"], cleaned: &cleaned, logger: logger)
        spec.columnCount = columns.count

        if let data = description["data"] {
            if let rows = data as? [Any], rows.allSatisfy(isDataRow) {
                cleaned["data"] = rows
            } else {
                logger?.log("Chart: 'data' must be an array of rows, each an array of strings, numbers, booleans or null; ignoring", .warning)
            }
        }

        if let content = description["content"] {
            if let entries = content as? [Any] {
                var cleanedEntries: [Any] = []
                spec.content = parseEntries(entries, insideForEach: false, columns: columns, cleaned: &cleanedEntries, logger: logger)
                cleaned["content"] = cleanedEntries
            } else {
                logger?.log("Chart: 'content' must be an array of chart content entries; ignoring", .warning)
            }
        }

        // One type per axis: number and integer may share an axis, string and date may not
        // share it with anything else. Marks that disagree with the first mark are dropped.
        let xType = axisType(spec.content, \.x)
        let yType = axisType(spec.content, \.y)
        var cleanedContent = cleaned["content"] as? [Any] ?? []
        spec.content = dropMismatched(spec.content, cleaned: &cleanedContent, xType: xType, yType: yType, logger: logger)
        if cleaned["content"] != nil {
            cleaned["content"] = cleanedContent
        }

        spec.x = parseAxis("X", axisType: xType, description: description, cleaned: &cleaned, logger: logger)
        spec.y = parseAxis("Y", axisType: yType, description: description, cleaned: &cleaned, logger: logger)

        if let legend = description["chartLegend"] {
            if let visibility = legend as? String, let parsed = parseVisibility(visibility) {
                spec.legendVisibility = parsed
                cleaned["chartLegend"] = visibility
            } else if let options = legend as? [String: Any],
                      let position = options["position"] as? String, let parsed = parsePosition(position) {
                spec.legendPosition = parsed
                cleaned["chartLegend"] = ["position": position]
            } else {
                logger?.log("Chart: 'chartLegend' must be \"automatic\", \"visible\", \"hidden\" or {\"position\": ...}; ignoring", .warning)
            }
        }
        return (cleaned, spec)
    }

    // MARK: - Columns and data

    private static func parseColumns(_ value: Any?, cleaned: inout [String: Any], logger: (any ActionUILogger)?) -> [Column] {
        guard let value else { return [] }
        guard let items = value as? [Any] else {
            logger?.log("Chart: 'columns' must be an array; ignoring", .warning)
            return []
        }
        var columns: [Column] = []
        var cleanedItems: [Any] = []
        var names: Set<String> = []
        for item in items {
            var name: String?
            var type: ChartColumnType?
            if let plain = item as? String {
                name = plain
            } else if let object = item as? [String: Any] {
                name = object["name"] as? String
                if let typeName = object["type"] as? String {
                    type = ChartColumnType(rawValue: typeName)
                    if type == nil {
                        logger?.log("Chart: column type '\(typeName)' must be string, number, integer or date; leaving it untyped", .warning)
                    }
                }
            } else {
                logger?.log("Chart: a column must be a name or {\"name\", \"type\"}; leaving it unnamed", .warning)
            }
            if let candidate = name, !isIdentifier(candidate) || names.contains(candidate) {
                logger?.log("Chart: column name '\(candidate)' must be a unique identifier (letters, digits, _); leaving it unnamed", .warning)
                name = nil
            }
            if let name { names.insert(name) }
            let isBareName = item is String && name != nil
            columns.append(Column(name: name, type: type, isBareName: isBareName))
            switch (name, type) {
            case (let name?, nil) where isBareName:
                cleanedItems.append(name)
            default:
                // An untyped {"name"} stays an object: as a bare name it would turn into a
                // string column on the next re-validation.
                var object: [String: Any] = [:]
                object["name"] = name
                object["type"] = type?.rawValue
                cleanedItems.append(object)
            }
        }
        cleaned["columns"] = cleanedItems
        return columns
    }

    private static func isDataRow(_ row: Any) -> Bool {
        guard let cells = row as? [Any] else { return false }
        return cells.allSatisfy { $0 is String || $0 is NSNumber || $0 is NSNull }
    }

    /// Turns inline `data` rows into row strings, by one rule on every platform: integers
    /// without a decimal point, other numbers as the shortest decimal that reads back the
    /// same, booleans as true/false, null as an empty cell.
    static func rowStrings(_ data: [Any]) -> [[String]] {
        data.compactMap { row in
            (row as? [Any])?.map(cellString)
        }
    }

    static func cellString(_ cell: Any) -> String {
        switch cell {
        case let string as String:
            return string
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            let value = number.doubleValue
            if value == 0 {
                return "0"
            }
            if value.rounded() == value, abs(value) < 9_007_199_254_740_992 {
                return String(Int64(value))
            }
            return String(value)
        default:
            return ""
        }
    }

    // MARK: - Content

    private static func parseEntries(_ entries: [Any], insideForEach: Bool, columns: [Column],
                                     cleaned: inout [Any], logger: (any ActionUILogger)?) -> [ChartEntry] {
        var result: [ChartEntry] = []
        for item in entries {
            guard let entry = item as? [String: Any], let type = entry["type"] as? String else {
                logger?.log("Chart: a content entry must be an object with a 'type'; ignoring it", .warning)
                continue
            }
            if type == "ForEach" {
                if insideForEach {
                    logger?.log("Chart: a ForEach cannot be inside another ForEach; ignoring it", .warning)
                    continue
                }
                guard let children = entry["content"] as? [Any] else {
                    logger?.log("Chart: ForEach requires 'content' (an array); ignoring it", .warning)
                    continue
                }
                var cleanedChildren: [Any] = []
                let parsed = parseEntries(children, insideForEach: true, columns: columns, cleaned: &cleanedChildren, logger: logger)
                result.append(.forEach(parsed))
                cleaned.append(["type": "ForEach", "content": cleanedChildren])
                continue
            }
            guard let kind = ChartMarkKind(rawValue: type) else {
                logger?.log("Chart: content type '\(type)' is not supported; ignoring it", .warning)
                continue
            }
            if let mark = parseMark(kind, entry, insideForEach: insideForEach, columns: columns, logger: logger) {
                result.append(.mark(mark.spec))
                cleaned.append(mark.cleaned)
            }
        }
        return result
    }

    private static func parseMark(_ kind: ChartMarkKind, _ entry: [String: Any], insideForEach: Bool, columns: [Column],
                                  logger: (any ActionUILogger)?) -> (spec: ChartMarkSpec, cleaned: [String: Any])? {
        var cleaned: [String: Any] = ["type": kind.rawValue]
        let supported: Set<String> = ["type", "x", "y", "foregroundStyle"]
        for key in entry.keys where !supported.contains(key) {
            logger?.log("Chart: '\(key)' is not supported on \(kind.rawValue); ignoring it", .warning)
        }
        guard let xObject = entry["x"] as? [String: Any], let yObject = entry["y"] as? [String: Any] else {
            logger?.log("Chart: \(kind.rawValue) requires 'x' and 'y', each {\"label\", \"value\"}; ignoring it", .warning)
            return nil
        }
        guard let x = parsePlottable(xObject, role: "\(kind.rawValue).x", insideForEach: insideForEach, columns: columns, logger: logger),
              let y = parsePlottable(yObject, role: "\(kind.rawValue).y", insideForEach: insideForEach, columns: columns, logger: logger) else {
            return nil
        }
        cleaned["x"] = x.cleaned
        cleaned["y"] = y.cleaned

        var foregroundColor: SwiftUI.Color?
        var foregroundBy: ChartPlottable?
        if let style = entry["foregroundStyle"] {
            if let colorName = style as? String, let color = ColorHelper.resolveColor(colorName) {
                foregroundColor = color
                cleaned["foregroundStyle"] = colorName
            } else if let object = style as? [String: Any], let by = object["by"] as? [String: Any],
                      let parsed = parsePlottable(by, role: "foregroundStyle.by", insideForEach: insideForEach, columns: columns, logger: logger) {
                foregroundBy = parsed.value
                cleaned["foregroundStyle"] = ["by": parsed.cleaned]
            } else {
                logger?.log("Chart: \(kind.rawValue) foregroundStyle must be a color or {\"by\": {\"label\", \"value\"}}; ignoring it", .warning)
            }
        }
        return (ChartMarkSpec(kind: kind, x: x.value, y: y.value, foregroundColor: foregroundColor, foregroundBy: foregroundBy), cleaned)
    }

    private static func parsePlottable(_ object: [String: Any], role: String, insideForEach: Bool, columns: [Column],
                                       logger: (any ActionUILogger)?) -> (value: ChartPlottable, cleaned: [String: Any])? {
        guard let label = object["label"] as? String else {
            logger?.log("Chart: \(role) requires a 'label' string; ignoring the mark", .warning)
            return nil
        }
        var cleaned: [String: Any] = ["label": label]
        var declaredType: ChartColumnType?
        if let typeName = object["type"] as? String {
            declaredType = ChartColumnType(rawValue: typeName)
            if declaredType == nil {
                logger?.log("Chart: \(role) type '\(typeName)' must be string, number, integer or date; ignoring the type", .warning)
            } else {
                cleaned["type"] = typeName
            }
        }
        var unit: Calendar.Component?
        if let unitName = object["unit"] as? String {
            unit = calendarComponent(unitName)
            if unit == nil {
                logger?.log("Chart: \(role) unit '\(unitName)' is not supported; ignoring the unit", .warning)
            } else {
                cleaned["unit"] = unitName
            }
        }

        let raw = object["value"]
        if insideForEach, let reference = raw as? String, let index = columnIndex(reference, columns: columns) {
            let columnType = index < columns.count ? columns[index].effectiveType : nil
            guard let type = declaredType ?? columnType ?? (unit != nil ? .date : nil) else {
                logger?.log("Chart: \(role) refers to column \(reference), which has no type; give the column or the value a \"type\". Plotting it as text", .warning)
                cleaned["value"] = reference
                cleaned["type"] = ChartColumnType.string.rawValue
                return (ChartPlottable(label: label, source: .column(index), type: .string, unit: nil), cleaned)
            }
            cleaned["value"] = reference
            return (ChartPlottable(label: label, source: .column(index), type: type, unit: type == .date ? unit : nil), cleaned)
        }
        // An explicit "type": "string" says the text is meant literally. Validation writes that
        // type, so re-validation (on every setElementProperty) does not repeat the warning.
        var literalReference = false
        if let reference = raw as? String, isReferenceShaped(reference), declaredType != .string {
            let reason = insideForEach ? "names no column" : "is outside a ForEach"
            logger?.log("Chart: \(role) value '\(reference)' looks like a column reference but \(reason); plotting it as literal text", .warning)
            literalReference = true
        }

        // A literal.
        if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            cleaned["value"] = number
            if declaredType == .integer {
                guard let whole = Int(exactly: number.doubleValue) else {
                    logger?.log("Chart: \(role) value \(number) is not a whole number in Int's range but the type is integer; ignoring the mark", .warning)
                    return nil
                }
                return (ChartPlottable(label: label, source: .literal(.integer(whole)), type: .integer, unit: nil), cleaned)
            }
            return (ChartPlottable(label: label, source: .literal(.number(number.doubleValue)), type: .number, unit: nil), cleaned)
        }
        if let string = raw as? String {
            cleaned["value"] = string
            if declaredType == .date || unit != nil {
                guard let date = DateHelper.parseDate(from: string) else {
                    logger?.log("Chart: \(role) value '\(string)' is not an ISO 8601 date; ignoring the mark", .warning)
                    return nil
                }
                cleaned["type"] = ChartColumnType.date.rawValue
                return (ChartPlottable(label: label, source: .literal(.date(date)), type: .date, unit: unit), cleaned)
            }
            if literalReference {
                cleaned["type"] = ChartColumnType.string.rawValue
            }
            return (ChartPlottable(label: label, source: .literal(.string(string)), type: .string, unit: nil), cleaned)
        }
        logger?.log("Chart: \(role) requires a 'value' (a column reference, a number or a string); ignoring the mark", .warning)
        return nil
    }

    // MARK: - Axes

    private enum AxisFamily {
        case numeric, string, date
    }

    private static func family(_ type: ChartColumnType) -> AxisFamily {
        switch type {
        case .number, .integer: return .numeric
        case .string: return .string
        case .date: return .date
        }
    }

    private static func axisType(_ entries: [ChartEntry], _ keyPath: KeyPath<ChartMarkSpec, ChartPlottable>) -> ChartColumnType? {
        for entry in entries {
            switch entry {
            case .mark(let mark):
                return mark[keyPath: keyPath].type
            case .forEach(let children):
                if let type = axisType(children, keyPath) { return type }
            }
        }
        return nil
    }

    private static func dropMismatched(_ entries: [ChartEntry], cleaned: inout [Any], xType: ChartColumnType?, yType: ChartColumnType?,
                                       logger: (any ActionUILogger)?) -> [ChartEntry] {
        var kept: [ChartEntry] = []
        var keptCleaned: [Any] = []
        for (entry, json) in zip(entries, cleaned) {
            switch entry {
            case .mark(let mark):
                if let xType, family(mark.x.type) != family(xType) {
                    logger?.log("Chart: \(mark.kind.rawValue) plots \(mark.x.type.rawValue) on an x axis of \(xType.rawValue) values; ignoring it", .warning)
                    continue
                }
                if let yType, family(mark.y.type) != family(yType) {
                    logger?.log("Chart: \(mark.kind.rawValue) plots \(mark.y.type.rawValue) on a y axis of \(yType.rawValue) values; ignoring it", .warning)
                    continue
                }
                kept.append(entry)
                keptCleaned.append(json)
            case .forEach(let children):
                var childJSON = ((json as? [String: Any])?["content"] as? [Any]) ?? []
                let keptChildren = dropMismatched(children, cleaned: &childJSON, xType: xType, yType: yType, logger: logger)
                kept.append(.forEach(keptChildren))
                keptCleaned.append(["type": "ForEach", "content": childJSON])
            }
        }
        cleaned = keptCleaned
        return kept
    }

    private static func parseAxis(_ axis: String, axisType: ChartColumnType?, description: [String: Any],
                                  cleaned: inout [String: Any], logger: (any ActionUILogger)?) -> ChartAxisSpec {
        var spec = ChartAxisSpec()
        let scaleKey = "chart\(axis)Scale"
        if let scale = description[scaleKey] {
            if let object = scale as? [String: Any], let domain = object["domain"],
               let parsed = parseDomain(domain, axisType: axisType) {
                spec.domain = parsed
                cleaned[scaleKey] = ["domain": domain]
                for key in object.keys where key != "domain" {
                    logger?.log("Chart: '\(key)' in \(scaleKey) is not supported; ignoring it", .warning)
                }
            } else {
                logger?.log("Chart: \(scaleKey) must be {\"domain\": ...} with two numbers or dates, a list of strings, or {\"automatic\": {...}}, typed by the axis; ignoring it", .warning)
            }
        }
        let axisKey = "chart\(axis)Axis"
        if let visibility = description[axisKey] {
            if let name = visibility as? String, let parsed = parseVisibility(name) {
                spec.visibility = parsed
                cleaned[axisKey] = name
            } else {
                logger?.log("Chart: \(axisKey) must be \"automatic\", \"visible\" or \"hidden\"; ignoring it", .warning)
            }
        }
        let labelKey = "chart\(axis)AxisLabel"
        if let label = description[labelKey] {
            if let text = label as? String {
                spec.label = text
                cleaned[labelKey] = text
            } else {
                logger?.log("Chart: \(labelKey) must be a string; ignoring it", .warning)
            }
        }
        return spec
    }

    private static func parseDomain(_ value: Any, axisType: ChartColumnType?) -> ForwardingDomain? {
        if let object = value as? [String: Any], let automatic = object["automatic"] as? [String: Any], object.count == 1 {
            return ForwardingDomain(.automatic(includesZero: automatic["includesZero"] as? Bool,
                                               reversed: automatic["reversed"] as? Bool))
        }
        guard let items = value as? [Any] else { return nil }
        let family = axisType.map(family)
        if family == nil || family == .numeric,
           items.count == 2, let low = items[0] as? NSNumber, let high = items[1] as? NSNumber,
           CFGetTypeID(low) != CFBooleanGetTypeID(), CFGetTypeID(high) != CFBooleanGetTypeID(),
           low.doubleValue <= high.doubleValue {
            return ForwardingDomain(.numbers(low.doubleValue...high.doubleValue))
        }
        guard let strings = items as? [String] else { return nil }
        if family == .date {
            guard strings.count == 2, let low = DateHelper.parseDate(from: strings[0]),
                  let high = DateHelper.parseDate(from: strings[1]), low <= high else { return nil }
            return ForwardingDomain(.dates(low...high))
        }
        if family == nil || family == .string {
            return ForwardingDomain(.strings(strings))
        }
        return nil
    }

    // MARK: - Small parsers

    private static func parseVisibility(_ name: String) -> Visibility? {
        switch name {
        case "automatic": return .automatic
        case "visible": return .visible
        case "hidden": return .hidden
        default: return nil
        }
    }

    private static func parsePosition(_ name: String) -> AnnotationPosition? {
        switch name {
        case "automatic": return .automatic
        case "overlay": return .overlay
        case "top": return .top
        case "bottom": return .bottom
        case "leading": return .leading
        case "trailing": return .trailing
        case "topLeading": return .topLeading
        case "topTrailing": return .topTrailing
        case "bottomLeading": return .bottomLeading
        case "bottomTrailing": return .bottomTrailing
        default: return nil
        }
    }

    private static func calendarComponent(_ name: String) -> Calendar.Component? {
        switch name {
        case "year": return .year
        case "quarter": return .quarter
        case "month": return .month
        case "weekOfYear": return .weekOfYear
        case "weekOfMonth": return .weekOfMonth
        case "day": return .day
        case "hour": return .hour
        case "minute": return .minute
        case "second": return .second
        default: return nil
        }
    }

    private static func isIdentifier(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, first == "_" || (first.isASCII && CharacterSet.letters.contains(first)) else { return false }
        return name.unicodeScalars.allSatisfy { $0 == "_" || ($0.isASCII && CharacterSet.alphanumerics.contains($0)) }
    }

    // "$N" (1-based) or "$name"; nil when it is neither or names no column.
    private static func columnIndex(_ reference: String, columns: [Column]) -> Int? {
        guard reference.hasPrefix("$") else { return nil }
        let body = String(reference.dropFirst())
        if let number = Int(body), body.allSatisfy(\.isASCII) {
            // A positional reference may go past the declared columns: rows can be wider.
            return number >= 1 ? number - 1 : nil
        }
        return columns.firstIndex { $0.name == body }
    }

    private static func isReferenceShaped(_ string: String) -> Bool {
        guard string.hasPrefix("$"), string.count > 1 else { return false }
        return isIdentifier(String(string.dropFirst())) || Int(string.dropFirst()) != nil
    }
}
