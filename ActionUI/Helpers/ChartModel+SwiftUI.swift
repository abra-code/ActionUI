// Helpers/ChartModel+SwiftUI.swift
//
// Turns the chart model's neutral values (Core/Helpers/Chart/ChartModel.swift) into the Swift
// Charts and SwiftUI values the builders pass on. Colors and fonts go through ColorHelper and
// FontHelper. Each mapping keeps Swift Charts' own form: nil selects the one without parameters.

import Foundation
import SwiftUI
import Charts

extension ChartAxes {
    var axisSet: Axis.Set {
        var set: Axis.Set = []
        if contains(.horizontal) { set.insert(.horizontal) }
        if contains(.vertical) { set.insert(.vertical) }
        return set
    }
}

extension ChartAxis {
    var axis: Axis {
        switch self {
        case .horizontal: return .horizontal
        case .vertical: return .vertical
        }
    }
}

extension ChartSize {
    var cgSize: CGSize { CGSize(width: width, height: height) }
}

extension ChartDimension {
    var markDimension: MarkDimension {
        switch self {
        case .automatic: return .automatic
        case .fixed(let value): return .fixed(CGFloat(value))
        case .ratio(let value): return .ratio(CGFloat(value))
        case .inset(let value): return .inset(CGFloat(value))
        }
    }
}

extension ChartStacking {
    var stackingMethod: MarkStackingMethod {
        switch self {
        case .standard: return .standard
        case .normalized: return .normalized
        case .center: return .center
        case .unstacked: return .unstacked
        }
    }
}

extension ChartInterpolation {
    var interpolationMethod: InterpolationMethod {
        switch self {
        case .linear: return .linear
        case .monotone: return .monotone
        case .stepStart: return .stepStart
        case .stepCenter: return .stepCenter
        case .stepEnd: return .stepEnd
        case .cardinal(let tension):
            if let tension { return .cardinal(tension: CGFloat(tension)) }
            return .cardinal
        case .catmullRom(let alpha):
            if let alpha { return .catmullRom(alpha: CGFloat(alpha)) }
            return .catmullRom
        }
    }
}

extension ChartSymbol {
    var symbolShape: BasicChartSymbolShape {
        switch self {
        case .circle: return .circle
        case .square: return .square
        case .triangle: return .triangle
        case .diamond: return .diamond
        case .pentagon: return .pentagon
        case .plus: return .plus
        case .cross: return .cross
        case .asterisk: return .asterisk
        }
    }
}

extension ChartStroke {
    var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: CGFloat(lineWidth), lineCap: lineCap.cgLineCap, lineJoin: lineJoin.cgLineJoin, miterLimit: CGFloat(miterLimit),
                    dash: dash.map { CGFloat($0) }, dashPhase: CGFloat(dashPhase))
    }
}

extension ChartLineCap {
    fileprivate var cgLineCap: CGLineCap {
        switch self {
        case .butt: return .butt
        case .round: return .round
        case .square: return .square
        }
    }
}

extension ChartLineJoin {
    fileprivate var cgLineJoin: CGLineJoin {
        switch self {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
        }
    }
}

extension ChartCornerStyle {
    var cornerStyle: RoundedCornerStyle {
        switch self {
        case .continuous: return .continuous
        case .circular: return .circular
        }
    }
}

