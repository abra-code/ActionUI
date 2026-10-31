// Sources/Drawing/ChartSectors.swift
/*
 The outline of a SectorMark, without GTK, as Swift Charts draws one (measured on macOS 27). Angles
 run clockwise from the top, in radians.

 An inset moves a sector's straight edges in, parallel to themselves, so the gap between two sectors
 has parallel sides, and the outer radius stays. It stops at 5% of that radius. Where the edges meet
 before they reach the inner radius the sector ends in a point, on its middle line. Past half a turn
 they cannot meet: they go round the center at the inset's distance, as a hole would. A corner radius
 rounds the corners at the arcs, and stops at 10% of the outer radius, or where a sector is too thin
 or too shallow for it. At the inner arc it stops sooner: short of half a turn at what an outer arc
 of that radius would allow, and from there on at the inner radius less the inset. A point stays
 sharp. A sector of the whole circle has neither.
*/

import Glibc

struct ChartSector: Equatable {
    var center: ChartPoint
    var inner: Double
    var outer: Double
    var start: Double
    var end: Double
    var inset = 0.0
    var corner = 0.0
}

enum ChartSectors {
    private static let largestInset = 0.05
    private static let largestCorner = 0.1
    /// Past this a sector is the whole circle.
    private static let wholeCircle = 2 * Double.pi - 1e-9
    private static let quarter = Double.pi / 2
    /// The longest arc one curve follows, closely enough not to show.
    private static let longestPiece = Double.pi / 4

    /// Empty for a sector too thin to show under its inset.
    static func outline(_ sector: ChartSector) -> [ChartPathElement] {
        guard sector.outer > 0, sector.end > sector.start else { return [] }
        if sector.end - sector.start >= wholeCircle { return ring(sector) }
        return Outline(sector).elements
    }

    private static func ring(_ sector: ChartSector) -> [ChartPathElement] {
        var path = Arcs(center: sector.center)
        path.arc(radius: sector.outer, from: 0, to: 2 * .pi)
        path.close()
        if sector.inner > 0 {
            path.arc(radius: sector.inner, from: 2 * .pi, to: 0, moving: true)
            path.close()
        }
        return path.elements
    }

    /// Arcs and lines around a center.
    private struct Arcs {
        var center: ChartPoint
        var elements: [ChartPathElement] = []

        func point(_ angle: Double, _ radius: Double, around middle: ChartPoint? = nil) -> ChartPoint {
            let origin = middle ?? center
            return ChartPoint(x: origin.x + radius * sin(angle), y: origin.y - radius * cos(angle))
        }

        mutating func close() {
            elements.append(.close)
        }

        mutating func to(_ point: ChartPoint) {
            elements.append(elements.isEmpty ? .move(point) : .line(point))
        }

        // `moving` starts a new closed piece, for a ring's hole.
        mutating func arc(radius: Double, from: Double, to end: Double, around middle: ChartPoint? = nil, moving: Bool = false) {
            let origin = middle ?? center
            let first = point(from, radius, around: origin)
            elements.append(moving || elements.isEmpty ? .move(first) : .line(first))
            let pieces = max(Int((abs(end - from) / longestPiece).rounded(.up)), 1)
            let step = (end - from) / Double(pieces)
            let control = radius * 4 / 3 * tan(step / 4)
            for piece in 0..<pieces {
                let a = from + Double(piece) * step, b = a + step
                let p0 = point(a, radius, around: origin), p3 = point(b, radius, around: origin)
                elements.append(.curve(ChartPoint(x: p0.x + control * cos(a), y: p0.y + control * sin(a)),
                                       ChartPoint(x: p3.x - control * cos(b), y: p3.y - control * sin(b)), p3))
            }
        }
    }

    private struct Outline {
        let sector: ChartSector
        let inset: Double
        let half: Double
        let middle: Double
        var path: Arcs

