// Sources/Drawing/ChartScales.swift
/*
 The arithmetic of chart axes, without GTK: tick steps, the scale of an axis from values to points,
 and date bins and ticks. ChartLayout uses these; a test checks them as numbers.

 Steps are a power of ten times 1, 2 or 5, and an automatic domain is widened to whole steps, as
 Swift Charts' are ("0, 500, 1,000, 1,500" for values up to 1,250).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Glibc

enum ChartTicks {
    /// The smallest step of 1, 2 or 5 times a power of ten that covers `lo...hi` in at most
    /// `intervals` whole steps. This fits every axis measured on macOS 27 (maximum and step: 4 and 1,
    /// 5 and 2, 8 and 2, 9 and 5, 30 and 10, 60 and 20, 1,250 and 500).
    static func step(_ lo: Double, _ hi: Double, intervals: Int) -> Double {
        let span = hi - lo
        guard span > 0, span.isFinite else { return 1 }
        var power = pow(10, floor(log10(span / Double(max(intervals, 1)))))
        // Four decades always hold one, unless the values are at the ends of Double's range.
        for _ in 0..<4 {
            for factor in [1.0, 2.0, 5.0] {
                let step = factor * power
                if ceil(hi / step) - floor(lo / step) <= Double(intervals) { return step }
            }
            power *= 10
        }
        return span
    }

    /// `lo...hi` widened to whole steps, in at most `intervals` of them, and the ticks over it.
    static func domain(_ lo: Double, _ hi: Double, intervals: Int) -> (lo: Double, hi: Double, ticks: [Double]) {
        let top = hi > lo ? hi : lo + 1
        return domain(lo, top, step: step(lo, top, intervals: intervals))
    }

    /// `lo...top` widened to whole steps of `step`, and the ticks over it.
    static func domain(_ lo: Double, _ top: Double, step: Double) -> (lo: Double, hi: Double, ticks: [Double]) {
        let start = floor(lo / step) * step
        let end = ceil(top / step) * step
        let intervals = ((end - start) / step).rounded()
        // At the ends of Double's range whole steps do not exist: the values as they are.
        guard intervals.isFinite, intervals >= 1 else { return (lo, top, [lo, top]) }
        return (start, end, (0...Int(intervals)).map { start + Double($0) * step })
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

    var bandWidth: Double {
        guard case .bands(let names) = kind, !names.isEmpty else { return 0 }
        return (end - start) / Double(names.count)
    }

    func position(_ number: Double) -> Double {
        guard case .numbers(let lo, let hi) = kind else { return start }
        return hi == lo ? (start + end) / 2 : start + (number - lo) / (hi - lo) * (end - start)
    }

    func position(_ date: Date) -> Double {
        guard case .dates(let lo, let hi) = kind else { return start }
        let span = hi.timeIntervalSince(lo)
        return span == 0 ? (start + end) / 2 : start + date.timeIntervalSince(lo) / span * (end - start)
    }

    /// Where a value goes: a band's center, or a date with a unit in the middle of its bin, as
    /// Swift Charts places it. nil for a value of another type than the axis's.
    func position(_ value: ChartScalar, unit: Calendar.Component?) -> Double? {
        switch (kind, value) {
        case (.bands(let names), .string(let name)):
            return names[name].map { start + (Double($0) + 0.5) * bandWidth }
        case (.numbers, .number(let number)):
            return number.isFinite ? position(number) : nil
        case (.numbers, .integer(let number)):
            return position(Double(number))
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
