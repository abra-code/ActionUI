// Tests/Drawing/ChartCurvesTests.swift
/*
 Tests for the paths through a line's points: steps as Swift Charts draws them, curves that pass
 through every point, monotone that never overshoots, and points that are not in x order.
*/

import XCTest
@testable import ActionUI

final class ChartCurvesTests: XCTestCase {
    private let zigzag = [ChartPoint(x: 0, y: 1), ChartPoint(x: 10, y: 9), ChartPoint(x: 20, y: 2), ChartPoint(x: 30, y: 8), ChartPoint(x: 40, y: 3)]

    private func ends(_ elements: [ChartPathElement]) -> [ChartPoint] {
        elements.compactMap { element in
            switch element {
            case .move(let point), .line(let point): return point
            case .curve(_, _, let end): return end
            case .close: return nil
            }
        }
    }

    func testAPathOfNoPointsIsEmptyAndOfOneIsItsMove() {
        for method: ChartInterpolation in [.linear, .monotone, .stepCenter, .cardinal(tension: nil), .catmullRom(alpha: nil)] {
            XCTAssertEqual(ChartCurves.elements([], method), [])
            XCTAssertEqual(ChartCurves.elements([zigzag[0]], method), [.move(zigzag[0])])
        }
    }

    func testLinearJoinsThePointsInTheOrderGiven() {
        let points = [ChartPoint(x: 30, y: 5), ChartPoint(x: 10, y: 2), ChartPoint(x: 20, y: 8)]
        XCTAssertEqual(ChartCurves.elements(points, .linear), [.move(points[0]), .line(points[1]), .line(points[2])])
    }

    func testStepStartJumpsAtTheStartOfEachInterval() {
        let points = [ChartPoint(x: 0, y: 1), ChartPoint(x: 10, y: 9)]
        XCTAssertEqual(ChartCurves.elements(points, .stepStart), [.move(points[0]), .line(ChartPoint(x: 0, y: 9)), .line(points[1])])
    }

    func testStepEndJumpsAtTheEndOfEachInterval() {
        let points = [ChartPoint(x: 0, y: 1), ChartPoint(x: 10, y: 9)]
        XCTAssertEqual(ChartCurves.elements(points, .stepEnd), [.move(points[0]), .line(ChartPoint(x: 10, y: 1)), .line(points[1])])
    }

    func testStepCenterJumpsHalfway() {
        let points = [ChartPoint(x: 0, y: 1), ChartPoint(x: 10, y: 9)]
        XCTAssertEqual(ChartCurves.elements(points, .stepCenter),
                       [.move(points[0]), .line(ChartPoint(x: 5, y: 1)), .line(ChartPoint(x: 5, y: 9)), .line(points[1])])
    }

    func testCurvesPassThroughEveryPoint() {
        for method: ChartInterpolation in [.cardinal(tension: nil), .cardinal(tension: 0.5), .catmullRom(alpha: nil), .catmullRom(alpha: 0), .monotone] {
            XCTAssertEqual(ends(ChartCurves.elements(zigzag, method)), zigzag, "\(method)")
        }
    }

    func testAFullyTenseCardinalIsStraight() {
        for element in ChartCurves.elements(zigzag, .cardinal(tension: 1)).dropFirst() {
            guard case let .curve(first, second, end) = element else { return XCTFail("expected a curve") }
            XCTAssertTrue(zigzag.contains(first), "\(first)")
            XCTAssertEqual(second, end)
        }
    }

    func testCatmullRomWithAlphaZeroIsAPlainCardinalInside() {
        let plain = ChartCurves.elements(zigzag, .catmullRom(alpha: 0))
        let cardinal = ChartCurves.elements(zigzag, .cardinal(tension: 0))
        guard case let .curve(a1, a2, _) = plain[2], case let .curve(b1, b2, _) = cardinal[2] else { return XCTFail("expected curves") }
        XCTAssertEqual(a1.x, b1.x, accuracy: 1e-9)
        XCTAssertEqual(a1.y, b1.y, accuracy: 1e-9)
        XCTAssertEqual(a2.x, b2.x, accuracy: 1e-9)
        XCTAssertEqual(a2.y, b2.y, accuracy: 1e-9)
    }

    func testMonotoneIsFlatAtAnExtremeAndNeverOvershoots() {
        let elements = ChartCurves.elements(zigzag, .monotone)
        guard case let .curve(_, second, end) = elements[1] else { return XCTFail("expected a curve") }
        XCTAssertEqual(second.y, end.y, accuracy: 1e-9, "flat into the peak at 9")
        for element in elements {
            guard case let .curve(first, second, _) = element else { continue }
            for y in [first.y, second.y] {
                XCTAssertGreaterThanOrEqual(y, 1 - 1e-9)
                XCTAssertLessThanOrEqual(y, 9 + 1e-9)
            }
        }
    }

    func testMonotoneOfTwoPointsIsStraight() {
        let points = [ChartPoint(x: 0, y: 0), ChartPoint(x: 10, y: 10)]
        XCTAssertEqual(ChartCurves.elements(points, .monotone), [.move(points[0]), .line(points[1])])
    }

    func testBackwardDrawsTheSamePathTheOtherWay() {
        for method: ChartInterpolation in [.linear, .stepStart, .stepCenter, .stepEnd] {
            let forward = ends(ChartCurves.elements(zigzag, method))
            let back = ends(ChartCurves.elements(zigzag.reversed(), ChartCurves.backward(method)))
            XCTAssertEqual(forward, back.reversed(), "\(method)")
        }
    }

    func testPointsAtOneXStayFinite() {
        let points = [ChartPoint(x: 10, y: 1), ChartPoint(x: 10, y: 5), ChartPoint(x: 10, y: 5), ChartPoint(x: 20, y: 2)]
        for method: ChartInterpolation in [.cardinal(tension: nil), .catmullRom(alpha: nil), .monotone] {
            XCTAssertTrue(ChartPrimitive.fill(ChartCurves.elements(points, method), ink: .text(opacity: 1)).isDrawable, "\(method)")
        }
    }
}
