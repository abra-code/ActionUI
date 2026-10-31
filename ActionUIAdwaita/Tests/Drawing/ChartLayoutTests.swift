// Tests/Drawing/ChartLayoutTests.swift
/*
 Tests for the chart geometry: ticks, marks read over rows, stacking, bands, orientation, the
 forms of bars, points and rules, and series colors. Text is a fake of 6 points per character and
 10 points of height, so every position is a number to check, and no display is needed.
*/

import XCTest
@testable import ActionUI

@MainActor
final class ChartLayoutTests: XCTestCase {
    private let metrics = ChartTextMetrics(
        size: { ChartSize(width: Double($0.count) * 6, height: 10) },
        number: { abs($0) < 1e15 && $0 == $0.rounded() ? String(Int($0)) : String($0) },
        date: { _, skeleton in skeleton })

    private let columns: [Any] = ["day", ["name": "high", "type": "number"], "team"]

    private func value(_ label: String, _ value: Any) -> [String: Any] { ["label": label, "value": value] }

    private func chart(_ marks: [[String: Any]], _ extra: [String: Any] = [:]) -> [String: Any] {
        var description: [String: Any] = ["columns": columns, "content": [["type": "ForEach", "content": marks]]]
        description.merge(extra) { $1 }
        return description
    }

    private var bar: [String: Any] { ["type": "BarMark", "x": value("Day", "$day"), "y": value("High", "$high")] }

    private func layout(_ description: [String: Any], rows: [[String]] = [], width: Double = 306, height: Double = 220) -> [ChartPrimitive] {
        let spec = ChartDescription.parse(description, logger: nil).spec
        return ChartLayout.primitives(spec, marks: ChartMarkResolver.resolve(spec, rows: rows), width: width, height: height, metrics: metrics)
    }

    private func rects(_ primitives: [ChartPrimitive]) -> [ChartRect] {
        primitives.compactMap { primitive in
            if case .rect(let rect, _) = primitive { return rect } else { return nil }
        }
    }

    private func inks(_ primitives: [ChartPrimitive]) -> [ChartInk] {
        primitives.compactMap { primitive in
            if case .rect(_, let ink) = primitive { return ink } else { return nil }
        }
    }

    private func texts(_ primitives: [ChartPrimitive]) -> [String] {
        primitives.compactMap { primitive in
            if case .text(let text, _, _) = primitive { return text } else { return nil }
        }
    }

    private func labelY(_ label: String, in primitives: [ChartPrimitive]) -> Double? {
        primitives.lazy.compactMap { primitive -> Double? in
            if case .text(label, let position, _) = primitive { return position.y } else { return nil }
        }.first
    }

    private func lines(_ primitives: [ChartPrimitive], ink wanted: ChartInk) -> [(from: ChartPoint, to: ChartPoint, stroke: ChartStroke)] {
        primitives.compactMap { primitive in
            if case .line(let from, let to, let ink, let stroke) = primitive, ink == wanted { return (from, to, stroke) }
            return nil
        }
    }

    private func symbols(_ primitives: [ChartPrimitive]) -> [(shape: ChartSymbol, size: ChartSize, ink: ChartInk)] {
        primitives.compactMap { primitive in
            if case .symbol(let shape, _, let size, let ink) = primitive { return (shape, size, ink) } else { return nil }
        }
    }

    // A date column and a number, over one ForEach.
    private func dated(_ marks: [[String: Any]], _ extra: [String: Any] = [:]) -> [String: Any] {
        var description: [String: Any] = ["columns": [["name": "when", "type": "date"], ["name": "high", "type": "number"], "team"],
                                          "content": [["type": "ForEach", "content": marks]]]
        description.merge(extra) { $1 }
        return description
    }

