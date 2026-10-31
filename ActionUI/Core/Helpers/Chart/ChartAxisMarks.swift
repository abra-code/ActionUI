// Core/Helpers/Chart/ChartAxisMarks.swift
//
// Axis content of the Chart element: chartXAxis / chartYAxis as an array of AxisMarks dicts (see
// Core/Elements/Chart.swift).

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

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
                invalid("values", "\"automatic\", {\"automatic\": {\"desiredCount\" (1 to 100), \"roundLowerBound\", \"roundUpperBound\"}}, {\"stride\": {\"by\": a calendar unit but quarter or weekOfMonth (dates) or a step above 0 (numbers), \"count\"}}, or a list of values typed by the axis")
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
            guard let value = JSONNumber.plain(raw) else {
                invalid(key, "a number")
                return nil
            }
            cleaned[key] = raw
            return value
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
            let x = JSONNumber.plain(offset?["x"]), y = JSONNumber.plain(offset?["y"])
            if let offset, !keys.isEmpty, keys.isSubset(of: ["x", "y"]), offset["x"] == nil || x != nil, offset["y"] == nil || y != nil {
                item.offset = ChartSize(width: x ?? 0, height: y ?? 0)
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
                    // Swift Charts stops the app for these two: "Component is not supported" (macOS 27).
                    guard unit != .quarter, unit != .weekOfMonth else { return nil }
                    let count = stride["count"]
                    if count != nil, wholeNumber(count).map({ $0 > 0 }) != true { return nil }
                    return .calendarStride(unit, count: wholeNumber(count) ?? 1)
                }
                if let step = JSONNumber.plain(by), step > 0, axisType == .number || axisType == .integer, stride.count == 1 {
                    return .numberStride(step)
                }
            }
            return nil
        }
        guard let items = raw as? [Any], !items.isEmpty else { return nil }
        switch axisType {
        case .number, .integer:
            let numbers = items.compactMap { JSONNumber.plain($0) }
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
        if let value = JSONNumber.plain(raw), value >= 0 {
            return .fixed(value)
        }
        switch raw as? String {
        case "automatic": return .automatic
        case "label": return .label(0)
        case "longestLabel": return .longestLabel(0)
        default: break
        }
        guard let object = raw as? [String: Any], object.count == 1, let key = object.keys.first,
              key == "label" || key == "longestLabel", let options = object[key] as? [String: Any], options.count == 1,
              let extend = JSONNumber.plain(options["extendPastBy"]) else { return nil }
        return key == "label" ? .label(extend) : .longestLabel(extend)
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
        let priority = JSONNumber.plain(options["priority"]), spacing = JSONNumber.plain(options["minimumSpacing"])
        if (options["priority"] != nil && priority == nil) || (options["minimumSpacing"] != nil && spacing == nil) { return nil }
        return .greedy(priority: priority ?? 0, minimumSpacing: spacing)
    }

    private static func wholeNumber(_ raw: Any?) -> Int? {
        JSONNumber.plain(raw) == nil ? nil : raw as? Int
    }
}

// Collects FontSpec's warnings about one font value.
private final class ChartFontProblemLogger: ActionUILogger, @unchecked Sendable {
    private let lock = Lock()
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
