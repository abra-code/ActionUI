// Tests/Drawing/ChartSectorsTests.swift
/*
 The outline of a sector against what Swift Charts draws on macOS 27.
*/

import XCTest
@testable import ActionUI

final class ChartSectorsTests: XCTestCase {
    private let center = ChartPoint(x: 0, y: 0)

    // The outline's points, curves followed closely.
    private func points(_ elements: [ChartPathElement]) -> [ChartPoint] {
        var found: [ChartPoint] = []
        var last = ChartPoint(x: 0, y: 0)
        for element in elements {
            switch element {
            case .move(let point), .line(let point):
                found.append(point)
                last = point
            case let .curve(first, second, end):
                for step in 1...20 {
                    let t = Double(step) / 20, u = 1 - t
                    func at(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                        u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
                    }
                    found.append(ChartPoint(x: at(last.x, first.x, second.x, end.x), y: at(last.y, first.y, second.y, end.y)))
                }
                last = end
            case .close:
                break
            }
        }
        return found
    }

    private func radii(_ elements: [ChartPathElement]) -> [Double] {
        points(elements).map { hypot($0.x, $0.y) }
    }

    private func angles(_ elements: [ChartPathElement]) -> [Double] {
        points(elements).filter { hypot($0.x, $0.y) > 1e-6 }.map { atan2($0.x, -$0.y) }
    }

    private func sector(start: Double = 0, end: Double = 1, inner: Double = 0, inset: Double = 0, corner: Double = 0) -> [ChartPathElement] {
        ChartSectors.outline(ChartSector(center: center, inner: inner, outer: 100, start: start, end: end, inset: inset, corner: corner))
    }

    // How far a point is from the line through the center at `angle`.
    private func distance(_ point: ChartPoint, fromEdge angle: Double) -> Double {
        abs(point.x * cos(angle) + point.y * sin(angle))
    }

    func testAPieSliceStartsAtTheTopAndRunsClockwise() throws {
        let found = sector(start: 0, end: .pi / 2)
        let drawn = points(found)
        XCTAssertEqual(drawn[0].x, 0, accuracy: 1e-9)
        XCTAssertEqual(drawn[0].y, -100, accuracy: 1e-9, "up is negative")
        let tip = try XCTUnwrap(drawn.dropLast().last)
        XCTAssertEqual(tip.x, 100, accuracy: 1e-6, "a quarter turn is on the right")
        XCTAssertEqual(drawn.last?.x ?? 1, 0, accuracy: 1e-9, "and the point at the center")
    }