        init(_ sector: ChartSector) {
            self.sector = sector
            inset = min(max(sector.inset, 0), sector.outer * largestInset)
            half = (sector.end - sector.start) / 2
            middle = sector.start + half
            path = Arcs(center: sector.center)
        }

        // A point `along` a straight edge from the center, and `inset` in from it. Which edge is
        // the sign of `side`: 1 at the start, -1 at the end.
        private func onEdge(_ angle: Double, along: Double, side: Double) -> ChartPoint {
            let base = path.point(angle, along)
            let inward = path.point(angle + side * quarter, inset, around: ChartPoint(x: 0, y: 0))
            return ChartPoint(x: base.x + inward.x, y: base.y + inward.y)
        }

        private func angle(of point: ChartPoint, around middle: ChartPoint) -> Double {
            atan2(point.x - middle.x, middle.y - point.y)
        }

        // A corner of a sector turns clockwise, whichever arc it sits on.
        private mutating func corner(from: ChartPoint, to: ChartPoint, around middle: ChartPoint, radius: Double) {
            let start = angle(of: from, around: middle)
            var end = angle(of: to, around: middle)
            while end < start { end += 2 * .pi }
            path.arc(radius: radius, from: start, to: end, around: middle)
        }

        var elements: [ChartPathElement] {
            var outline = self
            return outline.build()
        }

        private mutating func build() -> [ChartPathElement] {
            let outer = sector.outer, inner = max(sector.inner, half < quarter ? 0 : inset), spine = sin(min(half, quarter))
            // Too thin: its edges have crossed before the outer arc.
            guard half >= quarter || outer * spine > inset else { return [] }
            let roundable = min(max(sector.corner, 0), outer * largestCorner, (outer - inner) / 2)
            // Past half a turn every corner has room: spine is 1, and these only bound the arcs.
            let outerCorner = max(min(roundable, (outer * spine - inset) / (1 + spine)), 0)
            let outerAngle = asin(min((inset + outerCorner) / (outer - outerCorner), 1))
            let hasInner = inner > 0 && inner * spine >= inset
            let innerCorner = hasInner ? max(min(roundable, half < quarter ? (inner * spine - inset) / (1 + spine) : inner - inset), 0) : 0
            let innerAngle = hasInner ? asin(min((inset + innerCorner) / (inner + innerCorner), 1)) : 0

            if outerCorner > 0 {
                let center = path.point(sector.start + outerAngle, outer - outerCorner)
                let edge = onEdge(sector.start, along: (outer - outerCorner) * cos(outerAngle), side: 1)
                corner(from: edge, to: path.point(sector.start + outerAngle, outer), around: center, radius: outerCorner)
            }
            path.arc(radius: outer, from: sector.start + outerAngle, to: sector.end - outerAngle)
            if outerCorner > 0 {
                let center = path.point(sector.end - outerAngle, outer - outerCorner)
                let edge = onEdge(sector.end, along: (outer - outerCorner) * cos(outerAngle), side: -1)
                corner(from: path.point(sector.end - outerAngle, outer), to: edge, around: center, radius: outerCorner)
            }
            if hasInner {
                if innerCorner > 0 {
                    let center = path.point(sector.end - innerAngle, inner + innerCorner)
                    let edge = onEdge(sector.end, along: (inner + innerCorner) * cos(innerAngle), side: -1)
                    path.to(edge)
                    corner(from: edge, to: path.point(sector.end - innerAngle, inner), around: center, radius: innerCorner)
                }
                path.arc(radius: inner, from: sector.end - innerAngle, to: sector.start + innerAngle)
                if innerCorner > 0 {
                    let center = path.point(sector.start + innerAngle, inner + innerCorner)
                    let edge = onEdge(sector.start, along: (inner + innerCorner) * cos(innerAngle), side: 1)
                    corner(from: path.point(sector.start + innerAngle, inner), to: edge, around: center, radius: innerCorner)
                }
            } else {
                path.to(path.point(middle, inset / sin(half)))
            }
            path.close()
            return path.elements
        }
    }
}
