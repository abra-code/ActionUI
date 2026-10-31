// Helpers/ChartAxisMarks.swift
//
// Axis content of the Chart element: chartXAxis / chartYAxis as an array of AxisMarks dicts (see
// Views/Chart.swift). Axis builders have no ForEach and cannot combine a list of erased items, so
// items and AxisMarks are erased (AnyAxisMark, AnyAxisContent) and combined by fixed-arity
// switches, up to four of each.

import Foundation
import SwiftUI
import Charts

// A label format. Number formats take TextField's convention ("integer", "decimal", "percent",
// "currency" with "fractionLength" and "currencyCode"); dates mirror Date.FormatStyle.
enum ChartAxisFormat {
    case number(NumberFormatSpec)
    case date(ChartDateFormat)
}

enum ChartAxisValues {
    case automatic(desiredCount: Int?, roundLowerBound: Bool?, roundUpperBound: Bool?)
    case calendarStride(Calendar.Component, count: Int)
    case numberStride(Double)
    // Explicit values, typed by the axis. Numbers are Double on number and integer axes alike:
    // Swift Charts places Double values on an Int axis exactly where Int values go.
    case numbers([Double])
    case dates([Date])
    case strings([String])
}

struct ChartAxisMarkItem {
    enum TickLength {
        case automatic, fixed(Double), label(Double), longestLabel(Double)
    }
    enum Kind {
        case gridLine(centered: Bool?, stroke: ChartStroke?)
        case tick(centered: Bool?, length: TickLength, stroke: ChartStroke?)
        case valueLabel(format: ChartAxisFormat?, centered: Bool?, anchor: ChartAlignment?, multiLabelAlignment: ChartAlignment?,
                        collisionResolution: ChartCollisionResolution, offsetsMarks: Bool?,
                        orientation: ChartLabelOrientation, horizontalSpacing: Double?, verticalSpacing: Double?)
    }
    let kind: Kind
    var foregroundStyle: ColorSpec?
    var font: FontSpec?
    var offset: ChartSize?
}

struct ChartAxisMarksSpec {
    var preset = ChartAxisPreset.automatic
    var position = ChartAxisMarkPosition.automatic
    var values: ChartAxisValues = .automatic(desiredCount: nil, roundLowerBound: nil, roundUpperBound: nil)
    // Only without `items` (AxisMarks(format:stroke:) keeps Swift's default marks).
    var format: ChartAxisFormat?
    var stroke: ChartStroke?
    // nil: Swift's default marks. Empty: no marks at all.
    var items: [ChartAxisMarkItem]?
}

// MARK: - Parsing

extension ChartDescription {
    static let maxAxisMarks = 4
    // Swift Charts lays out as many marks as asked; a huge count stalls the main thread.
    static let maxDesiredCount = 100

    /// Parses chartXAxis / chartYAxis given as an array of AxisMarks dicts; returns the specs and
    /// the cleaned array.
    static func parseAxisMarks(_ items: [Any], key: String, axisType: ChartColumnType?,
                               logger: (any ActionUILogger)?) -> (specs: [ChartAxisMarksSpec], cleaned: [Any]) {
        var specs: [ChartAxisMarksSpec] = []
        var cleaned: [Any] = []
        for (index, item) in items.enumerated() {
            let role = "\(key)[\(index)]"
            guard let object = item as? [String: Any], object["type"] as? String == "AxisMarks" else {
                logger?.log("Chart: \(role) must be {\"type\": \"AxisMarks\", ...}; ignoring it", .warning)
                continue
            }
            guard specs.count < maxAxisMarks else {
                logger?.log("Chart: \(key) takes at most \(maxAxisMarks) AxisMarks; ignoring \(role)", .warning)
                continue
            }
            let parsed = parseOneAxisMarks(object, role: role, axisType: axisType, logger: logger)
            specs.append(parsed.spec)
            cleaned.append(parsed.cleaned)
        }
        return (specs, cleaned)
    }

