// Sources/Drawing/ChartLayout.swift
/*
 Lays out a chart for a size: its marks, axes and gridlines as drawing primitives in points. No GTK
 here: text is measured and formatted through ChartTextMetrics, so a test checks the geometry as
 numbers, and Elements/Chart+Adwaita.swift only draws the primitives.

 The goal is a chart comparable to Swift Charts, not a copy (Documentation/Schemas/Chart.md lists the
 differences). Swift Charts' look, as drawn on macOS 27:
 - The y axis is on the trailing side; solid gridlines at its ticks, and the plot's height gives
   about one tick per 60 points.
 - Categories are bands of equal width, in order of first use, with dashed lines at the band edges.
 - Number and date ticks on the x axis have a dashed line, and their label starts at the tick.
 - An automatic number domain includes 0 and is widened to whole steps, and a date axis covers each
   value's whole bin.
 - A bar takes 0.7 of its band or date bin, and 8 points where a value has neither. Bars at one
   position stack in row order, those below 0 downward. A normalized stack is that divided by the
   longer side, on an axis labeled 0, 25, ... 100 without a percent sign; a centered one is that
   moved so its two ends are as far from 0.
 - A start and end on an axis of categories run from the edge of one band to the far edge of the other;
   dates with a unit go in the middle of their bins, as a single value does.
 - Points given to a mark count from the plot's top leading corner.
 - A point's size is the area of its symbol, 50 unless given, and a rule is 2 wide unless given.
 - The modifier nearest a mark wins: its own over its Plot's.
 - Marks draw in the order of the content, over the grid.

 Bars, points and rules draw here; other marks still count on the axes.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

struct ChartPoint: Equatable {
    var x: Double
    var y: Double
}

struct ChartRect: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

enum ChartInk: Equatable {
    case color(ColorSpec)
    /// The widget's text color at this opacity, so axes follow the theme.
    case text(opacity: Double)
}

enum ChartPrimitive: Equatable {
    case line(from: ChartPoint, to: ChartPoint, ink: ChartInk, stroke: ChartStroke)
    case rect(ChartRect, ink: ChartInk)
    case symbol(ChartSymbol, center: ChartPoint, size: ChartSize, ink: ChartInk)
    /// `alignment` is the point of the text placed at `position`, as fractions of its size.
    case text(String, position: ChartPoint, alignment: ChartPoint)

    /// Whether GSK can take it: values from a document or rows can pass what its floats hold (they
    /// would reach it as infinities), and a line needs a width.
    var isDrawable: Bool {
        func finite(_ values: Double...) -> Bool { values.allSatisfy { Float($0).isFinite } }
        switch self {
        case let .line(from, to, _, stroke):
            return stroke.lineWidth > 0 && finite(from.x, from.y, to.x, to.y, stroke.lineWidth, stroke.miterLimit, stroke.dashPhase)
                && stroke.dash.allSatisfy { finite($0) }
        case let .rect(rect, _):
            return finite(rect.x, rect.y, rect.width, rect.height)
        case let .symbol(_, center, size, _):
            return finite(center.x, center.y, size.width, size.height)
        case let .text(_, position, _):
            return finite(position.x, position.y)
        }
    }
}

/// Text as the renderer measures and formats it.
struct ChartTextMetrics {
    var size: (String) -> ChartSize
    var number: (Double) -> String
    var date: (Date, _ skeleton: String) -> String
}

struct ChartLayout {
    // Swift Charts' order for series, in ActionUI's named colors.
    static let seriesColors: [ColorSpec] = [.named(.blue), .named(.green), .named(.orange), .named(.purple), .named(.red), .named(.cyan), .named(.yellow)]
    static let gridInk = ChartInk.text(opacity: 0.14)
    static let axisInk = ChartInk.text(opacity: 0.3)
    static let labelInk = ChartInk.text(opacity: 0.6)
    private static let tickDash = ChartStroke(lineWidth: 1, dash: [2, 2])
    private static let barRatio = 0.7
    private static let unbinnedBarThickness = 8.0
    private static let pointsPerTick = 60.0
    private static let pointsPerXTick = 80.0
    private static let defaultSymbolArea = 50.0
    private static let defaultRuleWidth = 2.0
    // Below the plot: from its edge to the labels, and how far a tick line runs into that room.
    private static let labelGap = 4.0
    private static let tickLength = 6.0
    private static let normalizedStep = 0.25

    private let spec: ChartSpec
    private let marks: ChartResolvedMarks
    private let metrics: ChartTextMetrics
    private let width: Double
    private let height: Double

    static func primitives(_ spec: ChartSpec, marks: ChartResolvedMarks, width: Double, height: Double, metrics: ChartTextMetrics) -> [ChartPrimitive] {
        ChartLayout(spec: spec, marks: marks, metrics: metrics, width: width, height: height).layout()
    }

    // MARK: - Extents

    /// What one axis plots, before it has points.
    private struct Extent {
        var categories: [String] = []
        var seen: Set<String> = []
        var lo = Double.infinity
        var hi = -Double.infinity
        var dateLo: Date?
        var dateHi: Date?
        var normalized = false

        mutating func add(_ value: ChartScalar, unit: Calendar.Component?) {
            switch value {
            case .string(let name):
                if seen.insert(name).inserted { categories.append(name) }
            case .number(let number):
                add(number)
            case .integer(let number):
                add(Double(number))
            case .date(let date):
                let bin = ChartDates.bin(date, unit)
                dateLo = dateLo.map { min($0, bin.start) } ?? bin.start
                dateHi = dateHi.map { max($0, bin.end) } ?? bin.end
            }
        }

        mutating func add(_ number: Double) {
            guard number.isFinite else { return }
            lo = min(lo, number)
            hi = max(hi, number)
        }

        var hasNumbers: Bool { lo <= hi }
    }

    /// One bar's reach along its value axis, when it comes from stacking.
    private struct Stacked {
        var vertical: Bool
        var low: Double
        var high: Double
    }

    private func isNumber(_ value: ChartScalar?) -> Bool {
        switch value {
        case .number?, .integer?: return true
        default: return false
        }
    }

    private func number(_ value: ChartScalar?) -> Double? {
        switch value {
        case .number(let number)?: return number
        case .integer(let number)?: return Double(number)
        default: return nil
        }
    }

    /// What bars stack by: their direction and position, one for a date bin however the dates in
    /// it differ, and one for a number written as an integer or not.
    private struct StackKey: Hashable {
        enum Position: Hashable {
            case none
            case category(String)
            case number(Double)
            case date(Date)
        }
        var vertical: Bool
        var position: Position
    }

    private func stackPosition(_ value: ChartScalar?, unit: Calendar.Component?) -> StackKey.Position {
        switch value {
        case .string(let name)?: return .category(name)
        case .number(let number)?: return .number(number)
        case .integer(let number)?: return .number(Double(number))
        case .date(let date)?: return .date(ChartDates.bin(date, unit).start)
        case nil: return .none
        }
    }

    // The value of a bar that stacks, and where. nil for one that spans two values of its own or
    // has no number.
    private func stackedValue(_ instance: ChartMarkInstance) -> (value: Double, key: StackKey)? {
        guard instance.mark.kind == .BarMark || instance.mark.kind == .AreaMark else { return nil }
        let x = instance.values["x"], y = instance.values["y"]
        switch instance.mark.form {
        case .xy, .xySeries:
            let vertical = !(isNumber(x) && !isNumber(y))
            let position = vertical ? stackPosition(x, unit: instance.mark.values["x"]?.unit) : stackPosition(y, unit: instance.mark.values["y"]?.unit)
            return number(vertical ? y : x).map { ($0, StackKey(vertical: vertical, position: position)) }
        case .xPoints:
            return number(x).map { ($0, StackKey(vertical: false, position: .none)) }
        case .yPoints:
            return number(y).map { ($0, StackKey(vertical: true, position: .none)) }
        default:
            return nil
        }
    }

    // Each stacking bar's span, by instance. Bars at one position and in one direction stack in
    // row order, out from 0 on each side. Normalized divides that by the longer side, so it reaches
    // 1; center moves it so its ends are as far from 0 (measured on macOS 27, negatives included).
    private func stacks() -> [Int: Stacked] {
        var entries: [(index: Int, value: Double, key: StackKey)] = []
        var totals: [StackKey: (positive: Double, negative: Double)] = [:]
        for (index, instance) in marks.instances.enumerated() {
            guard let stacked = stackedValue(instance), stacked.value.isFinite else { continue }
            entries.append((index, stacked.value, stacked.key))
            if stacked.value >= 0 {
                totals[stacked.key, default: (0, 0)].positive += stacked.value
            } else {
                totals[stacked.key, default: (0, 0)].negative += stacked.value
            }
        }
        var reached: [StackKey: (positive: Double, negative: Double)] = [:]
        var spans: [Int: Stacked] = [:]
        for entry in entries {
            let stacking = marks.instances[entry.index].mark.stacking
            var low = 0.0, high = entry.value
            if stacking != .unstacked {
                if entry.value >= 0 {
                    low = reached[entry.key]?.positive ?? 0
                    high = low + entry.value
                    reached[entry.key, default: (0, 0)].positive = high
                } else {
                    low = reached[entry.key]?.negative ?? 0
                    high = low + entry.value
                    reached[entry.key, default: (0, 0)].negative = high
                }
            }
            let total = totals[entry.key] ?? (0, 0)
            if stacking == .normalized {
                let longest = max(total.positive, -total.negative)
                low = longest == 0 ? 0 : low / longest
                high = longest == 0 ? 0 : high / longest
            } else if stacking == .center {
                let shift = (total.positive + total.negative) / 2
                low -= shift
                high -= shift
            }
            spans[entry.index] = Stacked(vertical: entry.key.vertical, low: low, high: high)
        }
        return spans
    }

    private func extents(_ stacks: [Int: Stacked]) -> (x: Extent, y: Extent) {
        var x = Extent(), y = Extent()
        for (index, instance) in marks.instances.enumerated() {
            let stack = stacks[index]
            for (keys, isX) in [(["x", "xStart", "xEnd"], true), (["y", "yStart", "yEnd"], false)] {
                let stacksHere = stack.map { $0.vertical != isX } ?? false
                // As Apple's ChartContentBuilder opens them, a start and end share one unit.
                let unit = keys.lazy.compactMap { instance.mark.values[$0]?.unit }.first
                for key in keys where !stacksHere {
                    guard let value = instance.values[key] else { continue }
                    if isX { x.add(value, unit: unit) } else { y.add(value, unit: unit) }
                }
            }
            guard let stack else { continue }
            let normalized = instance.mark.stacking == .normalized
            if stack.vertical {
                y.add(stack.low)
                y.add(stack.high)
                y.normalized = y.normalized || normalized
            } else {
                x.add(stack.low)
                x.add(stack.high)
                x.normalized = x.normalized || normalized
            }
        }
        return (x, y)
    }

    // MARK: - Axes

    /// An axis's scale, without its points, and its ticks: where each goes and its label.
    private struct Axis {
        var scale = ChartAxisScale()
        var ticks: [(value: ChartScalar, label: String)] = []
    }

    private func axis(_ extent: Extent, ticks count: Int) -> Axis {
        var axis = Axis()
        if !extent.categories.isEmpty {
            axis.scale.kind = .bands(Dictionary(uniqueKeysWithValues: extent.categories.enumerated().map { ($1, $0) }))
            axis.ticks = extent.categories.map { (.string($0), $0) }
        } else if let lo = extent.dateLo, let hi = extent.dateHi {
            axis.scale.kind = .dates(lo: lo, hi: hi)
            axis.ticks = dateTicks(lo, hi, count: count)
        } else if extent.hasNumbers {
            // An automatic domain holds 0.
            let lo = min(extent.lo, 0), hi = max(extent.hi, 0)
            let domain = extent.normalized ? ChartTicks.domain(lo, hi, step: Self.normalizedStep) : ChartTicks.domain(lo, hi, count: count)
            axis.scale.kind = .numbers(lo: domain.lo, hi: domain.hi)
            axis.ticks = domain.ticks.map { (.number($0), metrics.number(extent.normalized ? $0 * 100 : $0)) }
        }
        return axis
    }

    // A tick shows what changed since the one before: the year only at the first and when it turns.
    private func dateTicks(_ lo: Date, _ hi: Date, count: Int) -> [(value: ChartScalar, label: String)] {
        let stride = ChartDates.stride(lo, hi, count: count)
        var lastYear: Int?
        return ChartDates.ticks(lo, hi, stride: stride).map { tick in
            let year = Calendar.current.component(.year, from: tick)
            defer { lastYear = year }
            let skeleton: String
            switch stride.unit {
            case .year: skeleton = "y"
            case .month: skeleton = lastYear == year ? "MMM" : "yMMM"
            case .weekOfYear, .day: skeleton = "MMMd"
            case .hour: skeleton = "j"
            case .minute: skeleton = "jm"
            default: skeleton = "jms"
            }
            return (.date(tick), metrics.date(tick, skeleton))
        }
    }

    // MARK: - Layout

    private func layout() -> [ChartPrimitive] {
        let stacks = stacks()
        let extents = extents(stacks)
        let lineHeight = metrics.size("0").height
        let xShown = spec.x.visibility != .hidden
        let yShown = spec.y.visibility != .hidden

        // The y labels' width sets the plot's width, which sets the x ticks; the height is known first.
        let hasX = !extents.x.categories.isEmpty || extents.x.dateLo != nil || extents.x.hasNumbers
        let hasY = !extents.y.categories.isEmpty || extents.y.dateLo != nil || extents.y.hasNumbers
        let top = yShown && hasY ? lineHeight / 2 : 0
        let bottom = xShown && hasX ? lineHeight + Self.labelGap * 2 : 0
        let plotHeight = max(height - top - bottom, 1)
        var yAxis = axis(extents.y, ticks: max(2, min(Int(plotHeight / Self.pointsPerTick), 6)))
        let yLabelWidth = yShown ? yAxis.ticks.map { metrics.size($0.label).width }.max() ?? 0 : 0
        let plotWidth = max(width - (yLabelWidth > 0 ? yLabelWidth + Self.labelGap * 2 : 0), 1)
        var xAxis = axis(extents.x, ticks: max(2, min(Int(plotWidth / Self.pointsPerXTick), 8)))

        let plot = ChartRect(x: 0, y: top, width: plotWidth, height: plotHeight)
        xAxis.scale.start = plot.x
        xAxis.scale.end = plot.x + plot.width
        // Numbers and dates rise up the axis; bands read from the top.
        if case .bands = yAxis.scale.kind {
            yAxis.scale.start = plot.y
            yAxis.scale.end = plot.y + plot.height
        } else {
            yAxis.scale.start = plot.y + plot.height
            yAxis.scale.end = plot.y
        }

        var primitives: [ChartPrimitive] = []
        if yShown { appendYAxis(yAxis, plot, lineHeight: lineHeight, into: &primitives) }
        if xShown { appendXAxis(xAxis, plot, lineHeight: lineHeight, into: &primitives) }
        appendMarks(stacks, xAxis.scale, yAxis.scale, plot, into: &primitives)
        return primitives.filter(\.isDrawable)
    }

    // How many bands a label takes that needs `room` points, so labels never overlap, and their
    // lines, which would otherwise fill a tight axis.
    private func bandStride(_ scale: ChartAxisScale, room: Double) -> Int {
        let band = abs(scale.bandWidth)
        return band > 0 ? max(1, Int((room / band).rounded(.up))) : 1
    }

    private func appendYAxis(_ axis: Axis, _ plot: ChartRect, lineHeight: Double, into primitives: inout [ChartPrimitive]) {
        let right = plot.x + plot.width
        var every = 1
        if case .bands(let names) = axis.scale.kind {
            every = bandStride(axis.scale, room: lineHeight)
            for index in stride(from: 0, through: names.count, by: every) {
                let y = axis.scale.start + Double(index) * axis.scale.bandWidth
                primitives.append(.line(from: ChartPoint(x: plot.x, y: y), to: ChartPoint(x: right + Self.tickLength, y: y), ink: Self.gridInk, stroke: Self.tickDash))
            }
        }
        for (index, tick) in axis.ticks.enumerated() where index % every == 0 {
            guard let y = axis.scale.position(tick.value, unit: nil) else { continue }
            if case .bands = axis.scale.kind {} else {
                primitives.append(.line(from: ChartPoint(x: plot.x, y: y), to: ChartPoint(x: right, y: y), ink: Self.gridInk, stroke: ChartStroke()))
            }
            primitives.append(.text(tick.label, position: ChartPoint(x: right + Self.labelGap, y: y), alignment: ChartPoint(x: 0, y: 0.5)))
        }
    }

    private func appendXAxis(_ axis: Axis, _ plot: ChartRect, lineHeight: Double, into primitives: inout [ChartPrimitive]) {
        let bottom = plot.y + plot.height
        if case .none = axis.scale.kind { return }
        let labelY = bottom + Self.labelGap
        primitives.append(.line(from: ChartPoint(x: plot.x, y: bottom), to: ChartPoint(x: plot.x + plot.width, y: bottom), ink: Self.axisInk, stroke: ChartStroke()))
        func tickLine(_ x: Double) -> ChartPrimitive {
            .line(from: ChartPoint(x: x, y: plot.y), to: ChartPoint(x: x, y: bottom + Self.tickLength), ink: Self.gridInk, stroke: Self.tickDash)
        }
        if case .bands(let names) = axis.scale.kind {
            // Labels wider than their band show every few bands.
            let widest = axis.ticks.map { metrics.size($0.label).width }.max() ?? 0
            let every = bandStride(axis.scale, room: widest + Self.labelGap)
            for index in stride(from: 0, through: names.count, by: every) {
                primitives.append(tickLine(axis.scale.start + Double(index) * axis.scale.bandWidth))
            }
            for (index, tick) in axis.ticks.enumerated() where index % every == 0 {
                guard let x = axis.scale.position(tick.value, unit: nil) else { continue }
                primitives.append(.text(tick.label, position: ChartPoint(x: x, y: labelY), alignment: ChartPoint(x: 0.5, y: 0)))
            }
            return
        }
        let right = plot.x + plot.width
        var nextFree = -Double.infinity
        for tick in axis.ticks {
            guard let x = axis.scale.position(tick.value, unit: nil) else { continue }
            primitives.append(tickLine(x))
            // A label starts at its tick; one that would pass the plot's end or the label before
            // it is left out.
            let start = x + Self.labelGap
            let labelWidth = metrics.size(tick.label).width
            guard start >= nextFree, start + labelWidth <= right else { continue }
            primitives.append(.text(tick.label, position: ChartPoint(x: start, y: labelY), alignment: ChartPoint(x: 0, y: 0)))
            nextFree = start + labelWidth + Self.labelGap
        }
    }

    // MARK: - Marks

    private func seriesNames() -> [String] {
        var names: [String] = []
        var seen: Set<String> = []
        if case .strings(let domain) = spec.styles.foregroundDomain {
            names = domain
            seen = Set(domain)
        }
        for instance in marks.instances {
            if let key = instance.styleKey, seen.insert(key).inserted {
                names.append(key)
            }
        }
        return names
    }

    private func ink(_ instance: ChartMarkInstance, series: [String: Int]) -> ChartInk {
        if let key = instance.styleKey, let index = series[key] {
            if case .colors(let colors)? = spec.styles.foregroundRange, !colors.isEmpty {
                return .color(colors[index % colors.count])
            }
            return .color(Self.seriesColors[index % Self.seriesColors.count])
        }
        for modifier in instance.mark.modifiers {
            if case .foregroundStyle(let color) = modifier {
                return .color(color)
            }
        }
        return .color(Self.seriesColors[0])
    }

    private func appendMarks(_ stacks: [Int: Stacked], _ x: ChartAxisScale, _ y: ChartAxisScale, _ plot: ChartRect,
                             into primitives: inout [ChartPrimitive]) {
        var series: [String: Int] = [:]
        for (index, name) in seriesNames().enumerated() {
            series[name] = index
        }
        for (index, instance) in marks.instances.enumerated() {
            let ink = ink(instance, series: series)
            switch instance.mark.kind {
            case .BarMark:
                if let rect = bar(instance, stack: stacks[index], x, y, plot) {
                    primitives.append(.rect(rect, ink: ink))
                }
            case .PointMark:
                if let primitive = point(instance, x, y, plot, ink: ink) {
                    primitives.append(primitive)
                }
            case .RuleMark:
                if let primitive = rule(instance, x, y, plot, ink: ink) {
                    primitives.append(primitive)
                }
            case .LineMark, .AreaMark, .RectangleMark, .SectorMark:
                break
            }
        }
    }

    // How thick a bar is in `room`, the width of its band or bin. A value that has neither gives
    // no room: automatic is a fixed size there and a ratio nothing (measured on macOS 27).
    private func thickness(_ dimension: ChartDimension, room: Double) -> Double {
        switch dimension {
        case .automatic: return room > 0 ? room * Self.barRatio : Self.unbinnedBarThickness
        case .fixed(let points): return points
        case .ratio(let ratio): return room * ratio
        case .inset(let points): return max(room - 2 * points, 0)
        }
    }

    // The points a start and an end span on an axis: the middles of their date bins, or the outer
    // edges of their bands (measured on macOS 27: a pair of categories covers both whole).
    private func span(_ instance: ChartMarkInstance, _ startKey: String, _ endKey: String, _ scale: ChartAxisScale) -> (Double, Double)? {
        let unit = instance.mark.values[startKey]?.unit ?? instance.mark.values[endKey]?.unit
        guard let start = instance.values[startKey], let end = instance.values[endKey],
              let low = scale.position(start, unit: unit), let high = scale.position(end, unit: unit) else { return nil }
        return (low - scale.bandWidth / 2, high + scale.bandWidth / 2)
    }

    // A span in points from the plot's corner, or the plot's whole run where a mark gives none.
    private func pointsSpan(_ instance: ChartMarkInstance, _ startKey: String, _ endKey: String, whole: (Double, Double)) -> (Double, Double) {
        (instance.mark.points[startKey].map { whole.0 + $0 } ?? whole.0, instance.mark.points[endKey].map { whole.0 + $0 } ?? whole.1)
    }

    private func bar(_ instance: ChartMarkInstance, stack: Stacked?, _ x: ChartAxisScale, _ y: ChartAxisScale, _ plot: ChartRect) -> ChartRect? {
        let mark = instance.mark
        let wholeX = (plot.x, plot.x + plot.width), wholeY = (plot.y, plot.y + plot.height)

        func crossSpan(_ key: String, _ scale: ChartAxisScale, _ dimension: ChartDimension) -> (Double, Double)? {
            guard let value = instance.values[key], let center = scale.position(value, unit: mark.values[key]?.unit) else { return nil }
            let across = thickness(dimension, room: scale.binWidth(value, unit: mark.values[key]?.unit))
            return (center - across / 2, center + across / 2)
        }

        var xs: (Double, Double)?
        var ys: (Double, Double)?
        if let stack {
            if stack.vertical {
                ys = (y.position(stack.low), y.position(stack.high))
                xs = mark.form == .yPoints ? pointsSpan(instance, "xStart", "xEnd", whole: wholeX)
                    : crossSpan("x", x, mark.width)
            } else {
                xs = (x.position(stack.low), x.position(stack.high))
                ys = mark.form == .xPoints ? pointsSpan(instance, "yStart", "yEnd", whole: wholeY)
                    : crossSpan("y", y, mark.height)
            }
        } else {
            switch mark.form {
            case .xy:
                // No number on either axis: a block where the two values meet.
                xs = crossSpan("x", x, mark.width)
                ys = crossSpan("y", y, mark.height)
            case .xPoints:
                xs = crossSpan("x", x, mark.width)
                ys = pointsSpan(instance, "yStart", "yEnd", whole: wholeY)
            case .yPoints:
                ys = crossSpan("y", y, mark.height)
                xs = pointsSpan(instance, "xStart", "xEnd", whole: wholeX)
            case .xPair:
                xs = crossSpan("x", x, mark.width)
                ys = span(instance, "yStart", "yEnd", y)
            case .pairY:
                xs = span(instance, "xStart", "xEnd", x)
                ys = crossSpan("y", y, mark.height)
            case .pointsPair:
                xs = pointsSpan(instance, "xStart", "xEnd", whole: wholeX)
                ys = span(instance, "yStart", "yEnd", y)
            case .pairPoints:
                xs = span(instance, "xStart", "xEnd", x)
                ys = pointsSpan(instance, "yStart", "yEnd", whole: wholeY)
            default:
                break
            }
        }
        guard let xs, let ys else { return nil }
        return ChartRect(x: min(xs.0, xs.1), y: min(ys.0, ys.1), width: abs(xs.1 - xs.0), height: abs(ys.1 - ys.0))
    }

    // Where a mark's value goes on an axis. A coordinate in points counts from the plot's corner; a
    // missing one is its middle.
    private func coordinate(_ instance: ChartMarkInstance, _ key: String, _ scale: ChartAxisScale, origin: Double, length: Double) -> Double? {
        if let value = instance.values[key] {
            return scale.position(value, unit: instance.mark.values[key]?.unit)
        }
        return instance.mark.points[key].map { origin + $0 } ?? origin + length / 2
    }

    private func point(_ instance: ChartMarkInstance, _ x: ChartAxisScale, _ y: ChartAxisScale, _ plot: ChartRect, ink: ChartInk) -> ChartPrimitive? {
        let mark = instance.mark
        guard let centerX = coordinate(instance, "x", x, origin: plot.x, length: plot.width),
              let centerY = coordinate(instance, "y", y, origin: plot.y, length: plot.height) else { return nil }
        var shape = ChartSymbol.circle
        var area = Self.defaultSymbolArea
        var size: ChartSize?
        // Backward, so the modifier nearest the mark is the one that stays.
        for modifier in mark.modifiers.reversed() {
            switch modifier {
            case .symbol(let symbol):
                shape = symbol
            case .symbolArea(let given):
                area = max(given, 0)
                size = nil
            case .symbolSize(let given):
                size = given
            default:
                break
            }
        }
        // The area is the shape's own: a circle of 100 is 11.3 across, a square 10 (measured).
        let side = shape == .circle ? 2 * (area / .pi).squareRoot() : area.squareRoot()
        return .symbol(shape, center: ChartPoint(x: centerX, y: centerY), size: size ?? ChartSize(width: side, height: side), ink: ink)
    }

    private func rule(_ instance: ChartMarkInstance, _ x: ChartAxisScale, _ y: ChartAxisScale, _ plot: ChartRect, ink: ChartInk) -> ChartPrimitive? {
        let mark = instance.mark
        let wholeX = (plot.x, plot.x + plot.width), wholeY = (plot.y, plot.y + plot.height)
        var stroke = ChartStroke(lineWidth: Self.defaultRuleWidth)
        for modifier in mark.modifiers.reversed() {
            if case .lineStyle(let style) = modifier {
                stroke = style
            }
        }
        let atX = coordinate(instance, "x", x, origin: plot.x, length: plot.width).map { ($0, $0) }
        let atY = coordinate(instance, "y", y, origin: plot.y, length: plot.height).map { ($0, $0) }
        let xs: (Double, Double)?
        let ys: (Double, Double)?
        switch mark.form {
        case .xPoints:
            xs = atX
            ys = pointsSpan(instance, "yStart", "yEnd", whole: wholeY)
        case .yPoints:
            ys = atY
            xs = pointsSpan(instance, "xStart", "xEnd", whole: wholeX)
        case .xPair:
            xs = atX
            ys = span(instance, "yStart", "yEnd", y)
        case .pairY:
            ys = atY
            xs = span(instance, "xStart", "xEnd", x)
        case .pointsPair:
            xs = atX
            ys = span(instance, "yStart", "yEnd", y)
        case .pairPoints:
            ys = atY
            xs = span(instance, "xStart", "xEnd", x)
        default:
            return nil
        }
        guard let xs, let ys else { return nil }
        return .line(from: ChartPoint(x: xs.0, y: ys.0), to: ChartPoint(x: xs.1, y: ys.1), ink: ink, stroke: stroke)
    }
}
