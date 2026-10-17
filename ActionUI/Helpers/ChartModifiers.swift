// Helpers/ChartModifiers.swift
//
// The Chart element's view modifiers, applied as one chain whose type never changes. Every
// modifier is always applied, with a neutral value where the description is silent, so a
// replaced description changes values, not the view's type: SwiftUI keeps the same chart and can
// animate between the two. Each neutral value draws pixel-identically to leaving the modifier out.

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

extension SwiftUI.View {
    /// - Parameter plotStyle: applies the description's chartPlotStyle (baseline View
    ///   properties) to the plot area; nil when the description has none.
    @MainActor
    func chartModifiers(_ spec: ChartSpec, plotStyle: ((any SwiftUI.View) -> AnyView)?) -> some SwiftUI.View {
        self
            .chartXScale(domain: spec.x.domain, range: spec.x.range, type: spec.x.scaleType)
            .chartYScale(domain: spec.y.domain, range: spec.y.range, type: spec.y.scaleType)
            .chartXAxis(spec.x.visibility)
            .chartYAxis(spec.y.visibility)
            // An absent label is a zero-size view with zero spacing: an empty Text, or
            // EmptyView, still reserves space under the axis.
            .chartXAxisLabel(position: spec.x.labelPosition, alignment: spec.x.labelAlignment,
                             spacing: spec.x.label == nil ? 0 : spec.x.labelSpacing) {
                if let label = spec.x.label { SwiftUI.Text(label) } else { SwiftUI.Color.clear.frame(width: 0, height: 0) }
            }
            .chartYAxisLabel(position: spec.y.labelPosition, alignment: spec.y.labelAlignment,
                             spacing: spec.y.label == nil ? 0 : spec.y.labelSpacing) {
                if let label = spec.y.label { SwiftUI.Text(label) } else { SwiftUI.Color.clear.frame(width: 0, height: 0) }
            }
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