    private static func parseOneAxisMarks(_ object: [String: Any], role: String, axisType: ChartColumnType?,
                                          logger: (any ActionUILogger)?) -> (spec: ChartAxisMarksSpec, cleaned: [String: Any]) {
        var spec = ChartAxisMarksSpec()
        var cleaned: [String: Any] = ["type": "AxisMarks"]
        let known: Set<String> = ["type", "preset", "position", "values", "format", "fractionLength", "currencyCode", "stroke", "content"]
        for key in object.keys where !known.contains(key) {
            logger?.log("Chart: '\(key)' is not supported on AxisMarks (\(role)); ignoring it", .warning)
        }
        func invalid(_ key: String, _ expected: String) {
            logger?.log("Chart: \(role).\(key) must be \(expected); ignoring it", .warning)
        }

        if let raw = object["preset"] {
            if let preset = (raw as? String).flatMap(ChartAxisPreset.init(rawValue:)) { spec.preset = preset; cleaned["preset"] = raw } else { invalid("preset", "automatic, extended, aligned or inset") }
        }
        if let raw = object["position"] {
            if let position = (raw as? String).flatMap(ChartAxisMarkPosition.init(rawValue:)) { spec.position = position; cleaned["position"] = raw } else { invalid("position", "automatic, leading, trailing, top or bottom") }
        }
        if let raw = object["values"] {
            if let values = parseAxisValues(raw, axisType: axisType) {
                spec.values = values
                cleaned["values"] = raw
            } else {
                invalid("values", "\"automatic\", {\"automatic\": {\"desiredCount\" (1 to 100), \"roundLowerBound\", \"roundUpperBound\"}}, {\"stride\": {\"by\": a calendar unit (dates) or a step above 0 (numbers), \"count\"}}, or a list of values typed by the axis")
            }
        }

        let content = object["content"]
        if object["format"] != nil {
            if content != nil {
                logger?.log("Chart: \(role).format applies only without 'content' (give the AxisValueLabel a format); ignoring it", .warning)
            } else if let format = parseAxisFormat(object, role: role, axisType: axisType, logger: logger) {
                spec.format = format.value
                cleaned.merge(format.cleaned) { $1 }
            }
        } else {
            for key in ["fractionLength", "currencyCode"] where object[key] != nil {
                logger?.log("Chart: \(role).\(key) applies only with a number 'format'; ignoring it", .warning)
            }
        }
        if let raw = object["stroke"] {
            if content != nil {
                logger?.log("Chart: \(role).stroke applies only without 'content' (give the marks a stroke); ignoring it", .warning)
            } else if let stroke = (raw as? [String: Any]).flatMap(parseStrokeStyle) {
                spec.stroke = stroke
                cleaned["stroke"] = raw
            } else {
                invalid("stroke", "a stroke style {\"lineWidth\", \"lineCap\", \"lineJoin\", \"miterLimit\", \"dash\", \"dashPhase\"}")
            }
        }

        if let content {
            guard let entries = content as? [Any] else {
                invalid("content", "an array of AxisGridLine, AxisTick and AxisValueLabel entries")
                return (spec, cleaned)
            }
            var items: [ChartAxisMarkItem] = []
            var cleanedItems: [Any] = []
            for (index, entry) in entries.enumerated() {
                let itemRole = "\(role).content[\(index)]"
                guard items.count < maxAxisMarks else {
                    logger?.log("Chart: an AxisMarks takes at most \(maxAxisMarks) content entries; ignoring \(itemRole)", .warning)
                    continue
                }
                if let parsed = parseAxisMarkItem(entry, role: itemRole, axisType: axisType, logger: logger) {
                    items.append(parsed.item)
                    cleanedItems.append(parsed.cleaned)
                }
            }
            spec.items = items
            cleaned["content"] = cleanedItems
        }
        return (spec, cleaned)
    }