    private func assertRect(_ rect: ChartRect?, x: Double, y: Double, width: Double, height: Double, file: StaticString = #filePath, line: UInt = #line) {
        guard let rect else { return XCTFail("no rect", file: file, line: line) }
        XCTAssertEqual(rect.x, x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rect.y, y, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rect.width, width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(rect.height, height, accuracy: 0.001, file: file, line: line)
    }

    // MARK: - Ticks

    func testTicksAreWholeStepsOfOneTwoOrFive() {
        XCTAssertEqual(ChartTicks.domain(0, 1250, intervals: 4).ticks, [0, 500, 1000, 1500])
        XCTAssertEqual(ChartTicks.domain(0, 5, intervals: 4).ticks, [0, 2, 4, 6])
        XCTAssertEqual(ChartTicks.domain(0, 0.7, intervals: 4).hi, 0.8, accuracy: 1e-9)
        XCTAssertEqual(ChartTicks.domain(-30, 70, intervals: 4).ticks, [-50, 0, 50, 100])
    }

    func testADomainWithoutARangeStillHasOne() {
        let domain = ChartTicks.domain(0, 0, intervals: 4)
        XCTAssertLessThan(domain.lo, domain.hi)
    }

    func testADomainAtTheEndsOfDoubleStaysFinite() {
        for (lo, hi) in [(0, 1.7e308), (-1.7e308, 1.7e308), (0, 1e-323)] {
            let domain = ChartTicks.domain(lo, hi, intervals: 4)
            XCTAssertLessThan(domain.lo, domain.hi)
            XCTAssertTrue(domain.hi.isFinite)
            XCTAssertGreaterThanOrEqual(domain.ticks.count, 2)
        }
    }

    func testNumberTicksDoNotDependOnTheSize() {
        let rows = [["Mon", "1250"]]
        // Swift Charts' ticks are the same from 60 to 700 points tall.
        for height in [60.0, 220, 700] {
            XCTAssertEqual(texts(layout(chart([bar]), rows: rows, height: height)).filter { $0 != "Mon" }, ["0", "500", "1000", "1500"], "\(height)")
        }
    }

    func testTicksAreAsSwiftChartsDrawsThem() {
        // Measured on macOS 27, each maximum with the step it gets.
        for (maximum, expected) in [("4", "1"), ("5", "2"), ("6", "2"), ("8", "2"), ("9", "5"), ("10", "5"), ("30", "10"), ("40", "10"), ("60", "20"), ("1250", "500")] {
            let labels = texts(layout(chart([bar]), rows: [["Mon", maximum]])).filter { $0 != "Mon" }
            XCTAssertEqual(labels[1], expected, "up to \(maximum)")
        }
    }

    // MARK: - Reading marks

    func testARowWithACellThatDoesNotParseIsSkippedWhole() {
        let spec = ChartDescription.parse(chart([bar]), logger: nil).spec
        let marks = ChartMarkResolver.resolve(spec, rows: [["Mon", "1"], ["Tue", "x"], ["Wed", "3"]])
        XCTAssertEqual(marks.instances.count, 2)
        XCTAssertEqual(marks.skippedRows, 1)
        XCTAssertEqual(marks.firstSkip?.row, 1)
        XCTAssertEqual(marks.firstSkip?.column, 1)
        XCTAssertEqual(marks.firstSkip?.inlineData, false)
    }

    func testAForEachWithItsOwnDataDrawsOverThoseRows() {
        let own: [String: Any] = ["type": "ForEach", "data": [["Mon", 5], ["Tue", "x"]] as [Any], "content": [bar]]
        let spec = ChartDescription.parse(["columns": columns, "content": [own]], logger: nil).spec
        let marks = ChartMarkResolver.resolve(spec, rows: [["ignored", "1"], ["ignored", "2"], ["ignored", "3"]])
        XCTAssertEqual(marks.instances.count, 1)
        XCTAssertEqual(marks.firstSkip?.inlineData, true)
    }

    func testAMarkThatReadsTheSelectionIsNotDrawn() {
        let rule: [String: Any] = ["type": "RuleMark", "x": value("Day", "$selection")]
        let description: [String: Any] = ["columns": columns, "chartXSelection": "value",
                                          "content": [["type": "ForEach", "content": [bar]], rule]]
        let spec = ChartDescription.parse(description, logger: nil).spec
        let marks = ChartMarkResolver.resolve(spec, rows: [["Mon", "1"]])
        XCTAssertEqual(marks.instances.count, 1)
        XCTAssertEqual(marks.skippedRows, 0)
    }

    // MARK: - Bars

    func testBandsAreInOrderOfUseAndABarTakesPartOfOne() {
        // 306 wide less the widest label ("4", 6) and its two gaps (8) leaves 292, so bands of 97.33.
        let found = rects(layout(chart([bar]), rows: [["Mon", "2"], ["Tue", "4"], ["Wed", "1"]]))
        XCTAssertEqual(found.count, 3)
        let band = 292.0 / 3
        XCTAssertEqual(found[0].x + found[0].width / 2, band * 0.5, accuracy: 0.001)
        XCTAssertEqual(found[1].x + found[1].width / 2, band * 1.5, accuracy: 0.001)
        XCTAssertEqual(found[0].width, band * 0.7, accuracy: 0.001)
        XCTAssertEqual(found[1].height, found[0].height * 2, accuracy: 0.001)
        XCTAssertEqual(found[0].y + found[0].height, found[1].y + found[1].height, accuracy: 0.001, "on one baseline")
    }

    func testBarsStackInRowOrderAndBelowZeroDownward() {
        let found = rects(layout(chart([bar]), rows: [["Mon", "2"], ["Mon", "3"], ["Mon", "-1"], ["Mon", "-2"]]))
        XCTAssertEqual(found.count, 4)
        // Two up from zero, the second on the first; two down, the second under the first.
        XCTAssertEqual(found[0].y, found[1].y + found[1].height, accuracy: 0.001)
        XCTAssertEqual(found[2].y, found[0].y + found[0].height, accuracy: 0.001)
        XCTAssertEqual(found[3].y, found[2].y + found[2].height, accuracy: 0.001)
    }

    func testAnUnstackedBarStartsAtZero() {
        var mark = bar
        mark["stacking"] = "unstacked"
        let found = rects(layout(chart([mark]), rows: [["Mon", "2"], ["Mon", "3"]]))
        XCTAssertEqual(found[0].y + found[0].height, found[1].y + found[1].height, accuracy: 0.001)
    }

    func testANormalizedStackFillsTheAxisAndItsTicksArePercents() {
        var mark = bar
        mark["stacking"] = "normalized"
        let primitives = layout(chart([mark]), rows: [["Mon", "1"], ["Mon", "3"], ["Tue", "10"]])
        let found = rects(primitives)
        XCTAssertEqual(found[0].height / found[1].height, 1.0 / 3, accuracy: 0.001)
        XCTAssertEqual(found[0].height + found[1].height, found[2].height, accuracy: 0.001)
        XCTAssertEqual(texts(primitives).filter { $0 != "Mon" && $0 != "Tue" }, ["0", "25", "50", "75", "100"], "as Swift Charts labels it")
    }

    func testANormalizedStackWithNegativesDividesByTheLongerSide() throws {
        var mark = bar
        mark["stacking"] = "normalized"
        // As Swift Charts draws them: 1 and -4 are 25% up and 100% down.
        let primitives = layout(chart([mark]), rows: [["Mon", "1"], ["Mon", "-4"]])
        let found = rects(primitives)
        let zero = try XCTUnwrap(labelY("0", in: primitives))
        XCTAssertEqual(found[0].height / found[1].height, 0.25, accuracy: 0.001)
        XCTAssertEqual(found[0].y + found[0].height, zero, accuracy: 0.001)
        XCTAssertEqual(found[1].y, zero, accuracy: 0.001)
    }

    func testANormalizedStackEndsAtOneExactly() {
        var mark = bar
        mark["stacking"] = "normalized"
        // Fractions added one by one reach 1.0000000000000002 here, which widens the axis to a 125 tick.
        for rows in [[9.57, 73], [49, 79.71], [90, 38.95]] as [[Double]] {
            let primitives = layout(chart([mark]), rows: rows.map { ["Mon", String($0)] })
            XCTAssertEqual(texts(primitives).filter { $0 != "Mon" }.last, "100", "\(rows)")
        }
    }

    func testACenteredStackIsBalancedAroundZero() throws {
        var mark = bar
        mark["stacking"] = "center"
        let primitives = layout(chart([mark]), rows: [["Mon", "1"], ["Mon", "3"]])
        let found = rects(primitives)
        XCTAssertEqual(found[0].height / found[1].height, 1.0 / 3, accuracy: 0.001)
        let zero = try XCTUnwrap(labelY("0", in: primitives))
        XCTAssertEqual(zero - found[1].y, found[0].y + found[0].height - zero, accuracy: 0.001)
    }

    func testACenteredStackWithNegativesIsTheStandardStackMoved() throws {
        var mark = bar
        mark["stacking"] = "center"
        // As Swift Charts draws 3, -1, 2: -1 from -3 to -2, 3 from -2 to 1, 2 from 1 to 3.
        let primitives = layout(chart([mark]), rows: [["Mon", "3"], ["Mon", "-1"], ["Mon", "2"]])
        let found = rects(primitives)
        let unit = found[0].height / 3
        let zero = try XCTUnwrap(labelY("0", in: primitives))
        XCTAssertEqual(found[1].height, unit, accuracy: 0.001)
        XCTAssertEqual(found[2].height, unit * 2, accuracy: 0.001)
        XCTAssertEqual(found[0].y, zero - unit, accuracy: 0.001, "the 3 tops out at 1")
        XCTAssertEqual(found[0].y + found[0].height, found[1].y, accuracy: 0.001, "the -1 hangs under it")
        XCTAssertEqual(found[2].y + found[2].height, found[0].y, accuracy: 0.001, "the 2 sits on it")
    }

    func testBarsInOneDateBinStackTogether() {
        let mark: [String: Any] = ["type": "BarMark", "x": ["label": "When", "value": "$when", "unit": "year"], "y": value("High", "$high")]
        let rows = [["2026-06-10T10:00:00Z", "1"], ["2026-07-15T15:00:00Z", "2"], ["2027-06-10T10:00:00Z", "4"]]
        let found = rects(layout(dated([mark]), rows: rows))
        XCTAssertEqual(found[0].x, found[1].x, accuracy: 0.001)
        XCTAssertEqual(found[0].y, found[1].y + found[1].height, accuracy: 0.001, "the second sits on the first")
        XCTAssertEqual(found[1].y, found[2].y + found[2].height / 4, accuracy: 0.001, "1 and 2 reach 3 of the next year's 4")
    }

    func testAnIntegerAndANumberAtOnePositionStackTogether() {
        let number: [String: Any] = ["type": "BarMark", "x": value("X", 2.5 - 0.5), "y": value("Y", 1)]
        let integer: [String: Any] = ["type": "BarMark", "x": value("X", 2), "y": value("Y", 3)]
        let found = rects(layout(["columns": columns, "content": [number, integer]]))
        XCTAssertEqual(found[0].y, found[1].y + found[1].height, accuracy: 0.001)
    }

    func testANumberOnXAndACategoryOnYIsAHorizontalBar() {
        let mark: [String: Any] = ["type": "BarMark", "x": value("High", "$high"), "y": value("Day", "$day")]
        let found = rects(layout(chart([mark]), rows: [["Mon", "2"], ["Tue", "4"]]))
        XCTAssertEqual(found[0].x, 0, accuracy: 0.001)
        XCTAssertLessThan(found[0].y, found[1].y, "bands read from the top")
        XCTAssertLessThan(found[0].width, found[1].width)
        XCTAssertEqual(found[0].height, found[1].height, accuracy: 0.001)
    }

    func testABarDimensionSetsItsWidth() {
        // Labels of one digit: 300 wide less 6 and 8 is a plot of 286, so bands of 95.33.
        let band = 286.0 / 3
        for (dimension, expected) in [(20 as Any, 20.0), (["ratio": 0.5] as Any, band / 2), (["inset": 10] as Any, band - 20)] {
            var mark = bar
            mark["width"] = dimension
            let found = rects(layout(chart([mark]), rows: [["Mon", "5"], ["Tue", "5"], ["Wed", "5"]], width: 300))
            XCTAssertEqual(found.first?.width ?? 0, expected, accuracy: 0.001, "\(dimension)")
        }
    }

    func testARangeBarSpansItsTwoValues() {
        let mark: [String: Any] = ["type": "BarMark", "x": value("Day", "$day"), "yStart": value("Low", 10), "yEnd": value("High", 30)]
        let found = rects(layout(chart([mark]), rows: [["Mon", "1"]]))
        let whole = rects(layout(chart([bar]), rows: [["Mon", "30"]]))
        XCTAssertEqual(found[0].y, whole[0].y, accuracy: 0.001, "the top is at 30")
        XCTAssertEqual(found[0].height / whole[0].height, 2.0 / 3, accuracy: 0.001)
    }

    func testABarWithPointsFillsThePlotAcrossUnlessGiven() {
        let mark: [String: Any] = ["type": "BarMark", "x": value("High", "$high"), "yStart": 10, "yEnd": 30]
        let found = rects(layout(chart([mark]), rows: [["Mon", "4"]]))
        XCTAssertEqual(found[0].x, 0, accuracy: 0.001)
        XCTAssertEqual(found[0].height, 20, accuracy: 0.001)
    }

    func testABarAtANumberOrADateWithoutAUnitIsEightWide() {
        let number: [String: Any] = ["type": "BarMark", "x": value("X", "$high"), "y": value("Y", "$high")]
        for rows in [[["Mon", "1"], ["Tue", "2"], ["Wed", "4"]], [["Mon", "3"]]] {
            XCTAssertEqual(rects(layout(chart([number]), rows: rows)).map(\.width), rows.map { _ in 8 })
        }
        let date: [String: Any] = ["type": "BarMark", "x": value("When", "$when"), "y": value("High", "$high")]
        XCTAssertEqual(rects(layout(dated([date]), rows: [["2026-01-03T12:00:00Z", "1"], ["2026-01-05T12:00:00Z", "2"]])).map(\.width), [8, 8])
    }

    func testARatioOfNoBinDrawsNoWidth() {
        var mark: [String: Any] = ["type": "BarMark", "x": value("X", "$high"), "y": value("Y", "$high")]
        mark["width"] = ["ratio": 0.5]
        XCTAssertEqual(rects(layout(chart([mark]), rows: [["Mon", "1"]])).first?.width, 0)
    }

    func testABarWithoutANumberIsABlockWhereItsValuesMeet() throws {
        let mark: [String: Any] = ["type": "BarMark", "x": value("Day", "$day"), "y": value("Team", "$team")]
        let rows = [["Mon", "1", "A"], ["Tue", "1", "B"]]
        let found = rects(layout(chart([mark]), rows: rows, width: 306, height: 220))
        XCTAssertEqual(found.count, 2)
        XCTAssertLessThan(found[0].x + found[0].width, found[1].x)
        XCTAssertLessThan(found[0].y + found[0].height, found[1].y)
        let date: [String: Any] = ["type": "BarMark", "x": value("Day", "$team"), "y": value("When", "$when")]
        let thin = try XCTUnwrap(rects(layout(dated([date]), rows: [["2026-01-03T12:00:00Z", "1", "A"], ["2026-01-05T12:00:00Z", "1", "B"]])).first)
        XCTAssertEqual(thin.height, 8, accuracy: 0.001)
    }

    func testAStartAndEndOfCategoriesCoverBothBands() throws {
        let span: [String: Any] = ["type": "BarMark", "xStart": value("A", "Mon"), "xEnd": value("B", "Tue"), "y": value("N", 1), "height": 10, "foregroundStyle": "red"]
        let description: [String: Any] = ["columns": columns, "content": [["type": "ForEach", "content": [bar]], span], "chartYAxis": "hidden"]
        let primitives = layout(description, rows: [["Mon", "2"], ["Tue", "2"], ["Wed", "2"]], width: 300)
        let found = try XCTUnwrap(zip(rects(primitives), inks(primitives)).first { $0.1 == .color(.named(.red)) }?.0)
        assertRect(found, x: 0, y: found.y, width: 200, height: 10)
    }

    func testAStartAndEndWithAUnitGoInTheMiddleOfTheirBins() throws {
        let mark: [String: Any] = ["type": "BarMark", "xStart": ["label": "A", "value": "$when", "unit": "month"],
                                   "xEnd": ["label": "B", "value": "2026-06-02T12:00:00Z", "type": "date", "unit": "month"], "y": value("Y", "a")]
        // Near the start of March and of June, in an axis of 122 days from March 1 to the end of June.
        let found = try XCTUnwrap(rects(layout(dated([mark], ["chartYAxis": "hidden"]), rows: [["2026-03-02T12:00:00Z", "1", "A"]], width: 306)).first)
        XCTAssertEqual(found.x / 306, 15.5 / 122, accuracy: 0.01)
        XCTAssertEqual((found.x + found.width) / 306, 107.0 / 122, accuracy: 0.01)
    }

    func testADateAxisCoversEachValuesOwnBin() throws {
        // A rule without a unit before bars with one: the bars' bin still sets the axis.
        let rule: [String: Any] = ["type": "RuleMark", "x": ["label": "T", "value": "2026-03-10T12:00:00Z", "type": "date"]]
        let mark: [String: Any] = ["type": "BarMark", "x": ["label": "When", "value": "$when", "unit": "year"], "y": value("High", "$high")]
        let description: [String: Any] = ["columns": [["name": "when", "type": "date"], ["name": "high", "type": "number"]],
                                          "content": [rule, ["type": "ForEach", "content": [mark]]], "chartYAxis": "hidden"]
        let found = try XCTUnwrap(rects(layout(description, rows: [["2026-06-10T10:00:00Z", "1"]], width: 306)).first)
        assertRect(found, x: 306 * 0.15, y: found.y, width: 306 * 0.7, height: found.height)
    }

    // MARK: - Colors

    func testSeriesTakeTheColorsInOrderOfUse() {
        var mark = bar
        mark["foregroundStyle"] = ["by": value("Team", "$team")]
        let found = inks(layout(chart([mark]), rows: [["Mon", "1", "B"], ["Mon", "1", "A"], ["Tue", "1", "B"]]))
        XCTAssertEqual(found, [.color(.named(.blue)), .color(.named(.green)), .color(.named(.blue))])
    }

    func testAScaleSetsTheOrderAndTheColors() {
        var mark = bar
        mark["foregroundStyle"] = ["by": value("Team", "$team")]
        let scale: [String: Any] = ["chartForegroundStyleScale": ["domain": ["A", "B"], "range": ["red", "#00ff00"]]]
        let found = inks(layout(chart([mark], scale), rows: [["Mon", "1", "B"], ["Mon", "1", "A"]]))
        XCTAssertEqual(found.first, .color(ColorSpec.parse("#00ff00")!))
        XCTAssertEqual(found.last, .color(.named(.red)))
    }

    func testAMarkWithoutAStyleIsTheFirstSeriesColor() {
        XCTAssertEqual(inks(layout(chart([bar]), rows: [["Mon", "1"]])), [.color(.named(.blue))])
        var mark = bar
        mark["foregroundStyle"] = "orange"
        XCTAssertEqual(inks(layout(chart([mark]), rows: [["Mon", "1"]])), [.color(.named(.orange))])
    }

    func testAMarksOwnStyleWinsOverItsPlots() {
        var red = bar
        red["foregroundStyle"] = "red"
        let plot: [String: Any] = ["type": "Plot", "foregroundStyle": "blue", "content": [["type": "ForEach", "content": [red]]]]
        let description: [String: Any] = ["columns": columns, "content": [plot]]
        XCTAssertEqual(inks(layout(description, rows: [["Mon", "1"]])), [.color(.named(.red))])

        var series = bar
        series["foregroundStyle"] = ["by": value("Team", "$team")]
        let inner: [String: Any] = ["type": "Plot", "foregroundStyle": "red", "content": [["type": "ForEach", "content": [series]]]]
        XCTAssertEqual(inks(layout(["columns": columns, "content": [inner]], rows: [["Mon", "1", "A"], ["Mon", "1", "B"]])),
                       [.color(.named(.blue)), .color(.named(.green))])
    }

    func testAMarksOwnSymbolAndStrokeWinOverItsPlots() {
        let point: [String: Any] = ["type": "PointMark", "x": value("Day", "$day"), "y": value("High", "$high"), "symbol": "diamond", "symbolSize": 100]
        let points: [String: Any] = ["type": "Plot", "symbol": "square", "symbolSize": 400, "content": [["type": "ForEach", "content": [point]]]]
        let found = symbols(layout(["columns": columns, "content": [points]], rows: [["Mon", "1"]]))
        XCTAssertEqual(found.first?.shape, .diamond)
        XCTAssertEqual(found.first?.size, ChartSize(width: 10, height: 10))

        let rule: [String: Any] = ["type": "RuleMark", "y": value("Y", 1), "lineStyle": ["lineWidth": 1], "foregroundStyle": "red"]
        let rules: [String: Any] = ["type": "Plot", "lineStyle": ["lineWidth": 6], "content": [rule]]
        XCTAssertEqual(lines(layout(["columns": columns, "content": [rules]]), ink: .color(.named(.red))).first?.stroke.lineWidth, 1)
    }

    // MARK: - Points and rules

    func testASymbolsSizeIsItsArea() throws {
        // As measured on Swift Charts: a default circle is 8 across, one of 100 is 11.3, a square of 100 is 10.
        func sized(_ extra: [String: Any]) throws -> ChartSize {
            var mark: [String: Any] = ["type": "PointMark", "x": value("Day", "$day"), "y": value("High", "$high")]
            mark.merge(extra) { $1 }
            return try XCTUnwrap(symbols(layout(chart([mark]), rows: [["Mon", "1"]])).first?.size)
        }
        XCTAssertEqual(try sized([:]).width, 7.98, accuracy: 0.01)
        XCTAssertEqual(try sized(["symbolSize": 100]).width, 11.28, accuracy: 0.01)
        XCTAssertEqual(try sized(["symbolSize": 100, "symbol": "square"]).width, 10, accuracy: 0.01)
    }

    func testARuleWithoutAStyleIsTwoWide() {
        let rule: [String: Any] = ["type": "RuleMark", "y": value("Y", 1), "foregroundStyle": "red"]
        XCTAssertEqual(lines(layout(["columns": columns, "content": [rule]]), ink: .color(.named(.red))).first?.stroke.lineWidth, 2)
    }

    func testAPointGoesAtItsValuesWithItsSymbolAndArea() throws {
        var mark: [String: Any] = ["type": "PointMark", "x": value("Day", "$day"), "y": value("High", "$high")]
        mark["symbol"] = "diamond"
        mark["symbolSize"] = 100
        let primitives = layout(chart([mark]), rows: [["Mon", "1"]])
        let symbol = primitives.compactMap { primitive -> (ChartSymbol, ChartSize)? in
            if case .symbol(let shape, _, let size, _) = primitive { return (shape, size) } else { return nil }
        }.first
        XCTAssertEqual(symbol?.0, .diamond)
        XCTAssertEqual(symbol?.1, ChartSize(width: 10, height: 10))
    }

    func testAPointWithoutOneCoordinateIsInTheMiddleOfThePlot() {
        let mark: [String: Any] = ["type": "PointMark", "x": value("Day", "$day")]
        let center = layout(chart([mark]), rows: [["Mon"]], width: 300, height: 200).compactMap { primitive -> ChartPoint? in
            if case .symbol(_, let center, _, _) = primitive { return center } else { return nil }
        }.first
        XCTAssertEqual(center?.y ?? 0, 91, accuracy: 0.001, "the middle of a plot of 182 above the labels")
    }

    func testARuleAtAValueRunsAcrossThePlotInItsStroke() throws {
        let top: [String: Any] = ["type": "RuleMark", "y": value("Goal", 3), "lineStyle": ["lineWidth": 2, "dash": [4, 2]], "foregroundStyle": "gray"]
        let description: [String: Any] = ["columns": columns, "content": [["type": "ForEach", "content": [bar]], top]]
        let line = layout(description, rows: [["Mon", "6"]]).compactMap { primitive -> (ChartPoint, ChartPoint, ChartInk, ChartStroke)? in
            if case .line(let from, let to, let ink, let stroke) = primitive, ink == .color(.named(.gray)) { return (from, to, ink, stroke) }
            return nil
        }.first
        let found = try XCTUnwrap(line)
        XCTAssertEqual(found.0.x, 0, accuracy: 0.001)
        XCTAssertEqual(found.0.y, found.1.y, accuracy: 0.001)
        XCTAssertGreaterThan(found.1.x, 250)
        XCTAssertEqual(found.3, ChartStroke(lineWidth: 2, dash: [4, 2]))
    }

    func testARuleWithPointsRunsThatFar() throws {
        let mark: [String: Any] = ["type": "RuleMark", "x": value("Day", "$day"), "yStart": 10, "yEnd": 30, "foregroundStyle": "red"]
        let line = layout(chart([mark]), rows: [["Mon"]]).compactMap { primitive -> (ChartPoint, ChartPoint)? in
            if case .line(let from, let to, .color(.named(.red)), _) = primitive { return (from, to) }
            return nil
        }.first
        let found = try XCTUnwrap(line)
        XCTAssertEqual(found.1.y - found.0.y, 20, accuracy: 0.001)
    }

    // MARK: - Lines and areas

    private func paths(_ primitives: [ChartPrimitive]) -> [(elements: [ChartPathElement], ink: ChartInk, stroke: ChartStroke)] {
        primitives.compactMap { primitive in
            if case .path(let elements, let ink, let stroke) = primitive { return (elements, ink, stroke) } else { return nil }
        }
    }

    private func fills(_ primitives: [ChartPrimitive]) -> [[ChartPathElement]] {
        primitives.compactMap { primitive in
            if case .fill(let elements, _) = primitive { return elements } else { return nil }
        }
    }

    private func points(_ elements: [ChartPathElement]) -> [ChartPoint] {
        elements.compactMap { element in
            switch element {
            case .move(let point), .line(let point): return point
            case .curve(_, _, let end): return end
            }
        }
    }

    private let numberColumns: [Any] = [["name": "x", "type": "number"], ["name": "y", "type": "number"], "team", ["name": "z", "type": "number"]]
    private var line: [String: Any] { ["type": "LineMark", "x": value("X", "$x"), "y": value("Y", "$y")] }

    private func numbers(_ marks: [[String: Any]]) -> [String: Any] {
        ["columns": numberColumns, "content": [["type": "ForEach", "content": marks]]]
    }

    func testALineJoinsItsPointsInDataOrderTwoWide() throws {
        let found = paths(layout(numbers([line]), rows: [["30", "5"], ["10", "2"], ["20", "8"]]))
        XCTAssertEqual(found.count, 1)
        let joined = points(try XCTUnwrap(found.first).elements)
        XCTAssertGreaterThan(joined[0].x, joined[2].x)
        XCTAssertGreaterThan(joined[2].x, joined[1].x, "30, then 10, then 20")
        XCTAssertEqual(found.first?.stroke.lineWidth, 2)
        XCTAssertEqual(found.first?.ink, .color(.named(.blue)))
    }

    func testASeriesOrAByStyleMakesALinePerValue() {
        var bySeries = line
        bySeries["series"] = value("Team", "$team")
        var byStyle = line
        byStyle["foregroundStyle"] = ["by": value("Team", "$team")]
        let rows = [["1", "1", "A"], ["1", "2", "B"], ["2", "3", "A"], ["2", "4", "B"]]
        XCTAssertEqual(paths(layout(numbers([bySeries]), rows: rows)).count, 2)
        let styled = paths(layout(numbers([byStyle]), rows: rows))
        XCTAssertEqual(styled.map(\.ink), [.color(.named(.blue)), .color(.named(.green))])
    }

    func testTwoLinesWithoutASeriesAreOneInTheStyleOfTheFirst() throws {
        var first = line
        first["foregroundStyle"] = "red"
        var second: [String: Any] = ["type": "LineMark", "x": value("X", "$x"), "y": value("Z", "$z")]
        second["foregroundStyle"] = "blue"
        let found = paths(layout(numbers([first, second]), rows: [["1", "2", "A", "6"], ["2", "8", "A", "1"]]))
        XCTAssertEqual(found.count, 1, "joined across marks, as Swift Charts joins them")
        XCTAssertEqual(found.first?.ink, .color(.named(.red)))
        XCTAssertEqual(points(try XCTUnwrap(found.first).elements).count, 4)
    }

    func testALineOfOnePointDrawsNothing() {
        XCTAssertEqual(paths(layout(numbers([line]), rows: [["1", "1"]])).count, 0)
    }

    private func moves(_ elements: [ChartPathElement]) -> Int {
        elements.filter { if case .move = $0 { return true } else { return false } }.count
    }

    func testAPointThatIsNotFiniteBreaksTheLine() throws {
        let rows = [["1", "1"], ["2", "4"], ["3", "nan"], ["4", "2"], ["5", "5"]]
        let found = try XCTUnwrap(paths(layout(numbers([line]), rows: rows)).first)
        XCTAssertEqual(moves(found.elements), 2, "two pieces")
        XCTAssertEqual(points(found.elements).count, 4)
        let onX = try XCTUnwrap(paths(layout(numbers([line]), rows: [["1", "1"], ["2", "4"], ["nan", "3"], ["4", "2"], ["5", "5"]])).first)
        XCTAssertEqual(moves(onX.elements), 2, "on either axis")
    }

    func testAPieceOfOnePointDrawsNothing() throws {
        let rows = [["1", "1"], ["2", "nan"], ["3", "3"], ["4", "nan"], ["5", "5"], ["6", "2"]]
        let found = try XCTUnwrap(paths(layout(numbers([line]), rows: rows)).first)
        XCTAssertEqual(moves(found.elements), 1)
        XCTAssertEqual(points(found.elements).count, 2)
    }

    func testAPointThatIsNotFiniteBreaksAnArea() throws {
        let area: [String: Any] = ["type": "AreaMark", "x": value("X", "$x"), "y": value("Y", "$y")]
        let found = try XCTUnwrap(fills(layout(numbers([area]), rows: [["1", "1"], ["2", "4"], ["3", "nan"], ["4", "2"], ["5", "5"]])).first)
        XCTAssertEqual(moves(found), 2)
        XCTAssertEqual(points(found).count, 8, "each piece along its top and back")
    }

    func testAByStyleASmallerOneReplacesDoesNotSplitALine() {
        let rows = [["1", "1", "A"], ["1", "2", "B"], ["2", "3", "A"], ["2", "4", "B"]]
        let by = ["by": value("Team", "$team")]
        func plot(_ key: String, over mark: [String: Any]) -> [String: Any] {
            ["columns": numberColumns, "content": [["type": "ForEach", "content": [["type": "Plot", key: by, "content": [mark]]]]]]
        }
        var colored = line
        colored["foregroundStyle"] = "red"
        XCTAssertEqual(paths(layout(plot("foregroundStyle", over: colored), rows: rows)).count, 1)
        var styled = line
        styled["lineStyle"] = ["lineWidth": 2]
        XCTAssertEqual(paths(layout(plot("lineStyle", over: styled), rows: rows)).count, 1)
        var shaped = line
        shaped["symbol"] = "square"
        XCTAssertEqual(paths(layout(plot("symbol", over: shaped), rows: rows)).count, 1)
    }

    func testOnlyColorLineStyleAndSymbolSplitALine() {
        let rows = [["1", "1", "A"], ["1", "2", "B"], ["2", "3", "A"], ["2", "4", "B"]]
        let by = ["by": value("Team", "$team")]
        for (key, count) in [("lineStyle", 2), ("symbol", 2), ("symbolSize", 1)] {
            var mark = line
            mark[key] = by
            XCTAssertEqual(paths(layout(numbers([mark]), rows: rows)).count, count, key)
        }
        var placed = line
        placed["position"] = by
        XCTAssertEqual(paths(layout(numbers([placed]), rows: rows)).count, 1, "position")
    }

    func testALineTakesItsStyleAndInterpolation() throws {
        var mark = line
        mark["lineStyle"] = ["lineWidth": 3]
        mark["interpolationMethod"] = "stepEnd"
        let found = try XCTUnwrap(paths(layout(numbers([mark]), rows: [["1", "1"], ["2", "4"]])).first)
        XCTAssertEqual(found.stroke, ChartStroke(lineWidth: 3))
        XCTAssertEqual(found.elements.count, 3, "move, across, up")
    }

    func testALineOnBandsGoesThroughTheirCenters() throws {
        let mark: [String: Any] = ["type": "LineMark", "x": value("Day", "$day"), "y": value("High", "$high")]
        let found = try XCTUnwrap(paths(layout(chart([mark]), rows: [["Mon", "1"], ["Tue", "2"]])).first)
        let joined = points(found.elements)
        XCTAssertEqual(joined[1].x, joined[0].x * 3, accuracy: 0.001, "centers of two equal bands")
    }

    func testAnAreaRunsDownToZeroAndClosesAlongIt() throws {
        let area: [String: Any] = ["type": "AreaMark", "x": value("X", "$x"), "y": value("Y", "$y")]
        let found = points(try XCTUnwrap(fills(layout(numbers([area]), rows: [["10", "4"], ["20", "8"]])).first))
        XCTAssertEqual(found.count, 4)
        XCTAssertEqual(found[2].x, found[1].x, "down at the last point")
        XCTAssertEqual(found[3].x, found[0].x, "back to the first")
        XCTAssertEqual(found[2].y, found[3].y, "along the baseline")
        XCTAssertGreaterThan(found[2].y, found[0].y)
    }

    func testAreasStackInRowOrderOfTheirSeries() throws {
        var area: [String: Any] = ["type": "AreaMark", "x": value("X", "$x"), "y": value("Y", "$y")]
        area["foregroundStyle"] = ["by": value("Team", "$team")]
        let rows = [["1", "2", "A"], ["2", "4", "A"], ["1", "1", "B"], ["2", "2", "B"]]
        let found = fills(layout(numbers([area]), rows: rows)).map(points)
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found[1][3].y, found[0][0].y, accuracy: 0.001, "B starts where A ends")
        XCTAssertLessThan(found[1][0].y, found[0][0].y, "B is above A")
    }

