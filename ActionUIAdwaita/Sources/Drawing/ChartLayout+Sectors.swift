// Sources/Drawing/ChartLayout+Sectors.swift
/*
 Where SectorMarks go: their angles and radii. Their outline is ChartSectors'.

 Sectors share one circle in the middle of the plot, as wide as its short side, each the share of
 the sum its size makes, in order from the top, negatives first with the last of them leading.
 Outer radii count from that circle and stop at it, and inner ones count from the outer. A chart
 with sectors has no axes, even when asked, and a zero draws nothing but keeps its color and its
 legend entry.
*/

extension ChartLayout {
    // Each sector's start and end, clockwise from the top. Values stack as bars do, out from 0 on
    // each side, and the whole span runs from the top, so negatives come first, the last of them
    // first (measured on macOS 27). Each is first measured against the largest, so a sum of large
    // values stays finite.
    func sectorAngles() -> [Int: (start: Double, end: Double)] {
        var values: [(index: Int, value: Double)] = []
        for (index, instance) in marks.instances.enumerated() where instance.mark.kind == .SectorMark {
            if let value = number(instance.values["angle"]), value.isFinite, value != 0 {
                values.append((index, value))
            }
        }
        guard let largest = values.map({ abs($0.value) }).max() else { return [:] }
        let negative = values.reduce(0) { $0 + ($1.value < 0 ? -$1.value / largest : 0) }
        let sum = values.reduce(0) { $0 + abs($1.value) / largest }
        var angles: [Int: (start: Double, end: Double)] = [:]
        var above = negative, below = negative
        for (index, value) in values {
            let share = abs(value) / largest
            if value > 0 {
                angles[index] = (above / sum * 2 * .pi, min((above + share) / sum, 1) * 2 * .pi)
                above += share
            } else {
                angles[index] = (max(below - share, 0) / sum * 2 * .pi, below / sum * 2 * .pi)
                below -= share
            }
        }
        return angles
    }

    func sector(_ instance: ChartMarkInstance, _ angle: (start: Double, end: Double), _ plot: ChartRect) -> ChartSector {
        func radius(_ dimension: ChartDimension, of whole: Double, automatic: Double) -> Double {
            switch dimension {
            case .automatic: return automatic
            case .fixed(let points): return points
            case .ratio(let ratio): return whole * ratio
            case .inset(let points): return whole - points
            }
        }
        let mark = instance.mark
        let whole = min(plot.width, plot.height) / 2
        let outer = max(min(radius(mark.outerRadius, of: whole, automatic: whole), whole), 0)
        let inner = min(max(radius(mark.innerRadius, of: outer, automatic: 0), 0), outer)
        var corner = 0.0
        for modifier in mark.modifiers.reversed() {
            if case .cornerRadius(let given, _) = modifier {
                corner = given
            }
        }
        return ChartSector(center: ChartPoint(x: plot.x + plot.width / 2, y: plot.y + plot.height / 2), inner: inner, outer: outer,
                           start: angle.start, end: angle.end, inset: mark.points["angularInset"] ?? 0, corner: corner)
    }
}
