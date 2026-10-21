// Helpers/ChartMarkParsing.swift
//
// Chart content entries: ForEach, Plot, the marks and their modifiers (see Views/Chart.swift). Each
// mark entry holds its Swift initializer's arguments as keys; an argument is a plottable value
// object or a number in points, and the set of keys must match exactly one initializer.

import Foundation
import SwiftUI
import Charts

enum ChartMarkKind: String {
    case BarMark, LineMark, PointMark, RuleMark, AreaMark, RectangleMark, SectorMark
}

// The argument shapes the mark initializers share. "Pair" is a start/end pair of plottable
// values of one type; "points" are optional numbers in points.
enum ChartMarkForm {
    case xy            // x, y
    case xySeries      // x, y, series (LineMark, AreaMark)
    case xPoints       // x; yStart/yEnd points (PointMark: y point)
    case yPoints       // y; xStart/xEnd points (PointMark: x point)
    case xPair         // x; yStart + yEnd
    case pairY         // xStart + xEnd; y
    case pointsPair    // xStart/xEnd points (RuleMark: x point); yStart + yEnd
    case pairPoints    // xStart + xEnd; yStart/yEnd points (RuleMark: y point)
    case xPairSeries   // x; yStart + yEnd; series (AreaMark)
    case pairYSeries   // xStart + xEnd; y; series (AreaMark)
    case pairPair      // xStart + xEnd; yStart + yEnd (RectangleMark)
    case pointsOnly    // xStart/xEnd/yStart/yEnd points (RectangleMark)
    case angle         // angle; angularInset points (SectorMark)
}

enum ChartText {
    case literal(String)
    // Contains "$N" references (names already resolved), substituted per row.
    case perRow(String)
}

enum ChartOffset {
    case xy(x: CGFloat, y: CGFloat)
    case xYRange(x: CGFloat, yStart: CGFloat, yEnd: CGFloat)
    case xRangeY(xStart: CGFloat, xEnd: CGFloat, y: CGFloat)
    case ranges(xStart: CGFloat, xEnd: CGFloat, yStart: CGFloat, yEnd: CGFloat)
}

// A view drawn next to a mark: an ActionUI element, built for each row as a template row is
// (TemplateHelper.buildTemplateView), with its "$name" references already turned into "$N".
struct ChartAnnotationSpec {
    var position: AnnotationPosition = .automatic
    var alignment: Alignment = .center
    var spacing: CGFloat?
    var overflow = AnnotationOverflowResolution.automatic
    let content: ActionUIElement
    // Written inside a ForEach. A Plot outside one that holds a ForEach appends its annotation
    // to marks drawn per row, but its text reads no row, as its other modifiers' does.
    let readsRows: Bool
}

// Mark and Plot modifiers, applied in this declaration order.
enum ChartMarkModifier {
    case foregroundStyle(SwiftUI.Color)
    case foregroundStyleBy(ChartPlottable)
    case symbol(BasicChartSymbolShape)
    case symbolBy(ChartPlottable)
    case symbolArea(CGFloat)
    case symbolSize(CGSize)
    case symbolSizeBy(ChartPlottable)
    case lineStyle(StrokeStyle)
    case lineStyleBy(ChartPlottable)
    case interpolationMethod(InterpolationMethod)
    case position(ChartPlottable, axis: Axis?, span: MarkDimension)
    case cornerRadius(CGFloat, RoundedCornerStyle)
    case opacity(Double)
    case zIndex(Double)
    case offset(ChartOffset)
    case blur(CGFloat)
    case shadow(color: SwiftUI.Color?, radius: CGFloat, x: CGFloat, y: CGFloat)
    case alignsMarkStylesWithPlotArea(Bool)
    case accessibilityLabel(ChartText)
    case accessibilityValue(ChartText)
    case accessibilityIdentifier(ChartText)
    case accessibilityHidden(Bool)
    case annotation(ChartAnnotationSpec)

    var plottable: ChartPlottable? {
        switch self {
        case .foregroundStyleBy(let value), .symbolBy(let value), .symbolSizeBy(let value), .lineStyleBy(let value):
            return value
        case .position(let value, _, _):
            return value
        default:
            return nil
        }
    }
}

struct ChartMarkSpec {
    let kind: ChartMarkKind
    let form: ChartMarkForm
    // Plottable arguments by initializer label (x, y, xStart, xEnd, yStart, yEnd, series, angle).
    var values: [String: ChartPlottable]
    // Point arguments by initializer label.
    let points: [String: CGFloat]
    var width: MarkDimension = .automatic
    var height: MarkDimension = .automatic
    var stacking: MarkStackingMethod = .standard
    var innerRadius: MarkDimension = .automatic
    var outerRadius: MarkDimension = .automatic
    var modifiers: [ChartMarkModifier] = []

    var xValues: [ChartPlottable] { ["x", "xStart", "xEnd"].compactMap { values[$0] } }
    var yValues: [ChartPlottable] { ["y", "yStart", "yEnd"].compactMap { values[$0] } }
    var plottables: [ChartPlottable] {
        ["x", "y", "xStart", "xEnd", "yStart", "yEnd", "series", "angle"].compactMap { values[$0] } + modifiers.compactMap(\.plottable)
    }
}

