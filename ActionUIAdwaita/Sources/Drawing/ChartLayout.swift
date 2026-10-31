// Sources/Drawing/ChartLayout.swift
/*
 Lays out a chart for a size: its marks, axes and gridlines as drawing primitives in points. No GTK
 here: text is measured and formatted through ChartTextMetrics, so a test checks the geometry as
 numbers, and Elements/Chart+Adwaita.swift only draws the primitives.

 The goal is a chart comparable to Swift Charts, not a copy (Documentation/Schemas/Chart.md lists the
 differences). Swift Charts' look, as drawn on macOS 27:
 - The y axis is on the trailing side, with solid gridlines at its ticks.
 - Categories are bands of equal width, in order of first use, with dashed lines at the band edges.
 - Number and date ticks on the x axis have a dashed line, and their label starts at the tick.
 - An automatic number domain includes 0 and is widened to whole steps (ChartTicks), and a date
   axis covers each value's whole bin. An explicit domain is exact; marks past it still draw, and a
   category it does not name does not. Labels of one axis share their decimals. A domain of one
   value has no ticks and puts every mark in the middle.
 - A value the scale's math has no answer for is not drawn, and a bar stands on 0, so a log scale
   draws no bars at all, not even the upper bar of a stack. Stacked areas draw the layers that have
   both edges. A value past a domain goes where the math puts it, on every scale type.
 - A bar takes 0.7 of its band or date bin, and 8 points where a value has neither. Bars at one
   position stack in row order, those below 0 downward. A normalized stack is that as a percentage
   of the longer side, on an axis of plain numbers (a rule at 40 sits at 40 of 100); a centered one
   is that moved so its two ends are as far from 0.
 - A start and end on an axis of categories run from the edge of one band to the far edge of the other;
   dates with a unit go in the middle of their bins, as a single value does.
 - Points given to a mark count from the plot's top leading corner.
 - A point's size is the area of its symbol, 50 unless given, and a rule is 2 wide unless given.
 - The modifier nearest a mark wins: its own over its Plot's.
 - An AxisMarks chooses its ticks and draws in its own way: desiredCount is the count of ticks an
   automatic axis aims for, and explicit values or a stride change the ticks, not the domain, which
   holds what each automatic AxisMarks widens it to. A list of names on bands changes nothing.
   Marks with content draw only that content, each entry its own way. Lines on x and on bands are
   dashed, and on bands they sit at the band edges, centered or not. A tick's given length adds to
   the room around the plot and moves no label.
 - A label's anchor counts only in these (measured on macOS 27): on x topTrailing and bottomTrailing
   end it before its tick or its band's end, and bottomLeading and bottomTrailing put it inside the
   plot; on a y axis of numbers top and bottom put it under or over its tick, and the side that
   faces the plot puts it inside. A centered label on x numbers and dates sits between its tick and
   the next.
 - Marks draw in the order of the content, over the grid.
 - A line or an area joins its points in data order, not by x. Marks with one series and the same
   {"by"} styles are one line, in the style of the first, drawn where that one is. A value that is
   not finite breaks it in two, and one point alone draws nothing. A line is 2 wide, an area is
   opaque, and stacked areas stack as bars do, each kind on its own. A start and end on an axis of
   categories run from edge to edge, as a bar's do.

 Bars, points, rules, lines and areas draw here; other marks still count on the axes.
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
    case path([ChartPathElement], ink: ChartInk, stroke: ChartStroke)
    case fill([ChartPathElement], ink: ChartInk)
    /// `alignment` is the point of the text placed at `position`, as fractions of its size.
    case text(String, position: ChartPoint, alignment: ChartPoint, ink: ChartInk)

    /// Whether GSK can take it: values from a document or rows can pass what its floats hold (they
    /// would reach it as infinities), and a line needs a width.
    var isDrawable: Bool {
        func finite(_ values: Double...) -> Bool { values.allSatisfy { Float($0).isFinite } }
        switch self {
        case let .line(from, to, _, stroke):
            return Float(stroke.lineWidth) > 0 && finite(from.x, from.y, to.x, to.y, stroke.lineWidth, stroke.miterLimit, stroke.dashPhase)
                && stroke.dash.allSatisfy { finite($0) }
        case let .rect(rect, _):
            return finite(rect.x, rect.y, rect.width, rect.height)
        case let .symbol(_, center, size, _):
            return finite(center.x, center.y, size.width, size.height)
        case let .path(elements, _, stroke):
            return Float(stroke.lineWidth) > 0 && finite(stroke.lineWidth, stroke.miterLimit, stroke.dashPhase)
                && stroke.dash.allSatisfy { finite($0) } && Self.finite(elements)
        case let .fill(elements, _):
            return Self.finite(elements)
        case let .text(_, position, _, _):
            return finite(position.x, position.y)
        }
    }

    private static func finite(_ elements: [ChartPathElement]) -> Bool {
        func finite(_ point: ChartPoint) -> Bool { Float(point.x).isFinite && Float(point.y).isFinite }
        return elements.allSatisfy { element in
            switch element {
            case .move(let point), .line(let point): return finite(point)
            case let .curve(first, second, end): return finite(first) && finite(second) && finite(end)
            }
        }
    }
}

/// Text as the renderer measures and formats it.
struct ChartTextMetrics {
    var size: (String) -> ChartSize
    /// A number with this many decimals.
    var number: (Double, Int) -> String
    /// A number in an axis's own format.
    var formatted: (Double, NumberFormatSpec) -> String
    var date: (Date, _ skeleton: String) -> String
}

private extension ChartAlignment {
    var isLeading: Bool { self == .leading || self == .topLeading || self == .bottomLeading }
    var isTrailing: Bool { self == .trailing || self == .topTrailing || self == .bottomTrailing }
    var isTop: Bool { self == .top || self == .topLeading || self == .topTrailing }
    var isBottom: Bool { self == .bottom || self == .bottomLeading || self == .bottomTrailing }
}

struct ChartLayout {
    // Swift Charts' order for series, in ActionUI's named colors.
    static let seriesColors: [ColorSpec] = [.named(.blue), .named(.green), .named(.orange), .named(.purple), .named(.red), .named(.cyan), .named(.yellow)]
    static let gridInk = ChartInk.text(opacity: 0.14)
    static let labelInk = ChartInk.text(opacity: 0.6)
    private static let tickDash = ChartStroke(lineWidth: 1, dash: [2, 2])
    private static let barRatio = 0.7
    private static let unbinnedBarThickness = 8.0
    private static let pointsPerDateTick = 80.0
    private static let defaultSymbolArea = 50.0
    private static let defaultRuleWidth = 2.0
    private static let defaultLine = ChartStroke(lineWidth: 2, lineCap: .round, lineJoin: .round)
    // Below the plot: from its edge to the labels, and how far a tick line runs into that room.
    private static let labelGap = 4.0
    private static let tickLength = 6.0
    private static let yTickLength = 4.0
    private static let percent = 100.0

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

    /// What marks stack by: their kind (a bar and an area at one place do not stack, measured on
    /// macOS 27), direction and position, one for a date bin however the dates in it differ, and one
    /// for a number written as an integer or not.
    private struct StackKey: Hashable {
        enum Position: Hashable {
            case none
            case category(String)
            case number(Double)
            case date(Date)
        }
        var kind: ChartMarkKind
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
            return number(vertical ? y : x).map { ($0, StackKey(kind: instance.mark.kind, vertical: vertical, position: position)) }
        case .xPoints:
            return number(x).map { ($0, StackKey(kind: instance.mark.kind, vertical: false, position: .none)) }
        case .yPoints:
            return number(y).map { ($0, StackKey(kind: instance.mark.kind, vertical: true, position: .none)) }
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
                low = longest == 0 ? 0 : low / longest * Self.percent
                high = longest == 0 ? 0 : high / longest * Self.percent
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
            if stack.vertical {
                y.add(stack.low)
                y.add(stack.high)
            } else {
                x.add(stack.low)
                x.add(stack.high)
            }
        }
        return (x, y)
    }

    // MARK: - Axes

    /// An axis's scale, without its points, and its ticks: where each goes and its label.
    private struct Axis {
        var scale = ChartAxisScale()
        /// As a plain axis ticks. An AxisMarks that says how makes its own.
        var ticks: [(value: ChartScalar, label: String)] = []
        /// What an automatic AxisMarks steps over, and whether that is an explicit domain. nil where
        /// a count of ticks means nothing: on a log scale, or over one value (measured on macOS 27).
        var steps: (lo: Double, hi: Double, exact: Bool)?
        var reversed = false

        var isEmpty: Bool {
            if case .none = scale.kind { return true }
            return false
        }
    }

    private func axis(_ extent: Extent, _ spec: ChartAxisSpec, length: Double) -> Axis {
        var axis = Axis()
        var includesZero = true
        if case .automatic(let zero, let reversed) = spec.domain {
            includesZero = zero ?? true
            axis.reversed = reversed ?? false
        }
        var dates: (lo: Date, hi: Date)?
        if let lo = extent.dateLo, let hi = extent.dateHi { dates = (lo, hi) }
        var categories = extent.categories
        switch spec.domain {
        case .strings(let names):
            // A name given twice is one band here. Swift Charts keeps a band for each, the first empty.
            var seen: Set<String> = []
            categories = names.filter { seen.insert($0).inserted }
        case .dates(let range):
            dates = (range.lowerBound, range.upperBound)
        case .numbers(let range):
            numberAxis(&axis, spec, lo: range.lowerBound, hi: range.upperBound, exact: true)
            return axis
        case .automatic:
            break
        }
        if !categories.isEmpty {
            axis.scale.kind = .bands(Dictionary(uniqueKeysWithValues: categories.enumerated().map { ($1, $0) }))
            axis.ticks = categories.map { (.string($0), $0) }
        } else if let dates {
            axis.scale.kind = .dates(lo: dates.lo, hi: dates.hi)
            axis.ticks = dateTicks(dates.lo, dates.hi, count: max(2, min(Int(length / Self.pointsPerDateTick), 8)))
        } else if extent.hasNumbers {
            let lo = includesZero ? min(extent.lo, 0) : extent.lo
            let hi = includesZero ? max(extent.hi, 0) : extent.hi
            numberAxis(&axis, spec, lo: lo, hi: hi, exact: false)
        }
        return axis
    }

    private func numberAxis(_ axis: inout Axis, _ spec: ChartAxisSpec, lo: Double, hi: Double, exact: Bool) {
        let transform = ChartScaleTransform(spec.scaleType)
        axis.scale.transform = transform
        // One value, explicit or the only one plotted (measured on macOS 27).
        guard hi > lo else {
            axis.scale.kind = .numbers(lo: lo, hi: hi)
            return
        }
        var low = lo, high = hi
        var ticks: [Double]
        var digits = 0
        switch transform {
        case .log:
            ticks = ChartTicks.powersOfTen(lo, hi)
            digits = smallestDigits(ticks)
        case .symmetricLog:
            let scale = ChartTicks.symmetricLog(lo, hi, widening: !exact)
            (low, high, ticks) = (scale.lo, scale.hi, scale.ticks)
            digits = smallestDigits(ticks)
        case .linear, .squareRoot, .power:
            axis.steps = (lo, hi, exact)
            if exact {
                let inside = ChartTicks.inside(lo, hi)
                (ticks, digits) = (inside.ticks, ChartTicks.fractionDigits(inside.step))
            } else {
                let plain = ChartTicks.widened(lo, hi)
                (low, high, ticks, digits) = (plain.lo, plain.hi, plain.ticks, ChartTicks.fractionDigits(plain.step))
                // The domain holds what each automatic AxisMarks widens it to (measured on
                // macOS 27: 4 and 8 ticks over values up to 90 are 0...100, in either order).
                let domains = automaticMarks(spec).map {
                    ChartTicks.widened(lo, hi, ideal: $0.ideal, roundLower: $0.roundLower, roundUpper: $0.roundUpper)
                }
                low = domains.map(\.lo).min() ?? low
                high = domains.map(\.hi).max() ?? high
            }
        }
        axis.scale.kind = .numbers(lo: low, hi: high)
        axis.ticks = ticks.map { (.number($0), metrics.number($0, $0 == 0 ? 0 : digits)) }
    }

    // The AxisMarks with automatic values, which set an automatic domain; a plain axis has one, and
    // so has an axis whose AxisMarks all give their own values.
    private func automaticMarks(_ spec: ChartAxisSpec) -> [(ideal: Int, roundLower: Bool, roundUpper: Bool)] {
        let automatic = marks(spec).compactMap { marks -> (ideal: Int, roundLower: Bool, roundUpper: Bool)? in
            guard case .automatic(let count, let lower, let upper) = marks.values else { return nil }
            return (count ?? ChartTicks.idealTicks, lower ?? true, upper ?? true)
        }
        return automatic.isEmpty ? [(ChartTicks.idealTicks, true, true)] : automatic
    }

    // Powers of ten have no step: their labels take the decimals of the smallest, as 0.01 and 100.00.
    private func smallestDigits(_ ticks: [Double]) -> Int {
        ticks.map(abs).filter { $0 > 0 }.min().map(ChartTicks.fractionDigits) ?? 0
    }

    // A tick shows what changed since the one before: the year only at the first and when it turns.
    private func dateTicks(_ lo: Date, _ hi: Date, count: Int) -> [(value: ChartScalar, label: String)] {
        let stride = ChartDates.stride(lo, hi, count: count)
        return dateLabels(ChartDates.ticks(lo, hi, stride: stride), unit: stride.unit)
    }

    private func dateLabels(_ dates: [Date], unit: Calendar.Component) -> [(value: ChartScalar, label: String)] {
        var lastYear: Int?
        return dates.map { tick in
            let year = ChartDates.calendar.component(.year, from: tick)
            defer { lastYear = year }
            let skeleton: String
            switch unit {
            case .year: skeleton = "y"
            case .month: skeleton = lastYear == year ? "MMM" : "yMMM"
            case .weekOfYear, .weekOfMonth, .day: skeleton = "MMMd"
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

        // The y labels' width sets the plot's width, which sets the x ticks; the height is known
        // first. An x axis's kind and edges decide the room around the plot.
        let hasX = !axis(extents.x, spec.x, length: 0).isEmpty
        let hasY = !axis(extents.y, spec.y, length: 0).isEmpty
        let xRows = hasX ? labelEdges(spec.x, isX: true) : []
        let rowHeight = lineHeight + Self.labelGap * 2
        let yShown = hasY && !labelEdges(spec.y, isX: false).isEmpty
        let topTicks = hasX ? tickRoom(spec.x, isX: true, .top) : 0, bottomTicks = hasX ? tickRoom(spec.x, isX: true, .bottom) : 0
        let top = (xRows.contains(.top) ? rowHeight : yShown ? lineHeight / 2 : 0) + topTicks
        let bottom = (xRows.contains(.bottom) ? rowHeight : 0) + bottomTicks
        let plotHeight = max(height - top - bottom, 1)
        var yAxis = axis(extents.y, spec.y, length: plotHeight)
        let yGroups = groups(spec.y, yAxis, isX: false)
        func room(_ edge: ChartAxisMarkPosition) -> Double {
            let widest = yGroups.filter { $0.edge == edge && $0.label != nil }.flatMap(\.ticks).map { metrics.size($0.label).width }.max() ?? 0
            return (widest > 0 ? widest + Self.labelGap * 2 : 0) + (hasY ? tickRoom(spec.y, isX: false, edge) : 0)
        }
        let leading = room(.leading), trailing = room(.trailing)
        let plotWidth = max(width - leading - trailing, 1)
        var xAxis = axis(extents.x, spec.x, length: plotWidth)
        let xGroups = groups(spec.x, xAxis, isX: true)

        let plot = ChartRect(x: leading, y: top, width: plotWidth, height: plotHeight)
        place(&xAxis, spec.x, from: plot.x, to: plot.x + plot.width)
        // Numbers and dates rise up the axis; bands read from the top.
        if case .bands = yAxis.scale.kind {
            place(&yAxis, spec.y, from: plot.y, to: plot.y + plot.height)
        } else {
            place(&yAxis, spec.y, from: plot.y + plot.height, to: plot.y)
        }

        var primitives: [ChartPrimitive] = []
        for group in yGroups { appendYGroup(group, yAxis.scale, plot, lineHeight: lineHeight, into: &primitives) }
        for group in xGroups { appendXGroup(group, xAxis.scale, plot, into: &primitives) }
        appendMarks(stacks, xAxis.scale, yAxis.scale, plot, into: &primitives)
        return primitives.filter(\.isDrawable)
    }

    // Puts an axis on the plot, between `from` and `to` in the direction it reads, with its padding
    // or its range in points, which count from the plot's corner.
    private func place(_ axis: inout Axis, _ spec: ChartAxisSpec, from: Double, to: Double) {
        var start = from, end = to
        switch spec.range {
        case .defaultPlotDimension:
            break
        case .plotDimension(let startPadding, let endPadding):
            let direction: Double = to >= from ? 1 : -1
            start += direction * startPadding
            end -= direction * endPadding
        case .points(let range):
            let corner = min(from, to)
            start = corner + range.lowerBound
            end = corner + range.upperBound
        }
        axis.scale.start = axis.reversed ? end : start
        axis.scale.end = axis.reversed ? start : end
    }

    // How many bands a label takes that needs `room` points, so labels never overlap, and their
    // lines, which would otherwise fill a tight axis.
    private func bandStride(_ scale: ChartAxisScale, room: Double) -> Int {
        guard case .bands(let names) = scale.kind else { return 1 }
        let band = abs(scale.bandWidth)
        // A range in points can make bands far narrower than an Int counts: past the last is enough.
        return band > 0 ? max(1, Int(min((room / band).rounded(.up), Double(names.count + 1)))) : 1
    }

    // MARK: - Axis marks

    /// A line of an axis: a gridline across the plot, running `length` past it, or a tick that is
    /// only that part outside it.
    private struct AxisLine {
        var ink = ChartLayout.gridInk
        var stroke: ChartStroke
        var length = 0.0
    }

    private struct AxisLabel {
        var ink = ChartLayout.labelInk
        var anchor: ChartAlignment?
        var centered = false
        var offset = ChartSize(width: 0, height: 0)
    }

    /// One thing an AxisMarks draws, or Swift Charts' default marks: the ticks, the edge its labels
    /// and ticks are on, and what it draws at them.
    private struct AxisGroup {
        var ticks: [(value: ChartScalar, label: String)]
        var edge: ChartAxisMarkPosition
        var grid: AxisLine?
        var tick: AxisLine?
        var label: AxisLabel?
    }

    private func marks(_ spec: ChartAxisSpec) -> [ChartAxisMarksSpec] {
        guard spec.visibility != .hidden else { return [] }
        return spec.marks.flatMap { $0.isEmpty ? nil : $0 } ?? [ChartAxisMarksSpec()]
    }

    private func edge(_ marks: ChartAxisMarksSpec, isX: Bool) -> ChartAxisMarkPosition {
        switch (marks.position, isX) {
        case (.top, true), (.bottom, true), (.leading, false), (.trailing, false): return marks.position
        case (_, true): return .bottom
        case (_, false): return .trailing
        }
    }

    // The edges that hold labels, known before any tick is.
    private func labelEdges(_ spec: ChartAxisSpec, isX: Bool) -> Set<ChartAxisMarkPosition> {
        Set(marks(spec).filter { marks in
            guard let items = marks.items else { return true }
            return items.contains { item in
                if case .valueLabel = item.kind { return true } else { return false }
            }
        }.map { edge($0, isX: isX) })
    }

    // What ticks add to the room on an edge: a given length, and an automatic one on a y axis,
    // however long the labels there; they run on under the labels (measured on macOS 27).
    private func tickRoom(_ spec: ChartAxisSpec, isX: Bool, _ edge: ChartAxisMarkPosition) -> Double {
        var room = 0.0
        for marks in marks(spec) where self.edge(marks, isX: isX) == edge {
            for item in marks.items ?? [] {
                guard case .tick(_, let length, _) = item.kind else { continue }
                switch length {
                case .fixed(let points): room = max(room, points)
                case .automatic where !isX: room = max(room, Self.yTickLength)
                default: break
                }
            }
        }
        return room
    }

    private func groups(_ spec: ChartAxisSpec, _ axis: Axis, isX: Bool) -> [AxisGroup] {
        // Lines on x and on bands are dashed, and on a y axis of numbers plain (measured on macOS 27).
        var dashed = isX
        if case .bands = axis.scale.kind { dashed = true }
        let lineStroke = dashed ? Self.tickDash : ChartStroke()
        return marks(spec).flatMap { marks -> [AxisGroup] in
            let ticks = ticks(marks, axis)
            let edge = edge(marks, isX: isX)
            guard let items = marks.items else {
                // Swift Charts' default: on x and on bands a line that runs on past the plot.
                let length = dashed ? Self.tickLength : 0
                return [AxisGroup(ticks: marks.format.map { labeled(ticks, $0) } ?? ticks, edge: edge,
                                  grid: AxisLine(stroke: marks.stroke ?? lineStroke, length: length), label: AxisLabel())]
            }
            // Every entry draws, two labels or gridlines of one AxisMarks too (measured on macOS 27).
            return items.map { item in
                var group = AxisGroup(ticks: ticks, edge: edge)
                let ink = item.foregroundStyle.map { ChartInk.color($0) }
                switch item.kind {
                case let .gridLine(_, stroke):
                    group.grid = AxisLine(ink: ink ?? Self.gridInk, stroke: stroke ?? lineStroke)
                case let .tick(_, length, stroke):
                    group.tick = AxisLine(ink: ink ?? Self.gridInk, stroke: stroke ?? lineStroke, length: tickLength(length, ticks, isX: isX))
                case let .valueLabel(format, centered, anchor, _, _, _, _, _, _):
                    if let format { group.ticks = labeled(ticks, format) }
                    group.label = AxisLabel(ink: ink ?? Self.labelInk, anchor: anchor, centered: centered == true,
                                            offset: item.offset ?? ChartSize(width: 0, height: 0))
                }
                return group
            }
        }
    }

    // How far a tick runs: to the far side of a label, across an axis's labels (measured on macOS 27).
    private func tickLength(_ length: ChartAxisMarkItem.TickLength, _ ticks: [(value: ChartScalar, label: String)], isX: Bool) -> Double {
        switch length {
        case .automatic: return isX ? Self.tickLength : Self.yTickLength
        case .fixed(let points): return points
        case .label(let past), .longestLabel(let past):
            let sizes = ticks.map { metrics.size($0.label) }
            return (sizes.map { isX ? $0.height : $0.width }.max() ?? 0) + Self.labelGap + past
        }
    }

    private func labeled(_ ticks: [(value: ChartScalar, label: String)], _ format: ChartAxisFormat) -> [(value: ChartScalar, label: String)] {
        ticks.map { tick in
            switch (format, tick.value) {
            case (.number(let spec), .number(let number)): return (tick.value, metrics.formatted(number, spec))
            case (.number(let spec), .integer(let number)): return (tick.value, metrics.formatted(Double(number), spec))
            case (.date(let format), .date(let date)): return (tick.value, metrics.date(date, format.skeleton))
            default: return tick
            }
        }
    }

    // The ticks an AxisMarks asks for. Values outside the domain have no tick; they do not move it.
    // A stride or a list past ChartAxisStrideLimit is automatic values: a draw of 100,000 lines runs
    // the box out of memory. A list is in the axis's order, and a list of names on bands changes
    // nothing (measured on macOS 27).
    private func ticks(_ marks: ChartAxisMarksSpec, _ axis: Axis) -> [(value: ChartScalar, label: String)] {
        func numbers(_ values: [Double], digits: Int) -> [(value: ChartScalar, label: String)] {
            values.map { (.number($0), metrics.number($0, $0 == 0 ? 0 : digits)) }
        }
        func chosen(_ values: [Double]) -> [(value: ChartScalar, label: String)] {
            numbers(values, digits: ChartTicks.fractionDigits(of: values))
        }
        switch (marks.values, axis.scale.kind) {
        case let (.automatic(count, lower, upper), .numbers) where count != nil || lower != nil || upper != nil:
            guard let steps = axis.steps else { return axis.ticks }
            let ideal = count ?? ChartTicks.idealTicks
            if steps.exact {
                let inside = ChartTicks.inside(steps.lo, steps.hi, ideal: ideal)
                return numbers(inside.ticks, digits: ChartTicks.fractionDigits(inside.step))
            }
            let widened = ChartTicks.widened(steps.lo, steps.hi, ideal: ideal, roundLower: lower ?? true, roundUpper: upper ?? true)
            return numbers(widened.ticks, digits: ChartTicks.fractionDigits(widened.step))
        case let (.automatic(count?, _, _), .dates(lo, hi)):
            return dateTicks(lo, hi, count: count)
        case let (.numberStride(step), .numbers(lo, hi)) where hi > lo && (hi - lo) / step <= Double(ChartAxisStrideLimit.maxStrideMarks):
            return chosen(ChartTicks.multiples(of: step, lo, hi))
        case let (.calendarStride(unit, count), .dates(lo, hi)):
            let dates = ChartDates.ticks(lo, hi, stride: ChartDateStride(unit: unit, count: count))
            return dates.count < ChartAxisStrideLimit.maxStrideMarks ? dateLabels(dates, unit: unit) : axis.ticks
        case let (.numbers(values), .numbers(lo, hi)):
            let shown = values.filter { $0 >= lo && $0 <= hi }
            return shown.count <= ChartAxisStrideLimit.maxStrideMarks ? chosen(shown.sorted()) : axis.ticks
        case let (.dates(values), .dates(lo, hi)):
            let shown = values.filter { $0 >= lo && $0 <= hi }
            return shown.count <= ChartAxisStrideLimit.maxStrideMarks ? dateLabels(shown.sorted(), unit: .day) : axis.ticks
        default:
            return axis.ticks
        }
    }

    // A band's lines are at its edges, centered or not (measured on macOS 27).
    private func linePositions(_ group: AxisGroup, _ scale: ChartAxisScale, every: Int) -> [Double] {
        if case .bands(let names) = scale.kind {
            return stride(from: 0, through: names.count, by: every).map { scale.start + Double($0) * scale.bandWidth }
        }
        return group.ticks.compactMap { scale.position($0.value, unit: nil) }
    }

    private func appendYGroup(_ group: AxisGroup, _ scale: ChartAxisScale, _ plot: ChartRect, lineHeight: Double, into primitives: inout [ChartPrimitive]) {
        let left = plot.x, right = plot.x + plot.width
        let trailing = group.edge == .trailing
        let every = bandStride(scale, room: lineHeight)
        if let grid = group.grid {
            for y in linePositions(group, scale, every: every) {
                let from = ChartPoint(x: trailing ? left : left - grid.length, y: y)
                let to = ChartPoint(x: trailing ? right + grid.length : right, y: y)
                primitives.append(.line(from: from, to: to, ink: grid.ink, stroke: grid.stroke))
            }
        }
        if let tick = group.tick {
            for y in linePositions(group, scale, every: every) {
                let start = trailing ? right : left
                let end = trailing ? right + tick.length : left - tick.length
                primitives.append(.line(from: ChartPoint(x: start, y: y), to: ChartPoint(x: end, y: y), ink: tick.ink, stroke: tick.stroke))
            }
        }
        guard let label = group.label else { return }
        var anchor = label.anchor
        if case .bands = scale.kind { anchor = nil }
        // The anchor's side that faces the plot puts a label inside it, on either edge.
        let inward = trailing ? anchor?.isTrailing == true : anchor?.isLeading == true
        let rightward = trailing != inward
        let x = (trailing ? right : left) + (rightward ? Self.labelGap : -Self.labelGap)
        for (index, tick) in group.ticks.enumerated() where index % every == 0 {
            guard var y = scale.position(tick.value, unit: nil) else { continue }
            var alignment = 0.5
            // Under or over its tick, one that would then pass the plot's end is left out.
            if anchor?.isTop == true {
                y += Self.labelGap
                alignment = 0
                guard y + lineHeight <= plot.y + plot.height else { continue }
            } else if anchor?.isBottom == true {
                y -= Self.labelGap
                alignment = 1
                guard y - lineHeight >= plot.y else { continue }
            }
            primitives.append(.text(tick.label, position: ChartPoint(x: x + label.offset.width, y: y + label.offset.height),
                                    alignment: ChartPoint(x: rightward ? 0 : 1, y: alignment), ink: label.ink))
        }
    }

    private func appendXGroup(_ group: AxisGroup, _ scale: ChartAxisScale, _ plot: ChartRect, into primitives: inout [ChartPrimitive]) {
        if case .none = scale.kind { return }
        let top = plot.y, bottom = plot.y + plot.height
        let below = group.edge == .bottom
        let edgeY = below ? bottom : top
        let outward = below ? 1.0 : -1.0
        var every = 1
        if case .bands = scale.kind {
            // Labels wider than their band show every few bands.
            let widest = group.ticks.map { metrics.size($0.label).width }.max() ?? 0
            every = bandStride(scale, room: widest + Self.labelGap)
        }
        if let grid = group.grid {
            for x in linePositions(group, scale, every: every) {
                let far = below ? top : bottom
                primitives.append(.line(from: ChartPoint(x: x, y: far), to: ChartPoint(x: x, y: edgeY + outward * grid.length), ink: grid.ink, stroke: grid.stroke))
            }
        }
        if let tick = group.tick {
            for x in linePositions(group, scale, every: every) {
                primitives.append(.line(from: ChartPoint(x: x, y: edgeY), to: ChartPoint(x: x, y: edgeY + outward * tick.length), ink: tick.ink, stroke: tick.stroke))
            }
        }
        guard let label = group.label else { return }
        let inside = label.anchor == .bottomLeading || label.anchor == .bottomTrailing
        let ending = label.anchor == .topTrailing || label.anchor == .bottomTrailing
        let labelY = edgeY + (inside ? -outward : outward) * Self.labelGap
        let textY = below != inside ? 0.0 : 1.0
        if case .bands = scale.kind {
            for (index, tick) in group.ticks.enumerated() where index % every == 0 {
                guard let center = scale.position(tick.value, unit: nil) else { continue }
                let x = ending ? center + abs(scale.bandWidth) / 2 - Self.labelGap : center
                primitives.append(.text(tick.label, position: ChartPoint(x: x + label.offset.width, y: labelY + label.offset.height),
                                        alignment: ChartPoint(x: ending ? 1 : 0.5, y: textY), ink: label.ink))
            }
            return
        }
        let right = plot.x + plot.width
        // On an axis that runs right to left a label ends at its tick (measured on macOS 27).
        let backward = scale.end < scale.start
        var nextFree = backward ? Double.infinity : -Double.infinity
        let places = group.ticks.compactMap { tick in scale.position(tick.value, unit: nil).map { (label: tick.label, x: $0) } }
        for (index, place) in places.enumerated() {
            // A label starts at its tick; one that would pass the plot's end or the label before
            // it is left out. A centered one sits between its tick and the next, and the last,
            // which has none, stays at its tick (measured on macOS 27).
            let labelWidth = metrics.size(place.label).width
            var start = backward || ending ? place.x - Self.labelGap - labelWidth : place.x + Self.labelGap
            if label.centered, index + 1 < places.count {
                start = (place.x + places[index + 1].x - labelWidth) / 2
            }
            let fits = backward ? start + labelWidth <= nextFree && start >= plot.x
                : start >= nextFree && start + labelWidth <= right && (!ending || start >= plot.x)
            guard fits else { continue }
            primitives.append(.text(place.label, position: ChartPoint(x: start + label.offset.width, y: labelY + label.offset.height),
                                    alignment: ChartPoint(x: 0, y: textY), ink: label.ink))
            nextFree = backward ? start - Self.labelGap : start + labelWidth + Self.labelGap
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
        var joined: [JoinedMarks: [Int]] = [:]
        for (index, instance) in marks.instances.enumerated() where instance.mark.kind == .LineMark || instance.mark.kind == .AreaMark {
            joined[JoinedMarks(kind: instance.mark.kind, series: instance.seriesKey), default: []].append(index)
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
            case .LineMark:
                if let indices = joined.removeValue(forKey: JoinedMarks(kind: .LineMark, series: instance.seriesKey)),
                   let primitive = line(indices, x, y, ink: ink) {
                    primitives.append(primitive)
                }
            case .AreaMark:
                if let indices = joined.removeValue(forKey: JoinedMarks(kind: .AreaMark, series: instance.seriesKey)),
                   let primitive = area(indices, stacks, x, y, ink: ink) {
                    primitives.append(primitive)
                }
            case .RectangleMark, .SectorMark:
                break
            }
        }
    }

    /// The marks that draw as one line or one area.
    private struct JoinedMarks: Hashable {
        var kind: ChartMarkKind
        var series: String
    }

    // The interpolation of the first mark, nearest modifier first.
    private func interpolation(_ mark: ChartMarkSpec) -> ChartInterpolation {
        for modifier in mark.modifiers {
            if case .interpolationMethod(let method) = modifier {
                return method
            }
        }
        return .linear
    }

    private func position(_ instance: ChartMarkInstance, _ key: String, _ scale: ChartAxisScale) -> Double? {
        instance.values[key].flatMap { scale.position($0, unit: instance.mark.values[key]?.unit) }
    }

    // A value that has no place on its axis breaks the line (measured on macOS 27, not a number on
    // either axis), and a piece of one point draws nothing.
    private func line(_ indices: [Int], _ x: ChartAxisScale, _ y: ChartAxisScale, ink: ChartInk) -> ChartPrimitive? {
        let mark = marks.instances[indices[0]].mark
        let method = interpolation(mark)
        var elements: [ChartPathElement] = []
        var piece: [ChartPoint] = []
        func endPiece() {
            if piece.count > 1 { elements += ChartCurves.elements(piece, method) }
            piece = []
        }
        for index in indices {
            let instance = marks.instances[index]
            if let px = position(instance, "x", x), let py = position(instance, "y", y) {
                piece.append(ChartPoint(x: px, y: py))
            } else {
                endPiece()
            }
        }
        endPiece()
        guard !elements.isEmpty else { return nil }
        var stroke = Self.defaultLine
        for modifier in mark.modifiers.reversed() {
            if case .lineStyle(let style) = modifier {
                stroke = style
            }
        }
        return .path(elements, ink: ink, stroke: stroke)
    }

    // Where an area's two edges are at one mark: nil where it has no place on an axis.
    private func areaEdges(_ instance: ChartMarkInstance, stack: Stacked?, _ x: ChartAxisScale, _ y: ChartAxisScale) -> (upper: ChartPoint, lower: ChartPoint)? {
        if let stack {
            if stack.vertical {
                return position(instance, "x", x).map { (ChartPoint(x: $0, y: y.position(stack.high)), ChartPoint(x: $0, y: y.position(stack.low))) }
            }
            return position(instance, "y", y).map { (ChartPoint(x: x.position(stack.high), y: $0), ChartPoint(x: x.position(stack.low), y: $0)) }
        }
        if let px = position(instance, "x", x), let ys = span(instance, "yStart", "yEnd", y) {
            return (ChartPoint(x: px, y: ys.1), ChartPoint(x: px, y: ys.0))
        }
        if let py = position(instance, "y", y), let xs = span(instance, "xStart", "xEnd", x) {
            return (ChartPoint(x: xs.1, y: py), ChartPoint(x: xs.0, y: py))
        }
        return nil
    }

    private func area(_ indices: [Int], _ stacks: [Int: Stacked], _ x: ChartAxisScale, _ y: ChartAxisScale, ink: ChartInk) -> ChartPrimitive? {
        let method = interpolation(marks.instances[indices[0]].mark)
        var elements: [ChartPathElement] = []
        var upper: [ChartPoint] = [], lower: [ChartPoint] = []
        // Along the top in data order, and back along the bottom, joined by straight ends. Both
        // edges take the method going forward (measured on macOS 27), so stacked areas share theirs.
        func endPiece() {
            if upper.count > 1 {
                elements += ChartCurves.elements(upper, method)
                for element in ChartCurves.elements(lower.reversed(), ChartCurves.backward(method)) {
                    if case .move(let point) = element {
                        elements.append(.line(point))
                    } else {
                        elements.append(element)
                    }
                }
            }
            upper = []
            lower = []
        }
        for index in indices {
            if let edges = areaEdges(marks.instances[index], stack: stacks[index], x, y) {
                upper.append(edges.upper)
                lower.append(edges.lower)
            } else {
                endPiece()
            }
        }
        endPiece()
        return elements.isEmpty ? nil : .fill(elements, ink: ink)
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
            // A stacked bar stands on 0 even above another: no place for 0, no bars (measured on macOS 27).
            guard (stack.vertical ? y : x).position(0).isFinite else { return nil }
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
