// Core/Helpers/Chart/ChartModel.swift
/*
 The vocabulary of a chart description, free of any renderer's types. ChartSpec and its parts hold
 these; on Apple, Helpers/ChartModel+SwiftUI.swift turns them into Swift Charts and SwiftUI values.

 Lengths are points as Double, colors ColorSpec, fonts FontSpec, number formats NumberFormatSpec.
 Raw values are the names a description writes. Where Swift Charts has a form without parameters
 beside one with them (.cardinal, .cardinal(tension:)), nil selects the form without.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

enum ChartAxis: Sendable {
    case horizontal, vertical
}

struct ChartAxes: OptionSet, Sendable {
    let rawValue: Int
    static let horizontal = ChartAxes(rawValue: 1)
    static let vertical = ChartAxes(rawValue: 2)
}

struct ChartSize: Equatable, Sendable {
    var width: Double
    var height: Double
}

// A mark's width, height or radius.
enum ChartDimension: Equatable, Sendable {
    case automatic
    case fixed(Double)
    case ratio(Double)
    case inset(Double)
}

enum ChartStacking: String, Sendable {
    case standard, normalized, center, unstacked
}

enum ChartInterpolation: Equatable, Sendable {
    case linear, monotone, stepStart, stepCenter, stepEnd
    case cardinal(tension: Double?)
    case catmullRom(alpha: Double?)
}

enum ChartSymbol: String, Sendable {
    case circle, square, triangle, diamond, pentagon, plus, cross, asterisk
}

enum ChartLineCap: String, Sendable {
    case butt, round, square
}

enum ChartLineJoin: String, Sendable {
    case miter, round, bevel
}

struct ChartStroke: Equatable, Sendable {
    var lineWidth = 1.0
    var lineCap = ChartLineCap.butt
    var lineJoin = ChartLineJoin.miter
    var miterLimit = 10.0
    var dash: [Double] = []
    var dashPhase = 0.0
}

enum ChartCornerStyle: String, Sendable {
    case continuous, circular
}

// Where an annotation, an axis label or the legend goes.
enum ChartPosition: String, Sendable {
    case automatic, overlay, top, bottom, leading, trailing, topLeading, topTrailing, bottomLeading, bottomTrailing
}

enum ChartAlignment: String, Sendable {
    case center, leading, trailing, top, bottom, topLeading, topTrailing, bottomLeading, bottomTrailing
}

enum ChartVisibility: String, Sendable {
    case automatic, visible, hidden
}

enum ChartScaleType: Equatable, Sendable {
    case linear, log, date, category, squareRoot
    case symmetricLog(slopeAtZero: Double?)
    case power(exponent: Double)
}

// The values a scale covers: on a position axis, or a style channel's {"by"} values.
enum ChartDomain: Equatable, Sendable {
    case automatic(includesZero: Bool? = nil, reversed: Bool? = nil)
    case numbers(ClosedRange<Double>)
    case dates(ClosedRange<Date>)
    case strings([String])
}

// The points a position scale maps its domain onto.
enum ChartPositionRange: Equatable, Sendable {
    case defaultPlotDimension
    case plotDimension(startPadding: Double, endPadding: Double)
    case points(ClosedRange<Double>)
}

enum ChartColorRange: Equatable, Sendable {
    case colors([ColorSpec])
    case gradient([ColorSpec])
}

// What an annotation does when it does not fit. A chart that names none has no value at all
// (ChartAnnotationSpec.overflow is nil).
struct ChartOverflowResolution: Equatable, Sendable {
    enum Boundary: String, Sendable {
        case plot, chart, automatic
    }
    enum Strategy: Equatable, Sendable {
        case automatic, fit, padScale, disabled
        case fitTo(Boundary)
    }
    var x = Strategy.automatic
    var y = Strategy.automatic
}

enum ChartAxisPreset: String, Sendable {
    case automatic, extended, aligned, inset
}

enum ChartAxisMarkPosition: String, Sendable {
    case automatic, leading, trailing, top, bottom
}

enum ChartLabelOrientation: String, Sendable {
    case automatic, horizontal, vertical, verticalReversed
}

enum ChartCollisionResolution: Equatable, Sendable {
    case automatic, truncate, disabled
    case greedy(priority: Double?, minimumSpacing: Double?)
}

// One field of a date format with its width, as "field.width". Every pair a description may
// write is a case, so a renderer's mapping is exhaustive.
enum ChartDateField: String, CaseIterable, Sendable {
    case yearDefaultDigits = "year.defaultDigits"
    case yearTwoDigits = "year.twoDigits"
    case quarterOneDigit = "quarter.oneDigit"
    case quarterTwoDigits = "quarter.twoDigits"
    case quarterAbbreviated = "quarter.abbreviated"
    case quarterWide = "quarter.wide"
    case quarterNarrow = "quarter.narrow"
    case monthDefaultDigits = "month.defaultDigits"
    case monthTwoDigits = "month.twoDigits"
    case monthAbbreviated = "month.abbreviated"
    case monthWide = "month.wide"
    case monthNarrow = "month.narrow"
    case dayDefaultDigits = "day.defaultDigits"
    case dayTwoDigits = "day.twoDigits"
    case weekdayAbbreviated = "weekday.abbreviated"
    case weekdayWide = "weekday.wide"
    case weekdayNarrow = "weekday.narrow"
    case weekdayShort = "weekday.short"
    case hourDefaultDigits = "hour.defaultDigits"
    case hourTwoDigits = "hour.twoDigits"
    case minuteDefaultDigits = "minute.defaultDigits"
    case minuteTwoDigits = "minute.twoDigits"
    case secondDefaultDigits = "second.defaultDigits"
    case secondTwoDigits = "second.twoDigits"
}

enum ChartDateStyle: String, Sendable {
    case omitted, numeric, abbreviated, long, complete
}

enum ChartTimeStyle: String, Sendable {
    case omitted, shortened, standard, complete
}

enum ChartDateFormat: Equatable, Sendable {
    case fields([ChartDateField])
    case styles(date: ChartDateStyle, time: ChartTimeStyle)
}
