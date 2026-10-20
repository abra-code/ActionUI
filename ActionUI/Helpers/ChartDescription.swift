// Helpers/ChartDescription.swift
//
// Parses a Chart element's `chart` description (see Views/Chart.swift) into a typed ChartSpec.
// The same parse serves the Chart element's store, which keeps the cleaned JSON and logs what it
// dropped (on load, and when "chart" is set), and the renderer, which re-parses the stored JSON
// without a logger. Cleaning is idempotent: parsing the cleaned JSON again drops nothing.

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
        // "$selection" outside a ForEach: the chart's selection on this axis (ChartSelection).
        case selection(Axis)
    }

    var isSelection: Bool {
        if case .selection = source { return true }
        return false
    }
    let label: String
    let source: Source
    let type: ChartColumnType
    let unit: Calendar.Component?
}

indirect enum ChartEntry {
    case mark(ChartMarkSpec)
    // `data` is the ForEach's own inline rows; nil draws it over the chart's rows.
    case forEach([ChartEntry], data: [[String]]?)
    // A Plot's entries, its modifiers already appended to every mark inside.
    case plot([ChartEntry])

    var children: [ChartEntry] {
        switch self {
        case .mark: return []
        case .forEach(let children, _), .plot(let children): return children
        }
    }
}

// The style scales (chartForegroundStyleScale and the others). Each domain is typed by the
// values its channel's {"by"} modifiers plot.
struct ChartStyleScales {
    var foregroundDomain: ForwardingDomain = .automatic
    var foregroundRange: ForwardingColorRange?
    var symbolDomain: ForwardingDomain = .automatic
    var symbolRange: [BasicChartSymbolShape] = []
    var lineStyleDomain: ForwardingDomain = .automatic
    var lineStyleRange: [StrokeStyle] = []
    var symbolSizeDomain: ForwardingDomain = .automatic
    var symbolSizeRange: ClosedRange<CGFloat>?
}

struct ChartAxisSpec {
    var domain: ForwardingDomain = .automatic
    var range: ForwardingPositionRange = .automatic
    var scaleType: ScaleType?
    var visibility: Visibility = .automatic
    // AxisMarks content; nil draws Swift's default axis.
    var marks: [ChartAxisMarksSpec]?
    var label: String?
    var labelPosition: AnnotationPosition = .automatic
    var labelAlignment: Alignment?
    var labelSpacing: CGFloat?
}

struct ChartSpec {
    var columnCount = 0
    var content: [ChartEntry] = []
    var x = ChartAxisSpec()
    var y = ChartAxisSpec()
    var styles = ChartStyleScales()
    var legendVisibility: Visibility = .automatic
    var legendPosition: AnnotationPosition = .automatic
    // View modifier properties for the plot area: baseline View properties, as given.
    var plotStyle: [String: Any] = [:]
    var selection = ChartSelectionSpec()
    var scroll = ChartScrollSpec()

    // Every (column, type) pair the marks read from the chart's rows, so the rows are parsed
    // once per pair. A ForEach with its own data reads its own rows (referencedColumns(in:)).
    var referencedColumns: [ChartColumnRef] { Self.referencedColumns(in: content) }

    static func referencedColumns(in entries: [ChartEntry]) -> [ChartColumnRef] {
        var refs: [ChartColumnRef] = []
        func visit(_ entries: [ChartEntry]) {
            for entry in entries {
                switch entry {
                case .forEach(_, data: .some):
                    continue
                case .forEach(let children, data: nil), .plot(let children):
                    visit(children)
                case .mark(let mark):
                    for value in mark.plottables {
                        if case .column(let index) = value.source {
                            let ref = ChartColumnRef(index: index, type: value.type)
                            if !refs.contains(ref) { refs.append(ref) }
                        }
                    }
                }
            }
        }
        visit(entries)
        return refs
    }

    // How many annotation views the content draws over `rowCount` rows (a ForEach with its own
    // data draws over those), unparsable rows included.
    static func annotationCount(in entries: [ChartEntry], rowCount: Int) -> Int {
        entries.reduce(0) { total, entry in
            switch entry {
            case .mark(let mark):
                return total + mark.modifiers.filter { if case .annotation = $0 { true } else { false } }.count
            case .plot(let children):
                return total + annotationCount(in: children, rowCount: rowCount)
            case .forEach(let children, let data):
                return total + (data?.count ?? rowCount) * annotationCount(in: children, rowCount: rowCount)
            }
        }
    }
}

