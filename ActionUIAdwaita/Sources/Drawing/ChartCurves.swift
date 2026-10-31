// Sources/Drawing/ChartCurves.swift
/*
 The path through a line's or an area's points, for each interpolation method, without GTK. Points
 stay in the order given: Swift Charts joins them in data order, not by x.

 stepStart jumps at the start of each interval, stepEnd at its end and stepCenter halfway (measured
 on macOS 27). The curves pass through every point and are the standard ones, as in D3: cardinal is
 a cubic through neighbors, reflected at the ends; catmullRom is parameterized by chord length to the
 power alpha, centripetal unless given; monotone keeps each interval's direction (Steffen's method),
 so it never overshoots.
*/

import Glibc

enum ChartPathElement: Equatable {
    case move(ChartPoint)
    case line(ChartPoint)
    case curve(ChartPoint, ChartPoint, ChartPoint)
}

enum ChartCurves {
    private static let defaultCatmullRomAlpha = 0.5

    /// A path through `points`, starting with a move; empty without points.
    static func elements(_ points: [ChartPoint], _ method: ChartInterpolation) -> [ChartPathElement] {
        guard let first = points.first else { return [] }
        var elements: [ChartPathElement] = [.move(first)]
        guard points.count > 1 else { return elements }
        switch method {
        case .linear:
            elements += points.dropFirst().map { .line($0) }
        case .stepStart:
            for (from, to) in zip(points, points.dropFirst()) {
                elements.append(.line(ChartPoint(x: from.x, y: to.y)))
                elements.append(.line(to))
            }
        case .stepEnd:
            for (from, to) in zip(points, points.dropFirst()) {
                elements.append(.line(ChartPoint(x: to.x, y: from.y)))
                elements.append(.line(to))
            }
        case .stepCenter:
            for (from, to) in zip(points, points.dropFirst()) {
                let middle = (from.x + to.x) / 2
                elements.append(.line(ChartPoint(x: middle, y: from.y)))
                elements.append(.line(ChartPoint(x: middle, y: to.y)))
                elements.append(.line(to))
            }
        case .cardinal(let tension):
            elements += cardinal(points, tension: tension ?? 0)
        case .catmullRom(let alpha):
            elements += catmullRom(points, alpha: alpha ?? defaultCatmullRomAlpha)
        case .monotone:
            elements += monotone(points)
        }
        return elements
    }

    /// The method that draws the same path walked from the last point to the first: a step that
    /// jumps at the start of an interval going forward jumps at its end going back.
    static func backward(_ method: ChartInterpolation) -> ChartInterpolation {
        switch method {
        case .stepStart: return .stepEnd
        case .stepEnd: return .stepStart
        default: return method
        }
    }

    private static func cardinal(_ points: [ChartPoint], tension: Double) -> [ChartPathElement] {
        let k = (1 - tension) / 6
        return points.indices.dropLast().map { index in
            let p1 = points[index], p2 = points[index + 1]
            // At an end, the neighbor on the other side stands in for the missing one.
            let p0 = index > 0 ? points[index - 1] : p2
            let p3 = index + 2 < points.count ? points[index + 2] : p1
            return .curve(ChartPoint(x: p1.x + k * (p2.x - p0.x), y: p1.y + k * (p2.y - p0.y)),
                          ChartPoint(x: p2.x + k * (p1.x - p3.x), y: p2.y + k * (p1.y - p3.y)), p2)
        }
    }

    private static func catmullRom(_ points: [ChartPoint], alpha: Double) -> [ChartPathElement] {
        func chord(_ a: ChartPoint, _ b: ChartPoint) -> Double {
            pow((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y), alpha / 2)
        }
        return points.indices.dropLast().map { index in
            let p1 = points[index], p2 = points[index + 1]
            let d12 = chord(p1, p2)
            var c1 = p1, c2 = p2
            if index > 0 {
                let p0 = points[index - 1]
                let d01 = chord(p0, p1)
                if d01 > 1e-12 {
                    let a = 2 * d01 * d01 + 3 * d01 * d12 + d12 * d12
                    let n = 3 * d01 * (d01 + d12)
                    c1 = ChartPoint(x: (p1.x * a - p0.x * d12 * d12 + p2.x * d01 * d01) / n,
                                    y: (p1.y * a - p0.y * d12 * d12 + p2.y * d01 * d01) / n)
                }
            }
            if index + 2 < points.count {
                let p3 = points[index + 2]
                let d23 = chord(p2, p3)
                if d23 > 1e-12 {
                    let b = 2 * d23 * d23 + 3 * d23 * d12 + d12 * d12
                    let m = 3 * d23 * (d23 + d12)
                    c2 = ChartPoint(x: (p2.x * b + p1.x * d23 * d23 - p3.x * d12 * d12) / m,
                                    y: (p2.y * b + p1.y * d23 * d23 - p3.y * d12 * d12) / m)
                }
            }
            return .curve(c1, c2, p2)
        }
    }

    private static func monotone(_ points: [ChartPoint]) -> [ChartPathElement] {
        // Two points have no tangent to take from a neighbor: straight, as Swift Charts draws them.
        guard points.count > 2 else { return points.dropFirst().map { .line($0) } }
        var slopes = [Double](repeating: 0, count: points.count)
        func sign(_ value: Double) -> Double { value < 0 ? -1 : 1 }
        func finite(_ value: Double) -> Double { value.isFinite ? value : 0 }
        for index in points.indices.dropFirst().dropLast() {
            let h0 = points[index].x - points[index - 1].x, h1 = points[index + 1].x - points[index].x
            let s0 = (points[index].y - points[index - 1].y) / h0, s1 = (points[index + 1].y - points[index].y) / h1
            let p = (s0 * h1 + s1 * h0) / (h0 + h1)
            slopes[index] = finite((sign(s0) + sign(s1)) * min(abs(s0), abs(s1), 0.5 * abs(p)))
        }
        func endSlope(_ from: ChartPoint, _ to: ChartPoint, _ tangent: Double) -> Double {
            let h = to.x - from.x
            return h != 0 ? finite((3 * (to.y - from.y) / h - tangent) / 2) : tangent
        }
        let last = points.count - 1
        slopes[0] = endSlope(points[0], points[1], slopes[1])
        slopes[last] = endSlope(points[last - 1], points[last], slopes[last - 1])
        return points.indices.dropLast().map { index in
            let p1 = points[index], p2 = points[index + 1]
            let third = (p2.x - p1.x) / 3
            return .curve(ChartPoint(x: p1.x + third, y: p1.y + third * slopes[index]),
                          ChartPoint(x: p2.x - third, y: p2.y - third * slopes[index + 1]), p2)
        }
    }
}
