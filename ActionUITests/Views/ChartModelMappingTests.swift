// Tests/Views/ChartModelMappingTests.swift
import XCTest
import SwiftUI
import Charts
@testable import ActionUI

// The chart model's neutral values against the Swift Charts and SwiftUI values they stand for.
// Most of those types are not Equatable, so values compare by their dumps; each table also requires
// its entries to differ, which fails if two map alike or if a dump shows nothing.
final class ChartModelMappingTests: XCTestCase {
    private func text(_ value: some Any) -> String {
        var output = ""
        dump(value, to: &output)
        return output
    }

    private func check<Neutral, Mapped>(_ table: [(Neutral, Mapped)], _ map: (Neutral) -> Mapped,
                                        file: StaticString = #filePath, line: UInt = #line) {
        var seen: Set<String> = []
        for (neutral, expected) in table {
            let mapped = text(map(neutral))
            XCTAssertEqual(mapped, text(expected), "\(neutral)", file: file, line: line)
            seen.insert(mapped)
        }
        XCTAssertEqual(seen.count, table.count, "entries must map to different values", file: file, line: line)
    }

    func testAxes() {
        XCTAssertEqual(ChartAxes.horizontal.axisSet, .horizontal)
        XCTAssertEqual(ChartAxes.vertical.axisSet, .vertical)
        XCTAssertEqual(([.horizontal, .vertical] as ChartAxes).axisSet, [.horizontal, .vertical])
        XCTAssertEqual(ChartAxis.horizontal.axis, .horizontal)
        XCTAssertEqual(ChartAxis.vertical.axis, .vertical)
    }

    func testMarkValues() {
        check([(ChartDimension.automatic, MarkDimension.automatic), (.fixed(3), .fixed(3)), (.ratio(0.5), .ratio(0.5)), (.inset(2), .inset(2))],
              \.markDimension)
        check([(ChartStacking.standard, MarkStackingMethod.standard), (.normalized, .normalized), (.center, .center), (.unstacked, .unstacked)],
              \.stackingMethod)
        check([(ChartInterpolation.linear, InterpolationMethod.linear), (.monotone, .monotone), (.stepStart, .stepStart),
               (.stepCenter, .stepCenter), (.stepEnd, .stepEnd), (.cardinal(tension: nil), .cardinal), (.cardinal(tension: 0.5), .cardinal(tension: 0.5)),
               (.catmullRom(alpha: nil), .catmullRom), (.catmullRom(alpha: 0.25), .catmullRom(alpha: 0.25))], \.interpolationMethod)
        check([(ChartSymbol.circle, BasicChartSymbolShape.circle), (.square, .square), (.triangle, .triangle), (.diamond, .diamond),
               (.pentagon, .pentagon), (.plus, .plus), (.cross, .cross), (.asterisk, .asterisk)], \.symbolShape)
        check([(ChartCornerStyle.continuous, RoundedCornerStyle.continuous), (.circular, .circular)], \.cornerStyle)
    }

