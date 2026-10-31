// Sources/Drawing/ChartSymbols.swift
/*
 The outlines of Swift Charts' symbols, without GTK. Each sits in a box of one side, which a circle
 fills exactly; the others reach past it or stop short of it by their own amounts, and their corners
 are rounded (measured on macOS 27, at an area of 900). Each is centered by what it covers.
*/

import Glibc

enum ChartSymbols {
    private static let cornerRadius = 0.09
    /// From a corner of a circle's quarter to its curve's control points, for a radius of 1.
    private static let circleControl = 0.5523
    private static let squareHalf = 0.455
    private static let triangle = [ChartPoint(x: 0, y: -0.551), ChartPoint(x: 0.61, y: 0.485), ChartPoint(x: -0.61, y: 0.485)]
    private static let diamondHalf = 0.577
    private static let pentagon: [ChartPoint] = (0..<5).map { index in
        let angle = -Double.pi / 2 + Double(index) * 2 * .pi / 5
        return ChartPoint(x: 0.584 * cos(angle), y: 0.584 * sin(angle) + 0.046)
    }

    /// Whether it has an inside: on a line it is then an outline, and the line stops at it. Plus,
    /// cross and asterisk stay solid there.
    static func isHollowOnALine(_ shape: ChartSymbol) -> Bool {
        switch shape {
        case .circle, .square, .triangle, .diamond, .pentagon: return true
        case .plus, .cross, .asterisk: return false
        }
    }

    static func outline(_ shape: ChartSymbol, center: ChartPoint, side: Double) -> [ChartPathElement] {
        switch shape {
        case .circle:
            return circle(center, radius: side / 2)
        case .square:
            let half = squareHalf
            return rounded([(-half, -half), (half, -half), (half, half), (-half, half)].map { ChartPoint(x: $0.0, y: $0.1) }, center, side)
        case .triangle:
            return rounded(triangle, center, side)
        case .diamond:
            let half = diamondHalf
            return rounded([(0, -half), (half, 0), (0, half), (-half, 0)].map { ChartPoint(x: $0.0, y: $0.1) }, center, side)
        case .pentagon:
            return rounded(pentagon, center, side)
        case .plus:
            return bars(length: 1.14, thickness: 0.37, degrees: [0, 90], center, side)
        case .cross:
            return bars(length: 1.08, thickness: 0.37, degrees: [45, 135], center, side)
        case .asterisk:
            return bars(length: 1.15, thickness: 0.295, degrees: [0, 60, 120], center, side)
        }
    }

    private static func circle(_ center: ChartPoint, radius: Double) -> [ChartPathElement] {
        let control = radius * circleControl
        func point(_ x: Double, _ y: Double) -> ChartPoint { ChartPoint(x: center.x + x, y: center.y + y) }
        return [
            .move(point(radius, 0)),
            .curve(point(radius, control), point(control, radius), point(0, radius)),
            .curve(point(-control, radius), point(-radius, control), point(-radius, 0)),
            .curve(point(-radius, -control), point(-control, -radius), point(0, -radius)),
            .curve(point(control, -radius), point(radius, -control), point(radius, 0)),
            .close
        ]
    }

    // Upright bars turned around the middle. They overlap, and a winding fill draws them as one.
    private static func bars(length: Double, thickness: Double, degrees: [Double], _ center: ChartPoint, _ side: Double) -> [ChartPathElement] {
        let halfLength = length / 2, halfThickness = thickness / 2
        return degrees.flatMap { angle -> [ChartPathElement] in
            let radians = angle * .pi / 180, sine = sin(radians), cosine = cos(radians)
            let corners = [(-halfThickness, -halfLength), (halfThickness, -halfLength), (halfThickness, halfLength), (-halfThickness, halfLength)]
            return rounded(corners.map { ChartPoint(x: $0.0 * cosine - $0.1 * sine, y: $0.0 * sine + $0.1 * cosine) }, center, side)
        }
    }

    // A closed shape of `corners`, in a box of 1 around 0, each corner rounded to the same radius.
    private static func rounded(_ corners: [ChartPoint], _ center: ChartPoint, _ side: Double) -> [ChartPathElement] {
        func placed(_ point: ChartPoint) -> ChartPoint {
            ChartPoint(x: center.x + point.x * side, y: center.y + point.y * side)
        }
        func toward(_ from: ChartPoint, _ to: ChartPoint, by share: Double) -> ChartPoint {
            ChartPoint(x: from.x + (to.x - from.x) * share, y: from.y + (to.y - from.y) * share)
        }
        var elements: [ChartPathElement] = []
        for (index, corner) in corners.enumerated() {
            let before = corners[(index + corners.count - 1) % corners.count], after = corners[(index + 1) % corners.count]
            let backward = ChartPoint(x: before.x - corner.x, y: before.y - corner.y), forward = ChartPoint(x: after.x - corner.x, y: after.y - corner.y)
            let toBefore = hypot(backward.x, backward.y), toAfter = hypot(forward.x, forward.y)
            let cosine = (backward.x * forward.x + backward.y * forward.y) / (toBefore * toAfter)
            // Where a circle of the radius touches the two sides.
            let reach = min(cornerRadius / ((1 - cosine) / (1 + cosine)).squareRoot(), min(toBefore, toAfter) / 2)
            let start = toward(corner, before, by: reach / toBefore), end = toward(corner, after, by: reach / toAfter)
            elements.append(index == 0 ? .move(placed(start)) : .line(placed(start)))
            elements.append(.curve(placed(toward(start, corner, by: 2.0 / 3)), placed(toward(end, corner, by: 2.0 / 3)), placed(end)))
        }
        elements.append(.close)
        return elements
    }
}