    private static func parseAxisMarkItem(_ entry: Any, role: String, axisType: ChartColumnType?,
                                          logger: (any ActionUILogger)?) -> (item: ChartAxisMarkItem, cleaned: [String: Any])? {
        guard let object = entry as? [String: Any], let type = object["type"] as? String,
              ["AxisGridLine", "AxisTick", "AxisValueLabel"].contains(type) else {
            logger?.log("Chart: \(role) must be an AxisGridLine, AxisTick or AxisValueLabel entry; ignoring it", .warning)
            return nil
        }
        var cleaned: [String: Any] = ["type": type]
        func invalid(_ key: String, _ expected: String) {
            logger?.log("Chart: \(role).\(key) must be \(expected); ignoring it", .warning)
        }
        func number(_ key: String) -> Double? {
            guard let raw = object[key] else { return nil }
            guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else {
                invalid(key, "a number")
                return nil
            }
            cleaned[key] = raw
            return value.doubleValue
        }
        func flag(_ key: String) -> Bool? {
            guard let raw = object[key] else { return nil }
            guard let value = raw as? Bool else {
                invalid(key, "true or false")
                return nil
            }
            cleaned[key] = value
            return value
        }
        func stroke() -> ChartStroke? {
            guard let raw = object["stroke"] else { return nil }
            guard let style = (raw as? [String: Any]).flatMap(parseStrokeStyle) else {
                invalid("stroke", "a stroke style {\"lineWidth\", \"lineCap\", \"lineJoin\", \"miterLimit\", \"dash\", \"dashPhase\"}")
                return nil
            }
            cleaned["stroke"] = raw
            return style
        }

        let common: Set<String> = ["type", "foregroundStyle", "font", "offset"]
        let own: Set<String>
        let kind: ChartAxisMarkItem.Kind
        switch type {
        case "AxisGridLine":
            own = ["centered", "stroke"]
            kind = .gridLine(centered: flag("centered"), stroke: stroke())
        case "AxisTick":
            own = ["centered", "length", "stroke"]
            var length = ChartAxisMarkItem.TickLength.automatic
            if let raw = object["length"] {
                if let parsed = parseTickLength(raw) {
                    length = parsed
                    cleaned["length"] = raw
                } else {
                    invalid("length", "a number, \"automatic\", \"label\", \"longestLabel\", {\"label\": {\"extendPastBy\"}} or {\"longestLabel\": {\"extendPastBy\"}}")
                }
            }
            kind = .tick(centered: flag("centered"), length: length, stroke: stroke())
        default: // AxisValueLabel
            own = ["format", "fractionLength", "currencyCode", "centered", "anchor", "multiLabelAlignment", "collisionResolution",
                   "offsetsMarks", "orientation", "horizontalSpacing", "verticalSpacing"]
            var format: ChartAxisFormat?
            if object["format"] != nil {
                if let parsed = parseAxisFormat(object, role: role, axisType: axisType, logger: logger) {
                    format = parsed.value
                    cleaned.merge(parsed.cleaned) { $1 }
                }
            } else {
                for key in ["fractionLength", "currencyCode"] where object[key] != nil {
                    logger?.log("Chart: \(role).\(key) applies only with a number 'format'; ignoring it", .warning)
                }
            }
            var anchor: ChartAlignment?
            if let raw = object["anchor"] {
                // Swift Charts supports only the named points here.
                anchor = (raw as? String).flatMap(ChartAlignment.init(rawValue:))
                if anchor != nil { cleaned["anchor"] = raw } else { invalid("anchor", "center, leading, trailing, top, bottom, topLeading, topTrailing, bottomLeading or bottomTrailing") }
            }
            var alignment: ChartAlignment?
            if let raw = object["multiLabelAlignment"] {
                alignment = (raw as? String).flatMap(ChartAlignment.init(rawValue:))
                if alignment != nil { cleaned["multiLabelAlignment"] = raw } else { invalid("multiLabelAlignment", "an alignment such as leading or center") }
            }
            var collision = ChartCollisionResolution.automatic
            if let raw = object["collisionResolution"] {
                if let parsed = parseCollisionResolution(raw) {
                    collision = parsed
                    cleaned["collisionResolution"] = raw
                } else {
                    invalid("collisionResolution", "automatic, greedy, truncate, disabled or {\"greedy\": {\"priority\", \"minimumSpacing\"}}")
                }
            }
            var orientation = ChartLabelOrientation.automatic
            if let raw = object["orientation"] {
                if let parsed = (raw as? String).flatMap(ChartLabelOrientation.init(rawValue:)) { orientation = parsed; cleaned["orientation"] = raw } else { invalid("orientation", "automatic, horizontal, vertical or verticalReversed") }
            }
            kind = .valueLabel(format: format, centered: flag("centered"), anchor: anchor, multiLabelAlignment: alignment,
                               collisionResolution: collision, offsetsMarks: flag("offsetsMarks"), orientation: orientation,
                               horizontalSpacing: number("horizontalSpacing"), verticalSpacing: number("verticalSpacing"))
        }
        for key in object.keys where !common.contains(key) && !own.contains(key) {
            logger?.log("Chart: '\(key)' is not supported on \(type) (\(role)); ignoring it", .warning)
        }

        var item = ChartAxisMarkItem(kind: kind)
        if let raw = object["foregroundStyle"] {
            if let color = ColorSpec.parse(raw as? String) {
                item.foregroundStyle = color
                cleaned["foregroundStyle"] = raw
            } else {
                invalid("foregroundStyle", "a color")
            }
        }
        if let raw = object["font"] {
            // A font FontSpec complains about is dropped whole, so the cleaned dict re-parses
            // without a warning.
            let fontProblems = ChartFontProblemLogger()
            let font = raw is String || raw is [String: Any] ? FontSpec.parse(raw, logger: fontProblems) : nil
            if let font, fontProblems.messages.isEmpty {
                item.font = font
                cleaned["font"] = raw
            } else {
                let detail = fontProblems.messages.isEmpty ? "" : " (\(fontProblems.messages.joined(separator: "; ")))"
                invalid("font", "a text style or font name, or {\"name\", \"size\", \"weight\", \"design\"}\(detail)")
            }
        }
        if let raw = object["offset"] {
            let offset = raw as? [String: Any]
            let keys = Set(offset?.keys.map { $0 } ?? [])
            let x = plainNumber(offset?["x"]), y = plainNumber(offset?["y"])
            if let offset, !keys.isEmpty, keys.isSubset(of: ["x", "y"]), offset["x"] == nil || x != nil, offset["y"] == nil || y != nil {
                item.offset = ChartSize(width: x?.doubleValue ?? 0, height: y?.doubleValue ?? 0)
                cleaned["offset"] = raw
            } else {
                invalid("offset", "{\"x\", \"y\"} (numbers)")
            }
        }
        return (item, cleaned)
    }

