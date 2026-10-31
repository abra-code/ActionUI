// Sources/Drawing/ChartScales.swift
/*
 The arithmetic of chart axes, without GTK: tick steps, the scale of an axis from values to points,
 and date bins and ticks. ChartLayout uses these; a test checks them as numbers.

 Steps are a power of ten times 1, 2, 2.5 or 5, and an automatic domain is widened to whole steps,
 as Swift Charts' are ("0, 500, 1,000, 1,500" for values up to 1,250).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Glibc

enum ChartTicks {
    /// How many number ticks an axis aims for.
    static let idealTicks = 4.0

    /// The step of 1, 2, 2.5 or 5 times a power of ten that gives the count of ticks closest to
    /// `idealTicks`, the smaller step of two as close, counted to whole steps past the ends when
    /// `widening` (an automatic domain) and inside them otherwise (an explicit one). 2.5 only when
    /// the step is a whole number. This fits all 71 axes measured on macOS 27 (automatic, maximum and
    /// step: 1 and 0.5, 4 and 1, 5 and 2, 9 and 5, 16 and 5, 50 and 20, 75 and 25, 80 and 20, 100
    /// and 25, 1,250 and 500; explicit: 0...9 and 2, 0...100 and 25, 3...47 and 10, 15...37 and 5,
    /// 10...90 and 20, 20...100 and 25). The size of the chart plays no part.
    static func step(_ lo: Double, _ hi: Double, widening: Bool) -> Double {
        let span = hi - lo
        guard span > 0, span.isFinite else { return 1 }
        var power = pow(10, floor(log10(span / idealTicks)) - 1)
        var best = span, bestMiss = Double.infinity
        // Five decades always hold one, unless the values are at the ends of Double's range.
        for _ in 0..<5 {
            for factor in [1.0, 2.0, 2.5, 5.0] where factor != 2.5 || power >= 10 {
                let step = factor * power
                let intervals = widening ? ceil(hi / step) - floor(lo / step) : floor(hi / step) - ceil(lo / step)
                let miss = abs(intervals + 1 - idealTicks)
                if miss < bestMiss {
                    best = step
                    bestMiss = miss
                }
            }
            power *= 10
        }
        return best
    }

    /// `lo...hi` widened to whole steps, and the ticks over it.
    static func widened(_ lo: Double, _ hi: Double) -> (lo: Double, hi: Double, step: Double, ticks: [Double]) {
        let top = hi > lo ? hi : lo + 1
        let step = step(lo, top, widening: true)
        let start = floor(lo / step) * step
        let end = ceil(top / step) * step
        let intervals = ((end - start) / step).rounded()
        // At the ends of Double's range whole steps do not exist: the values as they are.
        guard intervals.isFinite, intervals >= 1 else { return (lo, top, step, [lo, top]) }
        return (start, end, step, (0...Int(intervals)).map { start + Double($0) * step })
    }

    /// The ticks of whole steps inside `lo...hi`, which stays as it is.
    static func inside(_ lo: Double, _ hi: Double) -> (step: Double, ticks: [Double]) {
        let step = step(lo, hi, widening: false)
        let first = ceil(lo / step), last = floor(hi / step)
        let intervals = last - first
        guard intervals.isFinite, intervals >= 0 else { return (step, [lo, hi]) }
        return (step, (0...Int(intervals)).map { (first + Double($0)) * step })
    }

    /// How many decimals a step's labels take, so all of an axis's show the same: 1.0, 0.5, 0.
    static func fractionDigits(_ step: Double) -> Int {
        guard step > 0, step.isFinite else { return 0 }
        return min(max(0, Int(ceil(-log10(step) - 1e-9))), 15)
    }

    /// The powers of ten inside `lo...hi`, for a log scale.
    static func powersOfTen(_ lo: Double, _ hi: Double) -> [Double] {
        guard lo > 0, hi >= lo, hi.isFinite else { return [] }
        let first = ceil(log10(lo)), last = floor(log10(hi))
        guard first <= last else { return [] }
        return (0...Int(last - first)).map { pow(10, first + Double($0)) }
    }

    /// A symmetric log scale's domain and ticks: on each side of 0 the powers of ten from 10, or
    /// from the decade of the near end when all of `lo...hi` is on that side, out to the first at or
    /// past the far end; and 0 between two sides that have any. An automatic domain (`widening`)
    /// grows to its outer ticks; an explicit one stays, with the ticks inside it (measured on
    /// macOS 27: 0...2 ticks 10, -5...5 ticks -10, 0, 10, 2...3 ticks 1, 10, and 0...1 none).
    static func symmetricLog(_ lo: Double, _ hi: Double, widening: Bool) -> (lo: Double, hi: Double, ticks: [Double]) {
        // Distances from 0, `far` the larger.
        func powers(_ near: Double, _ far: Double) -> [Double] {
            guard far > 0, far.isFinite else { return [] }
            let first = near > 0 ? max(floor(log10(near)), -323) : 1, last = min(ceil(log10(far)), 308)
            guard first <= last else { return [] }
            return (0...Int(last - first)).map { pow(10, first + Double($0)) }
        }
        let above = powers(lo, hi), below = powers(-hi, -lo)
        let ticks = below.reversed().map { -$0 } + (above.isEmpty || below.isEmpty ? [] : [0]) + above
        guard widening else { return (lo, hi, ticks.filter { $0 >= lo && $0 <= hi }) }
        return (min(ticks.first ?? lo, lo), max(ticks.last ?? hi, hi), ticks)
    }
}

/// How an axis spaces its numbers.
enum ChartScaleTransform: Equatable {
    case linear, log, squareRoot
    case power(Double)
    /// `log1p` of the distance from 0, with this slope there, signed.
    case symmetricLog(Double)

    init(_ type: ChartScaleType?) {
        switch type {
        case .log?: self = .log
        case .squareRoot?: self = .squareRoot
        case .power(let exponent)?: self = .power(exponent)
        case .symmetricLog(let slope)?: self = .symmetricLog(slope ?? 1)
        case .linear?, .date?, .category?, nil: self = .linear
        }
    }

    func apply(_ number: Double) -> Double {
        switch self {
        case .linear: return number
        case .log: return log10(number)
        case .squareRoot: return number.squareRoot()
        case .power(let exponent): return pow(number, exponent)
        case .symmetricLog(let slope):
            let distance = log1p(abs(number) * slope)
            return number < 0 ? -distance : distance
        }
    }
}

/// How a date axis marks time: every `count` of `unit`.
struct ChartDateStride: Equatable {
    var unit: Calendar.Component
    var count: Int

    fileprivate var seconds: Double {
        let one: Double
        switch unit {
        case .year: one = 365 * 86400
        case .month: one = 30 * 86400
        case .weekOfYear: one = 7 * 86400
        case .day: one = 86400
        case .hour: one = 3600
        case .minute: one = 60
        default: one = 1
        }
        return one * Double(count)
    }

    fileprivate static let automatic: [ChartDateStride] = [
        .init(unit: .second, count: 1), .init(unit: .second, count: 15), .init(unit: .minute, count: 1), .init(unit: .minute, count: 5),
        .init(unit: .minute, count: 15), .init(unit: .hour, count: 1), .init(unit: .hour, count: 3), .init(unit: .hour, count: 6),
        .init(unit: .hour, count: 12), .init(unit: .day, count: 1), .init(unit: .day, count: 2), .init(unit: .weekOfYear, count: 1),
        .init(unit: .weekOfYear, count: 2), .init(unit: .month, count: 1), .init(unit: .month, count: 3), .init(unit: .month, count: 6),
        .init(unit: .year, count: 1), .init(unit: .year, count: 2), .init(unit: .year, count: 5), .init(unit: .year, count: 10),
        .init(unit: .year, count: 20), .init(unit: .year, count: 50), .init(unit: .year, count: 100),
    ]
}

enum ChartDates {
    /// The calendar bins and ticks use. Chart+Adwaita.swift gives it the first day of the user's
    /// week, which ICU knows and FoundationEssentials does not. Main thread only.
    nonisolated(unsafe) static var calendar = Calendar.current

    /// The bin a date falls in: the interval of `unit` holding it, or the date itself without a unit.
    static func bin(_ date: Date, _ unit: Calendar.Component?) -> (start: Date, end: Date) {
        guard let unit, let interval = calendar.dateInterval(of: unit, for: date) else { return (date, date) }
        return (interval.start, interval.end)
    }

    /// The first stride that draws at most `count` ticks over the span.
    static func stride(_ lo: Date, _ hi: Date, count: Int) -> ChartDateStride {
        let span = hi.timeIntervalSince(lo)
        return ChartDateStride.automatic.first { span / $0.seconds <= Double(max(count, 1)) } ?? .init(unit: .year, count: 1000)
    }

    /// The whole strides inside `lo...hi`.
    static func ticks(_ lo: Date, _ hi: Date, stride: ChartDateStride) -> [Date] {
        // A domain of one instant has none (measured on macOS 27), as one number has none.
        guard lo < hi else { return [] }
        var tick = bin(lo, stride.unit).start
        var ticks: [Date] = []
        // The bound only guards a stride the calendar cannot step: `stride` draws far fewer.
        while tick <= hi, ticks.count < 1000 {
            if tick >= lo { ticks.append(tick) }
            guard let next = calendar.date(byAdding: stride.unit, value: stride.count, to: tick), next > tick else { break }
            tick = next
        }
        return ticks
    }
}

/// An axis: what it covers and the points it maps that onto (`start` is where the low end goes).
struct ChartAxisScale {
    enum Kind {
        case none
        /// Each category's place, so that finding one does not walk the rest.
        case bands([String: Int])
        case numbers(lo: Double, hi: Double)
        case dates(lo: Date, hi: Date)
    }

    var kind = Kind.none
    var start = 0.0
    var end = 0.0
    var transform = ChartScaleTransform.linear

    var bandWidth: Double {
        guard case .bands(let names) = kind, !names.isEmpty else { return 0 }
        return (end - start) / Double(names.count)
    }

    /// Any number has the place the scale's math gives it, in or past the domain (measured on
    /// macOS 27, for all scale types); one the math has no answer for (0 or less on a log scale, say)
    /// comes back not finite.
    func position(_ number: Double) -> Double {
        guard case .numbers(let lo, let hi) = kind else { return start }
        guard hi != lo else { return (start + end) / 2 }
        let low = transform.apply(lo)
        return start + (transform.apply(number) - low) / (transform.apply(hi) - low) * (end - start)
    }

    func position(_ date: Date) -> Double {
        guard case .dates(let lo, let hi) = kind else { return start }
        let span = hi.timeIntervalSince(lo)
        return span == 0 ? (start + end) / 2 : start + date.timeIntervalSince(lo) / span * (end - start)
    }

    /// A number's place, nil when it has none on this axis.
    private func placed(_ number: Double) -> Double? {
        let place = position(number)
        return number.isFinite && place.isFinite ? place : nil
    }

    /// Where a value goes: a band's center, or a date with a unit in the middle of its bin, as
    /// Swift Charts places it. nil for a value of another type than the axis's, or one with no place.
    func position(_ value: ChartScalar, unit: Calendar.Component?) -> Double? {
        switch (kind, value) {
        case (.bands(let names), .string(let name)):
            return names[name].map { start + (Double($0) + 0.5) * bandWidth }
        case (.numbers, .number(let number)):
            return placed(number)
        case (.numbers, .integer(let number)):
            return placed(Double(number))
        case (.dates, .date(let date)):
            guard unit != nil else { return position(date) }
            let bin = ChartDates.bin(date, unit)
            return (position(bin.start) + position(bin.end)) / 2
        default:
            return nil
        }
    }

    /// The room a value's bin takes on the axis: a band, or a date bin; 0 where values have none.
    func binWidth(_ value: ChartScalar, unit: Calendar.Component?) -> Double {
        if case .bands = kind { return abs(bandWidth) }
        guard unit != nil, case .date(let date) = value else { return 0 }
        let bin = ChartDates.bin(date, unit)
        return abs(position(bin.end) - position(bin.start))
    }
}
