// Helpers/ChartSelection.swift
//
// Chart selection: what a description declares (chartXSelection, chartYSelection,
// chartAngleSelection), the selection as the element's value (a JSON string), and the view
// modifiers that install Swift Charts' selection bindings. A chart that declares no selection
// gets no selection modifier at all, so its gestures and drawing are those of a plain chart.

import Foundation
import SwiftUI
import Charts

enum ChartSelectionMode: String {
    case value, range
}

/// What a description declares, with the type of each selected axis.
struct ChartSelectionSpec: Equatable {
    /// The plotted value that reads the selection, outside a ForEach.
    static let reference = "$selection"

    var x: ChartSelectionMode?
    var y: ChartSelectionMode?
    var angle = false
    var xType: ChartColumnType?
    var yType: ChartColumnType?
    var angleType: ChartColumnType?
    // A date axis whose first mark has a unit of a day or coarser prints its selection as a
    // calendar day; any other date axis prints a local date and time, as DatePicker does.
    var xDateOnly = false
    var yDateOnly = false

    var isEmpty: Bool { x == nil && y == nil && !angle }
}

/// One axis's selection: a value, or a range for "range" mode.
enum ChartSelectionPart: Equatable {
    case value(ChartScalar)
    case range(ChartScalar, ChartScalar)
}

/// The selection a chart holds, decoded from and encoded to the element's JSON value.
struct ChartSelection: Equatable {
    var x: ChartSelectionPart?
    var y: ChartSelectionPart?
    var angle: Double?
    // The 0-based row of the selected sector; resolved when the user selects, kept as given when
    // a host sets the value.
    var row: Int?

    var isEmpty: Bool { x == nil && y == nil && angle == nil }

    /// Decodes `value` for `spec`. A part that does not fit the spec (no such selection
    /// declared, or a value of another type) is left out, so it reads as nothing selected.
    static func decode(_ value: String?, spec: ChartSelectionSpec) -> ChartSelection {
        var selection = ChartSelection()
        guard let value, !value.isEmpty, !spec.isEmpty,
              let data = value.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return selection
        }
        selection.x = part(object["x"], mode: spec.x, type: spec.xType)
        selection.y = part(object["y"], mode: spec.y, type: spec.yType)
        if spec.angle, let number = plainNumber(object["angle"]), number.isFinite {
            selection.angle = number
            if let row = plainNumber(object["row"]), let whole = Int(exactly: row), whole >= 0 {
                selection.row = whole
            }
        }
        return selection
    }

    /// The JSON value, keys sorted; "" when nothing is selected.
    func encode(spec: ChartSelectionSpec) -> String {
        var object: [String: Any] = [:]
        if let x, let json = Self.json(x, dateOnly: spec.xDateOnly) { object["x"] = json }
        if let y, let json = Self.json(y, dateOnly: spec.yDateOnly) { object["y"] = json }
        if let angle {
            object["angle"] = angle
            if let row { object["row"] = row }
        }
        guard !object.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    private static func part(_ raw: Any?, mode: ChartSelectionMode?, type: ChartColumnType?) -> ChartSelectionPart? {
        guard let raw, let mode, let type else { return nil }
        switch mode {
        case .value:
            return scalar(raw, type: type).map { .value($0) }
        case .range:
            guard let pair = raw as? [Any], pair.count == 2,
                  let start = scalar(pair[0], type: type), let end = scalar(pair[1], type: type),
                  ordered(start, end) else { return nil }
            return .range(start, end)
        }
    }

    private static func scalar(_ raw: Any, type: ChartColumnType) -> ChartScalar? {
        switch type {
        case .string:
            return (raw as? String).map { .string($0) }
        case .number:
            return plainNumber(raw).flatMap { $0.isFinite ? .number($0) : nil }
        case .integer:
            return plainNumber(raw).flatMap { Int(exactly: $0) }.map { .integer($0) }
        case .date:
            return (raw as? String).flatMap(DateHelper.parseDate(from:)).map { .date($0) }
        }
    }

    // A JSON number, not a boolean (JSONSerialization gives both as NSNumber).
    private static func plainNumber(_ raw: Any?) -> Double? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    private static func ordered(_ start: ChartScalar, _ end: ChartScalar) -> Bool {
        switch (start, end) {
        case (.string(let a), .string(let b)): return a <= b
        case (.number(let a), .number(let b)): return a <= b
        case (.integer(let a), .integer(let b)): return a <= b
        case (.date(let a), .date(let b)): return a <= b
        default: return false
        }
    }

    private static func json(_ part: ChartSelectionPart, dateOnly: Bool) -> Any? {
        switch part {
        case .value(let scalar):
            return json(scalar, dateOnly: dateOnly)
        case .range(let start, let end):
            guard let a = json(start, dateOnly: dateOnly), let b = json(end, dateOnly: dateOnly) else { return nil }
            return [a, b]
        }
    }

    private static func json(_ scalar: ChartScalar, dateOnly: Bool) -> Any? {
        switch scalar {
        case .string(let text): return text
        case .number(let number): return number.isFinite ? number : nil
        case .integer(let integer): return integer
        case .date(let date): return dateOnly ? DateHelper.formatDate(from: date) : DateHelper.formatDateTime(from: date)
        }
    }
}

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

    func value<P: ChartSelectable>(_ axis: Axis, as type: P.Type) -> Binding<P?> {
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

    func range<P: ChartSelectable & Comparable>(_ axis: Axis, as type: P.Type) -> Binding<ClosedRange<P>?> {
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
    let axis: Axis
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