    // The format keys of an AxisMarks or AxisValueLabel dict, checked against the axis type.
    private static func parseAxisFormat(_ object: [String: Any], role: String, axisType: ChartColumnType?,
                                        logger: (any ActionUILogger)?) -> (value: ChartAxisFormat, cleaned: [String: Any])? {
        let raw = object["format"]
        if let name = raw as? String {
            guard ["integer", "decimal", "percent", "currency"].contains(name), NumberFormatSpec.resolve(from: object) != nil else {
                logger?.log("Chart: \(role).format must be integer, decimal, percent or currency, or a date format object; ignoring it", .warning)
                return nil
            }
            guard axisType == .number || axisType == .integer else {
                logger?.log("Chart: \(role).format '\(name)' formats numbers, but the axis plots \(axisType?.rawValue ?? "no values"); ignoring it", .warning)
                return nil
            }
            var cleaned: [String: Any] = ["format": name]
            if let fractionLength = object["fractionLength"] {
                let valid = wholeNumber(fractionLength).map { $0 >= 0 } ?? (fractionLength as? [String: Any]).map { range in
                    Set(range.keys).isSubset(of: ["min", "max"]) && !range.isEmpty && range.values.allSatisfy { wholeNumber($0).map { $0 >= 0 } ?? false }
                } ?? false
                if valid { cleaned["fractionLength"] = fractionLength } else {
                    logger?.log("Chart: \(role).fractionLength must be a whole number or {\"min\", \"max\"}; ignoring it", .warning)
                }
            }
            if let code = object["currencyCode"] {
                if name == "currency", code is String { cleaned["currencyCode"] = code } else {
                    logger?.log("Chart: \(role).currencyCode applies to a currency format and must be text; ignoring it", .warning)
                }
            }
            // Re-resolve from the accepted keys only, so an ignored key changes nothing.
            return NumberFormatSpec.resolve(from: cleaned).map { (.number($0), cleaned) }
        }
        guard let dateFormat = raw as? [String: Any], let format = parseDateFormat(dateFormat) else {
            logger?.log("Chart: \(role).format must be integer, decimal, percent or currency, {\"dateTime\": {...}} or {\"date\", \"time\"}; ignoring it", .warning)
            return nil
        }
        guard axisType == .date else {
            logger?.log("Chart: \(role).format formats dates, but the axis plots \(axisType?.rawValue ?? "no values"); ignoring it", .warning)
            return nil
        }
        // The number-format keys sit beside "format", in the AxisMarks or AxisValueLabel dict.
        for key in ["fractionLength", "currencyCode"] where object[key] != nil {
            logger?.log("Chart: \(role).\(key) applies only with a number format; ignoring it", .warning)
        }
        return (.date(format), ["format": dateFormat])
    }

    // {"dateTime": {"year": ..., "month": ...}} or {"date": style, "time": style}; every key must be valid.
    static func parseDateFormat(_ object: [String: Any]) -> ChartDateFormat? {
        if object.count == 1, let fields = object["dateTime"] as? [String: Any], !fields.isEmpty {
            var parsed: [ChartDateField] = []
            for (field, raw) in fields {
                guard let name = raw as? String, let dateField = ChartDateField(rawValue: "\(field).\(name)") else { return nil }
                parsed.append(dateField)
            }
            // Sorted: a dictionary's order must not make two equal descriptions differ.
            return .fields(parsed.sorted { $0.rawValue < $1.rawValue })
        }
        let keys = Set(object.keys)
        guard !keys.isEmpty, keys.isSubset(of: ["date", "time"]) else { return nil }
        var date = ChartDateStyle.omitted
        var time = ChartTimeStyle.omitted
        if let raw = object["date"] {
            guard let style = (raw as? String).flatMap(ChartDateStyle.init(rawValue:)) else { return nil }
            date = style
        }
        if let raw = object["time"] {
            guard let style = (raw as? String).flatMap(ChartTimeStyle.init(rawValue:)) else { return nil }
            time = style
        }
        return .styles(date: date, time: time)
    }