    func testAnArcStaysOnItsCircle() {
        let on = radii(sector(start: 0.3, end: 5)).filter { $0 > 1 }
        XCTAssertEqual(on.max() ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(on.min() ?? 0, 100, accuracy: 0.01)
    }

    func testADonutKeepsToItsTwoCircles() {
        let found = radii(sector(start: 0, end: 2, inner: 60))
        XCTAssertEqual(found.max() ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(found.min() ?? 0, 60, accuracy: 0.01)
    }

    func testAnInsetKeepsTheOuterRadiusAndHasParallelEdges() {
        let found = points(sector(start: 0, end: 2, inner: 40, inset: 3))
        XCTAssertEqual(found.map { hypot($0.x, $0.y) }.max() ?? 0, 100, accuracy: 0.01)
        let nearestStart = found.map { distance($0, fromEdge: 0) }.min() ?? 0
        XCTAssertEqual(nearestStart, 3, accuracy: 0.01, "3 in from the start along the whole edge")
        let atOuter = found[0], lastBeforeClose = found[found.count - 1]
        XCTAssertEqual(distance(atOuter, fromEdge: 0), 3, accuracy: 1e-6)
        XCTAssertEqual(distance(lastBeforeClose, fromEdge: 0), 3, accuracy: 1e-6)
    }

    func testAnInsetStopsAtFivePercentOfTheRadius() {
        XCTAssertEqual(sector(end: 2, inset: 40), sector(end: 2, inset: 5))
        XCTAssertNotEqual(sector(end: 2, inset: 4), sector(end: 2, inset: 5))
    }

    func testAnInsetPieEndsInAPointOnItsMiddleLine() throws {
        let tip = try XCTUnwrap(points(sector(start: 0, end: 1, inset: 4)).last)
        XCTAssertEqual(atan2(tip.x, -tip.y), 0.5, accuracy: 1e-9)
        XCTAssertEqual(hypot(tip.x, tip.y), 4 / sin(0.5), accuracy: 1e-9)
    }

    func testAThinSectorTapersPastItsInnerRadius() throws {
        let tip = try XCTUnwrap(points(sector(start: 0, end: 0.2, inner: 20, inset: 4)).last)
        XCTAssertEqual(hypot(tip.x, tip.y), 4 / sin(0.1), accuracy: 1e-6, "a point past the hole")
    }

    func testASectorTooThinForItsInsetDrawsNothing() {
        XCTAssertEqual(sector(start: 0, end: 0.05, inset: 5), [])
    }

    func testACornerCutsTheOuterCornerAndStopsAtTenPercent() {
        let plain = points(sector(start: 0, end: 2))
        let rounded = sector(start: 0, end: 2, corner: 8)
        XCTAssertNotEqual(rounded, sector(start: 0, end: 2))
        XCTAssertEqual(radii(rounded).max() ?? 0, 100, accuracy: 0.01, "the arc still reaches its radius")
        XCTAssertEqual(plain[0].y, -100, accuracy: 1e-9)
        XCTAssertGreaterThan(points(rounded)[0].y, -100, "and the corner is gone")
        XCTAssertEqual(sector(end: 2, corner: 70), sector(end: 2, corner: 10))
    }

    func testAPointStaysSharpUnderACorner() throws {
        let tip = try XCTUnwrap(points(sector(start: 0, end: 1, corner: 8)).last)
        XCTAssertEqual(hypot(tip.x, tip.y), 0, accuracy: 1e-9)
    }

    func testACornerRoundsAtTheInnerArcToo() {
        let found = sector(start: 0, end: 2, inner: 50, corner: 6)
        XCTAssertEqual(radii(found).min() ?? 0, 50, accuracy: 0.01)
        XCTAssertNotEqual(found, sector(start: 0, end: 2, inner: 50))
        XCTAssertEqual(angles(found).min() ?? -1, 0, accuracy: 1e-6, "the edges stay in the sector")
    }

    func testACornerStopsWhereARingIsShallow() {
        XCTAssertEqual(sector(start: 0, end: 2, inner: 90, corner: 9), sector(start: 0, end: 2, inner: 90, corner: 5))
    }

    func testACornerStopsWhereASectorIsThin() {
        let thin = 0.1
        let found = radii(sector(start: 0, end: thin, corner: 10))
        XCTAssertEqual(found.max() ?? 0, 100, accuracy: 0.5, "a round tip, still reaching the circle")
        let spread = angles(sector(start: 0, end: thin, corner: 10))
        XCTAssertLessThanOrEqual(spread.max() ?? 1, thin + 1e-6)
        XCTAssertGreaterThanOrEqual(spread.min() ?? -1, -1e-6)
    }

    func testAWholeCircleIgnoresItsInsetAndCorner() {
        let whole = 2 * Double.pi
        XCTAssertEqual(sector(end: whole, inset: 5, corner: 8), sector(end: whole))
        XCTAssertEqual(radii(sector(end: whole)).min() ?? 0, 100, accuracy: 0.02, "no point at the center")
    }

    func testARingIsTwoPieces() {
        let found = sector(end: 2 * Double.pi, inner: 60)
        XCTAssertEqual(found.filter { $0 == .close }.count, 2)
        XCTAssertEqual(radii(found).min() ?? 0, 60, accuracy: 0.02)
    }

    func testPastHalfATurnTheEdgesGoRoundTheCenter() {
        // Measured at 55, 60, 75, 90 and 99% of the circle: the gap always ends at the inset's distance.
        for end in [3.5, 4.5, 6.2] {
            let found = radii(sector(start: 0, end: end, inset: 3))
            XCTAssertEqual(found.min() ?? 0, 3, accuracy: 1e-6, "\(end)")
            XCTAssertEqual(found.max() ?? 0, 100, accuracy: 0.01, "\(end)")
        }
    }

    func testJustUnderAWholeTurnTheGapStopsAtTheCenter() {
        // Where the edges would cross is far past the circle here.
        let found = radii(sector(start: 0, end: 2 * .pi - 1e-6, inset: 5))
        XCTAssertEqual(found.max() ?? 0, 100, accuracy: 0.01)
        XCTAssertEqual(found.min() ?? 0, 5, accuracy: 1e-6)
    }

    func testAtHalfATurnTheEdgesAreOneLine() throws {
        let found = points(sector(start: 0, end: .pi, inset: 3))
        let tip = try XCTUnwrap(found.last)
        XCTAssertEqual(tip.x, 3, accuracy: 1e-9)
        XCTAssertEqual(tip.y, 0, accuracy: 1e-9)
    }

    func testAHoleInsideTheRoundCenterDoesNotShow() {
        XCTAssertEqual(sector(start: 0, end: 4.5, inner: 2, inset: 3), sector(start: 0, end: 4.5, inset: 3))
    }

    func testTheRoundCenterStaysRoundUnderACorner() {
        let found = radii(sector(start: 0, end: 4.5, inset: 3, corner: 8))
        XCTAssertEqual(found.min() ?? 0, 3, accuracy: 1e-6)
    }

    // Where the fillet leaves the start edge, from the center: the last point of a sector without an inset.
    private func fillet(_ radius: Double, under inner: Double) -> Double {
        let center = inner + radius
        return (center * center - radius * radius).squareRoot()
    }

    func testAnInnerCornerStopsAtTheInnerRadiusPastHalfATurn() throws {
        let last = try XCTUnwrap(points(sector(start: 0, end: 4.5, inner: 8, corner: 10)).last)
        XCTAssertEqual(hypot(last.x, last.y), fillet(8, under: 8), accuracy: 1e-6)
    }

    func testAnInnerCornerStopsShortOfThePointOnANarrowSector() throws {
        let spine = sin(0.5), most = 20 * spine / (1 + spine)
        let last = try XCTUnwrap(points(sector(start: 0, end: 1, inner: 20, corner: 10)).last)
        XCTAssertEqual(hypot(last.x, last.y), fillet(most, under: 20), accuracy: 1e-6)
    }

    func testNothingToDrawIsNothing() {
        XCTAssertEqual(sector(start: 1, end: 1), [])
        XCTAssertEqual(ChartSectors.outline(ChartSector(center: center, inner: 0, outer: 0, start: 0, end: 1)), [])
    }

    func testEveryPointIsFinite() {
        for start in stride(from: 0.0, to: 6.0, by: 0.7) {
            for end in stride(from: start + 0.01, to: 2 * Double.pi, by: 0.33) {
                for inner in [0.0, 5, 50, 99] {
                    for inset in [0.0, 1, 5] {
                        for corner in [0.0, 2, 10] {
                            let found = points(sector(start: start, end: end, inner: inner, inset: inset, corner: corner))
                            XCTAssertTrue(found.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "\(start) \(end) \(inner) \(inset) \(corner)")
                        }
                    }
                }
            }
        }
    }
}