    func testSteppedAreasShareTheirEdge() throws {
        for method in ["stepStart", "stepEnd", "stepCenter", "monotone"] {
            var area: [String: Any] = ["type": "AreaMark", "x": value("X", "$x"), "y": value("Y", "$y")]
            area["foregroundStyle"] = ["by": value("Team", "$team")]
            area["interpolationMethod"] = method
            let rows = [["1", "1", "A"], ["2", "3", "A"], ["3", "2", "A"], ["1", "2", "B"], ["2", "1", "B"], ["3", "3", "B"]]
            let found = fills(layout(numbers([area]), rows: rows))
            XCTAssertEqual(found.count, 2)
            // A's top is the first half of its path; B's bottom is the second half of its own, backward.
            let top = points(Array(found[0].prefix(found[0].count / 2)))
            let bottom = points(Array(found[1].suffix(found[1].count / 2)))
            XCTAssertEqual(top.count, bottom.count, method)
            for (a, b) in zip(top, bottom.reversed()) {
                XCTAssertEqual(a.x, b.x, accuracy: 0.001, method)
                XCTAssertEqual(a.y, b.y, accuracy: 0.001, method)
            }
        }
    }

    func testABarAndAnAreaAtOnePlaceDoNotStack() throws {
        let area: [String: Any] = ["type": "AreaMark", "x": value("Day", "$day"), "y": value("High", "$high")]
        let primitives = layout(chart([bar, area]), rows: [["Mon", "2"], ["Tue", "4"]])
        XCTAssertTrue(texts(primitives).contains("4"))
        XCTAssertFalse(texts(primitives).contains("8"), "the axis is not a stack of the two")
        let found = points(try XCTUnwrap(fills(primitives).first))
        XCTAssertEqual(found[2].y, found[3].y, accuracy: 0.001, "down to the baseline at both ends")
    }