    private static func parseAxisValues(_ raw: Any, axisType: ChartColumnType?) -> ChartAxisValues? {
        if raw as? String == "automatic" {
            return .automatic(desiredCount: nil, roundLowerBound: nil, roundUpperBound: nil)
        }
        if let object = raw as? [String: Any], object.count == 1 {
            if let automatic = object["automatic"] as? [String: Any] {
                guard Set(automatic.keys).isSubset(of: ["desiredCount", "roundLowerBound", "roundUpperBound"]) else { return nil }
                let count = automatic["desiredCount"]
                if count != nil, wholeNumber(count).map({ $0 > 0 && $0 <= maxDesiredCount }) != true { return nil }
                for key in ["roundLowerBound", "roundUpperBound"] where automatic[key] != nil && !(automatic[key] is Bool) { return nil }
                return .automatic(desiredCount: wholeNumber(count), roundLowerBound: automatic["roundLowerBound"] as? Bool,
                                  roundUpperBound: automatic["roundUpperBound"] as? Bool)
            }
            if let stride = object["stride"] as? [String: Any], let by = stride["by"] {
                if let unit = (by as? String).flatMap(calendarComponent) {
                    guard axisType == .date, Set(stride.keys).isSubset(of: ["by", "count"]) else { return nil }
                    let count = stride["count"]
                    if count != nil, wholeNumber(count).map({ $0 > 0 }) != true { return nil }
                    return .calendarStride(unit, count: wholeNumber(count) ?? 1)
                }
                if let step = by as? NSNumber, CFGetTypeID(step) != CFBooleanGetTypeID(), step.doubleValue > 0,
                   axisType == .number || axisType == .integer, stride.count == 1 {
                    return .numberStride(step.doubleValue)
                }
            }
            return nil
        }
        guard let items = raw as? [Any], !items.isEmpty else { return nil }
        switch axisType {
        case .number, .integer:
            let numbers = items.compactMap { item -> Double? in
                guard let value = item as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
                return value.doubleValue
            }
            return numbers.count == items.count ? .numbers(numbers) : nil
        case .date:
            let dates = items.compactMap { ($0 as? String).flatMap { DateHelper.parseDate(from: $0) } }
            return dates.count == items.count ? .dates(dates) : nil
        case .string:
            let strings = items.compactMap { $0 as? String }
            return strings.count == items.count ? .strings(strings) : nil
        case nil:
            return nil
        }
    }

    private static func parseTickLength(_ raw: Any) -> ChartAxisMarkItem.TickLength? {
        if let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue >= 0 {
            return .fixed(value.doubleValue)
        }
        switch raw as? String {
        case "automatic": return .automatic
        case "label": return .label(0)
        case "longestLabel": return .longestLabel(0)
        default: break
        }
        guard let object = raw as? [String: Any], object.count == 1, let key = object.keys.first,
              key == "label" || key == "longestLabel", let options = object[key] as? [String: Any], options.count == 1,
              let extend = options["extendPastBy"] as? NSNumber, CFGetTypeID(extend) != CFBooleanGetTypeID() else { return nil }
        let points = extend.doubleValue
        return key == "label" ? .label(points) : .longestLabel(points)
    }

    private static func parseCollisionResolution(_ raw: Any) -> ChartCollisionResolution? {
        switch raw as? String {
        case "automatic": return .automatic
        case "greedy": return .greedy(priority: nil, minimumSpacing: nil)
        case "truncate": return .truncate
        case "disabled": return .disabled
        default: break
        }
        guard let object = raw as? [String: Any], object.count == 1, let options = object["greedy"] as? [String: Any],
              Set(options.keys).isSubset(of: ["priority", "minimumSpacing"]) else { return nil }
        let priority = plainNumber(options["priority"]), spacing = plainNumber(options["minimumSpacing"])
        if (options["priority"] != nil && priority == nil) || (options["minimumSpacing"] != nil && spacing == nil) { return nil }
        return .greedy(priority: priority?.doubleValue ?? 0, minimumSpacing: spacing?.doubleValue)
    }