struct ChartColumnRef: Hashable {
    let index: Int
    let type: ChartColumnType
}

@MainActor
enum ChartDescription {
    static let supportedKeys: Set<String> = [
        "columns", "data", "content", "chartXScale", "chartYScale", "chartXAxis", "chartYAxis",
        "chartXAxisLabel", "chartYAxisLabel", "chartLegend", "chartPlotStyle",
        "chartForegroundStyleScale", "chartSymbolScale", "chartLineStyleScale", "chartSymbolSizeScale",
        "chartXSelection", "chartYSelection", "chartAngleSelection",
        "chartScrollableAxes", "chartXVisibleDomain", "chartYVisibleDomain", "chartScrollPosition",
    ]
    static let plotStyleKeys: Set<String> = [
        "padding", "background", "border", "frame", "cornerRadius", "clipShape", "shadow", "opacity", "offset", "foregroundStyle",
    ]

    struct Column {
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
        let xType = axisType(spec.content, \.xValues)
        let yType = axisType(spec.content, \.yValues)
        var cleanedContent = cleaned["content"] as? [Any] ?? []
        spec.content = dropMismatched(spec.content, cleaned: &cleanedContent, xType: xType, yType: yType, logger: logger)
        if cleaned["content"] != nil {
            cleaned["content"] = cleanedContent
        }

        spec.x = parseAxis("X", axisType: xType, description: description, cleaned: &cleaned, logger: logger)
        spec.y = parseAxis("Y", axisType: yType, description: description, cleaned: &cleaned, logger: logger)
        spec.styles = parseStyleScales(spec.content, description: description, cleaned: &cleaned, logger: logger)
        spec.selection = parseSelection(spec.content, xType: xType, yType: yType, description: description, cleaned: &cleaned, logger: logger)
        spec.content = typingSelectionValues(spec.content, spec: spec.selection, logger: logger)
        spec.scroll = parseScroll(xType: xType, yType: yType, description: description, cleaned: &cleaned, logger: logger)

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

        if let plotStyle = description["chartPlotStyle"] {
            if let properties = plotStyle as? [String: Any] {
                // The plot area takes the visual baseline View properties, read as on any view
                // (a value of the wrong type is ignored). Others (actions, accessibility, layout of
                // the chart itself) do not apply.
                var visual: [String: Any] = [:]
                for (key, value) in properties {
                    if plotStyleKeys.contains(key) {
                        visual[key] = value
                    } else {
                        logger?.log("Chart: '\(key)' does not apply in chartPlotStyle (it takes \(plotStyleKeys.sorted().joined(separator: ", "))); ignoring it", .warning)
                    }
                }
                spec.plotStyle = visual
                cleaned["chartPlotStyle"] = visual
            } else {
                logger?.log("Chart: 'chartPlotStyle' must be an object of View properties; ignoring", .warning)
            }
        }
        return (cleaned, spec)
    }

    // MARK: - Columns and data