    func testARangeOfCategoriesRunsFromEdgeToEdge() throws {
        let area: [String: Any] = ["type": "AreaMark", "x": value("High", "$high"), "yStart": value("A", "$day"), "yEnd": value("B", "$team")]
        let found = points(try XCTUnwrap(fills(layout(chart([area]), rows: [["Mon", "1", "Tue"], ["Mon", "2", "Tue"]])).first))
        // The plot runs from 5, half a line down, to 202, above the 18 of x labels.
        XCTAssertEqual(found[3].y, 5, accuracy: 0.001, "the top of the first band")
        XCTAssertEqual(found[0].y, 202, accuracy: 0.001, "the bottom of the last band")
    }

    func testARangeAreaFillsBetweenItsTwoValues() throws {
        let area: [String: Any] = ["type": "AreaMark", "x": value("X", "$x"), "yStart": value("L", 2), "yEnd": value("H", "$y")]
        let found = points(try XCTUnwrap(fills(layout(numbers([area]), rows: [["1", "6"], ["2", "8"]])).first))
        XCTAssertLessThan(found[0].y, found[3].y, "the top is the end value")
        XCTAssertEqual(found[2].y, found[3].y, accuracy: 0.001, "the bottom is level at 2")
    }

    func testANormalizedAxisStretchedByAnotherMarkKeepsFewTicks() {
        var stack = bar
        stack["stacking"] = "normalized"
        for far in [10_000_000.0, 1e19, 1e300] {
            let rule: [String: Any] = ["type": "RuleMark", "y": value("Far", far)]
            let description: [String: Any] = ["columns": columns, "content": [["type": "ForEach", "content": [stack]], rule]]
            XCTAssertLessThan(texts(layout(description, rows: [["Mon", "2"], ["Mon", "3"]])).count, 10, "\(far)")
        }
    }