extension ChartDescription {
    static let argumentKeys = ["x", "y", "xStart", "xEnd", "yStart", "yEnd", "series", "angle", "angularInset"]
    static let dimensionKeys = ["width", "height", "stacking", "innerRadius", "outerRadius"]
    static let modifierKeys = [
        "foregroundStyle", "symbol", "symbolSize", "lineStyle", "interpolationMethod", "position", "cornerRadius",
        "opacity", "zIndex", "offset", "blur", "shadow", "alignsMarkStylesWithPlotArea",
        "accessibilityLabel", "accessibilityValue", "accessibilityIdentifier", "accessibilityHidden", "annotation",
    ]

    private struct FormPattern {
        let form: ChartMarkForm
        let values: Set<String>
        let points: Set<String>
        // Which of width / height / stacking / innerRadius / outerRadius this initializer takes.
        let dimensions: Set<String>
        let text: String
    }

    // From the SDK's initializers (Charts.swiftinterface). A mark's plottable keys must equal
    // one pattern's `values`; its point keys must be among that pattern's `points`.
    private static func patterns(_ kind: ChartMarkKind) -> [FormPattern] {
        switch kind {
        case .BarMark:
            return [
                FormPattern(form: .xy, values: ["x", "y"], points: [], dimensions: ["width", "height", "stacking"], text: "x + y"),
                FormPattern(form: .xPoints, values: ["x"], points: ["yStart", "yEnd"], dimensions: ["width", "stacking"], text: "x (+ yStart/yEnd points)"),
                FormPattern(form: .xPair, values: ["x", "yStart", "yEnd"], points: [], dimensions: ["width"], text: "x + yStart + yEnd"),
                FormPattern(form: .yPoints, values: ["y"], points: ["xStart", "xEnd"], dimensions: ["height", "stacking"], text: "(xStart/xEnd points +) y"),
                FormPattern(form: .pointsPair, values: ["yStart", "yEnd"], points: ["xStart", "xEnd"], dimensions: [], text: "(xStart/xEnd points +) yStart + yEnd"),
                FormPattern(form: .pairY, values: ["xStart", "xEnd", "y"], points: [], dimensions: ["height"], text: "xStart + xEnd + y"),
                FormPattern(form: .pairPoints, values: ["xStart", "xEnd"], points: ["yStart", "yEnd"], dimensions: [], text: "xStart + xEnd (+ yStart/yEnd points)"),
            ]
        case .LineMark:
            return [
                FormPattern(form: .xy, values: ["x", "y"], points: [], dimensions: [], text: "x + y"),
                FormPattern(form: .xySeries, values: ["x", "y", "series"], points: [], dimensions: [], text: "x + y + series"),
            ]
        case .PointMark:
            return [
                FormPattern(form: .xy, values: ["x", "y"], points: [], dimensions: [], text: "x + y"),
                FormPattern(form: .yPoints, values: ["y"], points: ["x"], dimensions: [], text: "(x point +) y"),
                FormPattern(form: .xPoints, values: ["x"], points: ["y"], dimensions: [], text: "x (+ y point)"),
            ]
        case .RuleMark:
            return [
                FormPattern(form: .pointsPair, values: ["yStart", "yEnd"], points: ["x"], dimensions: [], text: "(x point +) yStart + yEnd"),
                FormPattern(form: .xPoints, values: ["x"], points: ["yStart", "yEnd"], dimensions: [], text: "x (+ yStart/yEnd points)"),
                FormPattern(form: .xPair, values: ["x", "yStart", "yEnd"], points: [], dimensions: [], text: "x + yStart + yEnd"),
                FormPattern(form: .yPoints, values: ["y"], points: ["xStart", "xEnd"], dimensions: [], text: "(xStart/xEnd points +) y"),
                FormPattern(form: .pairPoints, values: ["xStart", "xEnd"], points: ["y"], dimensions: [], text: "xStart + xEnd (+ y point)"),
                FormPattern(form: .pairY, values: ["xStart", "xEnd", "y"], points: [], dimensions: [], text: "xStart + xEnd + y"),
            ]
        case .AreaMark:
            return [
                FormPattern(form: .xy, values: ["x", "y"], points: [], dimensions: ["stacking"], text: "x + y"),
                FormPattern(form: .pairY, values: ["xStart", "xEnd", "y"], points: [], dimensions: [], text: "xStart + xEnd + y"),
                FormPattern(form: .xPair, values: ["x", "yStart", "yEnd"], points: [], dimensions: [], text: "x + yStart + yEnd"),
                FormPattern(form: .xySeries, values: ["x", "y", "series"], points: [], dimensions: ["stacking"], text: "x + y + series"),
                FormPattern(form: .pairYSeries, values: ["xStart", "xEnd", "y", "series"], points: [], dimensions: [], text: "xStart + xEnd + y + series"),
                FormPattern(form: .xPairSeries, values: ["x", "yStart", "yEnd", "series"], points: [], dimensions: [], text: "x + yStart + yEnd + series"),
            ]
        case .RectangleMark:
            return [
                FormPattern(form: .xy, values: ["x", "y"], points: [], dimensions: ["width", "height"], text: "x + y"),
                FormPattern(form: .xPoints, values: ["x"], points: ["yStart", "yEnd"], dimensions: ["width"], text: "x (+ yStart/yEnd points)"),
                FormPattern(form: .yPoints, values: ["y"], points: ["xStart", "xEnd"], dimensions: ["height"], text: "(xStart/xEnd points +) y"),
                FormPattern(form: .pairY, values: ["xStart", "xEnd", "y"], points: [], dimensions: ["height"], text: "xStart + xEnd + y"),
                FormPattern(form: .pairPoints, values: ["xStart", "xEnd"], points: ["yStart", "yEnd"], dimensions: [], text: "xStart + xEnd (+ yStart/yEnd points)"),
                FormPattern(form: .xPair, values: ["x", "yStart", "yEnd"], points: [], dimensions: ["width"], text: "x + yStart + yEnd"),
                FormPattern(form: .pointsPair, values: ["yStart", "yEnd"], points: ["xStart", "xEnd"], dimensions: [], text: "(xStart/xEnd points +) yStart + yEnd"),
                FormPattern(form: .pairPair, values: ["xStart", "xEnd", "yStart", "yEnd"], points: [], dimensions: [], text: "xStart + xEnd + yStart + yEnd"),
                FormPattern(form: .pointsOnly, values: [], points: ["xStart", "xEnd", "yStart", "yEnd"], dimensions: [], text: "xStart/xEnd/yStart/yEnd points"),
            ]
        case .SectorMark:
            return [
                FormPattern(form: .angle, values: ["angle"], points: ["angularInset"], dimensions: ["innerRadius", "outerRadius"],
                            text: "angle (+ angularInset points)"),
            ]
        }
    }