    // A JSON number that is not a boolean: JSON true and false arrive as NSNumber and convert to
    // Int and Double, but the verifier reports them as booleans.
    private static func plainNumber(_ raw: Any?) -> NSNumber? {
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        return value
    }

    private static func wholeNumber(_ raw: Any?) -> Int? {
        plainNumber(raw) == nil ? nil : raw as? Int
    }
}

// Collects FontSpec's warnings about one font value.
private final class ChartFontProblemLogger: ActionUILogger, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var messages: [String] { lock.withLock { recorded } }
    func log(_ message: String, _ level: LoggerLevel) {
        guard level == .warning || level == .error else { return }
        lock.withLock { recorded.append(message) }
    }
}

// MARK: - Stride limit

// Swift Charts lays out every mark a stride asks for: a step of 0.0000001 over 0...900, or a
// one-second stride over months, keeps the main thread busy for minutes. A stride is checked
// against the axis span (the explicit domain, else the plotted values, with 0 for numbers unless
// the automatic domain excludes it, and 0...1 for a normalized stack) whenever the marks are built, and one that would draw more
// than `maxStrideMarks` marks falls back to automatic values with a warning.
enum ChartAxisStrideLimit {
    static let maxStrideMarks = 1000

    /// `extent` is what the marks plot on the axis (dates as seconds since the reference date).
    static func limited(_ specs: [ChartAxisMarksSpec]?, domain: ChartDomain, extent: ClosedRange<Double>?,
                        key: String, viewID: Int, logger: any ActionUILogger) -> [ChartAxisMarksSpec]? {
        guard var specs else { return nil }
        for index in specs.indices {
            let span: Double?
            let stepSeconds: Double
            switch specs[index].values {
            case .numberStride(let step):
                stepSeconds = step
                span = self.span(domain, extent: extent, dates: false)
            case .calendarStride(let unit, let count):
                stepSeconds = approximateSeconds(unit) * Double(count)
                span = self.span(domain, extent: extent, dates: true)
            default:
                continue
            }
            guard let span, stepSeconds > 0, span / stepSeconds > Double(maxStrideMarks) else { continue }
            logger.log("Chart \(viewID): \(key)[\(index)] values stride would draw about \(Int(min(span / stepSeconds, 1e15))) marks (at most \(maxStrideMarks)); using automatic values", .warning)
            specs[index].values = .automatic(desiredCount: nil, roundLowerBound: nil, roundUpperBound: nil)
        }
        return specs
    }

    /// The axis span in the axis's unit (dates in seconds), as described above; also bounds a
    /// scrolling axis's visible length (ChartVisibleLengthLimit).
    static func span(_ domain: ChartDomain, extent: ClosedRange<Double>?, dates: Bool) -> Double? {
        if dates {
            if case .dates(let range) = domain {
                return range.upperBound.timeIntervalSince(range.lowerBound)
            }
            return extent.map { $0.upperBound - $0.lowerBound }
        }
        switch domain {
        case .numbers(let range):
            return range.upperBound - range.lowerBound
        case .automatic(let includesZero, _) where includesZero == false:
            return extent.map { $0.upperBound - $0.lowerBound }
        default:
            return extent.map { max($0.upperBound, 0) - min($0.lowerBound, 0) }
        }
    }

    // The shortest length of a unit, so the estimate never undercounts.
    private static func approximateSeconds(_ unit: Calendar.Component) -> Double {
        switch unit {
        case .year: return 365 * 86400
        case .quarter: return 89 * 86400
        case .month: return 28 * 86400
        case .weekOfYear, .weekOfMonth: return 7 * 86400
        case .day: return 86400
        case .hour: return 3600
        case .minute: return 60
        default: return 1
        }
    }
}

// MARK: - Building

@MainActor
enum ChartAxisContentBuilder {
    /// The axis content for chartXAxis / chartYAxis { }. nil is a plain AxisMarks(), which draws
    /// exactly like no axis content.
    static func content(_ specs: [ChartAxisMarksSpec]?) -> AnyAxisContent {
        guard let specs, !specs.isEmpty else {
            return AnyAxisContent(erasing: AxisMarks())
        }
        let c = specs.prefix(ChartDescription.maxAxisMarks).map(axisMarks)
        switch c.count {
        case 1: return c[0]
        case 2: return AnyAxisContent(erasing: pair(c[0], c[1]))
        case 3: return AnyAxisContent(erasing: triple(c[0], c[1], c[2]))
        default: return AnyAxisContent(erasing: quad(c[0], c[1], c[2], c[3]))
        }
    }

