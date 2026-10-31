// Core/Helpers/Chart/ChartScrolling.swift
//
// Chart scrolling: chartScrollableAxes, chartXVisibleDomain / chartYVisibleDomain and the
// initial scroll position, as a description declares them.

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The visible length of a scrolling axis, in the unit Swift Charts reads for its type: data
/// units on a number axis, seconds on a date axis, a count of categories on a string axis.
enum ChartVisibleLength: Equatable {
    case amount(Double)
    case categories(Int)
}

struct ChartScrollSpec: Equatable {
    var axes: ChartAxes = []
    var xLength: ChartVisibleLength?
    var yLength: ChartVisibleLength?
    var initialX: ChartScalar?
    var initialY: ChartScalar?
    // The type of each axis, for the visible length limit.
    var xType: ChartColumnType?
    var yType: ChartColumnType?

    var isEmpty: Bool { axes.isEmpty }
}

// Swift Charts lays out the automatic axis marks of the whole scrolling axis at the density of
// the visible part, and the cost grows faster than the count: measured in a window, about 0.09 s
// for 100 marks, 1 s for 500, seconds past that and minutes for a week of days read as 7 seconds,
// sooner with a large desiredCount. Like a stride (ChartAxisStrideLimit), the length is
// checked against the axis span whenever the marks are built, and one that would lay out more
// than `maxAutomaticMarks` is lengthened to the shortest that does not, with a warning: the chart
// keeps scrolling, and rows streamed in only lengthen it further. Measured, Swift's default marks cost about
// as much as a desiredCount of 2.5 per visible length; strides, explicit values and a hidden axis
// cost nothing here.
enum ChartVisibleLengthLimit {
    static let maxAutomaticMarks = 100.0
    static let defaultMarksPerLength = 2.5

    static func limited(_ scroll: ChartScrollSpec, x: ChartAxisSpec, y: ChartAxisSpec, xExtent: ClosedRange<Double>?,
                        yExtent: ClosedRange<Double>?, viewID: Int, logger: any ActionUILogger) -> ChartScrollSpec {
        var scroll = scroll
        scroll.xLength = limited(scroll.xLength, axis: x, type: scroll.xType, extent: xExtent, key: "chartXVisibleDomain",
                                 viewID: viewID, logger: logger)
        scroll.yLength = limited(scroll.yLength, axis: y, type: scroll.yType, extent: yExtent, key: "chartYVisibleDomain",
                                 viewID: viewID, logger: logger)
        return scroll
    }

    private static func limited(_ length: ChartVisibleLength?, axis: ChartAxisSpec, type: ChartColumnType?, extent: ClosedRange<Double>?,
                                key: String, viewID: Int, logger: any ActionUILogger) -> ChartVisibleLength? {
        let perLength = marksPerLength(axis)
        guard case .amount(let amount)? = length, let type, perLength > 0,
              let span = ChartAxisStrideLimit.span(axis.domain, extent: extent, dates: type == .date),
              span / amount * perLength > maxAutomaticMarks else { return length }
        let shortest = span * perLength / maxAutomaticMarks
        logger.log("Chart \(viewID): '\(key)' length \(amount) of an axis span of \(span) would lay out about \(Int(min(span / amount * perLength, 1e15))) automatic axis marks (at most \(Int(maxAutomaticMarks))); using a length of \(shortest)", .warning)
        return .amount(shortest)
    }

    // The automatic marks the axis asks for in each visible length; 0 when it draws none.
    private static func marksPerLength(_ axis: ChartAxisSpec) -> Double {
        guard axis.visibility != .hidden else { return 0 }
        guard let marks = axis.marks, !marks.isEmpty else { return defaultMarksPerLength }
        return marks.reduce(0) { sum, mark in
            guard case .automatic(let desiredCount, _, _) = mark.values else { return sum }
            return sum + (desiredCount.map(Double.init) ?? defaultMarksPerLength)
        }
    }
}
