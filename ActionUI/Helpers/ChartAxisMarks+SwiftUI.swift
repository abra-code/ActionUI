// Helpers/ChartAxisMarks+SwiftUI.swift
//
// The Swift Charts axis content of the Chart element, built from ChartAxisMarksSpec
// (Core/Helpers/Chart/ChartAxisMarks.swift). Axis builders have no ForEach and cannot combine a
// list of erased items, so items and AxisMarks are erased (AnyAxisMark, AnyAxisContent) and
// combined by fixed-arity switches, up to four of each.

import Foundation
import SwiftUI
import Charts

// MARK: - Building

@MainActor
enum ChartAxisContentBuilder {
    /// The axis content for chartXAxis / chartYAxis { }. nil is a plain AxisMarks(), which draws
    /// exactly like no axis content.
    static func content(_ specs: [ChartAxisMarksSpec]?) -> AnyAxisContent {
        guard let specs, !specs.isEmpty else {
            return AnyAxisContent(erasing: AxisMarks())
        }
        let c = specs.prefix(ChartDescription.maxAxisMarks).map(axisMarks)
        switch c.count {
        case 1: return c[0]
        case 2: return AnyAxisContent(erasing: pair(c[0], c[1]))
        case 3: return AnyAxisContent(erasing: triple(c[0], c[1], c[2]))
        default: return AnyAxisContent(erasing: quad(c[0], c[1], c[2], c[3]))
        }
    }

    @AxisContentBuilder
    private static func pair(_ a: AnyAxisContent, _ b: AnyAxisContent) -> some AxisContent {
        a
        b
    }

    @AxisContentBuilder
    private static func triple(_ a: AnyAxisContent, _ b: AnyAxisContent, _ c: AnyAxisContent) -> some AxisContent {
        a
        b
        c
    }

    @AxisContentBuilder
    private static func quad(_ a: AnyAxisContent, _ b: AnyAxisContent, _ c: AnyAxisContent, _ d: AnyAxisContent) -> some AxisContent {
        a
        b
        c
        d
    }