    @AxisContentBuilder
    private static func pair(_ a: AnyAxisContent, _ b: AnyAxisContent) -> some AxisContent {
        a
        b
    }

    @AxisContentBuilder
    private static func triple(_ a: AnyAxisContent, _ b: AnyAxisContent, _ c: AnyAxisContent) -> some AxisContent {
        a
        b
        c
    }

    @AxisContentBuilder
    private static func quad(_ a: AnyAxisContent, _ b: AnyAxisContent, _ c: AnyAxisContent, _ d: AnyAxisContent) -> some AxisContent {
        a
        b
        c
        d
    }

    private static func axisMarks(_ spec: ChartAxisMarksSpec) -> AnyAxisContent {
        guard let items = spec.items else {
            return defaultMarks(spec)
        }
        let m = items.prefix(ChartDescription.maxAxisMarks).map(mark)
        let preset = spec.preset.axisMarkPreset, position = spec.position.axisMarkPosition
        // One builder per item count; explicit values take AxisMarks' generic `values:` initializer.
        func marks(_ values: AxisMarkValues) -> AnyAxisContent {
            switch m.count {
            // AxisMark has no public way to draw nothing; an empty content is one invisible tick.
            case 0: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { AxisTick(length: 0, stroke: StrokeStyle(lineWidth: 0)) })
            case 1: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { m[0] })
            case 2: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { m[0]; m[1] })
            case 3: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { m[0]; m[1]; m[2] })
            default: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { m[0]; m[1]; m[2]; m[3] })
            }
        }
        func marks<V: Plottable>(_ values: [V]) -> AnyAxisContent {
            switch m.count {
            case 0: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { AxisTick(length: 0, stroke: StrokeStyle(lineWidth: 0)) })
            case 1: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { m[0] })
            case 2: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { m[0]; m[1] })
            case 3: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { m[0]; m[1]; m[2] })
            default: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { m[0]; m[1]; m[2]; m[3] })
            }
        }
        switch spec.values {
        case .numbers(let values): return marks(values)
        case .dates(let values): return marks(values)
        case .strings(let values): return marks(values)
        default: return marks(markValues(spec.values))
        }
    }

    // Swift's default marks, with the AxisMarks-level format and stroke.
    private static func defaultMarks(_ spec: ChartAxisMarksSpec) -> AnyAxisContent {
        let preset = spec.preset.axisMarkPreset, position = spec.position.axisMarkPosition, stroke = spec.stroke?.strokeStyle
        func formatted<F: FormatStyle>(_ format: F) -> AnyAxisContent where F.FormatInput: Plottable, F.FormatOutput == String {
            switch spec.values {
            case .numbers(let values):
                // Format input and value type must agree; a format other than a Double one is
                // only reached for date values below.
                if let values = values as? [F.FormatInput] {
                    return AnyAxisContent(erasing: AxisMarks(format: format, preset: preset, position: position, values: values, stroke: stroke))
                }
            case .dates(let values):
                if let values = values as? [F.FormatInput] {
                    return AnyAxisContent(erasing: AxisMarks(format: format, preset: preset, position: position, values: values, stroke: stroke))
                }
            case .strings:
                break
            default:
                return AnyAxisContent(erasing: AxisMarks(format: format, preset: preset, position: position, values: markValues(spec.values), stroke: stroke))
            }
            return AnyAxisContent(erasing: AxisMarks(format: format, preset: preset, position: position, stroke: stroke))
        }
        switch spec.format {
        case .number(let number):
            switch number {
            case .integer: return formatted(FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0)))
            case .decimal(let low, let high): return formatted(decimal(low, high))
            case .percent(let low, let high): return formatted(percent(low, high))
            case .currency(let code, let low, let high): return formatted(currency(code, low, high))
            }
        case .date(let format):
            return formatted(format.formatStyle)
        case nil:
            switch spec.values {
            case .numbers(let values): return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values, stroke: stroke))
            case .dates(let values): return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values, stroke: stroke))
            case .strings(let values): return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values, stroke: stroke))
            default: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: markValues(spec.values), stroke: stroke))
            }
        }
    }

    private static func markValues(_ values: ChartAxisValues) -> AxisMarkValues {
        switch values {
        case .automatic(let count, let lower, let upper):
            if count == nil, lower == nil, upper == nil { return .automatic }
            return .automatic(desiredCount: count, roundLowerBound: lower, roundUpperBound: upper)
        case .calendarStride(let unit, let count):
            return .stride(by: unit, count: count)
        case .numberStride(let step):
            return .stride(by: step)
        case .numbers, .dates, .strings:
            return .automatic // handled by the `values:` initializers
        }
    }

    private static func mark(_ item: ChartAxisMarkItem) -> AnyAxisMark {
        var mark: AnyAxisMark
        switch item.kind {
        case .gridLine(let centered, let stroke):
            mark = AnyAxisMark(erasing: AxisGridLine(centered: centered, stroke: stroke?.strokeStyle))
        case .tick(let centered, let length, let stroke):
            let style = stroke?.strokeStyle
            switch length {
            case .automatic: mark = AnyAxisMark(erasing: AxisTick(centered: centered, length: .automatic, stroke: style))
            case .fixed(let points): mark = AnyAxisMark(erasing: AxisTick(centered: centered, length: CGFloat(points), stroke: style))
            case .label(let extend): mark = AnyAxisMark(erasing: AxisTick(centered: centered, length: .label(extendPastBy: CGFloat(extend)), stroke: style))
            case .longestLabel(let extend): mark = AnyAxisMark(erasing: AxisTick(centered: centered, length: .longestLabel(extendPastBy: CGFloat(extend)), stroke: style))
            }
        case .valueLabel(let format, let centered, let anchor, let alignment, let collision, let offsetsMarks, let orientation,
                         let horizontalSpacing, let verticalSpacing):
            let unitPoint = anchor?.unitPoint, multiLabelAlignment = alignment?.alignment
            let collisionResolution = collision.collisionResolution, labelOrientation = orientation.labelOrientation
            let hSpacing = horizontalSpacing.map { CGFloat($0) }, vSpacing = verticalSpacing.map { CGFloat($0) }
            func label<F: FormatStyle>(_ format: F) -> AnyAxisMark where F.FormatInput: Plottable, F.FormatOutput == String {
                AnyAxisMark(erasing: AxisValueLabel(format: format, centered: centered, anchor: unitPoint, multiLabelAlignment: multiLabelAlignment,
                                                    collisionResolution: collisionResolution, offsetsMarks: offsetsMarks, orientation: labelOrientation,
                                                    horizontalSpacing: hSpacing, verticalSpacing: vSpacing))
            }
            switch format {
            case .number(.integer): mark = label(FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0)))
            case .number(.decimal(let low, let high)): mark = label(decimal(low, high))
            case .number(.percent(let low, let high)): mark = label(percent(low, high))
            case .number(.currency(let code, let low, let high)): mark = label(currency(code, low, high))
            case .date(let dateFormat): mark = label(dateFormat.formatStyle)
            case nil:
                mark = AnyAxisMark(erasing: AxisValueLabel(centered: centered, anchor: unitPoint, multiLabelAlignment: multiLabelAlignment,
                                                           collisionResolution: collisionResolution, offsetsMarks: offsetsMarks, orientation: labelOrientation,
                                                           horizontalSpacing: hSpacing, verticalSpacing: vSpacing))
            }
        }
        if let color = item.foregroundStyle { mark = AnyAxisMark(erasing: mark.foregroundStyle(ColorHelper.color(for: color))) }
        if let font = item.font { mark = AnyAxisMark(erasing: mark.font(FontHelper.font(for: font))) }
        if let offset = item.offset { mark = AnyAxisMark(erasing: mark.offset(offset.cgSize)) }
        return mark
    }

    // Number formats: Double styles on number and integer axes alike (Swift Charts formats an
    // Int axis value through a Double style).
    private static func precision(_ low: Int?, _ high: Int?) -> ClosedRange<Int>? {
        NumberFormatSpec.fractionRange(minFraction: low, maxFraction: high)
    }

    private static func decimal(_ low: Int?, _ high: Int?) -> FloatingPointFormatStyle<Double> {
        precision(low, high).map { FloatingPointFormatStyle<Double>.number.precision(.fractionLength($0)) } ?? .number
    }

    private static func percent(_ low: Int?, _ high: Int?) -> FloatingPointFormatStyle<Double>.Percent {
        precision(low, high).map { FloatingPointFormatStyle<Double>.Percent.percent.precision(.fractionLength($0)) } ?? .percent
    }

    private static func currency(_ code: String, _ low: Int?, _ high: Int?) -> FloatingPointFormatStyle<Double>.Currency {
        let style = FloatingPointFormatStyle<Double>.Currency(code: code)
        return precision(low, high).map { style.precision(.fractionLength($0)) } ?? style
    }
}