    func testAStrokeNarrowerThanAFloatHoldsIsNotDrawn() {
        let hairline = ChartStroke(lineWidth: 1e-50)
        let points = [ChartPathElement.move(ChartPoint(x: 0, y: 0)), .line(ChartPoint(x: 1, y: 1))]
        XCTAssertFalse(ChartPrimitive.path(points, ink: .text(opacity: 1), stroke: hairline).isDrawable)
        XCTAssertFalse(ChartPrimitive.line(from: ChartPoint(x: 0, y: 0), to: ChartPoint(x: 1, y: 1), ink: .text(opacity: 1), stroke: hairline).isDrawable)
    }

    // MARK: - Weeks

    func testAWeekStartsOnTheCalendarsFirstDay() throws {
        let saved = ChartDates.calendar
        defer { ChartDates.calendar = saved }
        let wednesday = try XCTUnwrap(saved.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 12)))
        ChartDates.calendar.firstWeekday = 1
        XCTAssertEqual(saved.component(.day, from: ChartDates.bin(wednesday, .weekOfYear).start), 2, "Sunday, August 2")
        ChartDates.calendar.firstWeekday = 2
        XCTAssertEqual(saved.component(.day, from: ChartDates.bin(wednesday, .weekOfYear).start), 3, "Monday, August 3")
    }

    // MARK: - Axes

    func testAHiddenAxisDrawsNoLabels() {
        let primitives = layout(chart([bar], ["chartXAxis": "hidden", "chartYAxis": "hidden"]), rows: [["Mon", "1"]])
        XCTAssertEqual(texts(primitives), [])
        XCTAssertEqual(rects(primitives).count, 1)
    }

    func testCategoryLabelsTooWideForTheirBandShowEveryFew() {
        let rows = (0..<20).map { ["Category \($0)", "1"] }
        let shown = texts(layout(chart([bar]), rows: rows)).filter { $0.hasPrefix("Category") }
        XCTAssertGreaterThan(shown.count, 1)
        XCTAssertLessThan(shown.count, 20)
    }

    func testCategoryLabelsTooTallForTheirBandShowEveryFew() throws {
        let mark: [String: Any] = ["type": "BarMark", "x": value("High", "$high"), "y": value("Day", "$day")]
        let primitives = layout(chart([mark]), rows: (0..<200).map { ["C\($0)", "1"] }, height: 200)
        let positions = primitives.compactMap { primitive -> Double? in
            if case .text(let label, let position, _) = primitive, label.hasPrefix("C") { return position.y } else { return nil }
        }
        XCTAssertGreaterThan(positions.count, 1)
        for (first, second) in zip(positions, positions.dropFirst()) {
            XCTAssertGreaterThanOrEqual(second - first, 10 - 0.001, "the fake text is 10 high")
        }
        XCTAssertLessThan(lines(primitives, ink: ChartLayout.gridInk).count, 50, "their lines thin out too")
    }

    func testAValueWithAUnitGoesInTheMiddleOfItsBin() {
        let scale = ChartAxisScale(kind: .dates(lo: Date(timeIntervalSinceReferenceDate: 0), hi: Date(timeIntervalSinceReferenceDate: 86400 * 10)), start: 0, end: 100)
        let date = Date(timeIntervalSinceReferenceDate: 86400 * 4 + 3600)
        let bin = ChartDates.bin(date, .day)
        let position = scale.position(.date(date), unit: .day)
        XCTAssertEqual(try XCTUnwrap(position), (scale.position(bin.start) + scale.position(bin.end)) / 2, accuracy: 0.001)
        XCTAssertEqual(scale.binWidth(.date(date), unit: .day), 10, accuracy: 0.5)
        XCTAssertEqual(scale.position(.date(date), unit: nil), scale.position(date))
    }

    func testADateAxisChoosesAStrideThatFits() {
        let lo = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertEqual(ChartDates.stride(lo, lo.addingTimeInterval(86400 * 28), count: 5).unit, .weekOfYear)
        XCTAssertEqual(ChartDates.stride(lo, lo.addingTimeInterval(86400 * 365), count: 5), ChartDateStride(unit: .month, count: 3))
        XCTAssertEqual(ChartDates.stride(lo, lo.addingTimeInterval(86400 * 365 * 8), count: 5), ChartDateStride(unit: .year, count: 2))
        // The start of a year in the time zone that bins dates, which need not be GMT.
        let january = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? lo
        let ticks = ChartDates.ticks(january, january.addingTimeInterval(86400 * 365), stride: ChartDateStride(unit: .month, count: 3))
        XCTAssertEqual(ticks.count, 5, "January to the next January: \(ticks)")
    }

    func testValuesThatAreNotFiniteDrawNothingAndBreakNothing() {
        let found = rects(layout(chart([bar]), rows: [["Mon", "nan"], ["Tue", "inf"], ["Wed", "2"]]))
        XCTAssertEqual(found.count, 1)
    }

    func testValuesPastWhatGSKHoldsNeverReachIt() {
        let rows = [[["Mon", "1.7e308"]], [["Mon", "1.7e308"], ["Tue", "-1.7e308"]], [["Mon", "1e-323"]], [["Mon", "1e308"], ["Mon", "1e308"]]]
        for rows in rows {
            for stacking in ["standard", "normalized", "center", "unstacked"] {
                var mark = bar
                mark["stacking"] = stacking
                XCTAssertTrue(layout(chart([mark]), rows: rows).allSatisfy(\.isDrawable), "\(rows) \(stacking)")
            }
        }
        var wide = bar
        wide["width"] = 1e300
        XCTAssertEqual(rects(layout(chart([wide]), rows: [["Mon", "1"]])), [])
    }

    func testARuleWithAWidthGSKRefusesIsNotDrawn() {
        for width in [0, -1, "inf", 1e300] as [Any] {
            let rule: [String: Any] = ["type": "RuleMark", "y": value("Y", 1), "lineStyle": ["lineWidth": width], "foregroundStyle": "red"]
            XCTAssertEqual(lines(layout(["columns": columns, "content": [rule]]), ink: .color(.named(.red))).count, 0, "\(width)")
        }
    }

    func testAnEmptyChartAndATinySizeDrawWithoutCrashing() {
        XCTAssertEqual(rects(layout(["columns": columns])), [])
        XCTAssertEqual(rects(layout(chart([bar]), rows: [["Mon", "1"]], width: 1, height: 1)).count, 1)
    }
}
