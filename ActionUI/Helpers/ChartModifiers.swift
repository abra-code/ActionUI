// Helpers/ChartModifiers.swift
//
// The Chart element's view modifiers, applied as one chain whose type never changes. Every
// modifier is always applied, with a neutral value where the description is silent, so a
// replaced description changes values, not the view's type: SwiftUI keeps the same chart and can
// animate between the two. Each neutral value draws pixel-identically to leaving the modifier out.
// Where Swift Charts has no neutral value (an axis label, a color or symbol size range), a view
// modifier of fixed type leaves the modifier out instead; adding or removing one of those
// recreates the chart.

import Foundation
import SwiftUI
import Charts

/// One ScaleDomain type for automatic and explicit domains. `chartXScale(domain:)` is generic
/// over its domain type, so `.automatic`, `0...100` and `["A", "B"]` would each give the chain a
/// different type. ScaleDomain's single requirement is forwarded to Apple's own conforming types.
struct ForwardingDomain: ScaleDomain {
    enum Kind {
        case automatic(includesZero: Bool?, reversed: Bool?)
        case numbers(ClosedRange<Double>)
        case dates(ClosedRange<Date>)
        case strings([String])
    }
    let kind: Kind

    init(_ kind: Kind) {
        self.kind = kind
    }

    static let automatic = ForwardingDomain(.automatic(includesZero: nil, reversed: nil))

    func _makeScaleDomain() -> _ScaleDomainOutputs {
        switch kind {
        case .automatic(let includesZero, let reversed):
            return AutomaticScaleDomain.automatic(includesZero: includesZero, reversed: reversed)._makeScaleDomain()
        case .numbers(let range):
            return range._makeScaleDomain()
        case .dates(let range):
            return range._makeScaleDomain()
        case .strings(let values):
            return values._makeScaleDomain()
        }
    }
}

/// One PositionScaleRange type for plot-dimension padding and explicit point ranges, for the
/// same reason as ForwardingDomain. `.plotDimension` with no padding draws exactly like no range.
struct ForwardingPositionRange: PositionScaleRange {
    typealias VisualValue = CGFloat
    enum Kind {
        case defaultPlotDimension
        case plotDimension(startPadding: CGFloat, endPadding: CGFloat)
        case points(ClosedRange<CGFloat>)
    }
    let kind: Kind

    init(_ kind: Kind) {
        self.kind = kind
    }

    static let automatic = ForwardingPositionRange(.defaultPlotDimension)

    func _makeScaleRange() -> _ScaleRangeOutputs<CGFloat> {
        switch kind {
        case .defaultPlotDimension:
            return PlotDimensionScaleRange.plotDimension._makeScaleRange()
        case .plotDimension(let start, let end):
            return PlotDimensionScaleRange.plotDimension(startPadding: start, endPadding: end)._makeScaleRange()
        case .points(let range):
            return range._makeScaleRange()
        }
    }
}

/// One ScaleRange type for a list of colors and a gradient, for the same reason as
/// ForwardingDomain. Both of Apple's types map values to Color.
struct ForwardingColorRange: ScaleRange {
    typealias VisualValue = SwiftUI.Color
    enum Kind {
        case colors([SwiftUI.Color])
        case gradient(Gradient)
    }
    let kind: Kind

    init(_ kind: Kind) {
        self.kind = kind
    }

    func _makeScaleRange() -> _ScaleRangeOutputs<SwiftUI.Color> {
        switch kind {
        case .colors(let colors):
            return colors._makeScaleRange()
        case .gradient(let gradient):
            return gradient._makeScaleRange()
        }
    }
}

// The foreground style and symbol size scales have no neutral range: an empty color list draws
// differently from no scale, and an empty size list stops the app inside Swift Charts. Without a
// range they take the domain-only form, which draws exactly like no scale; the modifier's own
// type stays the same either way (adding or removing a range recreates the chart, as a branch).
struct ChartForegroundStyleScaler: ViewModifier {
    let domain: ForwardingDomain
    let range: ForwardingColorRange?

