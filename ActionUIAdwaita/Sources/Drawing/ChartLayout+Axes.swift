// Sources/Drawing/ChartLayout+Axes.swift
/*
 An axis from what the marks plot: its domain, its scale and its ticks, and its place on the plot.

 - An automatic number domain includes 0 and is widened to whole steps (ChartTicks), and a date
   axis covers each value's whole bin. An explicit domain is exact; marks past it still draw, and a
   category it does not name does not. Labels of one axis share their decimals. A domain of one
   value has no ticks and puts every mark in the middle.
 - Numbers rise up a y axis, and dates read down it, the earliest at the top.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension ChartLayout {
    /// What one axis plots, before it has points.
    struct Extent {
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

    func extents(_ stacks: [Int: Stacked]) -> (x: Extent, y: Extent) {
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

    /// An axis's scale, without its points, and its ticks: where each goes and its label.
    struct Axis {
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

    func axis(_ extent: Extent, _ spec: ChartAxisSpec, length: Double, pointsPerTick: Double = Self.pointsPerDateTick) -> Axis {
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
            axis.ticks = dateTicks(dates.lo, dates.hi, count: max(2, min(Int(length / pointsPerTick), 8)))
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
    func dateTicks(_ lo: Date, _ hi: Date, count: Int) -> [(value: ChartScalar, label: String)] {
        let stride = ChartDates.stride(lo, hi, count: count)
        return dateLabels(ChartDates.ticks(lo, hi, stride: stride), unit: stride.unit)
    }

    func dateLabels(_ dates: [Date], unit: Calendar.Component) -> [(value: ChartScalar, label: String)] {
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

    // Puts an axis on the plot, between `from` and `to` in the direction it reads, with its padding
    // or its range in points, which count from the plot's corner.
    func place(_ axis: inout Axis, _ spec: ChartAxisSpec, from: Double, to: Double) {
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
}