    // MARK: - Entries

    static func parseEntries(_ entries: [Any], insideForEach: Bool, columns: [Column],
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
                for key in entry.keys where !["type", "content", "data", "columns"].contains(key) {
                    logger?.log("Chart: '\(key)' is not supported on ForEach; ignoring it", .warning)
                }
                var cleanedForEach: [String: Any] = ["type": "ForEach"]
                // Its own inline rows stay in the description (unlike the chart's data, which
                // becomes the rows), laid out by its own columns when it has them.
                var data: [[String]]?
                var rowColumns = columns
                if let raw = entry["data"] {
                    if let rows = raw as? [Any], rows.allSatisfy(isDataRow) {
                        data = rowStrings(rows)
                        cleanedForEach["data"] = rows
                    } else {
                        logger?.log("Chart: ForEach 'data' must be an array of rows, each an array of strings, numbers, booleans or null; drawing it over the chart's rows", .warning)
                    }
                }
                if let rawColumns = entry["columns"] {
                    if data != nil {
                        let own = parseColumns(rawColumns, cleaned: &cleanedForEach, logger: logger)
                        // Columns that are not an array are ignored (and not kept), so the chart's
                        // lay out the data, as on every later parse of the cleaned description.
                        if cleanedForEach["columns"] != nil {
                            rowColumns = own
                        }
                    } else {
                        logger?.log("Chart: ForEach 'columns' lay out its own 'data', which it does not have; ignoring them", .warning)
                    }
                }
                var cleanedChildren: [Any] = []
                let parsed = parseEntries(children, insideForEach: true, columns: rowColumns, cleaned: &cleanedChildren, logger: logger)
                result.append(.forEach(parsed, data: data))
                cleanedForEach["content"] = cleanedChildren
                cleaned.append(cleanedForEach)
                continue
            }
            if type == "Plot" {
                let known = Set(["type", "content"] + modifierKeys)
                for key in entry.keys where !known.contains(key) {
                    logger?.log("Chart: '\(key)' is not supported on Plot; ignoring it", .warning)
                }
                guard let children = entry["content"] as? [Any] else {
                    logger?.log("Chart: Plot requires 'content' (an array); ignoring it", .warning)
                    continue
                }
                var cleanedPlot: [String: Any] = ["type": "Plot"]
                let modifiers = parseModifiers(entry, role: "Plot", insideForEach: insideForEach, columns: columns,
                                               cleaned: &cleanedPlot, logger: logger)
                var cleanedChildren: [Any] = []
                let parsed = parseEntries(children, insideForEach: insideForEach, columns: columns, cleaned: &cleanedChildren, logger: logger)
                cleanedPlot["content"] = cleanedChildren
                // Swift applies a Plot's modifiers to everything inside it, after the content's own;
                // appending them to each mark draws the same (and keeps one flat list of marks).
                result.append(.plot(parsed.map { appending(modifiers, to: $0) }))
                cleaned.append(cleanedPlot)
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

    private static func appending(_ modifiers: [ChartMarkModifier], to entry: ChartEntry) -> ChartEntry {
        switch entry {
        case .mark(var spec):
            spec.modifiers += modifiers
            return .mark(spec)
        case .forEach(let children, let data):
            return .forEach(children.map { appending(modifiers, to: $0) }, data: data)
        case .plot(let children):
            return .plot(children.map { appending(modifiers, to: $0) })
        }
    }

    // MARK: - Marks

    private static func parseMark(_ kind: ChartMarkKind, _ entry: [String: Any], insideForEach: Bool, columns: [Column],
                                  logger: (any ActionUILogger)?) -> (spec: ChartMarkSpec, cleaned: [String: Any])? {
        let name = kind.rawValue
        var cleaned: [String: Any] = ["type": name]
        let known = Set(["type"] + argumentKeys + dimensionKeys + modifierKeys)
        for key in entry.keys where !known.contains(key) {
            logger?.log("Chart: '\(key)' is not supported on \(name); ignoring it", .warning)
        }

        var values: [String: ChartPlottable] = [:]
        var points: [String: CGFloat] = [:]
        for key in argumentKeys {
            guard let raw = entry[key] else { continue }
            if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                points[key] = CGFloat(number.doubleValue)
                cleaned[key] = number
            } else if let object = raw as? [String: Any] {
                let selectionAxis: Axis? = ["x", "xStart", "xEnd"].contains(key) ? .horizontal
                    : ["y", "yStart", "yEnd"].contains(key) ? .vertical : nil
                guard let parsed = parsePlottable(object, role: "\(name).\(key)", insideForEach: insideForEach, columns: columns,
                                                  selectionAxis: selectionAxis, logger: logger) else {
                    return nil
                }
                values[key] = parsed.value
                cleaned[key] = parsed.cleaned
            } else {
                logger?.log("Chart: \(name).\(key) must be {\"label\", \"value\"} or a number in points; ignoring the mark", .warning)
                return nil
            }
        }

        let candidates = patterns(kind)
        guard let pattern = candidates.first(where: { $0.values == Set(values.keys) && Set(points.keys).isSubset(of: $0.points) }) else {
            let forms = candidates.map(\.text).joined(separator: " | ")
            logger?.log("Chart: \(name) arguments do not match an initializer (plottable values are objects, points are numbers). Accepted: \(forms); ignoring it", .warning)
            return nil
        }
        for (start, end) in [("xStart", "xEnd"), ("yStart", "yEnd")] {
            // A selection value takes its axis's type later, so it has none to compare yet.
            if let a = values[start], let b = values[end], !a.isSelection, !b.isSelection, a.type != b.type {
                logger?.log("Chart: \(name) \(start) is \(a.type.rawValue) but \(end) is \(b.type.rawValue); a start and end must have one type. Ignoring the mark", .warning)
                return nil
            }
        }

        // A sector's size is its share of the angle values' sum, so the angle is a quantity.
        if let angle = values["angle"], angle.type != .number, angle.type != .integer {
            logger?.log("Chart: \(name).angle must be a number or integer value, not \(angle.type.rawValue); ignoring the mark", .warning)
            return nil
        }

        var spec = ChartMarkSpec(kind: kind, form: pattern.form, values: values, points: points)
        for key in dimensionKeys {
            guard let raw = entry[key] else { continue }
            guard pattern.dimensions.contains(key) else {
                logger?.log("Chart: \(name) (\(pattern.text)) takes no '\(key)'; ignoring it", .warning)
                continue
            }
            if key == "stacking" {
                if let method = (raw as? String).flatMap(parseStacking) {
                    spec.stacking = method
                    cleaned[key] = raw
                } else {
                    logger?.log("Chart: \(name).stacking must be standard, normalized, center or unstacked; ignoring it", .warning)
                }
            } else if let dimension = parseDimension(raw) {
                switch key {
                case "width": spec.width = dimension
                case "height": spec.height = dimension
                case "innerRadius": spec.innerRadius = dimension
                default: spec.outerRadius = dimension
                }
                cleaned[key] = raw
            } else {
                logger?.log("Chart: \(name).\(key) must be a number, \"automatic\", {\"ratio\"}, {\"inset\"} or {\"fixed\"}; ignoring it", .warning)
            }
        }

        spec.modifiers = parseModifiers(entry, role: name, insideForEach: insideForEach, columns: columns, cleaned: &cleaned, logger: logger)
        return (spec, cleaned)
    }