    func body(content: Content) -> some SwiftUI.View {
        if let range {
            content.chartForegroundStyleScale(domain: domain, range: range)
        } else {
            content.chartForegroundStyleScale(domain: domain)
        }
    }
}

// An axis label has no neutral form: an empty Text or EmptyView reserves space under the axis,
// and even a zero-size view with zero spacing moves a chart with a continuous size legend. Without
// a label the modifier is left out; its own type stays the same either way (adding or removing a
// label recreates the chart, as a branch).
struct ChartAxisLabeler: ViewModifier {
    let axis: Axis
    let spec: ChartAxisSpec

    func body(content: Content) -> some SwiftUI.View {
        if let label = spec.label {
            if axis == .horizontal {
                content.chartXAxisLabel(position: spec.labelPosition, alignment: spec.labelAlignment, spacing: spec.labelSpacing) {
                    SwiftUI.Text(label)
                }
            } else {
                content.chartYAxisLabel(position: spec.labelPosition, alignment: spec.labelAlignment, spacing: spec.labelSpacing) {
                    SwiftUI.Text(label)
                }
            }
        } else {
            content
        }
    }
}

struct ChartSymbolSizeScaler: ViewModifier {
    let domain: ForwardingDomain
    let range: ClosedRange<CGFloat>?

    func body(content: Content) -> some SwiftUI.View {
        if let range {
            content.chartSymbolSizeScale(domain: domain, range: range)
        } else {
            content.chartSymbolSizeScale(domain: domain)
        }
    }
}

extension SwiftUI.View {
    /// - Parameter plotStyle: applies the description's chartPlotStyle (baseline View
    ///   properties) to the plot area; nil when the description has none.
    @MainActor
    func chartModifiers(_ spec: ChartSpec, plotStyle: ((any SwiftUI.View) -> AnyView)?) -> some SwiftUI.View {
        self
            .chartXScale(domain: spec.x.domain, range: spec.x.range, type: spec.x.scaleType)
            .chartYScale(domain: spec.y.domain, range: spec.y.range, type: spec.y.scaleType)
            .modifier(ChartForegroundStyleScaler(domain: spec.styles.foregroundDomain, range: spec.styles.foregroundRange))
            // An empty symbol or line style list draws exactly like no scale.
            .chartSymbolScale(domain: spec.styles.symbolDomain, range: spec.styles.symbolRange)
            .chartLineStyleScale(domain: spec.styles.lineStyleDomain, range: spec.styles.lineStyleRange)
            .modifier(ChartSymbolSizeScaler(domain: spec.styles.symbolSizeDomain, range: spec.styles.symbolSizeRange))
            // Axis content is always given (a plain AxisMarks() draws like none), then visibility.
            .chartXAxis { ChartAxisContentBuilder.content(spec.x.marks) }
            .chartXAxis(spec.x.visibility)
            .chartYAxis { ChartAxisContentBuilder.content(spec.y.marks) }
            .chartYAxis(spec.y.visibility)
            .modifier(ChartAxisLabeler(axis: .horizontal, spec: spec.x))
            .modifier(ChartAxisLabeler(axis: .vertical, spec: spec.y))
            .chartLegend(position: spec.legendPosition, alignment: nil, spacing: nil)
            .chartLegend(spec.legendVisibility)
            .chartPlotStyle { plot in plot.modifier(ChartPlotStyler(style: plotStyle)) }
    }
}

// Applies a plot style, or passes the plot through untouched. The modifier's own type never
// changes, so the chart keeps its type whether or not a description has a plot style; wrapping
// an unstyled plot in AnyView instead moves a few pixels of antialiasing.
struct ChartPlotStyler: ViewModifier {
    let style: ((any SwiftUI.View) -> AnyView)?

    func body(content: Content) -> some SwiftUI.View {
        if let style {
            style(content)
        } else {
            content
        }
    }
}
