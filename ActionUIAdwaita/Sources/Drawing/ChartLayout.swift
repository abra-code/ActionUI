// Sources/Drawing/ChartLayout.swift
/*
 Lays out a chart for a size: its marks, axes and gridlines as drawing primitives in points. No GTK
 here: text is measured and formatted through ChartTextMetrics, so a test checks the geometry as
 numbers, and Elements/Chart+Adwaita.swift only draws the primitives.

 The goal is a chart comparable to Swift Charts, not a copy (Documentation/Schemas/Chart.md lists the
 differences). Swift Charts' look, as drawn on macOS 27:
 - The y axis is on the trailing side, with solid gridlines at its ticks.
 - Categories are bands of equal width, in order of first use, with dashed lines at the band edges
   on x and solid ones on y. On y their labels take no room: each sits on the top line of its band,
   inside the plot at the leading edge or just past it at the trailing edge, and nothing thins or
   clips them. A bar there has only what a label's row leaves of its band; on a tight axis that is
   less than nothing, it draws at that size and runs past its band. Other marks stay at the band's
   center. Automatic marks sit at the leading edge, and a tick there runs into the plot.
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
 - A bar has a corner of 2 unless given. A stack, or a bar on its own on 0, rounds as one shape that
   cuts its parts: an end at 0 stays square, so one that stands on 0 rounds only its tip, facing its
   own way, and a centered stack both ends; a bar from a start to an end rounds all four. A corner
   stops at half across, and at half the length, or the whole of it with one end to round. A
   RectangleMark takes a bar's forms and sizes, 8 at a number on either axis, with no corner unless
   given, and then all four.
 - A start and end on an axis of categories run from the edge of one band to the far edge of the other;
   dates with a unit go in the middle of their bins, as a single value does.
 - Points given to a mark count from the plot's top leading corner.
 - A point's size is the area of a circle in its box, 50 unless given, or the shorter side of a
   width and a height, and no symbol stretches. A rule is 2 wide unless given.
 - On a line a symbol shows only where one is asked for, with its own mark's line width as its
   outline, its size unchanged, and it still shows on a line 0 wide. Its inside is a hole in that
   line alone, so the plot shows through and a later line crosses it; plus, cross and asterisk are
   solid. Each point has its own symbol, in the line's color, and a size {"by"} reaches it only
   where the symbol is a {"by"} too. A point on its own still has its symbol, and a line takes its
   dash but its symbols do not.
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
 - An axis title sits outside the labels, 8 points off: an x title at the bottom and leading along
   the plot, a y title at the top and trailing along the whole chart, or leading on an axis with
   its labels there. On the leading or trailing side either is turned to run along the plot,
   centered unless aligned top or bottom. Two titles on one side do not stack, each is its own
   spacing off.
 - A plot style is a layer of its own, over the axes: its background hides the
   gridlines and any category labels on y, the marks draw on it, and its opacity, corner radius and
   clip shape take all of that together. Its border draws square around the layer, padding moves
   the plot and its axes in from the border, and a frame sets the plot's size, centered in its room.
 - A legend shows the names of the color scale's domain, or without one those of the series a
   {"by"} color makes, a dot and a name each, in that order, and then those of a symbol or line
   style or size scale, and a color scale over numbers or dates as a bar (ChartStyleMap). A series
   outside a domain is not listed. A color domain alone is
   enough, even over marks of a fixed color, and with no names there is no legend, however
   visible it is asked to be. It takes room outside everything else, at the
   bottom unless told otherwise, starting at the chart's own edge and in columns that line up. A
   plot style's frame centers the plot and all around it, and the legend stays with them. Across,
   it fills rows; at a side it fills columns as high as the chart. A name that does not fit is not
   shortened, and one too long for a side leaves the plot a point wide. The overlay position sits
   on the plot at its top trailing corner and the corner positions at its top leading corner,
   taking no room and wrapping inside the plot.
 - Marks draw in the order of the content, over the grid, lowest zIndex first.
 - A mark's opacity, offset, shadow and blur take the mark alone, not its legend entry, and the
   nearest opacity and shadow win: a Plot's opacity does not multiply a mark's. Offsets add, and
   blurs nest. An offset moves a whole mark, past its axis too. One with a start or an end moves
   those edges of a rule along it, or of a range bar or a rectangle, start being the one nearer the
   top or leading side. A bar on 0 moves only across its axis, so it narrows.
 - A line or an area joins its points in data order, not by x. Marks with one series are one
   line, whatever {"by"} styles they wear, and without a series so are marks with the same ones,
   in the style of the first, drawn where that one is. A value that is
   not finite breaks it in two, and one point alone draws nothing. A line is 2 wide, an area is
   opaque, and stacked areas stack as bars do, each kind on its own. A start and end on an axis of
   categories run from edge to edge, as a bar's do.

 Bars, rectangles, points, rules, lines and areas draw here; other marks still count on the axes.
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
    /// A point along even stops, 0 to 1.
    case blend([ColorSpec], at: Double)
}

enum ChartPrimitive: Equatable {
    case line(from: ChartPoint, to: ChartPoint, ink: ChartInk, stroke: ChartStroke)
    case rect(ChartRect, ink: ChartInk)
    /// A bar or a rectangle seen through `shape` with rounded corners; a stack's parts share one.
    case bar(ChartRect, shape: ChartRect, corners: ChartCorners, ink: ChartInk)
    /// `side` is the box of ChartSymbols.
    case symbol(ChartSymbol, center: ChartPoint, side: Double, ink: ChartInk)
    case path([ChartPathElement], ink: ChartInk, stroke: ChartStroke)
    /// A line with symbols on its points, which it may be too short to join.
    case markedLine([ChartPathElement], ink: ChartInk, stroke: ChartStroke, symbols: [ChartLineSymbol])
    case fill([ChartPathElement], ink: ChartInk)
    /// `alignment` is the point of the text placed at `position`, as fractions of its size.
    case text(String, position: ChartPoint, alignment: ChartPoint, ink: ChartInk)
    /// Text turned clockwise by `degrees` around its center.
    case turnedText(String, center: ChartPoint, degrees: Double, ink: ChartInk)
    /// What follows up to `endEffect` is one mark, under these effects.
    case beginEffect(ChartMarkEffect)
    case endEffect(ChartMarkEffect)
    /// What follows up to `endPlot` draws as one layer.
    case beginPlot(ChartPlotLayer)
    case endPlot(ChartPlotLayer)
    case roundedFill(ChartRect, radius: Double, ink: ChartInk)
    case border(ChartRect, width: Double, ink: ChartInk)
    /// Along `rect`, across if not `vertical`, its ends past the stops in their colors.
    case gradientBar(ChartRect, stops: [ChartGradientStop], vertical: Bool)

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
        case let .bar(rect, shape, corners, _):
            return finite(rect.x, rect.y, rect.width, rect.height, shape.x, shape.y, shape.width, shape.height,
                          corners.topLeading, corners.topTrailing, corners.bottomTrailing, corners.bottomLeading)
        case let .symbol(_, center, side, _):
            return finite(center.x, center.y, side)
        case let .path(elements, _, stroke):
            return Float(stroke.lineWidth) > 0 && finite(stroke.lineWidth, stroke.miterLimit, stroke.dashPhase)
                && stroke.dash.allSatisfy { finite($0) } && Self.finite(elements)
        case let .markedLine(elements, _, stroke, symbols):
            return finite(stroke.lineWidth, stroke.miterLimit, stroke.dashPhase)
                && stroke.dash.allSatisfy { finite($0) } && Self.finite(elements)
                && symbols.allSatisfy { finite($0.center.x, $0.center.y, $0.side) }
        case let .fill(elements, _):
            return Self.finite(elements)
        case let .text(_, position, _, _):
            return finite(position.x, position.y)
        case let .turnedText(_, center, _, _):
            return finite(center.x, center.y)
        case let .beginEffect(effect), let .endEffect(effect):
            return finite(effect.offset.x, effect.offset.y, effect.opacity, effect.blur)
                && (effect.shadow.map { finite($0.radius, $0.x, $0.y) } ?? true)
        case let .beginPlot(layer), let .endPlot(layer):
            return finite(layer.rect.x, layer.rect.y, layer.rect.width, layer.rect.height, layer.radius, layer.opacity)
        case let .roundedFill(rect, radius, _):
            return finite(rect.x, rect.y, rect.width, rect.height, radius)
        case let .border(rect, width, _):
            return width > 0 && finite(rect.x, rect.y, rect.width, rect.height, width)
        case let .gradientBar(rect, stops, _):
            return finite(rect.x, rect.y, rect.width, rect.height) && stops.allSatisfy { (0...1).contains($0.offset) }
        }
    }

    private static func finite(_ elements: [ChartPathElement]) -> Bool {
        func finite(_ point: ChartPoint) -> Bool { Float(point.x).isFinite && Float(point.y).isFinite }
        return elements.allSatisfy { element in
            switch element {
            case .move(let point), .line(let point): return finite(point)
            case let .curve(first, second, end): return finite(first) && finite(second) && finite(end)
            case .close: return true
            }
        }
    }
}

struct ChartMarkShadow: Equatable {
    /// SwiftUI's default when nil.
    var color: ColorSpec?
    var radius: Double
    var x: Double
    var y: Double
}

struct ChartMarkEffect: Equatable {
    var opacity = 1.0
    var offset = ChartPoint(x: 0, y: 0)
    var blur = 0.0
    var shadow: ChartMarkShadow?
}

struct ChartCorners: Equatable {
    var topLeading: Double
    var topTrailing: Double
    var bottomTrailing: Double
    var bottomLeading: Double
}

struct ChartLineSymbol: Equatable {
    var symbol: ChartSymbol
    var center: ChartPoint
    /// The box of ChartSymbols.
    var side: Double
    /// Its outline: the width its own mark's line style gives, not the line's.
    var lineWidth: Double
}

/// The layer a plot style draws the marks on.
struct ChartPlotLayer: Equatable {
    var rect: ChartRect
    var radius: Double
    var opacity: Double
    var clips: Bool
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
    private static let legendDateTicks = 4
    private static let defaultSymbolArea = 50.0
    private static let defaultBarCorner = 2.0
    // Thinner bars stay plain rectangles: no corner would show, and side by side under GSK's rounded
    // clip they ink too much, twice over at 5,000 in a plot 364 wide.
    private static let thinnestRoundedBar = 1.0
    static let defaultLine = ChartStroke(lineWidth: 2, lineCap: .round, lineJoin: .round)
    // Below the plot: from its edge to the labels, and how far a tick line runs into that room.
    private static let labelGap = 4.0
    private static let titleGap = 8.0
    private static let tickLength = 6.0
    private static let yTickLength = 4.0
    private static let percent = 100.0

    private let spec: ChartSpec
    private let marks: ChartResolvedMarks
    private let styles: ChartStyleMap
    private let metrics: ChartTextMetrics
    private let width: Double
    private let height: Double

    static func primitives(_ spec: ChartSpec, marks: ChartResolvedMarks, width: Double, height: Double, metrics: ChartTextMetrics) -> [ChartPrimitive] {
        ChartLayout(spec: spec, marks: marks, styles: ChartStyleMap(spec, marks), metrics: metrics, width: width, height: height).layout()
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
        /// The reach of its whole stack, which rounds as one shape.
        var whole: (low: Double, high: Double)
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
        var wholes: [StackKey: (low: Double, high: Double)] = [:]
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
            if stacking != .unstacked {
                let known = wholes[entry.key] ?? (low, high)
                wholes[entry.key] = (min(known.low, low, high), max(known.high, low, high))
            }
            spans[entry.index] = Stacked(vertical: entry.key.vertical, low: low, high: high, whole: (min(low, high), max(low, high)))
        }
        for entry in entries where marks.instances[entry.index].mark.stacking != .unstacked {
            spans[entry.index]?.whole = wholes[entry.key] ?? (0, 0)
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
        let unplacedY = axis(extents.y, spec.y, length: 0)
        let hasY = !unplacedY.isEmpty
        var yBands = false
        if case .bands = unplacedY.scale.kind { yBands = true }
        let xRows = hasX ? labelEdges(spec.x, isX: true) : []
        let rowHeight = lineHeight + Self.labelGap * 2
        // Labels of bands take no room, so they do not count as labels on the leading edge.
        let leadingLabels = !yBands && labelEdges(spec.y, isX: false) == [.leading]
        var legend = legend(lineHeight: lineHeight)
        let legendLeading = legend?.room(.leading) ?? 0, legendTrailing = legend?.room(.trailing) ?? 0
        let titles = [title(spec.x, isX: true, leadingLabels: false), title(spec.y, isX: false, leadingLabels: leadingLabels)].compactMap { $0 }
        // Two titles on an edge share it, and a spacing past the title's size takes no room back.
        func titleRoom(_ edge: ChartAxisMarkPosition) -> Double {
            titles.filter { $0.edge == edge }.map { max(0, lineHeight + $0.spacing) }.max() ?? 0
        }
        let yShown = hasY && !labelEdges(spec.y, isX: false).isEmpty
        let topTicks = hasX ? tickRoom(spec.x, isX: true, .top) : 0, bottomTicks = hasX ? tickRoom(spec.x, isX: true, .bottom) : 0
        let xLabelsTop = (xRows.contains(.top) ? rowHeight : 0) + topTicks
        let xLabelsBottom = (xRows.contains(.bottom) ? rowHeight : 0) + bottomTicks
        let top = max(xLabelsTop + titleRoom(.top) + (legend?.room(.top) ?? 0), yShown ? lineHeight / 2 : 0)
        let bottom = xLabelsBottom + titleRoom(.bottom) + (legend?.room(.bottom) ?? 0)
        let plotHeight = max(height - top - bottom, 1)
        var yAxis = axis(extents.y, spec.y, length: plotHeight)
        let yGroups = groups(spec.y, yAxis, isX: false)
        func room(_ edge: ChartAxisMarkPosition) -> Double {
            // Labels of bands sit in the plot and take none.
            let labeled = yBands ? [] : yGroups.filter { $0.edge == edge && $0.label != nil }
            let widest = labeled.flatMap(\.ticks).map { metrics.size($0.label).width }.max() ?? 0
            return (widest > 0 ? widest + Self.labelGap * 2 : 0) + (hasY ? tickRoom(spec.y, isX: false, edge, bands: yBands) : 0)
        }
        let yLabelsLeading = room(.leading), yLabelsTrailing = room(.trailing)
        let leading = yLabelsLeading + titleRoom(.leading) + legendLeading
        let trailing = yLabelsTrailing + titleRoom(.trailing) + legendTrailing
        let plotWidth = max(width - leading - trailing, 1)
        var xAxis = axis(extents.x, spec.x, length: plotWidth)
        let xGroups = groups(spec.x, xAxis, isX: true)

        let style = PlotStyle(spec.plotStyle)
        let frame = style.framed(ChartRect(x: leading, y: top, width: plotWidth, height: plotHeight))
        let plot = style.padded(frame)
        legend?.fit(overPlot: frame)
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
        let outerTop = plot.y - xLabelsTop, outerBottom = plot.y + plot.height + xLabelsBottom
        let outerLeading = plot.x - yLabelsLeading, outerTrailing = plot.x + plot.width + yLabelsTrailing
        for title in titles {
            // An x title runs along the plot and a y title along the chart inside any legend, its
            // ends moved as far as a plot style moved the plot's (measured on macOS 27).
            let start = title.isX ? plot.x : plot.x - leading + legendLeading
            let end = title.isX ? plot.x + plot.width : width - legendTrailing + ((plot.x + plot.width) - (leading + plotWidth))
            let across = start + (end - start) * title.along
            // A turned title is placed by its center: its ends line up with the plot's.
            let along = plot.y + plot.height * title.along + metrics.size(title.text).width * (0.5 - title.along)
            switch title.edge {
            case .top:
                primitives.append(.text(title.text, position: ChartPoint(x: across, y: outerTop - title.spacing), alignment: ChartPoint(x: title.along, y: 1), ink: Self.labelInk))
            case .bottom:
                primitives.append(.text(title.text, position: ChartPoint(x: across, y: outerBottom + title.spacing), alignment: ChartPoint(x: title.along, y: 0), ink: Self.labelInk))
            case .leading:
                primitives.append(.turnedText(title.text, center: ChartPoint(x: outerLeading - title.spacing - lineHeight / 2, y: along), degrees: 90, ink: Self.labelInk))
            case .trailing:
                primitives.append(.turnedText(title.text, center: ChartPoint(x: outerTrailing + title.spacing + lineHeight / 2, y: along), degrees: 90, ink: Self.labelInk))
            case .automatic:
                break
            }
        }
        // A label's row is the room under the band's top line (measured on macOS 27: it follows the font).
        let bandLabelRow = yBands && !labelEdges(spec.y, isX: false).isEmpty ? lineHeight + Self.labelGap : 0
        let layer = style.layer(frame)
        if let layer {
            primitives.append(.beginPlot(layer))
            if let background = style.background {
                primitives.append(.roundedFill(frame, radius: layer.radius, ink: .color(background)))
            }
        }
        appendMarks(stacks, xAxis.scale, yAxis.scale, plot, bandLabelRow: bandLabelRow, into: &primitives)
        if let layer { primitives.append(.endPlot(layer)) }
        if let border = style.border {
            primitives.append(.border(frame, width: border.width, ink: border.ink))
        }
        let area = ChartRect(x: frame.x - leading, y: frame.y - top, width: leading + frame.width + trailing, height: top + frame.height + bottom)
        legend?.append(to: &primitives, area: area, plot: frame)
        return primitives.filter(\.isDrawable)
    }

    private func legend(lineHeight: Double) -> Legend? {
        guard spec.legendVisibility != .hidden else { return nil }
        let place = Legend.Place(spec.legendPosition)
        let styled = styles.legendEntries(number: metrics.number) { lo, hi in
            dateLabels([lo, hi], unit: ChartDates.stride(lo, hi, count: Self.legendDateTicks).unit)
        }
        let entries = styled.map { Legend.Entry($0, lineHeight: lineHeight, down: place.fillsDown) { metrics.size($0).width } }
        guard !entries.isEmpty else { return nil }
        return Legend(place, entries, lineHeight: lineHeight, width: width, height: height)
    }

    /// A chart's legend, sized and laid out in a grid (measured on macOS 27).
    private struct Legend {
        enum Place {
            case top, bottom, leading, trailing, overPlotLeading, overPlotTrailing

            init(_ position: ChartPosition) {
                switch position {
                case .automatic, .bottom: self = .bottom
                case .top: self = .top
                case .leading: self = .leading
                case .trailing: self = .trailing
                case .overlay: self = .overPlotTrailing
                case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing: self = .overPlotLeading
                }
            }

            /// Rows fill first across the chart, columns first at a side.
            var fillsDown: Bool { self == .leading || self == .trailing }
        }

        struct Entry {
            let style: ChartLegendEntry
            let width: Double
            let height: Double
            /// How far a bar across the chart starts in: half its first label, which stays inside.
            let barStart: Double
            let sampleLength: Double
            let textStart: Double

            init(_ style: ChartLegendEntry, lineHeight: Double, down: Bool, measure: (String) -> Double) {
                self.style = style
                sampleLength = style.side.map { $0 + sizedSampleEnds } ?? sample
                textStart = style.stroke == nil ? (style.side ?? dot) + dotGap : sampleLength + sampleGap
                guard let bar = style.bar else {
                    height = max(lineHeight, style.side ?? 0)
                    barStart = 0
                    width = textStart + measure(style.name)
                    return
                }
                let labels = bar.ticks.map { measure($0.label) }
                let beside = barThickness + barTick + barLabelGap
                barStart = down ? 0 : (labels.first ?? 0) / 2
                width = down ? beside + (labels.max() ?? 0) : barStart + barLength + (labels.last ?? 0) / 2
                height = down ? barLength + lineHeight : beside + lineHeight
            }
        }

        private static let dot = 8.0, dotGap = 5.0, columnGap = 8.0, rowGap = 8.0
        /// A line's sample runs the whole of its room, and its caps past that; with a size scale it
        /// runs past the symbol's box instead, however small (measured on macOS 27).
        private static let sample = 16.0, sizedSampleEnds = 10.0, sampleGap = 5.0
        /// A color bar and the ticks past it, then a small gap to their labels.
        private static let barLength = 120.0, barThickness = 12.0, barTick = 4.0, barLabelGap = 2.0
        private static let barTickInk = ChartInk.text(opacity: 0.25)
        /// From a legend across the chart to what it shares an edge with, and from one at a side.
        private static let acrossGap = 4.0, sideGap = 8.0
        private static let plotInset = 8.0

        private let place: Place
        private let entries: [Entry]
        private let lineHeight: Double
        private let down: Bool
        private let rows: Int
        private let columnWidths: [Double]
        private let rowHeights: [Double]

        init(_ place: Place, _ entries: [Entry], lineHeight: Double, width: Double, height: Double) {
            self.place = place
            self.entries = entries
            self.lineHeight = lineHeight
            down = place.fillsDown
            let columns: Int
            if down {
                rows = Self.rowsFitting(entries, height)
                columns = (entries.count + rows - 1) / rows
            } else {
                columns = Self.columnsFitting(entries, width)
                rows = (entries.count + columns - 1) / columns
            }
            columnWidths = Self.widths(entries, columns: columns, down: down, rows: rows)
            rowHeights = Self.heights(entries, columns: columns, down: down, rows: rows)
        }

        // As many as every column holds, each counted by its own entries' heights, down to a single
        // row. Rows then line up, so a tall entry can still push others past the edge (measured on
        // macOS 27).
        private static func rowsFitting(_ entries: [Entry], _ height: Double) -> Int {
            var rows = 0, used = 0.0
            for entry in entries {
                let next = used + (rows > 0 ? rowGap : 0) + entry.height
                if rows > 0, next > height { break }
                used = next
                rows += 1
            }
            func fits(_ rows: Int) -> Bool {
                stride(from: 0, to: entries.count, by: rows).allSatisfy { start in
                    let column = entries[start..<min(start + rows, entries.count)]
                    return column.reduce(0) { $0 + $1.height } + rowGap * Double(column.count - 1) <= height
                }
            }
            while rows > 1, !fits(rows) { rows -= 1 }
            return max(rows, 1)
        }

        // Apple takes as many as fit the row as they come, then lines them up, which can push the
        // last past the edge. Here the columns stop where the lined up grid still fits.
        private static func columnsFitting(_ entries: [Entry], _ width: Double) -> Int {
            var columns = 0, used = 0.0
            for entry in entries {
                let next = used + (columns > 0 ? columnGap : 0) + entry.width
                if columns > 0, next > width { break }
                used = next
                columns += 1
            }
            while columns > 1, total(widths(entries, columns: columns, down: false, rows: 0)) > width {
                columns -= 1
            }
            return max(columns, 1)
        }

        private static func widths(_ entries: [Entry], columns: Int, down: Bool, rows: Int) -> [Double] {
            var widths = [Double](repeating: 0, count: columns)
            for (index, entry) in entries.enumerated() {
                let column = down ? index / rows : index % columns
                widths[column] = max(widths[column], entry.width)
            }
            return widths
        }

        private static func heights(_ entries: [Entry], columns: Int, down: Bool, rows: Int) -> [Double] {
            var heights = [Double](repeating: 0, count: rows)
            for (index, entry) in entries.enumerated() {
                let row = down ? index % rows : index / columns
                heights[row] = max(heights[row], entry.height)
            }
            return heights
        }

        private static func total(_ widths: [Double]) -> Double {
            widths.reduce(0, +) + columnGap * Double(max(widths.count - 1, 0))
        }

        private var size: ChartSize {
            ChartSize(width: Self.total(columnWidths), height: rowHeights.reduce(0, +) + Self.rowGap * Double(rows - 1))
        }

        /// What it takes from the plot on the edge it sits at, and nothing on any other.
        func room(_ edge: Place) -> Double {
            guard edge == place else { return 0 }
            switch place {
            case .top, .bottom: return size.height + Self.acrossGap
            case .leading, .trailing: return size.width + Self.sideGap
            case .overPlotLeading, .overPlotTrailing: return 0
            }
        }

        /// Over the plot it wraps inside it, which takes the plot's size, and that takes no room.
        mutating func fit(overPlot plot: ChartRect) {
            guard place == .overPlotLeading || place == .overPlotTrailing else { return }
            self = Legend(place, entries, lineHeight: lineHeight, width: plot.width - Self.plotInset * 2, height: plot.height)
        }

        /// `area` holds the plot and all around it: the chart, unless a frame sized the plot or
        /// what it holds does not fit. `plot` is the plot's frame, before any padding.
        func append(to primitives: inout [ChartPrimitive], area: ChartRect, plot: ChartRect) {
            var origin = ChartPoint(x: area.x, y: area.y)
            switch place {
            case .top, .leading: break
            case .bottom: origin.y = area.y + area.height - size.height
            case .trailing: origin.x = area.x + area.width - size.width
            case .overPlotLeading: origin = ChartPoint(x: plot.x + Self.plotInset, y: plot.y + Self.plotInset)
            case .overPlotTrailing: origin = ChartPoint(x: plot.x + plot.width - Self.plotInset - size.width, y: plot.y + Self.plotInset)
            }
            var columnStarts: [Double] = []
            var start = origin.x
            for width in columnWidths {
                columnStarts.append(start)
                start += width + Self.columnGap
            }
            var rowTops: [Double] = []
            var top = origin.y
            for height in rowHeights {
                rowTops.append(top)
                top += height + Self.rowGap
            }
            for (index, entry) in entries.enumerated() {
                let column = down ? index / rows : index % columnWidths.count
                let row = down ? index % rows : index / columnWidths.count
                let middle = rowTops[row] + rowHeights[row] / 2
                let x = columnStarts[column]
                if let bar = entry.style.bar {
                    append(bar, of: entry, x: x, top: middle - entry.height / 2, to: &primitives)
                    continue
                }
                if let stroke = entry.style.stroke {
                    primitives.append(.line(from: ChartPoint(x: x, y: middle), to: ChartPoint(x: x + entry.sampleLength, y: middle),
                                            ink: entry.style.ink, stroke: stroke))
                }
                let side = entry.style.side ?? Self.dot
                if let symbol = entry.style.symbol, side > 0 {
                    let center = x + (entry.style.stroke == nil ? side : entry.sampleLength) / 2
                    primitives.append(.symbol(symbol, center: ChartPoint(x: center, y: middle), side: side, ink: entry.style.ink))
                }
                primitives.append(.text(entry.style.name, position: ChartPoint(x: x + entry.textStart, y: middle),
                                        alignment: ChartPoint(x: 0, y: 0.5), ink: ChartLayout.labelInk))
            }
        }

        // Down the chart's side it runs from the top, half a label in, with its labels past its ticks.
        private func append(_ bar: ChartLegendBar, of entry: Entry, x: Double, top: Double, to primitives: inout [ChartPrimitive]) {
            let tickStroke = ChartStroke(lineWidth: 1)
            if down {
                let start = top + lineHeight / 2, tickStart = x + Self.barThickness, tickEnd = tickStart + Self.barTick
                primitives.append(.gradientBar(ChartRect(x: x, y: start, width: Self.barThickness, height: Self.barLength), stops: bar.stops, vertical: true))
                for tick in bar.ticks {
                    let y = start + tick.offset * Self.barLength
                    primitives.append(.line(from: ChartPoint(x: tickStart, y: y), to: ChartPoint(x: tickEnd, y: y), ink: Self.barTickInk, stroke: tickStroke))
                    primitives.append(.text(tick.label, position: ChartPoint(x: tickEnd + Self.barLabelGap, y: y), alignment: ChartPoint(x: 0, y: 0.5), ink: ChartLayout.labelInk))
                }
            } else {
                let start = x + entry.barStart, tickStart = top + Self.barThickness, tickEnd = tickStart + Self.barTick
                primitives.append(.gradientBar(ChartRect(x: start, y: top, width: Self.barLength, height: Self.barThickness), stops: bar.stops, vertical: false))
                for tick in bar.ticks {
                    let tickX = start + tick.offset * Self.barLength
                    primitives.append(.line(from: ChartPoint(x: tickX, y: tickStart), to: ChartPoint(x: tickX, y: tickEnd), ink: Self.barTickInk, stroke: tickStroke))
                    primitives.append(.text(tick.label, position: ChartPoint(x: tickX, y: tickEnd + Self.barLabelGap), alignment: ChartPoint(x: 0.5, y: 0), ink: ChartLayout.labelInk))
                }
            }
        }
    }

    /// What a chartPlotStyle asks of the plot, read as any view's properties are. Shadow, offset and
    /// foregroundStyle are not drawn.
    private struct PlotStyle {
        private static let systemPadding = 16.0
        private let modifiers: BaseModifiers
        let background: ColorSpec?
        let border: (width: Double, ink: ChartInk)?
        private let radius: Double

        init(_ properties: [String: Any]) {
            modifiers = BaseModifiers(properties)
            background = ColorSpec.parse(modifiers.background)
            border = modifiers.border.map { border in
                (border.width, .color(ColorSpec.parse(border.color) ?? .named(.black)))
            }
            // A corner radius and a rounded clip shape both clip, so the larger shows.
            var radius = modifiers.cornerRadius ?? 0
            if case .roundedRectangle(let x, let y)? = modifiers.clipShape {
                radius = max(radius, min(x, y))
            }
            self.radius = max(radius, 0)
        }

        // The size a frame sets, centered in the plot's room even when larger than it. A minimum
        // or a maximum limits the room, and an ideal size changes nothing (measured on macOS 27).
        func framed(_ area: ChartRect) -> ChartRect {
            guard let frame = modifiers.frame else { return area }
            let width = Self.size(area.width, fixed: frame.width, lowest: frame.minWidth, highest: frame.maxWidth)
            let height = Self.size(area.height, fixed: frame.height, lowest: frame.minHeight, highest: frame.maxHeight)
            return ChartRect(x: area.x + (area.width - width) / 2, y: area.y + (area.height - height) / 2, width: width, height: height)
        }

        private static func size(_ room: Double, fixed: Double?, lowest: Double?, highest: Double?) -> Double {
            var size = fixed ?? room
            if let highest { size = min(size, highest) }
            if let lowest { size = max(size, lowest) }
            return size.isFinite && size >= 0 ? size : room
        }

        func padded(_ frame: ChartRect) -> ChartRect {
            var top = 0.0, leading = 0.0, bottom = 0.0, trailing = 0.0
            switch modifiers.padding {
            case nil:
                return frame
            case .system?:
                (top, leading, bottom, trailing) = (Self.systemPadding, Self.systemPadding, Self.systemPadding, Self.systemPadding)
            case .uniform(let all)?:
                (top, leading, bottom, trailing) = (all, all, all, all)
            case .edges(let edgeTop, let edgeLeading, let edgeBottom, let edgeTrailing)?:
                (top, leading, bottom, trailing) = (edgeTop, edgeLeading, edgeBottom, edgeTrailing)
            }
            // Padding past the frame leaves a point of plot, in the middle (measured on macOS 27).
            let width = max(frame.width - leading - trailing, 1), height = max(frame.height - top - bottom, 1)
            return ChartRect(x: frame.x + (frame.width - width + leading - trailing) / 2,
                             y: frame.y + (frame.height - height + top - bottom) / 2, width: width, height: height)
        }

        // nil when the marks need no layer, so a chart without a style draws as it always did.
        func layer(_ frame: ChartRect) -> ChartPlotLayer? {
            let opacity = min(max(modifiers.opacity ?? 1, 0), 1)
            // A corner radius of 0 clips too (measured on macOS 27).
            let clips = modifiers.clipShape != nil || modifiers.cornerRadius != nil
            guard background != nil || opacity < 1 || clips else { return nil }
            // The largest is half the short side, however large the radius.
            return ChartPlotLayer(rect: frame, radius: min(radius, min(frame.width, frame.height) / 2), opacity: opacity, clips: clips)
        }
    }

    /// An axis title, resolved: `along` is how far along its side it sits, 0 at the start.
    private struct AxisTitle {
        var text: String
        var isX: Bool
        var edge: ChartAxisMarkPosition
        var along: Double
        var spacing: Double
    }

    // On the leading or trailing side only the vertical part of an alignment counts, and on the top
    // or bottom only the horizontal part (measured on macOS 27, for both axes).
    private func title(_ spec: ChartAxisSpec, isX: Bool, leadingLabels: Bool) -> AxisTitle? {
        guard let text = spec.label else { return nil }
        let edge: ChartAxisMarkPosition
        switch spec.labelPosition {
        case .top: edge = .top
        case .bottom: edge = .bottom
        case .leading: edge = .leading
        case .trailing: edge = .trailing
        default: edge = isX ? .bottom : .top
        }
        let alignment = spec.labelAlignment
        let along: Double
        if edge == .leading || edge == .trailing {
            along = alignment?.isTop == true ? 0 : alignment?.isBottom == true ? 1 : 0.5
        } else if let alignment {
            along = alignment.isLeading ? 0 : alignment.isTrailing ? 1 : 0.5
        } else {
            along = isX || leadingLabels ? 0 : 1
        }
        return AxisTitle(text: text, isX: isX, edge: edge, along: along, spacing: spec.labelSpacing ?? Self.titleGap)
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

    private func edge(_ marks: ChartAxisMarksSpec, isX: Bool, bands: Bool = false) -> ChartAxisMarkPosition {
        switch (marks.position, isX) {
        case (.top, true), (.bottom, true), (.leading, false), (.trailing, false): return marks.position
        case (_, true): return .bottom
        case (.automatic, false) where bands: return .leading
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
    private func tickRoom(_ spec: ChartAxisSpec, isX: Bool, _ edge: ChartAxisMarkPosition, bands: Bool = false) -> Double {
        var room = 0.0
        for marks in marks(spec) where self.edge(marks, isX: isX, bands: bands) == edge {
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
        // Lines are dashed on x and plain on y (measured on macOS 27).
        let dashed = isX
        let lineStroke = dashed ? Self.tickDash : ChartStroke()
        var bands = false
        if case .bands = axis.scale.kind { bands = true }
        return marks(spec).flatMap { marks -> [AxisGroup] in
            let ticks = ticks(marks, axis)
            let edge = edge(marks, isX: isX, bands: bands)
            guard let items = marks.items else {
                // Swift Charts' default: on x a line that runs on past the plot.
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
        var bands = false
        if case .bands = scale.kind { bands = true }
        // Bands keep every line and label however tight; only lines under a point apart thin.
        let every = bandStride(scale, room: 1)
        if let grid = group.grid {
            for y in linePositions(group, scale, every: every) {
                let from = ChartPoint(x: trailing ? left : left - grid.length, y: y)
                let to = ChartPoint(x: trailing ? right + grid.length : right, y: y)
                primitives.append(.line(from: from, to: to, ink: grid.ink, stroke: grid.stroke))
            }
        }
        if let tick = group.tick {
            for y in linePositions(group, scale, every: every) {
                // Out from the plot, and on bands into it (measured on macOS 27).
                let start = trailing ? right : left
                let end = start + (trailing != bands ? tick.length : -tick.length)
                primitives.append(.line(from: ChartPoint(x: start, y: y), to: ChartPoint(x: end, y: y), ink: tick.ink, stroke: tick.stroke))
            }
        }
        guard let label = group.label else { return }
        let anchor = label.anchor
        // The anchor's side that faces the plot puts a label inside it, on either edge. On bands a
        // label starts past its edge, unless a trailing anchor ends it there (measured on macOS 27).
        let inward = trailing ? anchor?.isTrailing == true : anchor?.isLeading == true
        let rightward = bands ? anchor?.isTrailing != true : trailing != inward
        let x = (trailing ? right : left) + (rightward ? Self.labelGap : -Self.labelGap)
        for (index, tick) in group.ticks.enumerated() where index % every == 0 {
            guard var y = scale.position(tick.value, unit: nil) else { continue }
            // A band's tick is its top line.
            if bands { y -= abs(scale.bandWidth) / 2 }
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

    private func appendMarks(_ stacks: [Int: Stacked], _ x: ChartAxisScale, _ y: ChartAxisScale, _ plot: ChartRect,
                             bandLabelRow: Double, into primitives: inout [ChartPrimitive]) {
        var joined: [JoinedMarks: [Int]] = [:]
        for (index, instance) in marks.instances.enumerated() where instance.mark.kind == .LineMark || instance.mark.kind == .AreaMark {
            joined[JoinedMarks(kind: instance.mark.kind, series: instance.seriesKey), default: []].append(index)
        }
        for index in drawingOrder() {
            let instance = marks.instances[index]
            let ink = styles.ink(instance)
            let start = primitives.count
            defer {
                if primitives.count > start, let effect = effect(instance) {
                    primitives.insert(.beginEffect(effect), at: start)
                    primitives.append(.endEffect(effect))
                }
            }
            switch instance.mark.kind {
            case .BarMark, .RectangleMark:
                if var rect = bar(instance, stack: stacks[index], x, y, plot, bandLabelRow: bandLabelRow) {
                    var moving = edges(instance)
                    if stacks[index]?.vertical == true {
                        moving.yStart = 0
                        moving.yEnd = 0
                    } else if stacks[index] != nil {
                        moving.xStart = 0
                        moving.xEnd = 0
                    }
                    rect = moved(rect, by: moving)
                    primitives.append(rounded(rect, instance, stack: stacks[index], x, y, ink: ink))
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
                // Joined marks draw at the first one's place, zIndex included, whichever comes up first.
                if let indices = joined[JoinedMarks(kind: .LineMark, series: instance.seriesKey)], indices[0] == index,
                   let primitive = line(indices, x, y, ink: ink) {
                    primitives.append(primitive)
                }
            case .AreaMark:
                if let indices = joined[JoinedMarks(kind: .AreaMark, series: instance.seriesKey)], indices[0] == index,
                   let primitive = area(indices, stacks, x, y, ink: ink) {
                    primitives.append(primitive)
                }
            case .SectorMark:
                break
            }
        }
    }

    // Lowest zIndex first, each level in the order of the content.
    private func drawingOrder() -> [Int] {
        func zIndex(_ instance: ChartMarkInstance) -> Double {
            for modifier in instance.mark.modifiers {
                if case .zIndex(let value) = modifier { return value }
            }
            return 0
        }
        let levels = marks.instances.map(zIndex)
        guard levels.contains(where: { $0 != 0 }) else { return Array(levels.indices) }
        return levels.indices.sorted { levels[$0] == levels[$1] ? $0 < $1 : levels[$0] < levels[$1] }
    }

    // What a mark asks of its drawing, nearest modifier first; nil for nothing.
    private func effect(_ instance: ChartMarkInstance) -> ChartMarkEffect? {
        var effect = ChartMarkEffect()
        for modifier in instance.mark.modifiers.reversed() {
            switch modifier {
            case .opacity(let opacity):
                effect.opacity = min(max(opacity, 0), 1)
            case .blur(let radius):
                let added = max(radius, 0)
                effect.blur = (effect.blur * effect.blur + added * added).squareRoot()
            case .shadow(let color, let radius, let x, let y):
                effect.shadow = ChartMarkShadow(color: color, radius: radius, x: x, y: y)
            case .offset(.xy(let x, let y)):
                effect.offset.x += x
                effect.offset.y += y
            case .offset(.xYRange(let x, _, _)):
                effect.offset.x += x
            case .offset(.xRangeY(_, _, let y)):
                effect.offset.y += y
            default:
                break
            }
        }
        return effect == ChartMarkEffect() ? nil : effect
    }

    /// How far an offset moves a mark's edges: start nearer the top or leading side.
    private struct MarkEdges {
        var xStart = 0.0
        var xEnd = 0.0
        var yStart = 0.0
        var yEnd = 0.0
    }

    private func edges(_ instance: ChartMarkInstance) -> MarkEdges {
        var edges = MarkEdges()
        for modifier in instance.mark.modifiers.reversed() {
            guard case .offset(let offset) = modifier else { continue }
            switch offset {
            case .xy:
                break
            case .xYRange(_, let yStart, let yEnd):
                edges.yStart += yStart
                edges.yEnd += yEnd
            case .xRangeY(let xStart, let xEnd, _):
                edges.xStart += xStart
                edges.xEnd += xEnd
            case .ranges(let xStart, let xEnd, let yStart, let yEnd):
                edges.xStart += xStart
                edges.xEnd += xEnd
                edges.yStart += yStart
                edges.yEnd += yEnd
            }
        }
        return edges
    }

    private func moved(_ rect: ChartRect, by edges: MarkEdges) -> ChartRect {
        let width = rect.width + edges.xEnd - edges.xStart, height = rect.height + edges.yEnd - edges.yStart
        return ChartRect(x: rect.x + edges.xStart + min(width, 0), y: rect.y + edges.yStart + min(height, 0), width: abs(width), height: abs(height))
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

    // A mark's symbol, if it names one, and its box.
    private func symbol(_ instance: ChartMarkInstance) -> (shape: ChartSymbol?, side: Double) {
        var shape: ChartSymbol?
        var area = Self.defaultSymbolArea
        var size: ChartSize?
        // Backward, so the modifier nearest the mark is the one that stays.
        for modifier in instance.mark.modifiers.reversed() {
            switch modifier {
            case .symbol(let symbol):
                shape = symbol
            case .symbolBy:
                shape = instance.symbolKey.map(styles.symbol(named:))
            case .symbolArea(let given):
                area = max(given, 0)
                size = nil
            case .symbolSizeBy:
                if let given = styles.area(instance) {
                    area = max(given, 0)
                    size = nil
                }
            case .symbolSize(let given):
                size = given
            default:
                break
            }
        }
        return (shape, size.map { max(min($0.width, $0.height), 0) } ?? 2 * (area / .pi).squareRoot())
    }

    private func stroke(_ instance: ChartMarkInstance, default fallback: ChartStroke) -> ChartStroke {
        if let key = instance.lineStyleKey { return styles.stroke(named: key) }
        if let value = instance.lineStyleValue { return styles.stroke(for: value) }
        var stroke = fallback
        for modifier in instance.mark.modifiers.reversed() {
            if case .lineStyle(let style) = modifier {
                stroke = style
            }
        }
        return stroke
    }

    // A value that has no place on its axis breaks the line (measured on macOS 27, not a number on
    // either axis), and a piece of one point draws only its symbol.
    private func line(_ indices: [Int], _ x: ChartAxisScale, _ y: ChartAxisScale, ink: ChartInk) -> ChartPrimitive? {
        let first = marks.instances[indices[0]]
        let method = interpolation(first.mark)
        var elements: [ChartPathElement] = []
        var piece: [ChartPoint] = []
        var symbols: [ChartLineSymbol] = []
        func endPiece() {
            if piece.count > 1 { elements += ChartCurves.elements(piece, method) }
            piece = []
        }
        for index in indices {
            let instance = marks.instances[index]
            if let px = position(instance, "x", x), let py = position(instance, "y", y) {
                let center = ChartPoint(x: px, y: py)
                piece.append(center)
                let (shape, side) = symbol(instance)
                // A size GSK cannot take costs this symbol, not the line.
                if let shape, Float(side).isFinite {
                    let lineWidth = max(self.stroke(instance, default: Self.defaultLine).lineWidth, 0)
                    symbols.append(ChartLineSymbol(symbol: shape, center: center, side: side, lineWidth: lineWidth))
                }
            } else {
                endPiece()
            }
        }
        endPiece()
        let stroke = stroke(first, default: Self.defaultLine)
        if !symbols.isEmpty {
            return .markedLine(elements, ink: ink, stroke: stroke, symbols: symbols)
        }
        return elements.isEmpty ? nil : .path(elements, ink: ink, stroke: stroke)
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

    private func bar(_ instance: ChartMarkInstance, stack: Stacked?, _ x: ChartAxisScale, _ y: ChartAxisScale, _ plot: ChartRect,
                     bandLabelRow: Double) -> ChartRect? {
        let mark = instance.mark
        let wholeX = (plot.x, plot.x + plot.width), wholeY = (plot.y, plot.y + plot.height)

        func crossSpan(_ key: String, _ scale: ChartAxisScale, _ dimension: ChartDimension) -> (Double, Double)? {
            guard let value = instance.values[key], let center = scale.position(value, unit: mark.values[key]?.unit) else { return nil }
            // On y a bar has what its band's label leaves of the band, in any form. Room below
            // nothing still counts, by its size (measured on macOS 27: 4.2 high on bands of 12, no minimum).
            if key == "y", bandLabelRow > 0 {
                let band = abs(scale.bandWidth), room = band - bandLabelRow
                var across = thickness(dimension, room: abs(room))
                if case .inset(let points) = dimension { across = abs(room - 2 * points) }
                let middle = center - band / 2 + bandLabelRow + room / 2
                return (middle - across / 2, middle + across / 2)
            }
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
            case .pairPair:
                xs = span(instance, "xStart", "xEnd", x)
                ys = span(instance, "yStart", "yEnd", y)
            case .pointsOnly:
                xs = pointsSpan(instance, "xStart", "xEnd", whole: wholeX)
                ys = pointsSpan(instance, "yStart", "yEnd", whole: wholeY)
            default:
                break
            }
        }
        guard let xs, let ys else { return nil }
        return ChartRect(x: min(xs.0, xs.1), y: min(ys.0, ys.1), width: abs(xs.1 - xs.0), height: abs(ys.1 - ys.0))
    }

    // A stack rounds as one shape, measured on macOS 27: a part under its corner is cut by it, an end
    // at 0 stays square, and with one end to round a corner has the whole length. Others have four.
    private func rounded(_ rect: ChartRect, _ instance: ChartMarkInstance, stack: Stacked?, _ x: ChartAxisScale, _ y: ChartAxisScale, ink: ChartInk) -> ChartPrimitive {
        var radius = instance.mark.kind == .BarMark ? Self.defaultBarCorner : 0
        for modifier in instance.mark.modifiers.reversed() {
            if case .cornerRadius(let given, _) = modifier {
                radius = given
            }
        }
        guard radius > 0 else { return .rect(rect, ink: ink) }
        guard let stack else {
            let side = min(rect.width, rect.height)
            guard side >= Self.thinnestRoundedBar else { return .rect(rect, ink: ink) }
            let corner = min(radius, side / 2)
            return .bar(rect, shape: rect, corners: ChartCorners(topLeading: corner, topTrailing: corner, bottomTrailing: corner, bottomLeading: corner), ink: ink)
        }
        let scale = stack.vertical ? y : x
        let lowEnd = scale.position(stack.whole.low), highEnd = scale.position(stack.whole.high)
        let start = min(lowEnd, highEnd), end = max(lowEnd, highEnd), length = end - start
        let startValue = lowEnd < highEnd ? stack.whole.low : stack.whole.high
        let endValue = lowEnd < highEnd ? stack.whole.high : stack.whole.low
        let across = stack.vertical ? rect.width : rect.height
        guard across >= Self.thinnestRoundedBar else { return .rect(rect, ink: ink) }
        let corner = min(radius, across / 2, startValue != 0 && endValue != 0 ? length / 2 : length)
        let partStart = stack.vertical ? rect.y : rect.x
        let partEnd = partStart + (stack.vertical ? rect.height : rect.width)
        let cutAtStart = startValue != 0 && partStart < start + corner
        let cutAtEnd = endValue != 0 && partEnd > end - corner
        guard cutAtStart || cutAtEnd else { return .rect(rect, ink: ink) }
        let atStart = cutAtStart ? corner : 0, atEnd = cutAtEnd ? corner : 0
        if stack.vertical {
            return .bar(rect, shape: ChartRect(x: rect.x, y: start, width: rect.width, height: length),
                        corners: ChartCorners(topLeading: atStart, topTrailing: atStart, bottomTrailing: atEnd, bottomLeading: atEnd), ink: ink)
        }
        return .bar(rect, shape: ChartRect(x: start, y: rect.y, width: length, height: rect.height),
                    corners: ChartCorners(topLeading: atStart, topTrailing: atEnd, bottomTrailing: atEnd, bottomLeading: atStart), ink: ink)
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
        guard let centerX = coordinate(instance, "x", x, origin: plot.x, length: plot.width),
              let centerY = coordinate(instance, "y", y, origin: plot.y, length: plot.height) else { return nil }
        let (shape, side) = symbol(instance)
        return .symbol(shape ?? .circle, center: ChartPoint(x: centerX, y: centerY), side: side, ink: ink)
    }

    private func rule(_ instance: ChartMarkInstance, _ x: ChartAxisScale, _ y: ChartAxisScale, _ plot: ChartRect, ink: ChartInk) -> ChartPrimitive? {
        let mark = instance.mark
        let wholeX = (plot.x, plot.x + plot.width), wholeY = (plot.y, plot.y + plot.height)
        let stroke = stroke(instance, default: Self.defaultLine)
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
        // Its ends are its only edges: an offset across a rule moves nothing (measured on macOS 27).
        func ends(_ span: (Double, Double), _ start: Double, _ end: Double) -> (Double, Double) {
            span.0 <= span.1 ? (span.0 + start, span.1 + end) : (span.0 + end, span.1 + start)
        }
        let edges = edges(instance)
        let isVertical = mark.form == .xPoints || mark.form == .xPair || mark.form == .pointsPair
        let along = isVertical ? (xs, ends(ys, edges.yStart, edges.yEnd)) : (ends(xs, edges.xStart, edges.xEnd), ys)
        return .line(from: ChartPoint(x: along.0.0, y: along.1.0), to: ChartPoint(x: along.0.1, y: along.1.1), ink: ink, stroke: stroke)
    }
}
