// Tests/Drawing/ChartScrollLayoutTests.swift
/*
 Tests for a scrolling chart's layout (ChartLayout+Scroll), as numbers with a fake text measurer
 (6 points a character, 10 high), against what Swift Charts was measured to show on macOS 27: the
 window's length by default and given, the initial position held in the domain, ticks spaced for
 the window, marks clipped to the plot.
*/

import XCTest
@testable import ActionUI

@MainActor
final class ChartScrollLayoutTests: XCTestCase {
    private let metrics = ChartTextMetrics(
        size: { ChartSize(width: Double($0.count) * 6, height: 10) },
        number: { value, _ in abs(value) < 1e15 && value == value.rounded() ? String(Int(value)) : String(value) },
        formatted: { value, format in "\(format): \(value)" },
        date: { _, skeleton in skeleton })

    private func value(_ label: String, _ value: Any) -> [String: Any] { ["label": label, "value": value] }

    /// Points at x 0...100, y the x's last digit.
    private let pointRows = (0...100).map { [String($0), String($0 % 10)] }

    private func points(_ extra: [String: Any]) -> [String: Any] {
        var description: [String: Any] = [
            "columns": [["name": "x", "type": "number"], ["name": "y", "type": "number"]],
            "chartScrollableAxes": "horizontal",
            "content": [["type": "ForEach", "content": [["type": "PointMark", "x": value("X", "$x"), "y": value("Y", "$y")]]]],
        ]
        description.merge(extra) { $1 }
        return description
    }

    private func bars(_ extra: [String: Any]) -> [String: Any] {
        var description: [String: Any] = [
            "columns": ["name", ["name": "n", "type": "number"]],
            "chartScrollableAxes": "horizontal",
            "content": [["type": "ForEach", "content": [["type": "BarMark", "x": value("Name", "$name"), "y": value("N", "$n")]]]],
        ]
        description.merge(extra) { $1 }
        return description
    }

    private let barRows = (0..<10).map { [String(UnicodeScalar(65 + $0)!), String($0 + 1)] }

    private func laidOut(_ description: [String: Any], rows: [[String]], scroll: (x: Double?, y: Double?) = (nil, nil))
        -> (primitives: [ChartPrimitive], geometry: ChartGeometry) {
        let spec = ChartDescription.parse(description, logger: nil).spec
        return ChartLayout.laidOut(spec, marks: ChartMarkResolver.resolve(spec, rows: rows), width: 400, height: 300,
                                   metrics: metrics, scroll: scroll)
    }

    private func texts(_ primitives: [ChartPrimitive]) -> [String] {
        primitives.compactMap { primitive in
            if case .text(let text, _, _, _) = primitive { return text } else { return nil }
        }
    }

