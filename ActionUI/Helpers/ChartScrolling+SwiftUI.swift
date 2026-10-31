// Helpers/ChartScrolling+SwiftUI.swift
//
// The Swift Charts view modifiers for chart scrolling (ChartScrollSpec,
// Core/Helpers/Chart/ChartScrolling.swift). None of them has a neutral form (an empty set of
// scrollable axes already moves pixels), so a chart that declares no scrolling gets none.

import Foundation
import SwiftUI
import Charts

// One modifier for all of it, of one type whatever the description says; declaring or
// removing scrolling recreates the chart.
struct ChartScroller: ViewModifier {
    let spec: ChartScrollSpec

    func body(content: Content) -> some SwiftUI.View {
        if spec.isEmpty {
            content
        } else {
            content
                .chartScrollableAxes(spec.axes.axisSet)
                .modifier(ChartVisibleDomainSetter(axis: .horizontal, length: spec.xLength))
                .modifier(ChartVisibleDomainSetter(axis: .vertical, length: spec.yLength))
                .modifier(ChartScrollPositioner(axis: .horizontal, initial: spec.initialX))
                .modifier(ChartScrollPositioner(axis: .vertical, initial: spec.initialY))
        }
    }
}

struct ChartVisibleDomainSetter: ViewModifier {
    let axis: ChartAxis
    let length: ChartVisibleLength?

    func body(content: Content) -> some SwiftUI.View {
        switch (axis, length) {
        case (.horizontal, .amount(let value)?): content.chartXVisibleDomain(length: value)
        case (.horizontal, .categories(let count)?): content.chartXVisibleDomain(length: count)
        case (.vertical, .amount(let value)?): content.chartYVisibleDomain(length: value)
        case (.vertical, .categories(let count)?): content.chartYVisibleDomain(length: count)
        default: content
        }
    }
}

struct ChartScrollPositioner: ViewModifier {
    let axis: ChartAxis
    let initial: ChartScalar?

    func body(content: Content) -> some SwiftUI.View {
        switch initial {
        case .string(let value)?: position(content, value)
        case .number(let value)?: position(content, value)
        case .integer(let value)?: position(content, value)
        case .date(let value)?: position(content, value)
        case nil: content
        }
    }

    @ViewBuilder
    private func position<P: Plottable>(_ content: Content, _ value: P) -> some SwiftUI.View {
        if axis == .horizontal {
            content.chartScrollPosition(initialX: value)
        } else {
            content.chartScrollPosition(initialY: value)
        }
    }
}