    static func parseColumns(_ value: Any?, cleaned: inout [String: Any], logger: (any ActionUILogger)?) -> [Column] {
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
                // string column the next time the description is cleaned (read back and set again).
                var object: [String: Any] = [:]
                object["name"] = name
                object["type"] = type?.rawValue
                cleanedItems.append(object)
            }
        }
        cleaned["columns"] = cleanedItems
        return columns
    }

    static func isDataRow(_ row: Any) -> Bool {
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

    // MARK: - Plottable values (marks and their modifiers are in ChartMarkParsing.swift)

    /// - Parameter selectionAxis: the axis of the mark argument being parsed (x, xStart, xEnd:
    ///   horizontal; y, yStart, yEnd: vertical), where "$selection" may read the selection; nil
    ///   elsewhere.
    static func parsePlottable(_ object: [String: Any], role: String, insideForEach: Bool, columns: [Column],
                                       selectionAxis: Axis? = nil,
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
        // "$selection" outside a ForEach reads the selection; its type is the axis's, set once
        // the axis types are known (typingSelectionValues).
        if !insideForEach, raw as? String == ChartSelectionSpec.reference, declaredType != .string {
            guard let selectionAxis else {
                logger?.log("Chart: \(role) value '\(ChartSelectionSpec.reference)' reads the selection only as a plotted x or y value (x, xStart, xEnd, y, yStart, yEnd); plotting it as literal text", .warning)
                cleaned["value"] = ChartSelectionSpec.reference
                cleaned["type"] = ChartColumnType.string.rawValue
                return (ChartPlottable(label: label, source: .literal(.string(ChartSelectionSpec.reference)), type: .string, unit: nil), cleaned)
            }
            cleaned["value"] = ChartSelectionSpec.reference
            cleaned["type"] = nil
            return (ChartPlottable(label: label, source: .selection(selectionAxis), type: .string, unit: nil), cleaned)
        }
        // An explicit "type": "string" says the text is meant literally. Cleaning writes that
        // type, so cleaning the description again (read back and set again) does not repeat the warning.
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

    // The type of the first value plotted on an axis (a mark may plot only points on it).
    // The type of the first value a style channel's {"by"} modifiers plot.
    private static func styleType(_ entries: [ChartEntry], _ matches: @escaping (ChartMarkModifier) -> ChartPlottable?) -> ChartColumnType? {
        firstType(entries) { mark in mark.modifiers.lazy.compactMap(matches).first }
    }

    // Selection values take their axis's type, so they never decide it.
    private static func axisType(_ entries: [ChartEntry], _ keyPath: KeyPath<ChartMarkSpec, [ChartPlottable]>) -> ChartColumnType? {
        firstType(entries) { $0[keyPath: keyPath].first { !$0.isSelection } }
    }

    private static func firstType(_ entries: [ChartEntry], _ value: (ChartMarkSpec) -> ChartPlottable?) -> ChartColumnType? {
        for entry in entries {
            if case .mark(let mark) = entry {
                if let first = value(mark) { return first.type }
            } else if let type = firstType(entry.children, value) {
                return type
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
                if let xType, let other = mark.xValues.first(where: { !$0.isSelection && family($0.type) != family(xType) }) {
                    logger?.log("Chart: \(mark.kind.rawValue) plots \(other.type.rawValue) on an x axis of \(xType.rawValue) values; ignoring it", .warning)
                    continue
                }
                if let yType, let other = mark.yValues.first(where: { !$0.isSelection && family($0.type) != family(yType) }) {
                    logger?.log("Chart: \(mark.kind.rawValue) plots \(other.type.rawValue) on a y axis of \(yType.rawValue) values; ignoring it", .warning)
                    continue
                }
                kept.append(entry)
                keptCleaned.append(json)
            case .forEach(let children, _), .plot(let children):
                // The group keeps its own keys (a Plot's modifiers, a ForEach's data); only its
                // content shrinks.
                var groupJSON = json as? [String: Any] ?? [:]
                var childJSON = groupJSON["content"] as? [Any] ?? []
                let keptChildren = dropMismatched(children, cleaned: &childJSON, xType: xType, yType: yType, logger: logger)
                if case .forEach(_, let data) = entry {
                    kept.append(.forEach(keptChildren, data: data))
                } else {
                    kept.append(.plot(keptChildren))
                }
                groupJSON["content"] = childJSON
                keptCleaned.append(groupJSON)
            }
        }
        cleaned = keptCleaned
        return kept
    }

    // chartXSelection / chartYSelection ("value" | "range") and chartAngleSelection ("value"),
    // typed by the axis (or the sectors' angle values) they select on.
    private static func parseSelection(_ entries: [ChartEntry], xType: ChartColumnType?, yType: ChartColumnType?,
                                       description: [String: Any], cleaned: inout [String: Any],
                                       logger: (any ActionUILogger)?) -> ChartSelectionSpec {
        var spec = ChartSelectionSpec()
        for (axis, type) in [("X", xType), ("Y", yType)] {
            let key = "chart\(axis)Selection"
            guard let raw = description[key] else { continue }
            guard let name = raw as? String, let mode = ChartSelectionMode(rawValue: name) else {
                logger?.log("Chart: '\(key)' must be \"value\" or \"range\"; ignoring it", .warning)
                continue
            }
            guard let type else {
                logger?.log("Chart: '\(key)' needs a mark that plots a value on the \(axis.lowercased()) axis; ignoring it", .warning)
                continue
            }
            // Swift orders a range of strings alphabetically, not as the categories stand on
            // the axis, so it would not mean what the user dragged over.
            if mode == .range, type == .string {
                logger?.log("Chart: '\(key)' \"range\" needs a number or date axis, not categories; ignoring it", .warning)
                continue
            }
            cleaned[key] = name
            if axis == "X" {
                spec.x = mode
                spec.xType = type
                spec.xDateOnly = type == .date && dateOnly(entries, \.xValues)
            } else {
                spec.y = mode
                spec.yType = type
                spec.yDateOnly = type == .date && dateOnly(entries, \.yValues)
            }
        }
        if let raw = description["chartAngleSelection"] {
            let angleType = firstType(entries) { $0.kind == .SectorMark ? $0.values["angle"] : nil }
            if raw as? String != ChartSelectionMode.value.rawValue {
                logger?.log("Chart: 'chartAngleSelection' must be \"value\"; ignoring it", .warning)
            } else if angleType == nil {
                logger?.log("Chart: 'chartAngleSelection' needs a SectorMark; ignoring it", .warning)
            } else {
                cleaned["chartAngleSelection"] = ChartSelectionMode.value.rawValue
                spec.angle = true
                spec.angleType = angleType
            }
        }
        return spec
    }

    // The longest visible length of a date axis, in seconds: about 30 million years.
    static let maxDateVisibleLength = 1e15

    // chartScrollableAxes, then each scrolling axis's visible length and initial position, in
    // the unit and type of the axis.
    private static func parseScroll(xType: ChartColumnType?, yType: ChartColumnType?, description: [String: Any],
                                    cleaned: inout [String: Any], logger: (any ActionUILogger)?) -> ChartScrollSpec {
        var spec = ChartScrollSpec(xType: xType, yType: yType)
        if let raw = description["chartScrollableAxes"] {
            let names = (raw as? String).map { [$0] } ?? (raw as? [Any])?.compactMap { $0 as? String }
            let count = (raw as? [Any])?.count ?? 1
            let axes = names?.compactMap { ["horizontal": Axis.Set.horizontal, "vertical": .vertical][$0] } ?? []
            // A repeated axis merges into one, as the verifier accepts it.
            if let names, !axes.isEmpty, axes.count == count {
                axes.forEach { spec.axes.formUnion($0) }
                cleaned["chartScrollableAxes"] = raw
            } else {
                logger?.log("Chart: 'chartScrollableAxes' must be \"horizontal\", \"vertical\" or both in an array; ignoring it", .warning)
            }
        }
        for (axis, type) in [("X", xType), ("Y", yType)] {
            let key = "chart\(axis)VisibleDomain"
            let scrolls = spec.axes.contains(axis == "X" ? .horizontal : .vertical)
            let direction = axis == "X" ? "horizontal" : "vertical"
            guard let raw = description[key] else { continue }
            guard scrolls else {
                logger?.log("Chart: '\(key)' needs chartScrollableAxes with \"\(direction)\"; ignoring it", .warning)
                continue
            }
            guard let type else {
                logger?.log("Chart: '\(key)' needs a mark that plots a value on the \(axis.lowercased()) axis; ignoring it", .warning)
                continue
            }
            let object = raw as? [String: Any] ?? [:]
            for name in object.keys where name != "length" {
                logger?.log("Chart: \(key).\(name) is not supported; ignoring it", .warning)
            }
            let number = (object["length"] as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.doubleValue }
            let length: ChartVisibleLength?
            switch (type, number) {
            case (.string, let value?) where value >= 1 && value == value.rounded() && value <= Double(Int32.max):
                length = .categories(Int(value))
            case (.number, let value?), (.integer, let value?):
                length = value.isFinite && value > 0 ? .amount(value) : nil
            case (.date, let value?):
                // Swift Charts stops the app at a date length of about 1e19 seconds (Int's range).
                length = value > 0 && value <= maxDateVisibleLength ? .amount(value) : nil
            default:
                length = nil
            }
            guard let length else {
                let unit = type == .string ? "a whole count of categories" : type == .date ? "a number of seconds above 0 and at most 1e15" : "a number above 0"
                logger?.log("Chart: '\(key)' must be {\"length\": n}, n \(unit) on this axis; ignoring it", .warning)
                continue
            }
            cleaned[key] = object.filter { $0.key == "length" }
            if axis == "X" { spec.xLength = length } else { spec.yLength = length }
        }
        if let raw = description["chartScrollPosition"] {
            guard let object = raw as? [String: Any] else {
                logger?.log("Chart: 'chartScrollPosition' must be {\"initialX\", \"initialY\"}; ignoring it", .warning)
                return spec
            }
            var cleanedPosition: [String: Any] = [:]
            for key in object.keys where key != "initialX" && key != "initialY" {
                logger?.log("Chart: chartScrollPosition.\(key) is not supported; ignoring it", .warning)
            }
            for (key, axis, type) in [("initialX", Axis.Set.horizontal, xType), ("initialY", Axis.Set.vertical, yType)] {
                guard let value = object[key] else { continue }
                guard spec.axes.contains(axis) else {
                    logger?.log("Chart: chartScrollPosition.\(key) needs chartScrollableAxes with \"\(axis == .horizontal ? "horizontal" : "vertical")\"; ignoring it", .warning)
                    continue
                }
                guard let type, let scalar = ChartSelection.scalar(value, type: type) else {
                    logger?.log("Chart: chartScrollPosition.\(key) must be a value of the axis's type\(type.map { " (\($0.rawValue))" } ?? ""); ignoring it", .warning)
                    continue
                }
                if axis == .horizontal { spec.initialX = scalar } else { spec.initialY = scalar }
                cleanedPosition[key] = value
            }
            if !cleanedPosition.isEmpty {
                cleaned["chartScrollPosition"] = cleanedPosition
            }
        }
        return spec
    }

    // Whether the first value plotted on an axis has a unit of a day or coarser.
    private static func dateOnly(_ entries: [ChartEntry], _ keyPath: KeyPath<ChartMarkSpec, [ChartPlottable]>) -> Bool {
        let coarse: Set<Calendar.Component> = [.era, .year, .quarter, .month, .weekOfYear, .weekOfMonth, .day]
        var unit: Calendar.Component??
        func find(_ entries: [ChartEntry]) {
            for entry in entries where unit == nil {
                if case .mark(let mark) = entry {
                    if let first = mark[keyPath: keyPath].first(where: { !$0.isSelection }) { unit = .some(first.unit) }
                } else {
                    find(entry.children)
                }
            }
        }
        find(entries)
        guard let found = unit, let component = found else { return false }
        return coarse.contains(component)
    }

    // "$selection" values take the type of the axis they are plotted on. Selection values sit
    // only in marks outside a ForEach (top level or in Plots).
    private static func typingSelectionValues(_ entries: [ChartEntry], spec: ChartSelectionSpec,
                                              logger: (any ActionUILogger)?) -> [ChartEntry] {
        entries.map { entry in
            switch entry {
            case .mark(var mark):
                for (key, value) in mark.values {
                    guard case .selection(let axis) = value.source else { continue }
                    let name = axis == .horizontal ? "X" : "Y"
                    let mode = axis == .horizontal ? spec.x : spec.y
                    let type = axis == .horizontal ? spec.xType : spec.yType
                    if mode == nil {
                        logger?.log("Chart: \(mark.kind.rawValue).\(key) reads the selection, but the description has no chart\(name)Selection; the mark is never drawn", .warning)
                    } else if mode == .range, key == "x" || key == "y" {
                        logger?.log("Chart: \(mark.kind.rawValue).\(key) reads a range selection, which only \(key)Start and \(key)End can read; the mark is never drawn", .warning)
                    }
                    mark.values[key] = ChartPlottable(label: value.label, source: value.source, type: type ?? .string, unit: nil)
                }
                return .mark(mark)
            case .plot(let children):
                return .plot(typingSelectionValues(children, spec: spec, logger: logger))
            case .forEach:
                return entry
            }
        }
    }

    private static func parseAxis(_ axis: String, axisType: ChartColumnType?, description: [String: Any],
                                  cleaned: inout [String: Any], logger: (any ActionUILogger)?) -> ChartAxisSpec {
        var spec = ChartAxisSpec()
        let scaleKey = "chart\(axis)Scale"
        if let scale = description[scaleKey] {
            if let object = scale as? [String: Any] {
                var cleanedScale: [String: Any] = [:]
                if let domain = object["domain"] {
                    if let parsed = parseDomain(domain, axisType: axisType) {
                        spec.domain = parsed
                        cleanedScale["domain"] = domain
                    } else {
                        logger?.log("Chart: \(scaleKey).domain must be two numbers or two dates (a range), a list of strings, or {\"automatic\": {...}}, typed by the axis; ignoring it", .warning)
                    }
                }
                if let range = object["range"] {
                    if let parsed = parseRange(range) {
                        spec.range = parsed
                        cleanedScale["range"] = range
                    } else {
                        logger?.log("Chart: \(scaleKey).range must be {\"startPadding\", \"endPadding\"}, {\"padding\"} or two numbers (points); ignoring it", .warning)
                    }
                }
                if let type = object["type"] {
                    if let parsed = parseScaleType(type) {
                        if let problem = scaleTypeProblem(type, axisType: axisType, domain: spec.domain) {
                            logger?.log("Chart: \(scaleKey).type \(problem); ignoring it", .warning)
                        } else {
                            spec.scaleType = parsed
                            cleanedScale["type"] = type
                        }
                    } else {
                        logger?.log("Chart: \(scaleKey).type must be linear, log, date, category, squareRoot, symmetricLog, {\"power\": {\"exponent\"}} or {\"symmetricLog\": {\"slopeAtZero\"}}; ignoring it", .warning)
                    }
                }
                for key in object.keys where !["domain", "range", "type"].contains(key) {
                    logger?.log("Chart: '\(key)' in \(scaleKey) is not supported; ignoring it", .warning)
                }
                cleaned[scaleKey] = cleanedScale
            } else {
                logger?.log("Chart: \(scaleKey) must be an object with 'domain', 'range' or 'type'; ignoring it", .warning)
            }
        }
        let axisKey = "chart\(axis)Axis"
        if let visibility = description[axisKey] {
            if let name = visibility as? String, let parsed = parseVisibility(name) {
                spec.visibility = parsed
                cleaned[axisKey] = name
            } else if let items = visibility as? [Any] {
                let parsed = parseAxisMarks(items, key: axisKey, axisType: axisType, logger: logger)
                spec.marks = parsed.specs
                cleaned[axisKey] = parsed.cleaned
            } else {
                logger?.log("Chart: \(axisKey) must be \"automatic\", \"visible\", \"hidden\" or an array of AxisMarks; ignoring it", .warning)
            }
        }
        let labelKey = "chart\(axis)AxisLabel"
        if let label = description[labelKey] {
            if let text = label as? String {
                spec.label = text
                cleaned[labelKey] = text
            } else if let object = label as? [String: Any], let text = object["text"] as? String {
                spec.label = text
                var cleanedLabel: [String: Any] = ["text": text]
                if let position = object["position"] as? String, let parsed = parsePosition(position) {
                    spec.labelPosition = parsed
                    cleanedLabel["position"] = position
                }
                if let alignment = object["alignment"] as? String, let parsed = parseAlignment(alignment) {
                    spec.labelAlignment = parsed
                    cleanedLabel["alignment"] = alignment
                }
                if let spacing = object["spacing"] as? NSNumber, CFGetTypeID(spacing) != CFBooleanGetTypeID() {
                    spec.labelSpacing = CGFloat(spacing.doubleValue)
                    cleanedLabel["spacing"] = spacing
                }
                for key in object.keys where cleanedLabel[key] == nil {
                    logger?.log("Chart: '\(key)' in \(labelKey) is not supported or not valid; ignoring it", .warning)
                }
                cleaned[labelKey] = cleanedLabel
            } else {
                logger?.log("Chart: \(labelKey) must be a string or {\"text\", \"position\", \"alignment\", \"spacing\"}; ignoring it", .warning)
            }
        }
        return spec
    }

    // MARK: - Style scales

    private static func parseStyleScales(_ content: [ChartEntry], description: [String: Any], cleaned: inout [String: Any],
                                         logger: (any ActionUILogger)?) -> ChartStyleScales {
        var styles = ChartStyleScales()

        // Each scale is {"domain", "range"}; the domain is typed by its channel's by-values.
        // `parseRange` returns nil for an invalid range, which is reported here.
        func scale<Range>(_ key: String, byType: ChartColumnType?, rangeForms: String,
                          parseRange: (Any) -> Range?) -> (domain: ForwardingDomain?, range: Range?) {
            guard let raw = description[key] else { return (nil, nil) }
            guard let object = raw as? [String: Any] else {
                logger?.log("Chart: \(key) must be an object with 'domain' and/or 'range'; ignoring it", .warning)
                return (nil, nil)
            }
            var cleanedScale: [String: Any] = [:]
            var domain: ForwardingDomain?
            var range: Range?
            if let rawDomain = object["domain"] {
                if let parsed = parseDomain(rawDomain, axisType: byType) {
                    domain = parsed
                    cleanedScale["domain"] = rawDomain
                } else {
                    logger?.log("Chart: \(key).domain must be two numbers or two dates (a range), a list of strings, or {\"automatic\": {...}}, typed by the {\"by\"} values it styles; ignoring it", .warning)
                }
            }
            if let rawRange = object["range"] {
                if let parsed = parseRange(rawRange) {
                    range = parsed
                    cleanedScale["range"] = rawRange
                } else {
                    logger?.log("Chart: \(key).range must be \(rangeForms); ignoring it", .warning)
                }
            }
            for name in object.keys where name != "domain" && name != "range" {
                logger?.log("Chart: '\(name)' in \(key) is not supported; ignoring it", .warning)
            }
            cleaned[key] = cleanedScale
            return (domain, range)
        }
        // A non-empty list whose items all parse.
        func list<T>(_ raw: Any, _ item: (Any) -> T?) -> [T]? {
            guard let items = raw as? [Any], !items.isEmpty else { return nil }
            let parsed = items.compactMap(item)
            return parsed.count == items.count ? parsed : nil
        }
        func color(_ raw: Any) -> SwiftUI.Color? { (raw as? String).flatMap(ColorHelper.resolveColor) }

        let foreground = scale("chartForegroundStyleScale", byType: styleType(content) { modifier in
            if case .foregroundStyleBy(let value) = modifier { return value } else { return nil }
        }, rangeForms: "a list of colors or {\"gradient\": [colors]}") { raw -> ForwardingColorRange? in
            if let object = raw as? [String: Any], object.count == 1, let stops = object["gradient"] {
                return list(stops, color).map { ForwardingColorRange(.gradient(Gradient(colors: $0))) }
            }
            return list(raw, color).map { ForwardingColorRange(.colors($0)) }
        }
        styles.foregroundDomain = foreground.domain ?? .automatic
        styles.foregroundRange = foreground.range

        let symbol = scale("chartSymbolScale", byType: styleType(content) { modifier in
            if case .symbolBy(let value) = modifier { return value } else { return nil }
        }, rangeForms: "a list of circle, square, triangle, diamond, pentagon, plus, cross or asterisk") { raw in
            list(raw) { ($0 as? String).flatMap(parseSymbol) }
        }
        styles.symbolDomain = symbol.domain ?? .automatic
        styles.symbolRange = symbol.range ?? []

        let lineStyle = scale("chartLineStyleScale", byType: styleType(content) { modifier in
            if case .lineStyleBy(let value) = modifier { return value } else { return nil }
        }, rangeForms: "a list of stroke styles {\"lineWidth\", \"lineCap\", \"lineJoin\", \"miterLimit\", \"dash\", \"dashPhase\"}") { raw in
            list(raw) { ($0 as? [String: Any]).flatMap(parseStrokeStyle) }
        }
        styles.lineStyleDomain = lineStyle.domain ?? .automatic
        styles.lineStyleRange = lineStyle.range ?? []

        // Two numbers, smallest and largest symbol area. (An empty list of sizes stops the app
        // inside Swift Charts, so sizes are a range, not a list.)
        let symbolSize = scale("chartSymbolSizeScale", byType: styleType(content) { modifier in
            if case .symbolSizeBy(let value) = modifier { return value } else { return nil }
        }, rangeForms: "two numbers 0 or more, the smallest and largest symbol area") { raw -> ClosedRange<CGFloat>? in
            guard let items = raw as? [Any], items.count == 2, let low = items[0] as? NSNumber, let high = items[1] as? NSNumber,
                  CFGetTypeID(low) != CFBooleanGetTypeID(), CFGetTypeID(high) != CFBooleanGetTypeID(),
                  low.doubleValue >= 0, low.doubleValue <= high.doubleValue else { return nil }
            return CGFloat(low.doubleValue)...CGFloat(high.doubleValue)
        }
        styles.symbolSizeDomain = symbolSize.domain ?? .automatic
        styles.symbolSizeRange = symbolSize.range
        return styles
    }

    private static func parseRange(_ value: Any) -> ForwardingPositionRange? {
        if let object = value as? [String: Any] {
            if object.count == 1, let padding = object["padding"] as? NSNumber {
                return ForwardingPositionRange(.plotDimension(startPadding: CGFloat(padding.doubleValue), endPadding: CGFloat(padding.doubleValue)))
            }
            let keys = Set(object.keys)
            guard !keys.isEmpty, keys.isSubset(of: ["startPadding", "endPadding"]) else { return nil }
            let start = (object["startPadding"] as? NSNumber)?.doubleValue
            let end = (object["endPadding"] as? NSNumber)?.doubleValue
            if (object["startPadding"] != nil && start == nil) || (object["endPadding"] != nil && end == nil) { return nil }
            return ForwardingPositionRange(.plotDimension(startPadding: CGFloat(start ?? 0), endPadding: CGFloat(end ?? 0)))
        }
        if let items = value as? [Any], items.count == 2, let low = items[0] as? NSNumber, let high = items[1] as? NSNumber,
           low.doubleValue <= high.doubleValue {
            return ForwardingPositionRange(.points(CGFloat(low.doubleValue)...CGFloat(high.doubleValue)))
        }
        return nil
    }

    private static func parseScaleType(_ value: Any) -> ScaleType? {
        if let name = value as? String {
            switch name {
            case "linear": return .linear
            case "log": return .log
            case "date": return .date
            case "category": return .category
            case "squareRoot": return .squareRoot
            case "symmetricLog": return .symmetricLog
            default: return nil
            }
        }
        if let object = value as? [String: Any], object.count == 1 {
            if let power = object["power"] as? [String: Any], let exponent = power["exponent"] as? NSNumber {
                return .power(exponent: exponent.doubleValue)
            }
            if let log = object["symmetricLog"] as? [String: Any], let slope = log["slopeAtZero"] as? NSNumber {
                return .symmetricLog(slopeAtZero: slope.doubleValue)
            }
        }
        return nil
    }

    // Swift Charts stops the app (a fatal error) for some scale types on a number or date axis:
    // "date" and "category" always, and log, squareRoot or power whenever a plotted value, a
    // bar's zero baseline included, is outside the type's domain (measured on macOS 27). An
    // explicit domain clamps the values, so those three need one that is inside their domain.
    // A string axis, or an axis that plots no values, takes any type unharmed.
    private static func scaleTypeProblem(_ raw: Any, axisType: ChartColumnType?, domain: ForwardingDomain) -> String? {
        guard let axisType, family(axisType) != .string else { return nil }
        let name = (raw as? String) ?? (raw as? [String: Any])?.keys.first ?? ""
        switch name {
        case "date", "category":
            return "\(name) does not apply to an axis of \(axisType.rawValue) values"
        case "log", "squareRoot", "power":
            if family(axisType) == .date {
                return "\(name) does not apply to an axis of dates"
            }
            // A power of 0 always fails; a negative power, like log, fails at 0.
            let exponent = (((raw as? [String: Any])?["power"] as? [String: Any])?["exponent"] as? NSNumber)?.doubleValue ?? 1
            if exponent == 0 {
                return "power needs a nonzero exponent"
            }
            let aboveZero = name == "log" || exponent < 0
            let inside: (Double) -> Bool = aboveZero ? { $0 > 0 } : { $0 >= 0 }
            guard case .numbers(let range) = domain.kind, inside(range.lowerBound) else {
                return "\(name) needs a 'domain' of two numbers whose low end is \(aboveZero ? "above 0" : "0 or more")"
            }
            return nil
        default:
            return nil
        }
    }

    static func parseAlignment(_ name: String) -> Alignment? {
        switch name {
        case "center": return .center
        case "leading": return .leading
        case "trailing": return .trailing
        case "top": return .top
        case "bottom": return .bottom
        case "topLeading": return .topLeading
        case "topTrailing": return .topTrailing
        case "bottomLeading": return .bottomLeading
        case "bottomTrailing": return .bottomTrailing
        default: return nil
        }
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

    static func parsePosition(_ name: String) -> AnnotationPosition? {
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

    static func calendarComponent(_ name: String) -> Calendar.Component? {
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

    static func isIdentifier(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, first == "_" || (first.isASCII && CharacterSet.letters.contains(first)) else { return false }
        return name.unicodeScalars.allSatisfy { $0 == "_" || ($0.isASCII && CharacterSet.alphanumerics.contains($0)) }
    }

    // "$N" (1-based) or "$name"; nil when it is neither or names no column.
    static func columnIndex(_ reference: String, columns: [Column]) -> Int? {
        guard reference.hasPrefix("$") else { return nil }
        let body = String(reference.dropFirst())
        if let number = Int(body), body.allSatisfy(\.isASCII) {
            // A positional reference may go past the declared columns: rows can be wider.
            return number >= 1 ? number - 1 : nil
        }
        return columns.firstIndex { $0.name == body }
    }

    static func isReferenceShaped(_ string: String) -> Bool {
        guard string.hasPrefix("$"), string.count > 1 else { return false }
        return isIdentifier(String(string.dropFirst())) || Int(string.dropFirst()) != nil
    }
}
