// Sources/Drawing/ChartStyleMap.swift
/*
 What a chart's style scales come to over its marks: the names on each, what a name draws, and the
 legend's entries (measured on macOS 27).

 A color scale has names from its domain alone. A symbol or line style scale needs a mark wearing
 its {"by"}, and a domain then is the whole list: a value outside it draws in the first automatic
 style, whatever range is given. Only points and lines wear a symbol's, and only lines and rules a
 line style's. Symbols come in one order of seven, or of five once any line wears a symbol. Scales
 over the same names share their legend entries, however they were reached; others follow in the
 order color, symbol, line style, size. An entry without a color is the first series color, even
 over marks of a fixed one.

 A {"by"} over numbers or dates is a scale of its own kind:
 - A color runs along a gradient over the data's lowest and highest, or a domain, and stops at its
   ends. Without a range the gradient is the first series color from nearly clear to full. Named
   colors make bins of one width and no legend. Its legend is a bar over that span widened to
   whole steps (0 only if a step lands there), so the bar can run on past the gradient's end, and a
   date's over its own span, labeled at its two ends: Apple writes seconds there, and a bar this
   short has room for little more. A single value sits halfway and has no bar. The bar comes after
   all other entries.
 - A size is an area in line with the value, over 0 and the data's highest, or a domain, onto 0 to
   1200 or a range, and no end stops it. A category takes its place among the names, the first
   drawing nothing, and one outside a domain is the default size. Its legend is a circle at each
   tick of the same automatic axis that has an area, and a single value has none. A size changes
   points, and a line's symbols where they are a {"by"} too; a line lists it either way.
 - A line style is a width, 0 to 5 over the data's lowest and highest, so the lowest does not show,
   with no legend. A single value is halfway.
 - A symbol has no such scale: a point is a circle and a line has none, with no legend.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct ChartLegendEntry {
    var name: String
    var ink: ChartInk
    /// What it shows: a symbol, a sample of a line, or a symbol on one.
    var symbol: ChartSymbol?
    var stroke: ChartStroke?
    /// A symbol's own box, where a size scale sets one.
    var side: Double?
    /// In place of all the rest.
    var bar: ChartLegendBar?
}

struct ChartGradientStop: Equatable {
    var color: ColorSpec
    /// Along the bar, 0 to 1.
    var offset: Double
}

struct ChartLegendBar {
    var stops: [ChartGradientStop]
    var ticks: [(offset: Double, label: String)]
}

/// Where values fall from `lo` to `hi`: a single value is halfway.
private struct ChartNumberSpan {
    var lo: Double
    var hi: Double

    init?(_ values: [Double]) {
        guard let lo = values.min(), let hi = values.max() else { return nil }
        self.lo = lo
        self.hi = hi
    }

    init(lo: Double, hi: Double) {
        self.lo = lo
        self.hi = hi
    }

    /// Halved, so the widest doubles do not overflow; the smallest can halve to no span at all.
    func share(_ value: Double) -> Double {
        let span = hi / 2 - lo / 2
        return span > 0 ? (value / 2 - lo / 2) / span : 0.5
    }

    var withZero: ChartNumberSpan { ChartNumberSpan(lo: min(lo, 0), hi: max(hi, 0)) }
}

struct ChartStyleMap {
    private static let pointSymbols: [ChartSymbol] = [.circle, .cross, .triangle, .plus, .square, .asterisk, .diamond]
    private static let lineSymbols: [ChartSymbol] = [.circle, .square, .triangle, .diamond, .pentagon]
    private static let lineStyles: [ChartStroke] = [
        ChartLayout.defaultLine,
        dashed([4, 4]),
        dashed([8, 4]),
        dashed([8, 4, 2, 4]),
        dashed([0, 3])
    ]

    private static let lowestColorOpacity = 0.2
    private static let widestLine = 5.0
    private static let automaticSizes = 0.0...1200.0

    private static func dashed(_ dash: [Double]) -> ChartStroke {
        var stroke = ChartLayout.defaultLine
        stroke.dash = dash
        return stroke
    }

    private let colorRange: [ColorSpec]
    private let symbols: [ChartSymbol]
    private let strokes: [ChartStroke]
    private let colorNames: [String]
    private let symbolNames: [String]
    private let lineStyleNames: [String]
    private let colorIndex: [String: Int]
    private let symbolIndex: [String: Int]
    private let lineStyleIndex: [String: Int]
    private let positionNames: [String]
    private let positionIndex: [String: Int]
    private let positionSpan: ChartNumberSpan?
    /// The first position's axis and span, which bars and rectangles without one go by.
    let firstPosition: (axis: String?, span: ChartDimension)?
    private let sizeNames: [String]
    private let sizeIndex: [String: Int]
    private let sizes: ClosedRange<Double>
    private let colorSpan: ChartNumberSpan?
    private let colorsAreDates: Bool
    private let colorBins: [ColorSpec]?
    private let gradient: [ColorSpec]
    private let lineWidthSpan: ChartNumberSpan?
    private let sizeSpan: ChartNumberSpan?

    private static func number(_ scalar: ChartScalar) -> Double? {
        let value: Double
        switch scalar {
        case .string: return nil
        case .number(let number): value = number
        case .integer(let number): value = Double(number)
        case .date(let date): value = date.timeIntervalSinceReferenceDate
        }
        return value.isFinite ? value : nil
    }

    private static func span(_ domain: ChartDomain) -> ChartNumberSpan? {
        switch domain {
        case .numbers(let range): return ChartNumberSpan(lo: range.lowerBound, hi: range.upperBound)
        case .dates(let range): return ChartNumberSpan(lo: range.lowerBound.timeIntervalSinceReferenceDate, hi: range.upperBound.timeIntervalSinceReferenceDate)
        default: return nil
        }
    }

    init(_ spec: ChartSpec, _ marks: ChartResolvedMarks) {
        let styles = spec.styles
        if case .colors(let colors)? = styles.foregroundRange, !colors.isEmpty {
            colorRange = colors
        } else {
            colorRange = ChartLayout.seriesColors
        }
        let linesWearSymbols = marks.instances.contains { instance in
            instance.mark.kind == .LineMark && instance.mark.modifiers.contains { modifier in
                switch modifier {
                case .symbol, .symbolBy: return true
                default: return false
                }
            }
        }
        symbols = styles.symbolRange.isEmpty ? (linesWearSymbols ? Self.lineSymbols : Self.pointSymbols) : styles.symbolRange
        strokes = styles.lineStyleRange.isEmpty ? Self.lineStyles : styles.lineStyleRange

        if case .strings(let domain) = styles.foregroundDomain {
            colorNames = domain
        } else {
            colorNames = Self.names(marks, \.styleKey)
        }
        symbolNames = Self.names(marks, \.symbolKey, of: [.PointMark, .LineMark], domain: styles.symbolDomain)
        lineStyleNames = Self.names(marks, \.lineStyleKey, of: [.LineMark, .RuleMark], domain: styles.lineStyleDomain)
        colorIndex = Self.index(colorNames)
        symbolIndex = Self.index(symbolNames)
        lineStyleIndex = Self.index(lineStyleNames)

        let scaled = marks.instances.filter { $0.mark.kind == .PointMark || $0.mark.kind == .LineMark }
        let lined = marks.instances.filter { $0.mark.kind == .LineMark || $0.mark.kind == .RuleMark }
        positionNames = Self.names(marks, \.positionName)
        positionIndex = Self.index(positionNames)
        positionSpan = ChartNumberSpan(marks.instances.compactMap(\.positionValue).flatMap { [$0.start, $0.end] })
        firstPosition = marks.instances.first { $0.positionKey != nil }.map { ($0.positionAxis, $0.positionSpan) }
        sizeNames = Self.names(marks, \.sizeKey, of: [.PointMark, .LineMark], domain: styles.symbolSizeDomain)
        sizeIndex = Self.index(sizeNames)
        sizes = styles.symbolSizeRange ?? Self.automaticSizes
        lineWidthSpan = ChartNumberSpan(lined.compactMap { $0.lineStyleValue.flatMap(Self.number) })
        let sized = ChartNumberSpan(scaled.compactMap { $0.sizeValue.flatMap(Self.number) })
        sizeSpan = sized.map { Self.span(styles.symbolSizeDomain) ?? $0.withZero }

        let colored = marks.instances.compactMap(\.colorValue)
        let domain = Self.span(styles.foregroundDomain)
        colorSpan = ChartNumberSpan(colored.compactMap(Self.number)).map { domain ?? $0 }
        colorsAreDates = colored.contains { scalar in
            if case .date = scalar { return true } else { return false }
        }
        let first = ChartLayout.seriesColors[0]
        switch styles.foregroundRange {
        case .colors(let colors)? where !colors.isEmpty:
            colorBins = colors
            gradient = []
        case .gradient(let colors)? where !colors.isEmpty:
            colorBins = nil
            gradient = colors
        default:
            colorBins = nil
            gradient = [.withOpacity(first, Self.lowestColorOpacity), first]
        }
    }

    // The names in order of use, or the domain's once a mark uses any.
    private static func names(_ marks: ChartResolvedMarks, _ key: KeyPath<ChartMarkInstance, String?>, of kinds: Set<ChartMarkKind>? = nil,
                              domain: ChartDomain = .automatic()) -> [String] {
        var names: [String] = []
        var seen: Set<String> = []
        for instance in marks.instances where kinds?.contains(instance.mark.kind) ?? true {
            if let name = instance[keyPath: key], seen.insert(name).inserted {
                names.append(name)
            }
        }
        if case .strings(let domain) = domain, !names.isEmpty { return domain }
        return names
    }

    private static func index(_ names: [String]) -> [String: Int] {
        var index: [String: Int] = [:]
        for (position, name) in names.enumerated() {
            index[name] = position
        }
        return index
    }

    func ink(_ instance: ChartMarkInstance) -> ChartInk {
        if let span = colorSpan, let value = instance.colorValue.flatMap(Self.number) {
            let share = min(max(span.share(value), 0), 1)
            if let colorBins {
                return .color(colorBins[min(Int(share * Double(colorBins.count)), colorBins.count - 1)])
            }
            return .blend(gradient, at: share)
        }
        if let key = instance.styleKey, let index = colorIndex[key] {
            return .color(colorRange[index % colorRange.count])
        }
        for modifier in instance.mark.modifiers {
            if case .foregroundStyle(let color) = modifier {
                return .color(color)
            }
        }
        return .color(ChartLayout.seriesColors[0])
    }

    /// Where a position scale puts a name: every name has a place in every band.
    func positionSlot(named name: String) -> (index: Int, count: Int)? {
        positionIndex[name].map { ($0, positionNames.count) }
    }

    /// How many slots a band has.
    var positionSlots: Int { positionNames.count }

    /// How far along a position's numbers or dates a value falls, halfway if they are all one.
    func positionShare(_ value: Double) -> Double {
        positionSpan?.share(value) ?? 0.5
    }

    func symbol(named name: String) -> ChartSymbol {
        symbolIndex[name].map { symbols[$0 % symbols.count] } ?? .circle
    }

    func stroke(named name: String) -> ChartStroke {
        lineStyleIndex[name].map { strokes[$0 % strokes.count] } ?? ChartLayout.defaultLine
    }

    /// A line's width by a number.
    func stroke(for value: ChartScalar) -> ChartStroke {
        guard let span = lineWidthSpan, let number = Self.number(value) else { return ChartLayout.defaultLine }
        var stroke = ChartLayout.defaultLine
        stroke.lineWidth = Self.widestLine * span.share(number)
        return stroke
    }

    private func area(_ share: Double) -> Double {
        sizes.lowerBound + (sizes.upperBound - sizes.lowerBound) * share
    }

    private func area(named name: String) -> Double? {
        sizeIndex[name].map { area(sizeNames.count > 1 ? Double($0) / Double(sizeNames.count - 1) : 0.5) }
    }

    /// The area a size scale gives a mark's symbol; nil where it gives none.
    func area(_ instance: ChartMarkInstance) -> Double? {
        guard instance.mark.kind == .PointMark || (instance.mark.kind == .LineMark && instance.symbolKey != nil) else { return nil }
        if let key = instance.sizeKey { return area(named: key) }
        guard let span = sizeSpan, let value = instance.sizeValue.flatMap(Self.number) else { return nil }
        return area(span.share(value))
    }

    private static func side(_ area: Double) -> Double {
        2 * (max(area, 0) / .pi).squareRoot()
    }

    private func sizeEntries(number: (Double, Int) -> String) -> [ChartLegendEntry] {
        guard let span = sizeSpan, span.hi > span.lo else { return [] }
        let axis = ChartTicks.widened(span.lo, span.hi)
        let digits = ChartTicks.fractionDigits(axis.step)
        return axis.ticks.compactMap { tick in
            let area = area(span.share(tick))
            guard area > 0 else { return nil }
            return ChartLegendEntry(name: number(tick, tick == 0 ? 0 : digits), ink: .color(ChartLayout.seriesColors[0]), symbol: .circle, side: Self.side(area))
        }
    }

    private func barEntry(number: (Double, Int) -> String, dateTicks: (Date, Date) -> [(value: ChartScalar, label: String)]) -> ChartLegendEntry? {
        guard colorBins == nil, let span = colorSpan, span.hi > span.lo else { return nil }
        var axis = span
        var ticks: [(value: Double, label: String)]
        if colorsAreDates {
            let dates = dateTicks(Date(timeIntervalSinceReferenceDate: span.lo), Date(timeIntervalSinceReferenceDate: span.hi))
            ticks = dates.compactMap { tick in Self.number(tick.value).map { ($0, tick.label) } }
        } else {
            let whole = ChartTicks.widened(span.lo, span.hi)
            let digits = ChartTicks.fractionDigits(whole.step)
            axis = ChartNumberSpan(lo: whole.lo, hi: whole.hi)
            ticks = whole.ticks.map { ($0, number($0, $0 == 0 ? 0 : digits)) }
        }
        let colors = gradient.count > 1 ? gradient : [gradient[0], gradient[0]]
        // Weighed, so the widest doubles do not overflow. Rounding can still pass the axis's end or
        // step back, and GSK takes offsets only in order from 0 to 1.
        var reached = 0.0
        let stops = colors.enumerated().map { index, color in
            let share = Double(index) / Double(colors.count - 1)
            reached = max(reached, min(axis.share(span.lo * (1 - share) + span.hi * share), 1))
            return ChartGradientStop(color: color, offset: reached)
        }
        let bar = ChartLegendBar(stops: stops, ticks: ticks.map { (axis.share($0.value), $0.label) })
        return ChartLegendEntry(name: "", ink: .color(ChartLayout.seriesColors[0]), bar: bar)
    }

    private struct LegendGroup {
        var names: [String]
        var colored = false
        var shaped = false
        var lined = false
        var sized = false
    }

    func legendEntries(number: (Double, Int) -> String, dateTicks: (Date, Date) -> [(value: ChartScalar, label: String)]) -> [ChartLegendEntry] {
        var groups: [LegendGroup] = []
        func add(_ names: [String], _ channel: WritableKeyPath<LegendGroup, Bool>) {
            guard !names.isEmpty else { return }
            let set = Set(names)
            if let index = groups.firstIndex(where: { Set($0.names) == set }) {
                groups[index][keyPath: channel] = true
            } else {
                var group = LegendGroup(names: names)
                group[keyPath: channel] = true
                groups.append(group)
            }
        }
        add(colorNames, \.colored)
        add(symbolNames, \.shaped)
        add(lineStyleNames, \.lined)
        add(sizeNames, \.sized)
        let listed = groups.flatMap { group in
            group.names.map { name in
                var ink = ChartInk.color(ChartLayout.seriesColors[0])
                if group.colored, let index = colorIndex[name] {
                    ink = .color(colorRange[index % colorRange.count])
                }
                let symbol = group.shaped ? symbol(named: name) : nil
                return ChartLegendEntry(name: name, ink: ink, symbol: symbol ?? (group.lined && !group.sized ? nil : .circle),
                                        stroke: group.lined ? stroke(named: name) : nil,
                                        side: group.sized ? area(named: name).map(Self.side) : nil)
            }
        }
        return listed + sizeEntries(number: number) + [barEntry(number: number, dateTicks: dateTicks)].compactMap { $0 }
    }
}