    func testWithoutALengthTheWindowIsAThirdOfTheDomain() throws {
        let (_, geometry) = laidOut(points([:]), rows: pointRows)
        let window = try XCTUnwrap(geometry.xScroll)
        XCTAssertEqual(window.visible, 100.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(window.leading, 0)
        // The window fills the plot: its end is at the plot's trailing edge.
        XCTAssertEqual(geometry.x.position(100.0 / 3), geometry.plot.x + geometry.plot.width, accuracy: 1e-6)
        XCTAssertNil(geometry.yScroll, "only the axes asked for scroll")
    }

    func testAVisibleLengthIsInDataUnitsAndTicksFollowIt() throws {
        let (primitives, geometry) = laidOut(points(["chartXVisibleDomain": ["length": 20]]), rows: pointRows)
        let window = try XCTUnwrap(geometry.xScroll)
        XCTAssertEqual(window.visible, 20)
        XCTAssertEqual(geometry.x.position(0), geometry.plot.x, accuracy: 1e-6)
        XCTAssertEqual(geometry.x.position(20), geometry.plot.x + geometry.plot.width, accuracy: 1e-6)
        // Ticks every 5, and only those in the window drawn: 0, 5, 10 and 15, as Swift Charts labels
        // it (the label at the trailing edge, 20, does not fit).
        XCTAssertEqual(Set(texts(primitives)).intersection(["0", "5", "10", "15", "20", "25", "30"]), ["0", "5", "10", "15"])
    }

    func testTheInitialPositionIsTheLeadingEdgeHeldInTheDomain() throws {
        let at50 = try XCTUnwrap(laidOut(points(["chartXVisibleDomain": ["length": 20], "chartScrollPosition": ["initialX": 50]]),
                                         rows: pointRows).geometry.xScroll)
        XCTAssertEqual(at50.leading, 50)
        let at95 = try XCTUnwrap(laidOut(points(["chartXVisibleDomain": ["length": 20], "chartScrollPosition": ["initialX": 95]]),
                                         rows: pointRows).geometry.xScroll)
        XCTAssertEqual(at95.leading, 80, "the window stays in the domain")
    }

    func testAWindowPlacedBeforeKeepsItsPlace() throws {
        let (_, geometry) = laidOut(points(["chartXVisibleDomain": ["length": 20], "chartScrollPosition": ["initialX": 50]]),
                                    rows: pointRows, scroll: (x: 30, y: nil))
        XCTAssertEqual(geometry.xScroll?.leading, 30, "a place the user scrolled to wins over the initial one")
        XCTAssertEqual(geometry.x.position(30), geometry.plot.x, accuracy: 1e-6)
        let past = laidOut(points(["chartXVisibleDomain": ["length": 20]]), rows: pointRows, scroll: (x: 500, y: nil)).geometry
        XCTAssertEqual(past.xScroll?.leading, 80)
    }

    func testACategoryLengthShowsNOverNMinusOneBandsPerCategory() throws {
        let three = try XCTUnwrap(laidOut(bars(["chartXVisibleDomain": ["length": 3]]), rows: barRows).geometry.xScroll)
        XCTAssertEqual(three.visible, 3.0 * 10 / 9, accuracy: 1e-9)
        let plain = try XCTUnwrap(laidOut(bars([:]), rows: barRows).geometry.xScroll)
        XCTAssertEqual(plain.visible, 10.0 / 3, accuracy: 1e-9)
        let atE = try XCTUnwrap(laidOut(bars(["chartXVisibleDomain": ["length": 3], "chartScrollPosition": ["initialX": "E"]]),
                                        rows: barRows).geometry)
        XCTAssertEqual(atE.xScroll?.leading, 4, "E is the fifth band")
        // E's band starts at the plot's leading edge; the labels of bands out of view are not drawn.
        let primitives = laidOut(bars(["chartXVisibleDomain": ["length": 3], "chartScrollPosition": ["initialX": "E"]]), rows: barRows).primitives
        let labels = Set(texts(primitives))
        XCTAssertTrue(["E", "F", "G"].allSatisfy(labels.contains), "\(labels)")
        XCTAssertFalse(labels.contains("A"))
        XCTAssertFalse(labels.contains("J"))
    }

    func testAScrollingChartClipsItsMarksToThePlot() {
        let primitives = laidOut(points(["chartXVisibleDomain": ["length": 20]]), rows: pointRows).primitives
        let clipped = primitives.contains { primitive in
            if case .beginPlot(let layer) = primitive { return layer.clips }
            return false
        }
        XCTAssertTrue(clipped)
        let plain = laidOut(points(["chartScrollableAxes": [String]()]), rows: pointRows).primitives
        XCTAssertFalse(plain.contains { if case .beginPlot = $0 { return true } else { return false } }, "no layer without scrolling")
    }

    func testAVerticalWindowStartsAtTheBottomOfARisingAxis() throws {
        var description = points(["chartScrollableAxes": "vertical", "chartYVisibleDomain": ["length": 3]])
        description["columns"] = [["name": "x", "type": "number"], ["name": "y", "type": "number"]]
        let geometry = laidOut(description, rows: pointRows).geometry
        let window = try XCTUnwrap(geometry.yScroll)
        XCTAssertEqual(window.leading, window.lo)
        XCTAssertEqual(geometry.y.position(window.lo), geometry.plot.y + geometry.plot.height, accuracy: 1e-6)
        XCTAssertEqual(geometry.y.position(window.lo + 3), geometry.plot.y, accuracy: 1e-6)
        XCTAssertLessThan(window.pointsPerUnit, 0, "a move down the plot is toward lower numbers")
    }

    func testAPlotStyleFrameOrPaddingHoldsTheWindowToTheEnd() throws {
        for style: [String: Any] in [["padding": 20], ["frame": ["width": 200]]] {
            let description = points(["chartXVisibleDomain": ["length": 20], "chartPlotStyle": style])
            let geometry = laidOut(description, rows: pointRows).geometry
            XCTAssertEqual(geometry.x.position(20), geometry.plot.x + geometry.plot.width, accuracy: 1e-6, "\(style)")
            // Held at its end, the domain's end is at the plot's trailing edge, not past it.
            let end = laidOut(description, rows: pointRows, scroll: (x: 500, y: nil)).geometry
            XCTAssertEqual(end.x.position(100), end.plot.x + end.plot.width, accuracy: 1e-6, "\(style) at the end")
        }
    }

    func testARangeInPointsHoldsTheWindow() throws {
        let description = points(["chartXVisibleDomain": ["length": 20], "chartXScale": ["range": [0, 200]]])
        let start = laidOut(description, rows: pointRows).geometry
        XCTAssertEqual(start.x.position(0), start.plot.x, accuracy: 1e-6)
        XCTAssertEqual(start.x.position(20), start.plot.x + 200, accuracy: 1e-6)
        let end = laidOut(description, rows: pointRows, scroll: (x: 500, y: nil)).geometry
        XCTAssertEqual(end.x.position(100), end.plot.x + 200, accuracy: 1e-6)
    }

    func testAScrolledBandAxisDrawsOnlyTheLinesInThePlot() throws {
        for scroll: Double? in [nil, 4] {
            let (primitives, geometry) = laidOut(bars(["chartXVisibleDomain": ["length": 3]]), rows: barRows, scroll: (x: scroll, y: nil))
            let xs = primitives.compactMap { primitive -> Double? in
                if case let .line(from, to, _, _) = primitive, from.x == to.x { return from.x }
                return nil
            }
            XCTAssertFalse(xs.isEmpty)
            XCTAssertTrue(xs.allSatisfy { $0 >= geometry.plot.x - 0.5 && $0 <= geometry.plot.x + geometry.plot.width + 0.5 }, "\(xs) \(geometry.plot)")
        }
    }

    func testThinnedBandLabelsKeepTheirBandsAsTheWindowMoves() throws {
        // Names 30 characters wide (180 points) on bands of 114 take every other band.
        let rows = barRows.map { [String(repeating: $0[0], count: 30), $0[1]] }
        for scroll in [3.0, 4.0] {
            let labels = Set(texts(laidOut(bars(["chartXVisibleDomain": ["length": 3]]), rows: rows, scroll: (x: scroll, y: nil)).primitives))
            let firsts = Set(labels.filter { $0.count == 30 }.compactMap(\.first))
            XCTAssertFalse(firsts.isEmpty)
            XCTAssertTrue(firsts.isSubset(of: ["A", "C", "E", "G", "I"]), "scrolled to \(scroll): \(firsts.sorted())")
        }
    }

    func testAWholeDomainInViewDoesNotScroll() {
        XCTAssertNil(laidOut(points(["chartXVisibleDomain": ["length": 500]]), rows: pointRows).geometry.xScroll)
    }
}
