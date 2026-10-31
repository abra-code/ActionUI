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
        XCTAssertEqual(ChartTicks.domain(0, 1250, count: 3).ticks, [0, 500, 1000, 1500])
        XCTAssertEqual(ChartTicks.domain(0, 5, count: 3).ticks, [0, 2, 4, 6])
        XCTAssertEqual(ChartTicks.domain(0, 0.7, count: 4).hi, 0.8, accuracy: 1e-9)
        XCTAssertEqual(ChartTicks.domain(-30, 70, count: 2).ticks, [-50, 0, 50, 100])
    }

    func testADomainWithoutARangeStillHasOne() {
        let domain = ChartTicks.domain(0, 0, count: 3)
        XCTAssertLessThan(domain.lo, domain.hi)
    }

    func testADomainAtTheEndsOfDoubleStaysFinite() {
        for (lo, hi) in [(0, 1.7e308), (-1.7e308, 1.7e308), (0, 1e-323)] {
            let domain = ChartTicks.domain(lo, hi, count: 3)
            XCTAssertLessThan(domain.lo, domain.hi)
            XCTAssertTrue(domain.hi.isFinite)
            XCTAssertGreaterThanOrEqual(domain.ticks.count, 2)
        }
    }

    func testTheNumberOfTicksFollowsTheHeight() {
        let rows = [["Mon", "1250"]]
        // 220 high: 200 of plot after the labels, three ticks' worth.
        XCTAssertEqual(texts(layout(chart([bar]), rows: rows)).filter { $0 != "Mon" }, ["0", "500", "1000", "1500"])
        XCTAssertEqual(texts(layout(chart([bar]), rows: rows, height: 420)).filter { $0 != "Mon" }.first(where: { $0 != "0" }), "200")
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