    func testStroke() {
        let stroke = ChartStroke(lineWidth: 2, lineCap: .round, lineJoin: .bevel, miterLimit: 4, dash: [3, 1], dashPhase: 1)
        XCTAssertEqual(stroke.strokeStyle, StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .bevel, miterLimit: 4, dash: [3, 1], dashPhase: 1))
        XCTAssertEqual(ChartStroke(lineCap: .square, lineJoin: .round).strokeStyle, StrokeStyle(lineWidth: 1, lineCap: .square, lineJoin: .round))
        XCTAssertEqual(ChartStroke().strokeStyle, StrokeStyle(lineWidth: 1))
    }

    func testPlacement() {
        check([(ChartPosition.automatic, AnnotationPosition.automatic), (.overlay, .overlay), (.top, .top), (.bottom, .bottom), (.leading, .leading),
               (.trailing, .trailing), (.topLeading, .topLeading), (.topTrailing, .topTrailing), (.bottomLeading, .bottomLeading),
               (.bottomTrailing, .bottomTrailing)], \.annotationPosition)
        check([(ChartAlignment.center, Alignment.center), (.leading, .leading), (.trailing, .trailing), (.top, .top), (.bottom, .bottom),
               (.topLeading, .topLeading), (.topTrailing, .topTrailing), (.bottomLeading, .bottomLeading), (.bottomTrailing, .bottomTrailing)],
              \.alignment)
        check([(ChartAlignment.center, UnitPoint.center), (.leading, .leading), (.trailing, .trailing), (.top, .top), (.bottom, .bottom),
               (.topLeading, .topLeading), (.topTrailing, .topTrailing), (.bottomLeading, .bottomLeading), (.bottomTrailing, .bottomTrailing)],
              \.unitPoint)
        check([(ChartVisibility.automatic, Visibility.automatic), (.visible, .visible), (.hidden, .hidden)], \.visibility)
        check([(ChartOverflowResolution(x: .fit, y: .padScale), AnnotationOverflowResolution(x: .fit, y: .padScale)),
               (ChartOverflowResolution(x: .disabled, y: .automatic), AnnotationOverflowResolution(x: .disabled, y: .automatic)),
               (ChartOverflowResolution(x: .fitTo(.plot), y: .automatic), AnnotationOverflowResolution(x: .fit(to: .plot), y: .automatic)),
               (ChartOverflowResolution(x: .fitTo(.chart), y: .automatic), AnnotationOverflowResolution(x: .fit(to: .chart), y: .automatic)),
               (ChartOverflowResolution(x: .fitTo(.automatic), y: .automatic), AnnotationOverflowResolution(x: .fit(to: .automatic), y: .automatic))],
              \.resolution)
    }

    func testScaleTypes() {
        check([(ChartScaleType.linear, ScaleType.linear), (.log, .log), (.date, .date), (.category, .category), (.squareRoot, .squareRoot),
               (.symmetricLog(slopeAtZero: nil), .symmetricLog), (.symmetricLog(slopeAtZero: 2), .symmetricLog(slopeAtZero: 2)),
               (.power(exponent: 3), .power(exponent: 3))], \.scaleType)
    }

    func testAxisValues() {
        check([(ChartAxisPreset.automatic, AxisMarkPreset.automatic), (.extended, .extended), (.aligned, .aligned), (.inset, .inset)], \.axisMarkPreset)
        check([(ChartAxisMarkPosition.automatic, AxisMarkPosition.automatic), (.leading, .leading), (.trailing, .trailing), (.top, .top), (.bottom, .bottom)],
              \.axisMarkPosition)
        check([(ChartLabelOrientation.automatic, AxisValueLabelOrientation.automatic), (.horizontal, .horizontal), (.vertical, .vertical),
               (.verticalReversed, .verticalReversed)], \.labelOrientation)
        check([(ChartCollisionResolution.automatic, AxisValueLabelCollisionResolution.automatic), (.truncate, .truncate), (.disabled, .disabled),
               (.greedy(priority: nil, minimumSpacing: nil), .greedy), (.greedy(priority: 2, minimumSpacing: 4), .greedy(priority: 2, minimumSpacing: 4))],
              \.collisionResolution)
    }

    func testDateFormats() {
        let style = Date.FormatStyle()
        let expected: [(ChartDateField, Date.FormatStyle)] = [
            (.yearDefaultDigits, style.year(.defaultDigits)), (.yearTwoDigits, style.year(.twoDigits)),
            (.quarterOneDigit, style.quarter(.oneDigit)), (.quarterTwoDigits, style.quarter(.twoDigits)), (.quarterAbbreviated, style.quarter(.abbreviated)),
            (.quarterWide, style.quarter(.wide)), (.quarterNarrow, style.quarter(.narrow)),
            (.monthDefaultDigits, style.month(.defaultDigits)), (.monthTwoDigits, style.month(.twoDigits)), (.monthAbbreviated, style.month(.abbreviated)),
            (.monthWide, style.month(.wide)), (.monthNarrow, style.month(.narrow)),
            (.dayDefaultDigits, style.day(.defaultDigits)), (.dayTwoDigits, style.day(.twoDigits)),
            (.weekdayAbbreviated, style.weekday(.abbreviated)), (.weekdayWide, style.weekday(.wide)), (.weekdayNarrow, style.weekday(.narrow)),
            (.weekdayShort, style.weekday(.short)),
            (.hourDefaultDigits, style.hour(.defaultDigits(amPM: .abbreviated))), (.hourTwoDigits, style.hour(.twoDigits(amPM: .abbreviated))),
            (.minuteDefaultDigits, style.minute(.defaultDigits)), (.minuteTwoDigits, style.minute(.twoDigits)),
            (.secondDefaultDigits, style.second(.defaultDigits)), (.secondTwoDigits, style.second(.twoDigits)),
        ]
        XCTAssertEqual(expected.count, ChartDateField.allCases.count)
        for (field, style) in expected {
            XCTAssertEqual(ChartDateFormat.fields([field]).formatStyle, style, "\(field)")
        }
        XCTAssertEqual(ChartDateFormat.fields([.monthWide, .yearTwoDigits]).formatStyle, style.month(.wide).year(.twoDigits))

        let dates: [(ChartDateStyle, Date.FormatStyle.DateStyle)] = [
            (.omitted, .omitted), (.numeric, .numeric), (.abbreviated, .abbreviated), (.long, .long), (.complete, .complete),
        ]
        let times: [(ChartTimeStyle, Date.FormatStyle.TimeStyle)] = [
            (.omitted, .omitted), (.shortened, .shortened), (.standard, .standard), (.complete, .complete),
        ]
        for (date, dateStyle) in dates {
            for (time, timeStyle) in times {
                XCTAssertEqual(ChartDateFormat.styles(date: date, time: time).formatStyle, Date.FormatStyle(date: dateStyle, time: timeStyle))
            }
        }
    }

    // A field and width that belong together parse; any other pair is refused.
    @MainActor
    func testDateFieldNames() {
        XCTAssertEqual(ChartDescription.parseDateFormat(["dateTime": ["year": "twoDigits"]]), .fields([.yearTwoDigits]))
        XCTAssertNil(ChartDescription.parseDateFormat(["dateTime": ["year": "wide"]]))
        XCTAssertNil(ChartDescription.parseDateFormat(["dateTime": ["era": "wide"]]))
        XCTAssertNil(ChartDescription.parseDateFormat(["dateTime": ["year": 2]]))
        XCTAssertEqual(ChartDescription.parseDateFormat(["time": "shortened"]), .styles(date: .omitted, time: .shortened))
        XCTAssertNil(ChartDescription.parseDateFormat(["date": "short"]))
    }
}
