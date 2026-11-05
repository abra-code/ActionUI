// Sources/Drawing/ChartSelectionHit.swift
/*
 A place in a laid-out chart read as a selection, as Swift Charts' selection gestures read one
 (ChartGeometry gives the plot and its scales; no GTK here).

 - A value on an axis is what the place stands for on its scale: the band under it on a category
   axis, the number or instant on a number or date axis (an integer axis gives the nearest whole
   number). Only places in the plot select.
 - A range is the values at the two ends of a drag, in order, each end held to the plot.
 - An angle is the place's direction from the plot's center, clockwise from the top, as a share of
   the sum of the sectors' positive values, as Swift Charts reads chartAngleSelection; its row is
   the first sector, in order, whose running sum reaches it (Apple's sectorRow).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Glibc

enum ChartSelectionHit {
    static func contains(_ plot: ChartRect, _ point: ChartPoint) -> Bool {
        point.x >= plot.x && point.x <= plot.x + plot.width && point.y >= plot.y && point.y <= plot.y + plot.height
    }

    /// The value at `point` on the x axis (`horizontal`) or the y axis, of the axis's `type`; nil
    /// outside the plot.
    static func value(at point: ChartPoint, _ axis: ChartAxis, type: ChartColumnType?, geometry: ChartGeometry) -> ChartScalar? {
        guard let type, contains(geometry.plot, point) else { return nil }
        return axis == .horizontal ? geometry.x.value(at: point.x, type: type) : geometry.y.value(at: point.y, type: type)
    }

    /// The range a drag from `start` to `end` covers on an axis, its ends held to the plot, in
    /// order; nil where the axis has no values.
    static func range(from start: ChartPoint, to end: ChartPoint, _ axis: ChartAxis, type: ChartColumnType?,
                      geometry: ChartGeometry) -> ChartSelectionPart? {
        guard let type else { return nil }
        let plot = geometry.plot
        func held(_ point: ChartPoint) -> ChartPoint {
            ChartPoint(x: min(max(point.x, plot.x), plot.x + plot.width), y: min(max(point.y, plot.y), plot.y + plot.height))
        }
        guard let first = value(at: held(start), axis, type: type, geometry: geometry),
              let second = value(at: held(end), axis, type: type, geometry: geometry) else { return nil }
        return ordered(first, second) ? .range(first, second) : .range(second, first)
    }

    /// Whether `a` comes before `b` (or is `b`); values of two types never come in order.
    static func ordered(_ a: ChartScalar, _ b: ChartScalar) -> Bool {
        switch (a, b) {
        case (.string(let x), .string(let y)): return x <= y
        case (.number(let x), .number(let y)): return x <= y
        case (.integer(let x), .integer(let y)): return x <= y
        case (.date(let x), .date(let y)): return x <= y
        default: return true
        }
    }

    /// The angle at `point` in the sectors' values, and the row of the sector there; nil outside
    /// the plot or without sectors that add up to more than 0. An integer `type` gives the nearest
    /// whole number.
    static func angle(at point: ChartPoint, marks: ChartResolvedMarks, type: ChartColumnType?,
                      geometry: ChartGeometry) -> (angle: Double, row: Int?)? {
        guard contains(geometry.plot, point) else { return nil }
        var sectors: [(value: Double, row: Int?)] = []
        for instance in marks.instances where instance.mark.kind == .SectorMark && !instance.readsSelection {
            let value: Double?
            switch instance.values["angle"] {
            case .number(let number)?: value = number
            case .integer(let number)?: value = Double(number)
            default: value = nil
            }
            if let value, value.isFinite, value > 0 {
                sectors.append((value, instance.row))
            }
        }
        let total = sectors.reduce(0) { $0 + $1.value }
        guard total > 0, total.isFinite else { return nil }
        let plot = geometry.plot
        let dx = point.x - (plot.x + plot.width / 2), dy = point.y - (plot.y + plot.height / 2)
        guard dx != 0 || dy != 0 else { return nil }
        var direction = atan2(dx, -dy)
        if direction < 0 { direction += 2 * .pi }
        var angle = direction / (2 * .pi) * total
        if type == .integer { angle = angle.rounded() }
        var end = 0.0
        for sector in sectors {
            end += sector.value
            if angle <= end { return (angle, sector.row) }
        }
        return (angle, sectors.last?.row)
    }
}