extension ChartPosition {
    var annotationPosition: AnnotationPosition {
        switch self {
        case .automatic: return .automatic
        case .overlay: return .overlay
        case .top: return .top
        case .bottom: return .bottom
        case .leading: return .leading
        case .trailing: return .trailing
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }
}

extension ChartAlignment {
    var alignment: Alignment {
        switch self {
        case .center: return .center
        case .leading: return .leading
        case .trailing: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }

    var unitPoint: UnitPoint {
        switch self {
        case .center: return .center
        case .leading: return .leading
        case .trailing: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }
}

extension ChartVisibility {
    var visibility: Visibility {
        switch self {
        case .automatic: return .automatic
        case .visible: return .visible
        case .hidden: return .hidden
        }
    }
}

extension ChartScaleType {
    var scaleType: ScaleType {
        switch self {
        case .linear: return .linear
        case .log: return .log
        case .date: return .date
        case .category: return .category
        case .squareRoot: return .squareRoot
        case .symmetricLog(let slope):
            if let slope { return .symmetricLog(slopeAtZero: slope) }
            return .symmetricLog
        case .power(let exponent): return .power(exponent: exponent)
        }
    }
}

extension ChartOverflowResolution {
    var resolution: AnnotationOverflowResolution {
        AnnotationOverflowResolution(x: Self.strategy(x), y: Self.strategy(y))
    }

    private static func strategy(_ strategy: Strategy) -> AnnotationOverflowResolution.Strategy {
        switch strategy {
        case .automatic: return .automatic
        case .fit: return .fit
        case .padScale: return .padScale
        case .disabled: return .disabled
        case .fitTo(.plot): return .fit(to: .plot)
        case .fitTo(.chart): return .fit(to: .chart)
        case .fitTo(.automatic): return .fit(to: .automatic)
        }
    }
}

extension ChartAxisPreset {
    var axisMarkPreset: AxisMarkPreset {
        switch self {
        case .automatic: return .automatic
        case .extended: return .extended
        case .aligned: return .aligned
        case .inset: return .inset
        }
    }
}

extension ChartAxisMarkPosition {
    var axisMarkPosition: AxisMarkPosition {
        switch self {
        case .automatic: return .automatic
        case .leading: return .leading
        case .trailing: return .trailing
        case .top: return .top
        case .bottom: return .bottom
        }
    }
}

extension ChartLabelOrientation {
    var labelOrientation: AxisValueLabelOrientation {
        switch self {
        case .automatic: return .automatic
        case .horizontal: return .horizontal
        case .vertical: return .vertical
        case .verticalReversed: return .verticalReversed
        }
    }
}

extension ChartCollisionResolution {
    var collisionResolution: AxisValueLabelCollisionResolution {
        switch self {
        case .automatic: return .automatic
        case .truncate: return .truncate
        case .disabled: return .disabled
        case .greedy(let priority, let spacing):
            guard let priority else { return .greedy }
            return .greedy(priority: priority, minimumSpacing: spacing.map { CGFloat($0) })
        }
    }
}

extension ChartDateFormat {
    var formatStyle: Date.FormatStyle {
        switch self {
        case .fields(let fields):
            return fields.reduce(Date.FormatStyle()) { $1.applied(to: $0) }
        case .styles(let date, let time):
            return Date.FormatStyle(date: date.dateStyle, time: time.timeStyle)
        }
    }
}

extension ChartDateField {
    fileprivate func applied(to style: Date.FormatStyle) -> Date.FormatStyle {
        switch self {
        case .yearDefaultDigits: return style.year(.defaultDigits)
        case .yearTwoDigits: return style.year(.twoDigits)
        case .quarterOneDigit: return style.quarter(.oneDigit)
        case .quarterTwoDigits: return style.quarter(.twoDigits)
        case .quarterAbbreviated: return style.quarter(.abbreviated)
        case .quarterWide: return style.quarter(.wide)
        case .quarterNarrow: return style.quarter(.narrow)
        case .monthDefaultDigits: return style.month(.defaultDigits)
        case .monthTwoDigits: return style.month(.twoDigits)
        case .monthAbbreviated: return style.month(.abbreviated)
        case .monthWide: return style.month(.wide)
        case .monthNarrow: return style.month(.narrow)
        case .dayDefaultDigits: return style.day(.defaultDigits)
        case .dayTwoDigits: return style.day(.twoDigits)
        case .weekdayAbbreviated: return style.weekday(.abbreviated)
        case .weekdayWide: return style.weekday(.wide)
        case .weekdayNarrow: return style.weekday(.narrow)
        case .weekdayShort: return style.weekday(.short)
        case .hourDefaultDigits: return style.hour(.defaultDigits(amPM: .abbreviated))
        case .hourTwoDigits: return style.hour(.twoDigits(amPM: .abbreviated))
        case .minuteDefaultDigits: return style.minute(.defaultDigits)
        case .minuteTwoDigits: return style.minute(.twoDigits)
        case .secondDefaultDigits: return style.second(.defaultDigits)
        case .secondTwoDigits: return style.second(.twoDigits)
        }
    }
}

extension ChartDateStyle {
    fileprivate var dateStyle: Date.FormatStyle.DateStyle {
        switch self {
        case .omitted: return .omitted
        case .numeric: return .numeric
        case .abbreviated: return .abbreviated
        case .long: return .long
        case .complete: return .complete
        }
    }
}

extension ChartTimeStyle {
    fileprivate var timeStyle: Date.FormatStyle.TimeStyle {
        switch self {
        case .omitted: return .omitted
        case .shortened: return .shortened
        case .standard: return .standard
        case .complete: return .complete
        }
    }
}
