// Helpers/ChartSelection+SwiftUI.swift
//
// The Swift Charts side of chart selection (Core/Helpers/Chart/ChartSelection.swift): the bindings
// and the view modifiers that install them. A chart that declares no selection gets no selection
// modifier at all, so its gestures and drawing are those of a plain chart.

import Foundation
import SwiftUI
import Charts

/// The types a selection binding can carry, converted to and from ChartScalar.
protocol ChartSelectable: Plottable {
    init?(chartScalar: ChartScalar)
    var chartScalar: ChartScalar { get }
}

extension String: ChartSelectable {
    init?(chartScalar: ChartScalar) {
        guard case .string(let text) = chartScalar else { return nil }
        self = text
    }
    var chartScalar: ChartScalar { .string(self) }
}

extension Double: ChartSelectable {
    init?(chartScalar: ChartScalar) {
        guard case .number(let number) = chartScalar else { return nil }
        self = number
    }
    var chartScalar: ChartScalar { .number(self) }
}

extension Int: ChartSelectable {
    init?(chartScalar: ChartScalar) {
        guard case .integer(let integer) = chartScalar else { return nil }
        self = integer
    }
    var chartScalar: ChartScalar { .integer(self) }
}

extension Date: ChartSelectable {
    init?(chartScalar: ChartScalar) {
        guard case .date(let date) = chartScalar else { return nil }
        self = date
    }
    var chartScalar: ChartScalar { .date(self) }
}

/// Reads and writes the selection held in the element's value. A write lands on the next
/// main-queue turn, outside the view update that reported it, then fires the action per
/// `selectionActionTiming`.
@MainActor
struct ChartSelectionBinder {
    let model: ViewModel
    let spec: ChartSelectionSpec
    let cache: ChartRenderCache
    let windowUUID: String
    let viewID: Int
    let actionID: String?
    let continuous: Bool

    /// The rest after the last change before a "settled" action fires.
    static let settleDelay: TimeInterval = 0.15

    var current: ChartSelection {
        ChartSelection.decode(model.value as? String, spec: spec)
    }

    func value<P: ChartSelectable>(_ axis: ChartAxis, as type: P.Type) -> Binding<P?> {
        mainActorBinding(
            get: {
                guard case .value(let scalar)? = axis == .horizontal ? current.x : current.y else { return nil }
                return P(chartScalar: scalar)
            },
            set: { newValue in
                let part = newValue.map { ChartSelectionPart.value($0.chartScalar) }
                write { axis == .horizontal ? ($0.x = part) : ($0.y = part) }
            })
    }

    func range<P: ChartSelectable & Comparable>(_ axis: ChartAxis, as type: P.Type) -> Binding<ClosedRange<P>?> {
        mainActorBinding(
            get: {
                guard case .range(let start, let end)? = axis == .horizontal ? current.x : current.y,
                      let lower = P(chartScalar: start), let upper = P(chartScalar: end), lower <= upper else { return nil }
                return lower...upper
            },
            set: { newValue in
                let part = newValue.map { ChartSelectionPart.range($0.lowerBound.chartScalar, $0.upperBound.chartScalar) }
                write { axis == .horizontal ? ($0.x = part) : ($0.y = part) }
            })
    }

    func angle<P: ChartSelectable>(as type: P.Type) -> Binding<P?> {
        mainActorBinding(
            get: {
                guard let angle = current.angle else { return nil }
                guard type == Int.self else { return P(chartScalar: .number(angle)) }
                // A host may set any finite angle; one past Int's range reads as nothing.
                return Int(exactly: angle.rounded()).flatMap { P(chartScalar: .integer($0)) }
            },
            set: { newValue in
                let angle: Double?
                switch newValue?.chartScalar {
                case .number(let number)?: angle = number
                case .integer(let integer)?: angle = Double(integer)
                default: angle = nil
                }
                let row = angle.flatMap { cache.sectorRow(at: $0) }
                write {
                    $0.angle = angle
                    $0.row = row
                }
            })
    }

    /// Applies `change` to the selection as it is when the write lands, so writes from several
    /// bindings in one gesture (x and y) do not undo each other.
    func write(_ change: @escaping @MainActor (inout ChartSelection) -> Void) {
        DispatchQueue.main.async {
            let before = model.value as? String ?? ""
            var selection = ChartSelection.decode(before, spec: spec)
            change(&selection)
            let after = selection.encode(spec: spec)
            guard after != before else { return }
            model.value = after
            if let actionID {
                cache.scheduleSelectionAction(cleared: after.isEmpty, continuous: continuous, delay: Self.settleDelay) {
                    ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: viewID, viewPartID: 0)
                }
            }
        }
    }
}

// One modifier per selection kind. Each keeps its own type whatever the description says;
// declaring or removing a selection, or changing its axis type, recreates the chart.
struct ChartXYSelector: ViewModifier {
    let axis: ChartAxis
    let mode: ChartSelectionMode?
    let type: ChartColumnType?
    let binder: ChartSelectionBinder

    func body(content: Content) -> some SwiftUI.View {
        switch (mode, type) {
        case (.value?, .string?): select(content, value: binder.value(axis, as: String.self))
        case (.value?, .number?): select(content, value: binder.value(axis, as: Double.self))
        case (.value?, .integer?): select(content, value: binder.value(axis, as: Int.self))
        case (.value?, .date?): select(content, value: binder.value(axis, as: Date.self))
        case (.range?, .string?): select(content, range: binder.range(axis, as: String.self))
        case (.range?, .number?): select(content, range: binder.range(axis, as: Double.self))
        case (.range?, .integer?): select(content, range: binder.range(axis, as: Int.self))
        case (.range?, .date?): select(content, range: binder.range(axis, as: Date.self))
        default: content
        }
    }

    @ViewBuilder
    private func select<P: Plottable>(_ content: Content, value: Binding<P?>) -> some SwiftUI.View {
        if axis == .horizontal {
            content.chartXSelection(value: value)
        } else {
            content.chartYSelection(value: value)
        }
    }

    @ViewBuilder
    private func select<P: Plottable & Comparable>(_ content: Content, range: Binding<ClosedRange<P>?>) -> some SwiftUI.View {
        if axis == .horizontal {
            content.chartXSelection(range: range)
        } else {
            content.chartYSelection(range: range)
        }
    }
}

struct ChartAngleSelector: ViewModifier {
    let enabled: Bool
    let type: ChartColumnType?
    let binder: ChartSelectionBinder

    func body(content: Content) -> some SwiftUI.View {
        switch (enabled, type) {
        case (true, .integer?): content.chartAngleSelection(value: binder.angle(as: Int.self))
        case (true, .number?): content.chartAngleSelection(value: binder.angle(as: Double.self))
        default: content
        }
    }
}

/// The description's selections; a chart that declares none gets none. A ViewModifier rather
/// than a View extension method: chaining a main-actor method on the opaque result of
/// chartModifiers warns about an isolated conformance in Swift 6.
struct ChartSelector: ViewModifier {
    let binder: ChartSelectionBinder

    func body(content: Content) -> some SwiftUI.View {
        let spec = binder.spec
        content
            .modifier(ChartXYSelector(axis: .horizontal, mode: spec.x, type: spec.xType, binder: binder))
            .modifier(ChartXYSelector(axis: .vertical, mode: spec.y, type: spec.yType, binder: binder))
            .modifier(ChartAngleSelector(enabled: spec.angle, type: spec.angleType, binder: binder))
    }
}
