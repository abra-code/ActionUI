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

extension SwiftUI.View {
    @MainActor
    func chartModifiers(_ spec: ChartSpec) -> some SwiftUI.View {
        self
            .chartXScale(domain: spec.x.domain)
            .chartYScale(domain: spec.y.domain)
            .chartXAxis(spec.x.visibility)
            .chartYAxis(spec.y.visibility)
            // An absent label is a zero-size view with zero spacing: an empty Text, or
            // EmptyView, still reserves space under the axis.
            .chartXAxisLabel(position: .automatic, alignment: nil, spacing: spec.x.label == nil ? 0 : nil) {
                if let label = spec.x.label { SwiftUI.Text(label) } else { SwiftUI.Color.clear.frame(width: 0, height: 0) }
            }
            .chartYAxisLabel(position: .automatic, alignment: nil, spacing: spec.y.label == nil ? 0 : nil) {
                if let label = spec.y.label { SwiftUI.Text(label) } else { SwiftUI.Color.clear.frame(width: 0, height: 0) }
            }
            .chartLegend(position: spec.legendPosition, alignment: nil, spacing: nil)
            .chartLegend(spec.legendVisibility)
    }
}