    // MARK: - Modifiers

    private static func parseModifiers(_ entry: [String: Any], role: String, insideForEach: Bool, columns: [Column],
                                       cleaned: inout [String: Any], logger: (any ActionUILogger)?) -> [ChartMarkModifier] {
        var modifiers: [ChartMarkModifier] = []

        // A `{"by": plottable}` form; returns nil when `raw` is not one.
        func by(_ raw: Any, _ key: String) -> (value: ChartPlottable, cleaned: [String: Any])?? {
            guard let object = raw as? [String: Any], let byObject = object["by"] else { return .none }
            guard object.count == 1, let plottable = byObject as? [String: Any] else {
                logger?.log("Chart: \(role).\(key) must be {\"by\": {\"label\", \"value\"}} with no other keys; ignoring it", .warning)
                return .some(nil)
            }
            // parsePlottable reports its own failure.
            return .some(parsePlottable(plottable, role: "\(role).\(key).by", insideForEach: insideForEach, columns: columns, logger: logger))
        }
        func invalid(_ key: String, _ expected: String) {
            logger?.log("Chart: \(role).\(key) must be \(expected); ignoring it", .warning)
        }
        func number(_ raw: Any?) -> CGFloat? {
            guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            return CGFloat(value.doubleValue)
        }

        for key in modifierKeys {
            guard let raw = entry[key] else { continue }
            switch key {
            case "foregroundStyle", "symbol", "symbolSize", "lineStyle":
                if let parsedBy = by(raw, key) {
                    guard let parsed = parsedBy else { continue }
                    cleaned[key] = ["by": parsed.cleaned]
                    switch key {
                    case "foregroundStyle": modifiers.append(.foregroundStyleBy(parsed.value))
                    case "symbol": modifiers.append(.symbolBy(parsed.value))
                    case "symbolSize": modifiers.append(.symbolSizeBy(parsed.value))
                    default: modifiers.append(.lineStyleBy(parsed.value))
                    }
                    continue
                }
                switch key {
                case "foregroundStyle":
                    if let name = raw as? String, let color = ColorHelper.resolveColor(name) {
                        modifiers.append(.foregroundStyle(color))
                        cleaned[key] = name
                    } else {
                        invalid(key, "a color or {\"by\": {\"label\", \"value\"}}")
                    }
                case "symbol":
                    if let name = raw as? String, let shape = parseSymbol(name) {
                        modifiers.append(.symbol(shape))
                        cleaned[key] = name
                    } else {
                        invalid(key, "circle, square, triangle, diamond, pentagon, plus, cross, asterisk or {\"by\": ...}")
                    }
                case "symbolSize":
                    if let area = number(raw) {
                        modifiers.append(.symbolArea(area))
                        cleaned[key] = raw
                    } else if let object = raw as? [String: Any], object.count == 2,
                              let width = number(object["width"]), let height = number(object["height"]) {
                        modifiers.append(.symbolSize(CGSize(width: width, height: height)))
                        cleaned[key] = raw
                    } else {
                        invalid(key, "an area number, {\"width\", \"height\"} or {\"by\": ...}")
                    }
                default:
                    if let object = raw as? [String: Any], let style = parseStrokeStyle(object) {
                        modifiers.append(.lineStyle(style))
                        cleaned[key] = raw
                    } else {
                        invalid(key, "a stroke style {\"lineWidth\", \"lineCap\", \"lineJoin\", \"miterLimit\", \"dash\", \"dashPhase\"} or {\"by\": ...}")
                    }
                }
            case "interpolationMethod":
                if let method = parseInterpolation(raw) {
                    modifiers.append(.interpolationMethod(method))
                    cleaned[key] = raw
                } else {
                    invalid(key, "linear, cardinal, catmullRom, monotone, stepStart, stepCenter, stepEnd, {\"cardinal\": {\"tension\"}} or {\"catmullRom\": {\"alpha\"}}")
                }
            case "position":
                guard let object = raw as? [String: Any], let byObject = object["by"] as? [String: Any],
                      Set(object.keys).isSubset(of: ["by", "axis", "span"]) else {
                    invalid(key, "{\"by\": {\"label\", \"value\"}, \"axis\": \"horizontal\"|\"vertical\", \"span\": ...}")
                    continue
                }
                guard let parsed = parsePlottable(byObject, role: "\(role).position.by", insideForEach: insideForEach, columns: columns, logger: logger) else { continue }
                var axis: Axis?
                var cleanedPosition: [String: Any] = ["by": parsed.cleaned]
                if let axisName = object["axis"] {
                    switch axisName as? String {
                    case "horizontal": axis = .horizontal
                    case "vertical": axis = .vertical
                    default: invalid("position.axis", "horizontal or vertical")
                    }
                    if axis != nil { cleanedPosition["axis"] = axisName }
                }
                var span: MarkDimension = .automatic
                if let spanValue = object["span"] {
                    if let parsedSpan = parseDimension(spanValue) {
                        span = parsedSpan
                        cleanedPosition["span"] = spanValue
                    } else {
                        invalid("position.span", "a number, \"automatic\", {\"ratio\"}, {\"inset\"} or {\"fixed\"}")
                    }
                }
                modifiers.append(.position(parsed.value, axis: axis, span: span))
                cleaned[key] = cleanedPosition
            case "cornerRadius":
                if let radius = number(raw) {
                    modifiers.append(.cornerRadius(radius, .continuous))
                    cleaned[key] = raw
                } else if let object = raw as? [String: Any], let radius = number(object["radius"]),
                          Set(object.keys).isSubset(of: ["radius", "style"]) {
                    let style: RoundedCornerStyle? = switch object["style"] as? String {
                    case nil: object["style"] == nil ? .continuous : nil
                    case "continuous": .continuous
                    case "circular": .circular
                    default: nil
                    }
                    if let style {
                        modifiers.append(.cornerRadius(radius, style))
                        cleaned[key] = raw
                    } else {
                        invalid(key, "a number or {\"radius\", \"style\": \"continuous\"|\"circular\"}")
                    }
                } else {
                    invalid(key, "a number or {\"radius\", \"style\": \"continuous\"|\"circular\"}")
                }
            case "opacity", "zIndex", "blur":
                guard let value = number(raw) else {
                    invalid(key, "a number")
                    continue
                }
                switch key {
                case "opacity": modifiers.append(.opacity(Double(value)))
                case "zIndex": modifiers.append(.zIndex(Double(value)))
                default: modifiers.append(.blur(value))
                }
                cleaned[key] = raw
            case "offset":
                if let object = raw as? [String: Any], let offset = parseOffset(object, number: number) {
                    modifiers.append(.offset(offset))
                    cleaned[key] = raw
                } else {
                    invalid(key, "{\"x\", \"y\"}, {\"x\", \"yStart\", \"yEnd\"}, {\"xStart\", \"xEnd\", \"y\"} or {\"xStart\", \"xEnd\", \"yStart\", \"yEnd\"} (numbers)")
                }
            case "shadow":
                guard let object = raw as? [String: Any], let radius = number(object["radius"]),
                      Set(object.keys).isSubset(of: ["color", "radius", "x", "y"]) else {
                    invalid(key, "{\"radius\", \"color\", \"x\", \"y\"} with a numeric radius")
                    continue
                }
                var color: SwiftUI.Color?
                if let name = object["color"] {
                    guard let resolved = (name as? String).flatMap(ColorHelper.resolveColor) else {
                        invalid("shadow.color", "a color")
                        continue
                    }
                    color = resolved
                }
                modifiers.append(.shadow(color: color, radius: radius, x: number(object["x"]) ?? 0, y: number(object["y"]) ?? 0))
                cleaned[key] = raw
            case "alignsMarkStylesWithPlotArea", "accessibilityHidden":
                guard let flag = raw as? Bool else {
                    invalid(key, "true or false")
                    continue
                }
                modifiers.append(key == "accessibilityHidden" ? .accessibilityHidden(flag) : .alignsMarkStylesWithPlotArea(flag))
                cleaned[key] = flag
            case "annotation":
                guard let object = raw as? [String: Any] else {
                    invalid(key, "{\"content\": {an element}, \"position\", \"alignment\", \"spacing\", \"overflowResolution\"}")
                    continue
                }
                // parseAnnotation reports its own failure.
                guard let parsed = parseAnnotation(object, role: "\(role).annotation", insideForEach: insideForEach,
                                                   columns: columns, logger: logger) else { continue }
                modifiers.append(.annotation(parsed.spec))
                cleaned[key] = parsed.cleaned
            default: // accessibilityLabel, accessibilityValue, accessibilityIdentifier
                guard let text = raw as? String else {
                    invalid(key, "text")
                    continue
                }
                let chartText = insideForEach ? textWithReferences(text, columns: columns) : .literal(text)
                switch key {
                case "accessibilityLabel": modifiers.append(.accessibilityLabel(chartText))
                case "accessibilityValue": modifiers.append(.accessibilityValue(chartText))
                default: modifiers.append(.accessibilityIdentifier(chartText))
                }
                cleaned[key] = text
            }
        }
        return modifiers
    }

