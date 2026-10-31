// Tests/Drawing/ChartSymbolsTests.swift
/*
 The symbols' outlines against what Swift Charts draws on macOS 27 at an area of 900, in a box of 1.
*/

import XCTest
@testable import ActionUI

final class ChartSymbolsTests: XCTestCase {
    private func extent(_ elements: [ChartPathElement]) -> (x: ClosedRange<Double>, y: ClosedRange<Double>) {
        var points: [ChartPoint] = []
        var last = ChartPoint(x: 0, y: 0)
        for element in elements {
            switch element {
            case .move(let point), .line(let point):
                points.append(point)
                last = point
            case let .curve(first, second, end):
                for step in 1...20 {
                    let t = Double(step) / 20, u = 1 - t
                    func at(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                        u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d
                    }
                    points.append(ChartPoint(x: at(last.x, first.x, second.x, end.x), y: at(last.y, first.y, second.y, end.y)))
                }
                last = end
            case .close:
                break
            }
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        return (xs.min()!...xs.max()!, ys.min()!...ys.max()!)
    }

    func testEachShapeCoversWhatSwiftChartsDoes() {
        let measured: [(ChartSymbol, width: Double, height: Double)] = [
            (.circle, 1, 1), (.square, 0.91, 0.91), (.triangle, 1.09, 0.97), (.diamond, 1.09, 1.09),
            (.pentagon, 1.08, 1.03), (.plus, 1.14, 1.12), (.cross, 0.975, 0.975), (.asterisk, 1.08, 1.15)
        ]
        for (shape, width, height) in measured {
            let found = extent(ChartSymbols.outline(shape, center: ChartPoint(x: 0, y: 0), side: 1))
            XCTAssertEqual(found.x.upperBound - found.x.lowerBound, width, accuracy: 0.03, "\(shape) across")
            XCTAssertEqual(found.y.upperBound - found.y.lowerBound, height, accuracy: 0.03, "\(shape) down")
            XCTAssertEqual(found.x.upperBound + found.x.lowerBound, 0, accuracy: 0.02, "\(shape) centered across")
            XCTAssertEqual(found.y.upperBound + found.y.lowerBound, 0, accuracy: 0.02, "\(shape) centered down")
        }
    }

    func testAnOutlineFollowsItsCenterAndSide() {
        for shape in [ChartSymbol.triangle, .asterisk] {
            let unit = extent(ChartSymbols.outline(shape, center: ChartPoint(x: 0, y: 0), side: 1))
            let moved = extent(ChartSymbols.outline(shape, center: ChartPoint(x: 100, y: 50), side: 30))
            XCTAssertEqual(moved.x.lowerBound, 100 + unit.x.lowerBound * 30, accuracy: 0.001)
            XCTAssertEqual(moved.y.upperBound, 50 + unit.y.upperBound * 30, accuracy: 0.001)
        }
    }

    func testEveryOutlineIsClosedAndAPlusHasItsTwoBars() {
        for shape in [ChartSymbol.circle, .square, .triangle, .diamond, .pentagon, .plus, .cross, .asterisk] {
            XCTAssertEqual(ChartSymbols.outline(shape, center: ChartPoint(x: 0, y: 0), side: 1).last, .close)
        }
        let closes = ChartSymbols.outline(.plus, center: ChartPoint(x: 0, y: 0), side: 1).filter { $0 == .close }
        XCTAssertEqual(closes.count, 2)
    }

    func testASizeOfNothingStaysFinite() {
        for shape in [ChartSymbol.circle, .square, .triangle, .diamond, .pentagon, .plus, .cross, .asterisk] {
            let found = extent(ChartSymbols.outline(shape, center: ChartPoint(x: 3, y: 4), side: 0))
            XCTAssertEqual(found.x.lowerBound, 3, accuracy: 1e-9)
            XCTAssertEqual(found.y.upperBound, 4, accuracy: 1e-9)
        }
    }
}