    private static func axisMarks(_ spec: ChartAxisMarksSpec) -> AnyAxisContent {
        guard let items = spec.items else {
            return defaultMarks(spec)
        }
        let m = items.prefix(ChartDescription.maxAxisMarks).map(mark)
        let preset = spec.preset.axisMarkPreset, position = spec.position.axisMarkPosition
        // One builder per item count; explicit values take AxisMarks' generic `values:` initializer.
        func marks(_ values: AxisMarkValues) -> AnyAxisContent {
            switch m.count {
            // AxisMark has no public way to draw nothing; an empty content is one invisible tick.
            case 0: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { AxisTick(length: 0, stroke: StrokeStyle(lineWidth: 0)) })
            case 1: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { m[0] })
            case 2: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { m[0]; m[1] })
            case 3: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { m[0]; m[1]; m[2] })
            default: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { m[0]; m[1]; m[2]; m[3] })
            }
        }
        func marks<V: Plottable>(_ values: [V]) -> AnyAxisContent {
            switch m.count {
            case 0: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { AxisTick(length: 0, stroke: StrokeStyle(lineWidth: 0)) })
            case 1: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { m[0] })
            case 2: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { m[0]; m[1] })
            case 3: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { m[0]; m[1]; m[2] })
            default: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values) { m[0]; m[1]; m[2]; m[3] })
            }
        }
        switch spec.values {
        case .numbers(let values): return marks(values)
        case .dates(let values): return marks(values)
        case .strings(let values): return marks(values)
        default: return marks(markValues(spec.values))
        }
    }

    // Swift's default marks, with the AxisMarks-level format and stroke.
    private static func defaultMarks(_ spec: ChartAxisMarksSpec) -> AnyAxisContent {
        let preset = spec.preset.axisMarkPreset, position = spec.position.axisMarkPosition, stroke = spec.stroke?.strokeStyle
        func formatted<F: FormatStyle>(_ format: F) -> AnyAxisContent where F.FormatInput: Plottable, F.FormatOutput == String {
            switch spec.values {
            case .numbers(let values):
                // Format input and value type must agree; a format other than a Double one is
                // only reached for date values below.
                if let values = values as? [F.FormatInput] {
                    return AnyAxisContent(erasing: AxisMarks(format: format, preset: preset, position: position, values: values, stroke: stroke))
                }
            case .dates(let values):
                if let values = values as? [F.FormatInput] {
                    return AnyAxisContent(erasing: AxisMarks(format: format, preset: preset, position: position, values: values, stroke: stroke))
                }
            case .strings:
                break
            default:
                return AnyAxisContent(erasing: AxisMarks(format: format, preset: preset, position: position, values: markValues(spec.values), stroke: stroke))
            }
            return AnyAxisContent(erasing: AxisMarks(format: format, preset: preset, position: position, stroke: stroke))
        }
        switch spec.format {
        case .number(let number):
            switch number {
            case .integer: return formatted(FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0)))
            case .decimal(let low, let high): return formatted(decimal(low, high))
            case .percent(let low, let high): return formatted(percent(low, high))
            case .currency(let code, let low, let high): return formatted(currency(code, low, high))
            }
        case .date(let format):
            return formatted(format.formatStyle)
        case nil:
            switch spec.values {
            case .numbers(let values): return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values, stroke: stroke))
            case .dates(let values): return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values, stroke: stroke))
            case .strings(let values): return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: values, stroke: stroke))
            default: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: markValues(spec.values), stroke: stroke))
            }
        }
    }

    private static func markValues(_ values: ChartAxisValues) -> AxisMarkValues {
        switch values {
        case .automatic(let count, let lower, let upper):
            if count == nil, lower == nil, upper == nil { return .automatic }
            return .automatic(desiredCount: count, roundLowerBound: lower, roundUpperBound: upper)
        case .calendarStride(let unit, let count):
            return .stride(by: unit, count: count)
        case .numberStride(let step):
            return .stride(by: step)
        case .numbers, .dates, .strings:
            return .automatic // handled by the `values:` initializers
        }
    }

    private static func mark(_ item: ChartAxisMarkItem) -> AnyAxisMark {
        var mark: AnyAxisMark
        switch item.kind {
        case .gridLine(let centered, let stroke):
            mark = AnyAxisMark(erasing: AxisGridLine(centered: centered, stroke: stroke?.strokeStyle))
        case .tick(let centered, let length, let stroke):
            let style = stroke?.strokeStyle
            switch length {
            case .automatic: mark = AnyAxisMark(erasing: AxisTick(centered: centered, length: .automatic, stroke: style))
            case .fixed(let points): mark = AnyAxisMark(erasing: AxisTick(centered: centered, length: CGFloat(points), stroke: style))
            case .label(let extend): mark = AnyAxisMark(erasing: AxisTick(centered: centered, length: .label(extendPastBy: CGFloat(extend)), stroke: style))
            case .longestLabel(let extend): mark = AnyAxisMark(erasing: AxisTick(centered: centered, length: .longestLabel(extendPastBy: CGFloat(extend)), stroke: style))
            }
        case .valueLabel(let format, let centered, let anchor, let alignment, let collision, let offsetsMarks, let orientation,
                         let horizontalSpacing, let verticalSpacing):
            let unitPoint = anchor?.unitPoint, multiLabelAlignment = alignment?.alignment
            let collisionResolution = collision.collisionResolution, labelOrientation = orientation.labelOrientation
            let hSpacing = horizontalSpacing.map { CGFloat($0) }, vSpacing = verticalSpacing.map { CGFloat($0) }
            func label<F: FormatStyle>(_ format: F) -> AnyAxisMark where F.FormatInput: Plottable, F.FormatOutput == String {
                AnyAxisMark(erasing: AxisValueLabel(format: format, centered: centered, anchor: unitPoint, multiLabelAlignment: multiLabelAlignment,
                                                    collisionResolution: collisionResolution, offsetsMarks: offsetsMarks, orientation: labelOrientation,
                                                    horizontalSpacing: hSpacing, verticalSpacing: vSpacing))
            }
            switch format {
            case .number(.integer): mark = label(FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0)))
            case .number(.decimal(let low, let high)): mark = label(decimal(low, high))
            case .number(.percent(let low, let high)): mark = label(percent(low, high))
            case .number(.currency(let code, let low, let high)): mark = label(currency(code, low, high))
            case .date(let dateFormat): mark = label(dateFormat.formatStyle)
            case nil:
                mark = AnyAxisMark(erasing: AxisValueLabel(centered: centered, anchor: unitPoint, multiLabelAlignment: multiLabelAlignment,
                                                           collisionResolution: collisionResolution, offsetsMarks: offsetsMarks, orientation: labelOrientation,
                                                           horizontalSpacing: hSpacing, verticalSpacing: vSpacing))
            }
        }
        if let color = item.foregroundStyle { mark = AnyAxisMark(erasing: mark.foregroundStyle(ColorHelper.color(for: color))) }
        if let font = item.font { mark = AnyAxisMark(erasing: mark.font(FontHelper.font(for: font))) }
        if let offset = item.offset { mark = AnyAxisMark(erasing: mark.offset(offset.cgSize)) }
        return mark
    }

    // Number formats: Double styles on number and integer axes alike (Swift Charts formats an
    // Int axis value through a Double style).
    private static func precision(_ low: Int?, _ high: Int?) -> ClosedRange<Int>? {
        NumberFormatSpec.fractionRange(minFraction: low, maxFraction: high)
    }

    private static func decimal(_ low: Int?, _ high: Int?) -> FloatingPointFormatStyle<Double> {
        precision(low, high).map { FloatingPointFormatStyle<Double>.number.precision(.fractionLength($0)) } ?? .number
    }

    private static func percent(_ low: Int?, _ high: Int?) -> FloatingPointFormatStyle<Double>.Percent {
        precision(low, high).map { FloatingPointFormatStyle<Double>.Percent.percent.precision(.fractionLength($0)) } ?? .percent
    }

    private static func currency(_ code: String, _ low: Int?, _ high: Int?) -> FloatingPointFormatStyle<Double>.Currency {
        let style = FloatingPointFormatStyle<Double>.Currency(code: code)
        return precision(low, high).map { style.precision(.fractionLength($0)) } ?? style
    }
}