    // MARK: - Annotations

    private static let annotationKeys: Set<String> = ["content", "position", "alignment", "spacing", "overflowResolution"]

    // The annotation's view must be a known element type, and cannot hold a Chart: the
    // per-row substitution would rewrite that chart's own references, and it would have no
    // rows. Its element is kept as given in the cleaned JSON; each row's instance reads its
    // properties after substitution, as a template row's does.
    private static func parseAnnotation(_ object: [String: Any], role: String, insideForEach: Bool, columns: [Column],
                                        logger: (any ActionUILogger)?) -> (spec: ChartAnnotationSpec, cleaned: [String: Any])? {
        for key in object.keys where !annotationKeys.contains(key) {
            logger?.log("Chart: '\(key)' is not supported in \(role); ignoring it", .warning)
        }
        guard let content = object["content"] as? [String: Any] else {
            logger?.log("Chart: \(role) requires 'content', a view element such as {\"type\": \"Text\", \"properties\": {\"text\": \"...\"}}; ignoring the annotation", .warning)
            return nil
        }
        guard let type = content["type"] as? String, ActionUIRegistry.shared.specs[type] != nil else {
            logger?.log("Chart: \(role).content must be a view element with a known 'type'; ignoring the annotation", .warning)
            return nil
        }
        if containsChart(content) {
            logger?.log("Chart: \(role).content cannot hold a Chart; ignoring the annotation", .warning)
            return nil
        }
        let resolved = insideForEach ? resolvingNames(in: content, columns: columns) as? [String: Any] ?? content : content
        guard let element = decodeElement(resolved, logger: logger) else {
            logger?.log("Chart: \(role).content is not a valid element; ignoring the annotation", .warning)
            return nil
        }
        var spec = ChartAnnotationSpec(content: ActionUIElement.normalizeTemplateIDs(element), readsRows: insideForEach)
        var cleaned: [String: Any] = ["content": content]
        if let raw = object["position"] {
            if let name = raw as? String, let position = parsePosition(name) {
                spec.position = position
                cleaned["position"] = name
            } else {
                logger?.log("Chart: \(role).position must be automatic, overlay, top, bottom, leading, trailing, topLeading, topTrailing, bottomLeading or bottomTrailing; ignoring it", .warning)
            }
        }
        if let raw = object["alignment"] {
            if let name = raw as? String, let alignment = parseAlignment(name) {
                spec.alignment = alignment
                cleaned["alignment"] = name
            } else {
                logger?.log("Chart: \(role).alignment must be center, leading, trailing, top, bottom, topLeading, topTrailing, bottomLeading or bottomTrailing; ignoring it", .warning)
            }
        }
        if let raw = object["spacing"] {
            if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                spec.spacing = CGFloat(number.doubleValue)
                cleaned["spacing"] = number
            } else {
                logger?.log("Chart: \(role).spacing must be a number; ignoring it", .warning)
            }
        }
        if let raw = object["overflowResolution"] {
            if let overflow = parseOverflowResolution(raw) {
                spec.overflow = overflow
                cleaned["overflowResolution"] = raw
            } else {
                logger?.log("Chart: \(role).overflowResolution must be {\"x\", \"y\"}, each automatic, fit, padScale, disabled or {\"fit\": \"plot\"|\"chart\"|\"automatic\"}; ignoring it", .warning)
            }
        }
        return (spec, cleaned)
    }

    private static func containsChart(_ value: Any) -> Bool {
        if let object = value as? [String: Any] {
            return object["type"] as? String == "Chart" || object.values.contains(where: containsChart)
        }
        if let items = value as? [Any] {
            return items.contains(where: containsChart)
        }
        return false
    }

    // Through the document decoder, which reads every subview key an element may have.
    private static func decodeElement(_ object: [String: Any], logger: (any ActionUILogger)?) -> ActionUIElement? {
        // A JSON null parsed by ActionUIJSON is ActionUIJSONNull, which JSONSerialization needs as NSNull.
        let object = FoundationBridge.foundation(object) as? [String: Any] ?? object
        guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        return try? JSONDecoder(logger: logger ?? SilentChartLogger.shared).decode(ActionUIElement.self, from: data)
    }

    // Every string in an annotation's element, its children's included, with "$name" turned
    // into "$N".
    private static func resolvingNames(in value: Any, columns: [Column]) -> Any {
        if let text = value as? String {
            return resolvingNames(text, columns: columns).text
        }
        if let object = value as? [String: Any] {
            return object.mapValues { resolvingNames(in: $0, columns: columns) }
        }
        if let items = value as? [Any] {
            return items.map { resolvingNames(in: $0, columns: columns) }
        }
        return value
    }

    private static func parseOverflowResolution(_ raw: Any) -> AnnotationOverflowResolution? {
        guard let object = raw as? [String: Any], Set(object.keys).isSubset(of: ["x", "y"]) else { return nil }
        var strategies: [String: AnnotationOverflowResolution.Strategy] = [:]
        for (axis, value) in object {
            guard let strategy = parseOverflowStrategy(value) else { return nil }
            strategies[axis] = strategy
        }
        return AnnotationOverflowResolution(x: strategies["x"] ?? .automatic, y: strategies["y"] ?? .automatic)
    }

    private static func parseOverflowStrategy(_ raw: Any) -> AnnotationOverflowResolution.Strategy? {
        if let name = raw as? String {
            switch name {
            case "automatic": return .automatic
            case "fit": return .fit
            case "padScale": return .padScale
            case "disabled": return .disabled
            default: return nil
            }
        }
        guard let object = raw as? [String: Any], object.count == 1, let boundary = object["fit"] as? String else { return nil }
        switch boundary {
        case "plot": return .fit(to: .plot)
        case "chart": return .fit(to: .chart)
        case "automatic": return .fit(to: .automatic)
        default: return nil
        }
    }

    // MARK: - Small parsers

    private static func parseDimension(_ raw: Any) -> MarkDimension? {
        if let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() {
            return .fixed(CGFloat(value.doubleValue))
        }
        if let name = raw as? String {
            return name == "automatic" ? .automatic : nil
        }
        guard let object = raw as? [String: Any], object.count == 1, let key = object.keys.first,
              let value = object[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        switch key {
        case "ratio": return .ratio(CGFloat(value.doubleValue))
        case "inset": return .inset(CGFloat(value.doubleValue))
        case "fixed": return .fixed(CGFloat(value.doubleValue))
        default: return nil
        }
    }

    private static func parseStacking(_ name: String) -> MarkStackingMethod? {
        switch name {
        case "standard": return .standard
        case "normalized": return .normalized
        case "center": return .center
        case "unstacked": return .unstacked
        default: return nil
        }
    }

    static func parseSymbol(_ name: String) -> BasicChartSymbolShape? {
        switch name {
        case "circle": return .circle
        case "square": return .square
        case "triangle": return .triangle
        case "diamond": return .diamond
        case "pentagon": return .pentagon
        case "plus": return .plus
        case "cross": return .cross
        case "asterisk": return .asterisk
        default: return nil
        }
    }

    private static func parseInterpolation(_ raw: Any) -> InterpolationMethod? {
        if let name = raw as? String {
            switch name {
            case "linear": return .linear
            case "cardinal": return .cardinal
            case "catmullRom": return .catmullRom
            case "monotone": return .monotone
            case "stepStart": return .stepStart
            case "stepCenter": return .stepCenter
            case "stepEnd": return .stepEnd
            default: return nil
            }
        }
        guard let object = raw as? [String: Any], object.count == 1 else { return nil }
        if let cardinal = object["cardinal"] as? [String: Any], let tension = cardinal["tension"] as? NSNumber {
            return .cardinal(tension: CGFloat(tension.doubleValue))
        }
        if let catmullRom = object["catmullRom"] as? [String: Any], let alpha = catmullRom["alpha"] as? NSNumber {
            return .catmullRom(alpha: CGFloat(alpha.doubleValue))
        }
        return nil
    }

    // Canvas's stroke keys. Every present key must be valid.
    static func parseStrokeStyle(_ object: [String: Any]) -> StrokeStyle? {
        let keys: Set<String> = ["lineWidth", "lineCap", "lineJoin", "miterLimit", "dash", "dashPhase"]
        guard Set(object.keys).isSubset(of: keys) else { return nil }
        if object["lineWidth"] != nil, object.cgFloat(forKey: "lineWidth") == nil { return nil }
        if object["miterLimit"] != nil, object.cgFloat(forKey: "miterLimit") == nil { return nil }
        if object["dashPhase"] != nil, object.cgFloat(forKey: "dashPhase") == nil { return nil }
        if object["dash"] != nil, object.cgFloatArray(forKey: "dash") == nil { return nil }
        if let cap = object["lineCap"], !["butt", "round", "square"].contains(cap as? String ?? "") { return nil }
        if let join = object["lineJoin"], !["miter", "round", "bevel"].contains(join as? String ?? "") { return nil }
        return StrokeStyle(
            lineWidth: object.cgFloat(forKey: "lineWidth") ?? 1,
            lineCap: CGLineCap.fromString(object["lineCap"] as? String ?? "butt"),
            lineJoin: CGLineJoin.fromString(object["lineJoin"] as? String ?? "miter"),
            miterLimit: object.cgFloat(forKey: "miterLimit") ?? 10,
            dash: object.cgFloatArray(forKey: "dash") ?? [],
            dashPhase: object.cgFloat(forKey: "dashPhase") ?? 0
        )
    }

    private static func parseOffset(_ object: [String: Any], number: (Any?) -> CGFloat?) -> ChartOffset? {
        let keys = Set(object.keys)
        guard !keys.isEmpty, keys.isSubset(of: ["x", "y", "xStart", "xEnd", "yStart", "yEnd"]),
              keys.allSatisfy({ number(object[$0]) != nil }) else { return nil }
        let xRange = keys.contains("xStart") || keys.contains("xEnd")
        let yRange = keys.contains("yStart") || keys.contains("yEnd")
        if (xRange && keys.contains("x")) || (yRange && keys.contains("y")) { return nil }
        func v(_ key: String) -> CGFloat { number(object[key]) ?? 0 }
        switch (xRange, yRange) {
        case (false, false): return .xy(x: v("x"), y: v("y"))
        case (false, true): return .xYRange(x: v("x"), yStart: v("yStart"), yEnd: v("yEnd"))
        case (true, false): return .xRangeY(xStart: v("xStart"), xEnd: v("xEnd"), y: v("y"))
        case (true, true): return .ranges(xStart: v("xStart"), xEnd: v("xEnd"), yStart: v("yStart"), yEnd: v("yEnd"))
        }
    }

    // Text inside a ForEach may embed "$N" or "$name" references; names become "$N" here so
    // each row only substitutes positions. A "$..." naming no column stays literal.
    private static func textWithReferences(_ text: String, columns: [Column]) -> ChartText {
        let resolved = resolvingNames(text, columns: columns)
        return resolved.found ? .perRow(resolved.text) : .literal(text)
    }

    private nonisolated static let referencePattern = try! NSRegularExpression(pattern: #"\$([A-Za-z_][A-Za-z0-9_]*|[0-9]+)"#)

    // `text` with its "$name" references as "$N"; `found` when it refers to any column.
    private static func resolvingNames(_ text: String, columns: [Column]) -> (text: String, found: Bool) {
        guard text.contains("$") else { return (text, false) }
        let ns = text as NSString
        var result = ""
        var cursor = 0
        var found = false
        for match in referencePattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range)
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            if let index = columnIndex(token, columns: columns) {
                result += "$\(index + 1)"
                found = true
            } else {
                result += token
            }
            cursor = match.range.location + match.range.length
        }
        result += ns.substring(from: cursor)
        return (result, found)
    }
}

// Parsing a description at render time has nowhere to report: the description was cleaned
// (and reported on) when it was set.
final class SilentChartLogger: ActionUILogger, Sendable {
    static let shared = SilentChartLogger()
    func log(_ message: String, _ level: LoggerLevel) {}
}
