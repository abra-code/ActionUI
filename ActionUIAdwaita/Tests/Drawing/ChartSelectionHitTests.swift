// Tests/Drawing/ChartSelectionHitTests.swift
/*
 Tests for reading a place in a chart as a selection (ChartSelectionHit, ChartAxisScale.value), and
 for the marks that read "$selection" (ChartMarkResolver), as numbers: no display needed.
*/

import XCTest
@testable import ActionUI

@MainActor
final class ChartSelectionHitTests: XCTestCase {
    private func geometry(x: ChartAxisScale = ChartAxisScale(), y: ChartAxisScale = ChartAxisScale()) -> ChartGeometry {
        ChartGeometry(plot: ChartRect(x: 0, y: 0, width: 300, height: 200), x: x, y: y)
    }

    private func bands(_ names: [String], start: Double = 0, end: Double = 300) -> ChartAxisScale {
        ChartAxisScale(kind: .bands(Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0) })), start: start, end: end)
    }

    func testABandIsTheCategoryUnderThePlace() {
        let scale = bands(["Mon", "Tue", "Wed"])
        XCTAssertEqual(scale.value(at: 10, type: .string), .string("Mon"))
        XCTAssertEqual(scale.value(at: 150, type: .string), .string("Tue"))
        XCTAssertEqual(scale.value(at: 299, type: .string), .string("Wed"))
        // At or past an end, the band there.
        XCTAssertEqual(scale.value(at: 300, type: .string), .string("Wed"))
        XCTAssertEqual(scale.value(at: -5, type: .string), .string("Mon"))
        // A y axis of bands runs the other way as placed; the place still picks its band.
        XCTAssertEqual(bands(["A", "B"], start: 200, end: 0).value(at: 150, type: .string), .string("A"))
    }

    func testANumberIsWhatThePlaceStandsFor() {
        let linear = ChartAxisScale(kind: .numbers(lo: 0, hi: 100), start: 0, end: 200)
        XCTAssertEqual(linear.value(at: 50, type: .number), .number(25))
        XCTAssertEqual(linear.value(at: 51, type: .integer), .integer(26), "the nearest whole number")
        // Up the y axis: the low end at the bottom.
        let rising = ChartAxisScale(kind: .numbers(lo: 0, hi: 10), start: 200, end: 0)
        XCTAssertEqual(rising.value(at: 50, type: .number), .number(7.5))
        let log = ChartAxisScale(kind: .numbers(lo: 1, hi: 1000), start: 0, end: 300, transform: .log)
        guard case .number(let tens)? = log.value(at: 100, type: .number) else { return XCTFail("a number") }
        XCTAssertEqual(tens, 10, accuracy: 1e-9)
    }

    func testEveryTransformInvertsItself() {
        for transform: ChartScaleTransform in [.linear, .log, .squareRoot, .power(3), .symmetricLog(1), .symmetricLog(0.5)] {
            for number in [0.5, 2.0, 37.0] {
                XCTAssertEqual(transform.invert(transform.apply(number)), number, accuracy: 1e-9, "\(transform)")
            }
        }
        XCTAssertEqual(ChartScaleTransform.symmetricLog(1).invert(ChartScaleTransform.symmetricLog(1).apply(-4)), -4, accuracy: 1e-9)
        // An odd whole exponent keeps a negative number's sign, and the inverse finds it again.
        for exponent in [3.0, -1.0] {
            let transform = ChartScaleTransform.power(exponent)
            XCTAssertEqual(transform.invert(transform.apply(-2)), -2, accuracy: 1e-9, "\(transform)")
        }
    }

    func testADateIsTheInstantThePlaceStandsFor() {
        let start = Date(timeIntervalSince1970: 0)
        let scale = ChartAxisScale(kind: .dates(lo: start, hi: start.addingTimeInterval(1000)), start: 0, end: 100)
        XCTAssertEqual(scale.value(at: 25, type: .date), .date(start.addingTimeInterval(250)))
    }

    func testOnlyAPlaceInThePlotSelects() {
        let shape = geometry(x: bands(["Mon", "Tue"]))
        XCTAssertEqual(ChartSelectionHit.value(at: ChartPoint(x: 200, y: 100), .horizontal, type: .string, geometry: shape), .string("Tue"))
        XCTAssertNil(ChartSelectionHit.value(at: ChartPoint(x: 200, y: 250), .horizontal, type: .string, geometry: shape))
        XCTAssertNil(ChartSelectionHit.value(at: ChartPoint(x: 200, y: 100), .horizontal, type: nil, geometry: shape))
    }

    func testARangeIsInOrderAndHeldToThePlot() {
        let shape = geometry(x: ChartAxisScale(kind: .numbers(lo: 0, hi: 30), start: 0, end: 300))
        XCTAssertEqual(ChartSelectionHit.range(from: ChartPoint(x: 200, y: 10), to: ChartPoint(x: 100, y: 10), .horizontal, type: .number, geometry: shape),
                       .range(.number(10), .number(20)))
        XCTAssertEqual(ChartSelectionHit.range(from: ChartPoint(x: 100, y: 10), to: ChartPoint(x: 900, y: 500), .horizontal, type: .number, geometry: shape),
                       .range(.number(10), .number(30)), "a drag past the plot stops at its edge")
    }

    // MARK: Sectors and selection marks, from a description

    private func resolved(_ description: [String: Any], rows: [[String]] = [], selection: ChartSelection = ChartSelection()) -> (ChartSpec, ChartResolvedMarks) {
        let spec = ChartDescription.parse(description, logger: nil).spec
        return (spec, ChartMarkResolver.resolve(spec, rows: rows, selection: selection))
    }

    private let pie: [String: Any] = [
        "columns": ["name", ["name": "n", "type": "number"]],
        "chartAngleSelection": "value",
        "content": [["type": "ForEach", "content": [["type": "SectorMark", "angle": ["label": "N", "value": "$n"],
                                                     "foregroundStyle": ["by": ["label": "Name", "value": "$name"]]]]]],
    ]

    func testAnAngleIsTheShareOfTheSumClockwiseFromTheTop() throws {
        let (spec, marks) = resolved(pie, rows: [["a", "1"], ["b", "3"]])
        XCTAssertTrue(spec.selection.angle)
        let shape = geometry()
        // The plot's center is (150, 100). Straight right is a quarter turn: 1 of the sum of 4, row 0.
        let right = try XCTUnwrap(ChartSelectionHit.angle(at: ChartPoint(x: 250, y: 100), marks: marks, type: .number, geometry: shape))
        XCTAssertEqual(right.angle, 1, accuracy: 1e-9)
        XCTAssertEqual(right.row, 0)
        // Straight down is half: 2, in the second sector.
        let down = try XCTUnwrap(ChartSelectionHit.angle(at: ChartPoint(x: 150, y: 190), marks: marks, type: .number, geometry: shape))
        XCTAssertEqual(down.angle, 2, accuracy: 1e-9)
        XCTAssertEqual(down.row, 1)
        XCTAssertNil(ChartSelectionHit.angle(at: ChartPoint(x: 150, y: 100), marks: marks, type: .number, geometry: shape), "no direction at the center")
    }

    private let barsWithRule: [String: Any] = [
        "columns": ["day", ["name": "n", "type": "number"]],
        "chartXSelection": "value",
        "content": [
            ["type": "ForEach", "content": [["type": "BarMark", "x": ["label": "Day", "value": "$day"], "y": ["label": "N", "value": "$n"]]]],
            ["type": "RuleMark", "x": ["label": "Selected", "value": "$selection"]],
        ],
    ]

    func testASelectionMarkIsDrawnOnlyWhileThereIsASelection() {
        let rows = [["Mon", "4"], ["Tue", "2"]]
        let (spec, none) = resolved(barsWithRule, rows: rows)
        XCTAssertEqual(none.instances.count, 2)
        let selection = ChartSelection.decode(#"{"x": "Tue"}"#, spec: spec.selection)
        let (_, selected) = resolved(barsWithRule, rows: rows, selection: selection)
        XCTAssertEqual(selected.instances.count, 3)
        let rule = selected.instances.last
        XCTAssertEqual(rule?.readsSelection, true)
        XCTAssertEqual(rule?.values["x"], .string("Tue"))
        // A category no other mark plots is not drawn: it would add one.
        let (_, elsewhere) = resolved(barsWithRule, rows: rows, selection: ChartSelection.decode(#"{"x": "Sun"}"#, spec: spec.selection))
        XCTAssertEqual(elsewhere.instances.count, 2)
    }

    func testARangeIsReadByStartAndEnd() {
        let description: [String: Any] = [
            "columns": [["name": "t", "type": "number"], ["name": "n", "type": "number"]],
            "chartXSelection": "range",
            "content": [
                ["type": "ForEach", "content": [["type": "PointMark", "x": ["label": "T", "value": "$t"], "y": ["label": "N", "value": "$n"]]]],
                ["type": "RectangleMark", "xStart": ["label": "From", "value": "$selection"], "xEnd": ["label": "To", "value": "$selection"]],
            ],
        ]
        let rows = [["1", "4"], ["9", "2"]]
        let spec = ChartDescription.parse(description, logger: nil).spec
        let selection = ChartSelection.decode(#"{"x": [2, 5]}"#, spec: spec.selection)
        let marks = ChartMarkResolver.resolve(spec, rows: rows, selection: selection)
        let band = marks.instances.first { $0.readsSelection }
        XCTAssertEqual(band?.values["xStart"], .number(2))
        XCTAssertEqual(band?.values["xEnd"], .number(5))
    }

    func testSelectionMarksSayNothingInTheChartsName() {
        var described = barsWithRule
        described["content"] = [
            ["type": "ForEach", "content": [["type": "BarMark", "x": ["label": "Day", "value": "$day"], "y": ["label": "N", "value": "$n"],
                                             "accessibilityLabel": "$day"]]],
            ["type": "RuleMark", "x": ["label": "Selected", "value": "$selection"], "accessibilityLabel": "Selected"],
        ]
        let rows = [["Mon", "4"]]
        let (spec, plain) = resolved(described, rows: rows)
        let (_, selected) = resolved(described, rows: rows, selection: ChartSelection.decode(#"{"x": "Mon"}"#, spec: spec.selection))
        XCTAssertEqual(plain.accessibleName, selected.accessibleName)
    }
}
