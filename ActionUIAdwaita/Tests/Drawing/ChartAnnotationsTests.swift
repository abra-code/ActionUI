// Tests/Drawing/ChartAnnotationsTests.swift
/*
 Tests for where an annotation goes (ChartAnnotationPlacement), against Swift Charts measured on
 macOS 27: a 20 x 10 view beside a bar from (130, 100) to (170, 200), a point of a 20-point symbol
 at (150, 100) and a horizontal rule at y 100 across a 300 x 200 chart. Also the frames the layout
 records for annotated marks.
*/

import XCTest
@testable import ActionUI

@MainActor
final class ChartAnnotationsTests: XCTestCase {
    private let bar = ChartRect(x: 130, y: 100, width: 40, height: 100)
    private let chart = ChartRect(x: 0, y: 0, width: 300, height: 200)
    private let size = ChartSize(width: 20, height: 10)

    private func spec(_ position: ChartPosition = .automatic, _ alignment: ChartAlignment = .center, spacing: Double? = nil,
                      overflow: ChartOverflowResolution? = nil) -> ChartAnnotationSpec {
        var annotation = ChartAnnotationSpec(content: ActionUIElement(id: 900, type: "Text", properties: [:], subviews: nil), readsRows: false)
        annotation.position = position
        annotation.alignment = alignment
        annotation.spacing = spacing
        annotation.overflow = overflow
        return annotation
    }

    private func origin(_ annotation: ChartAnnotationSpec, frame: ChartRect? = nil, center: ChartPoint? = nil) -> [Double] {
        let placed = ChartAnnotationPlacement.place(annotation, frame: frame ?? bar, center: center, size: size, plot: chart, chart: chart)
        return [placed.x, placed.y]
    }

    func testABarsPositions() {
        XCTAssertEqual(origin(spec()), [140, 86], "automatic is top, 4 above")
        XCTAssertEqual(origin(spec(.top)), [140, 86])
        XCTAssertEqual(origin(spec(.overlay)), [140, 145])
        XCTAssertEqual(origin(spec(.leading)), [106, 145])
        XCTAssertEqual(origin(spec(.trailing)), [174, 145])
        XCTAssertEqual(origin(spec(.topLeading)), [106, 86])
    }

    func testSpacingAndAlignment() {
        XCTAssertEqual(origin(spec(.top, spacing: 0)), [140, 90])
        XCTAssertEqual(origin(spec(.top, spacing: 10)), [140, 80])
        XCTAssertEqual(origin(spec(.top, .leading)), [130, 86])
        XCTAssertEqual(origin(spec(.top, .trailing)), [150, 86])
        XCTAssertEqual(origin(spec(.overlay, .top)), [140, 104])
    }

    func testAPointAndARule() {
        let half = 10 + ChartAnnotationPlacement.pointMargin
        let point = ChartRect(x: 150 - half, y: 100 - half, width: half * 2, height: half * 2)
        // Measured 140..160, 75..84.5 above the point, 165.5.. beside it.
        XCTAssertEqual(origin(spec(), frame: point)[1], 74.5, accuracy: 1)
        XCTAssertEqual(origin(spec(.trailing), frame: point)[0], 165.5, accuracy: 0.5)
        let rule = ChartRect(x: 0, y: 100, width: 300, height: 0)
        XCTAssertEqual(origin(spec(), frame: rule), [140, 86])
    }

    func testFitMovesAViewIntoTheChartAndOtherwiseItStays() {
        let half = 10 + ChartAnnotationPlacement.pointMargin
        let atEdge = ChartRect(x: 300 - half, y: 100 - half, width: half * 2, height: half * 2)
        XCTAssertGreaterThan(origin(spec(.trailing), frame: atEdge)[0], 300, "past the edge, cut off")
        let fit = ChartOverflowResolution(x: .fit, y: .fit)
        XCTAssertEqual(origin(spec(.trailing, overflow: fit), frame: atEdge)[0], 280, "measured 280..300")
        let disabled = ChartOverflowResolution(x: .disabled, y: .disabled)
        XCTAssertGreaterThan(origin(spec(.trailing, overflow: disabled), frame: atEdge)[0], 300)
    }

    func testASectorIsFramedByItsBoxAndOverlaidAtItsCentroid() {
        // A quarter at the top right of a pie of radius 100 centered at (150, 100), as measured.
        let quarter = ChartSector(center: ChartPoint(x: 150, y: 100), inner: 0, outer: 100, start: 0, end: .pi / 2)
        let box = ChartAnnotationPlacement.bounds(of: quarter)
        XCTAssertEqual(box.x, 150, accuracy: 1e-9)
        XCTAssertEqual(box.y, 0, accuracy: 1e-9)
        XCTAssertEqual(box.width, 100, accuracy: 1e-9)
        XCTAssertEqual(box.height, 100, accuracy: 1e-9)
        let centroid = ChartAnnotationPlacement.centroid(of: quarter)
        // Measured 184..203.5, 51.5..61: centered near (193.75, 56.25).
        let placed = origin(spec(.overlay), frame: box, center: centroid)
        XCTAssertEqual(placed[0] + 10, 193.75, accuracy: 2.5)
        XCTAssertEqual(placed[1] + 5, 56.25, accuracy: 2.5)
        // automatic is above the box: off the chart, as Apple's was.
        XCTAssertLessThan(origin(spec(), frame: box, center: centroid)[1], 0)
    }

    func testTheLayoutRecordsAnAnnotatedMarksFrame() throws {
        let metrics = ChartTextMetrics(size: { ChartSize(width: Double($0.count) * 6, height: 10) },
                                       number: { value, _ in String(Int(value)) }, formatted: { value, _ in "\(value)" },
                                       date: { _, skeleton in skeleton })
        let description: [String: Any] = [
            "columns": ["day", ["name": "n", "type": "number"]],
            "content": [["type": "ForEach", "content": [["type": "BarMark", "x": ["label": "Day", "value": "$day"],
                                                         "y": ["label": "N", "value": "$n"],
                                                         "annotation": ["content": ["type": "Text", "properties": ["text": "$n"]]]]]]],
        ]
        let parsed = ChartDescription.parse(description, logger: nil).spec
        let marks = ChartMarkResolver.resolve(parsed, rows: [["Mon", "4"], ["Tue", "-2"]])
        XCTAssertEqual(marks.instances.map(\.annotationRow), [["Mon", "4"], ["Tue", "-2"]])
        let geometry = ChartLayout.laidOut(parsed, marks: marks, width: 300, height: 200, metrics: metrics).geometry
        XCTAssertEqual(geometry.annotations.count, 2)
        // Measured: a negative bar's annotation is above it too, over its zero end.
        let negative = geometry.annotations[1].frame
        XCTAssertLessThan(origin(spec(), frame: negative)[1], negative.y)
        XCTAssertEqual(geometry.chart, ChartRect(x: 0, y: 0, width: 300, height: 200))
    }
}
