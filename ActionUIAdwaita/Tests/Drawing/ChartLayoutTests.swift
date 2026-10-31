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
        number: { value, _ in abs(value) < 1e15 && value == value.rounded() ? String(Int(value)) : String(value) },
        formatted: { value, format in "\(format): \(value)" },
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
            if case .text(let text, _, _, _) = primitive { return text } else { return nil }
        }
    }

    private func labelY(_ label: String, in primitives: [ChartPrimitive]) -> Double? {
        primitives.lazy.compactMap { primitive -> Double? in
            if case .text(label, let position, _, _) = primitive { return position.y } else { return nil }
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

    func testAnAutomaticDomainsStepIsSwiftChartsForEveryMaximumMeasured() {
        let measured: [(Double, Double)] = [
            (0.1, 0.05), (0.25, 0.1), (0.75, 0.2), (0.9, 0.5), (1, 0.5), (2.5, 1), (3, 1), (4, 1), (5, 2), (6, 2), (7, 2), (8, 2), (9, 5), (10, 5),
            (12, 5), (16, 5), (25, 10), (30, 10), (40, 10), (50, 20), (60, 20), (75, 25), (80, 20), (90, 25), (95, 25), (100, 25), (200, 50),
            (250, 100), (1250, 500), (75_000, 25_000), (1_000_000, 250_000),
        ]
        for (maximum, step) in measured {
            XCTAssertEqual(ChartTicks.step(0, maximum, widening: true), step, accuracy: step * 1e-9, "up to \(maximum)")
        }
    }

    // Predicted from the rule first, then measured on macOS 27: all twelve held.
    func testTheRuleHoldsForMaximumsItWasNotFoundFrom() {
        let measured: [(Double, Double)] = [(3, 1), (12, 5), (15, 5), (20, 5), (35, 10), (45, 20), (70, 25), (90, 25), (150, 50), (300, 100), (600, 200), (700, 250)]
        for (maximum, step) in measured {
            XCTAssertEqual(ChartTicks.step(0, maximum, widening: true), step, "up to \(maximum)")
        }
    }

    func testAnExactDomainsStepCountsOnlyTheTicksInsideIt() {
        let measured: [(Double, Double, Double)] = [
            (0, 9, 2), (0, 7, 2), (0, 10, 5), (0, 1, 0.5), (0, 100, 25), (0, 1000, 250), (3, 47, 10), (15, 37, 5), (100, 160, 20), (4, 100, 25),
            (5, 100, 25), (20, 100, 25), (1, 100, 25), (10, 90, 20), (4, 1000, 250), (0, 50, 20), (2, 10, 2), (1, 9, 2), (11, 29, 5), (40, 200, 50),
            (0, 80, 25), (0, 90, 25), (10, 100, 25), (0, 75, 20), (0, 800, 250), (30, 70, 10), (0, 40, 10), (50, 250, 50), (0, 3, 1), (0, 250, 100),
            (7, 93, 20), (0, 4, 1),
        ]
        for (lo, hi, step) in measured {
            XCTAssertEqual(ChartTicks.step(lo, hi, widening: false), step, accuracy: step * 1e-9, "\(lo)...\(hi)")
        }
        XCTAssertEqual(ChartTicks.inside(3, 47).ticks, [10, 20, 30, 40])
        XCTAssertEqual(ChartTicks.inside(15, 37).ticks, [15, 20, 25, 30, 35])
    }

    func testAWidenedDomainEndsOnWholeSteps() {
        XCTAssertEqual(ChartTicks.widened(0, 1250).ticks, [0, 500, 1000, 1500])
        XCTAssertEqual(ChartTicks.widened(0, 5).ticks, [0, 2, 4, 6])
        XCTAssertEqual(ChartTicks.widened(10, 30).ticks, [10, 15, 20, 25, 30])
        XCTAssertEqual(ChartTicks.widened(120, 180).ticks, [120, 140, 160, 180])
        XCTAssertEqual(ChartTicks.widened(-100, 25).ticks, [-100, -50, 0, 50], "as a normalized stack with negatives")
        XCTAssertEqual(ChartTicks.widened(-30, 70).ticks, [-50, 0, 50, 100])
    }

    func testALabelsDecimalsComeFromTheStep() {
        XCTAssertEqual(ChartTicks.fractionDigits(0.5), 1)
        XCTAssertEqual(ChartTicks.fractionDigits(0.05), 2)
        XCTAssertEqual(ChartTicks.fractionDigits(0.00002), 5)
        XCTAssertEqual(ChartTicks.fractionDigits(1), 0)
        XCTAssertEqual(ChartTicks.fractionDigits(250), 0)
    }

    func testAllLabelsOfAnAxisShareTheirDecimalsButZero() {
        var digits: [Double: Int] = [:]
        var recording = metrics
        recording.number = { value, count in
            digits[value] = count
            return String(value)
        }
        let spec = ChartDescription.parse(chart([bar]), logger: nil).spec
        _ = ChartLayout.primitives(spec, marks: ChartMarkResolver.resolve(spec, rows: [["Mon", "0.1"]]), width: 300, height: 200, metrics: recording)
        XCTAssertEqual(digits[0.05], 2)
        XCTAssertEqual(digits[0.1], 2)
        XCTAssertEqual(digits[0], 0)
    }

    func testADomainWithoutARangeStillHasOne() {
        let domain = ChartTicks.widened(0, 0)
        XCTAssertLessThan(domain.lo, domain.hi)
    }

    func testADomainAtTheEndsOfDoubleStaysFinite() {
        for (lo, hi) in [(0, 1.7e308), (-1.7e308, 1.7e308), (0, 1e-323)] {
            let domain = ChartTicks.widened(lo, hi)
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

    func testANormalizedAxisIsPlainNumbersUpToAHundred() {
        var stack = bar
        stack["stacking"] = "normalized"
        let rule: [String: Any] = ["type": "RuleMark", "y": value("Goal", 40), "foregroundStyle": "red"]
        let description: [String: Any] = ["columns": columns, "content": [["type": "ForEach", "content": [stack]], rule]]
        let primitives = layout(description, rows: [["Mon", "2"], ["Mon", "3"]])
        let y0 = labelY("0", in: primitives), y100 = labelY("100", in: primitives)
        let goal = primitives.compactMap { primitive -> Double? in
            if case .line(let from, _, .color(.named(.red)), _) = primitive { return from.y }
            return nil
        }.first
        XCTAssertEqual(try XCTUnwrap(goal), try XCTUnwrap(y0) + (try XCTUnwrap(y100) - XCTUnwrap(y0)) * 0.4, accuracy: 0.001, "a rule at 40 sits at 40 of 100")
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

    // MARK: - Scales

    private var point: [String: Any] { ["type": "PointMark", "x": value("X", "$x"), "y": value("Y", "$y")] }

    private func centers(_ primitives: [ChartPrimitive]) -> [ChartPoint] {
        primitives.compactMap { primitive in
            if case .symbol(_, let center, _, _) = primitive { return center } else { return nil }
        }
    }

    private func scaled(_ extra: [String: Any], rows: [[String]]) -> [ChartPrimitive] {
        var description = numbers([point])
        description.merge(extra) { $1 }
        return layout(description, rows: rows)
    }

    func testAnAutomaticDomainCanLeaveZeroOut() {
        let found = texts(scaled(["chartYScale": ["domain": ["automatic": ["includesZero": false]]]], rows: [["1", "120"], ["2", "180"]]))
        XCTAssertEqual(Array(found.prefix(4)), ["120", "140", "160", "180"], "the y labels come first")
        XCTAssertEqual(found[4], "0", "and the x axis still holds 0")
    }

    func testAnExplicitDomainIsExactAndAMarkPastItStillDraws() throws {
        let primitives = scaled(["chartYScale": ["domain": [100, 160]]], rows: [["1", "130"], ["2", "200"]])
        XCTAssertEqual(Array(texts(primitives).prefix(4)), ["100", "120", "140", "160"])
        let found = centers(primitives)
        let top = try XCTUnwrap(labelY("160", in: primitives)), bottom = try XCTUnwrap(labelY("100", in: primitives))
        XCTAssertEqual(found[0].y, (top + bottom) / 2, accuracy: 0.001)
        XCTAssertLessThan(found[1].y, top, "past the top of the domain")
    }

    func testADomainOfNamesSetsTheBandsAndOthersAreNotDrawn() {
        let mark: [String: Any] = ["type": "PointMark", "x": value("Day", "$day"), "y": value("High", "$high")]
        let primitives = layout(chart([mark], ["chartXScale": ["domain": ["Wed", "Mon", "Extra"]]]), rows: [["Mon", "3"], ["Tue", "8"], ["Wed", "5"]])
        XCTAssertEqual(texts(primitives).filter { $0.first?.isLetter == true }, ["Wed", "Mon", "Extra"])
        let found = centers(primitives)
        XCTAssertEqual(found.count, 2, "Tue has no band")
        XCTAssertLessThan(found[1].x, found[0].x, "Wed comes first")
    }

    func testAReversedDomainPutsZeroAtTheTop() {
        let bars: [String: Any] = ["type": "BarMark", "x": value("Day", "$day"), "y": value("High", "$high")]
        let found = rects(layout(chart([bars], ["chartYScale": ["domain": ["automatic": ["reversed": true]]]]), rows: [["Mon", "4"], ["Tue", "2"]]))
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found[1].y, 5, accuracy: 0.001, "the shorter bar hangs from half a line down")
        XCTAssertEqual(found[1].height, found[0].height / 2, accuracy: 0.001)
    }

    func testRangePaddingInsetsTheScale() throws {
        let plain = centers(scaled(["chartXScale": ["domain": [0, 10]]], rows: [["0", "1"], ["10", "1"]]))
        let padded = centers(scaled(["chartXScale": ["domain": [0, 10], "range": ["startPadding": 40, "endPadding": 20]]], rows: [["0", "1"], ["10", "1"]]))
        XCTAssertEqual(padded[0].x, plain[0].x + 40, accuracy: 0.001)
        XCTAssertEqual(padded[1].x, plain[1].x - 20, accuracy: 0.001)
    }

    func testARangeInPointsCountsFromThePlotsCorner() {
        let found = centers(scaled(["chartXScale": ["domain": [0, 10], "range": [50, 150]]], rows: [["0", "1"], ["10", "1"]]))
        XCTAssertEqual(found[0].x, 50, accuracy: 0.001)
        XCTAssertEqual(found[1].x, 150, accuracy: 0.001)
    }

    func testALogScaleTicksAtPowersOfTenEvenlySpaced() throws {
        let primitives = scaled(["chartYScale": ["domain": [1, 1000], "type": "log"]], rows: [["1", "10"]])
        let labels = ["1", "10", "100", "1000"]
        XCTAssertEqual(texts(primitives).filter { labels.contains($0) }, labels)
        let ys = try labels.map { try XCTUnwrap(labelY($0, in: primitives)) }
        XCTAssertEqual(ys[0] - ys[1], ys[1] - ys[2], accuracy: 0.001)
        XCTAssertEqual(centers(primitives)[0].y, ys[1], accuracy: 0.001)
    }

    func testABarStandsOnZeroSoAScaleWithoutZeroDrawsNone() {
        let bars: [String: Any] = ["type": "BarMark", "x": value("Day", "$day"), "y": value("High", "$high")]
        let types: [Any] = ["log", ["power": ["exponent": -1]]]
        for type in types {
            let found = rects(layout(chart([bars], ["chartYScale": ["domain": [1, 1000], "type": type]]), rows: [["Mon", "10"], ["Mon", "90"], ["Tue", "50"]]))
            XCTAssertEqual(found.count, 0, "as measured, not even the upper bar of a stack")
        }
    }

    func testABarWithItsOwnEndsDrawsOnALogScale() {
        let columns: [Any] = ["day", ["name": "low", "type": "number"], ["name": "high", "type": "number"]]
        let mark: [String: Any] = ["type": "BarMark", "x": value("Day", "$day"), "yStart": value("Low", "$low"), "yEnd": value("High", "$high")]
        let description: [String: Any] = ["columns": columns, "content": [["type": "ForEach", "content": [mark]]], "chartYScale": ["domain": [1, 1000], "type": "log"]]
        XCTAssertEqual(rects(layout(description, rows: [["Mon", "10", "100"], ["Tue", "0", "100"]])).count, 1, "and one that starts at 0 does not")
    }

    func testABarGoesPastADomainOnASquareRootScale() throws {
        let bars: [String: Any] = ["type": "BarMark", "x": value("Day", "$day"), "y": value("High", "$high")]
        let primitives = layout(chart([bars], ["chartYScale": ["domain": [4, 100], "type": "squareRoot"]]), rows: [["Mon", "16"]])
        let rect = try XCTUnwrap(rects(primitives).first)
        let top = try XCTUnwrap(labelY("100", in: primitives)), low = try XCTUnwrap(labelY("25", in: primitives))
        let length = (low - top) / (1 - 0.375)
        XCTAssertEqual(rect.height, length * 4 / 8, accuracy: 0.001, "from 0 to 16 is 4 of the 8 from 2 to 10")
    }

    func testSquareRootAndPowerSpaceTheirTicksAsMeasured() throws {
        let root = scaled(["chartYScale": ["domain": [0, 100], "type": "squareRoot"]], rows: [["1", "1"]])
        let y0 = try XCTUnwrap(labelY("0", in: root)), y100 = try XCTUnwrap(labelY("100", in: root))
        XCTAssertEqual((y0 - (try XCTUnwrap(labelY("25", in: root)))) / (y0 - y100), 0.5, accuracy: 0.001)
        let power = scaled(["chartYScale": ["domain": [0, 100], "type": ["power": ["exponent": 2]]]], rows: [["1", "1"]])
        let p0 = try XCTUnwrap(labelY("0", in: power)), p100 = try XCTUnwrap(labelY("100", in: power))
        XCTAssertEqual((p0 - (try XCTUnwrap(labelY("25", in: power)))) / (p0 - p100), 0.0625, accuracy: 0.001)
    }

    func testASymmetricLogScaleTicksAroundZero() throws {
        let primitives = scaled(["chartYScale": ["type": "symmetricLog"]], rows: [["1", "-100"], ["2", "0"], ["3", "100"]])
        XCTAssertEqual(Array(texts(primitives).prefix(5)), ["-100", "-10", "0", "10", "100"])
        let top = try XCTUnwrap(labelY("100", in: primitives)), zero = try XCTUnwrap(labelY("0", in: primitives))
        XCTAssertEqual((zero - (try XCTUnwrap(labelY("10", in: primitives)))) / (zero - top), 0.52, accuracy: 0.01, "as measured")
    }

    func testAnAxisWithADomainDrawsWithoutMarks() {
        let found = texts(layout(["columns": columns, "chartYScale": ["domain": [0, 10]]]))
        XCTAssertTrue(found.contains("10"), "\(found)")
    }

    // The y labels of a chart whose x axis is categories, so no other label is a number.
    private func yLabels(_ scale: [String: Any], values: [String]) -> [String] {
        let mark: [String: Any] = ["type": "PointMark", "x": value("Day", "$day"), "y": value("High", "$high")]
        let rows = values.enumerated().map { ["d\($0)", $1] }
        let found = layout(chart([mark], ["chartYScale": scale]), rows: rows)
        return found.compactMap { primitive in
            if case .text(let text, _, let alignment, _) = primitive, alignment.y == 0.5 { return text } else { return nil }
        }
    }

    func testASymmetricLogAxisTicksAsMeasuredAndGrowsToThem() {
        let measured: [(Double, Double, [String])] = [
            (0, 0.5, []), (0, 1, []), (0, 2, ["10"]), (0, 5, ["10"]), (0, 10, ["10"]), (0, 11, ["10", "100"]), (0, 150, ["10", "100", "1000"]),
            (0, 12345, ["10", "100", "1000", "10000", "100000"]), (-5, 5, ["-10", "0", "10"]), (-0.5, 5, ["10"]), (-0.5, 0, []),
            (-1000, 5, ["-1000", "-100", "-10", "0", "10"]), (-7, 150, ["-10", "0", "10", "100", "1000"]),
        ]
        for (lo, hi, labels) in measured {
            XCTAssertEqual(yLabels(["type": "symmetricLog"], values: [String(lo), String(hi)]), labels, "\(lo)...\(hi)")
        }
        let found = centers(scaled(["chartYScale": ["type": "symmetricLog"]], rows: [["1", "0"], ["2", "2"], ["3", "10"]]))
        XCTAssertEqual((found[0].y - found[1].y) / (found[0].y - found[2].y), log1p(2) / log1p(10), accuracy: 0.001, "2 sits on a domain grown to 10")
    }

    func testASymmetricLogAxisWithoutZeroGrowsToTheDecadesAround() {
        let noZero: [String: Any] = ["type": "symmetricLog", "domain": ["automatic": ["includesZero": false]]]
        for (lo, hi, labels) in [("20", "30", ["10", "100"]), ("2", "3", ["1", "10"]), ("-30", "-20", ["-100", "-10"]), ("0.2", "0.3", ["0.1", "1"])] {
            XCTAssertEqual(yLabels(noZero, values: [lo, hi]), labels, "\(lo)...\(hi)")
        }
    }

    func testASymmetricLogAxisWithADomainTicksOnlyInsideIt() {
        let measured: [(Double, Double, [String])] = [
            (0, 5, []), (-5, 5, ["0"]), (0, 1, []), (2, 8, []), (1, 1000, ["1", "10", "100", "1000"]), (-20, 150, ["-10", "0", "10", "100"]),
            (50, 150, ["100"]), (0, 1000, ["10", "100", "1000"]),
        ]
        for (lo, hi, labels) in measured {
            XCTAssertEqual(yLabels(["type": "symmetricLog", "domain": [lo, hi]], values: ["3"]), labels, "\(lo)...\(hi)")
        }
    }

    func testAFractionalLogScaleKeepsTheDecimalsOfItsSmallestTick() {
        var digits: [Double: Int] = [:]
        var recording = metrics
        recording.number = { value, count in
            digits[value] = count
            return String(value)
        }
        let mark: [String: Any] = ["type": "PointMark", "x": value("Day", "$day"), "y": value("High", "$high")]
        let spec = ChartDescription.parse(chart([mark], ["chartYScale": ["domain": [0.01, 100], "type": "log"]]), logger: nil).spec
        _ = ChartLayout.primitives(spec, marks: ChartMarkResolver.resolve(spec, rows: [["Mon", "1"]]), width: 300, height: 200, metrics: recording)
        XCTAssertEqual(digits, [0.01: 2, 0.1: 2, 1: 2, 10: 2, 100: 2])
    }

    func testALogScaleWithoutAPowerOfTenInsideHasNoTicks() {
        XCTAssertEqual(yLabels(["domain": [2, 8], "type": "log"], values: ["3"]), [])
        XCTAssertEqual(yLabels(["domain": [5, 50], "type": "log"], values: ["7"]), ["10"])
    }

    func testAValueBelowADomainGoesWhereTheScaleSays() throws {
        let log = scaled(["chartYScale": ["domain": [10, 100], "type": "log"]], rows: [["1", "5"], ["2", "50"]])
        let bottom = try XCTUnwrap(labelY("10", in: log)), top = try XCTUnwrap(labelY("100", in: log))
        XCTAssertEqual((bottom - centers(log)[0].y) / (bottom - top), log10(5) - 1, accuracy: 0.001, "past the bottom, not at it")
        let root = scaled(["chartYScale": ["domain": [4, 100], "type": "squareRoot"]], rows: [["1", "1"], ["2", "100"]])
        let found = centers(root), y25 = try XCTUnwrap(labelY("25", in: root))
        let length = (y25 - found[1].y) / (1 - 0.375)
        XCTAssertEqual(found[0].y, y25 + length * (0.375 + 0.125), accuracy: 0.001, "1 is 1/8 of the length under the low end, 25 is 3/8 over it")
    }

    func testAPowerIsThePlainPowerOfANegative() throws {
        let primitives = scaled(["chartYScale": ["domain": [1, 10], "type": ["power": ["exponent": 2]]]], rows: [["1", "-3"], ["2", "3"]])
        let found = centers(primitives)
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found[0].y, found[1].y, accuracy: 0.001)
    }

    func testAValueWithNoPlaceOnItsScaleIsNotDrawn() {
        XCTAssertEqual(centers(scaled(["chartYScale": ["domain": [1, 1000], "type": "log"]], rows: [["1", "100"], ["2", "0"], ["3", "-5"]])).count, 1)
        XCTAssertEqual(centers(scaled(["chartYScale": ["domain": [0, 100], "type": "squareRoot"]], rows: [["1", "25"], ["2", "-4"], ["3", "4"]])).count, 2)
        XCTAssertEqual(centers(scaled(["chartYScale": ["domain": [1, 10], "type": ["power": ["exponent": -1]]]], rows: [["1", "2"], ["2", "0"]])).count, 1)
    }

    func testAValueWithNoPlaceOnItsScaleBreaksALine() {
        let mark: [String: Any] = ["type": "LineMark", "x": value("Day", "$day"), "y": value("High", "$high")]
        let primitives = layout(chart([mark], ["chartYScale": ["domain": [1, 1000], "type": "log"]]), rows: [["a", "100"], ["b", "0"], ["c", "10"], ["d", "50"]])
        let moves = primitives.flatMap { primitive -> [ChartPoint] in
            guard case .path(let elements, _, _) = primitive else { return [] }
            return elements.compactMap { element in
                if case .move(let point) = element { return point } else { return nil }
            }
        }
        XCTAssertEqual(moves.count, 1, "the piece from c to d, and a alone draws nothing")
    }

    func testAStackedAreaDrawsOnlyTheLayersWithAPlaceOnAScaleWithoutZero() {
        let mark: [String: Any] = ["type": "AreaMark", "x": value("Day", "$day"), "y": value("High", "$high"), "foregroundStyle": ["by": value("Team", "$team")]]
        let primitives = layout(chart([mark], ["chartYScale": ["domain": [1, 1000], "type": "log"]]), rows: [["a", "10", "p"], ["a", "90", "q"], ["b", "20", "p"], ["b", "80", "q"]])
        let fills = primitives.filter { primitive in
            if case .fill = primitive { return true } else { return false }
        }
        XCTAssertEqual(fills.count, 1, "the upper layer, which stands on the lower")
    }

    func testAReversedXAxisEndsEachLabelAtItsTick() throws {
        let primitives = scaled(["chartXScale": ["domain": ["automatic": ["reversed": true]]]], rows: [["0", "1"], ["10", "1"]])
        let labels = primitives.compactMap { primitive -> (text: String, x: Double)? in
            if case .text(let text, let position, let alignment, _) = primitive, alignment.y == 0 { return (text, position.x) } else { return nil }
        }
        XCTAssertEqual(labels.map(\.text), ["0", "5"], "10 would pass the plot's edge")
        let found = centers(primitives)
        XCTAssertEqual(labels[0].x + 6, found[0].x - 4, accuracy: 0.001, "6 wide, 4 before the tick")
        XCTAssertEqual(labels[1].x + 6, (found[0].x + found[1].x) / 2 - 4, accuracy: 0.001)
    }

    func testADomainOfOneValueHasNoTicksAndPutsMarksInTheMiddle() {
        XCTAssertEqual(yLabels(["domain": [5, 5]], values: ["5", "6"]), [])
        XCTAssertEqual(yLabels(["domain": [5.5, 5.5]], values: ["5"]), [])
        XCTAssertEqual(yLabels(["domain": ["automatic": ["includesZero": false]]], values: ["50", "50"]), [])
        XCTAssertEqual(yLabels([:], values: ["0", "0"]), [])
        XCTAssertEqual(yLabels(["type": "symmetricLog"], values: ["0", "0"]), [])
        let found = centers(scaled(["chartYScale": ["domain": [5, 5]]], rows: [["1", "5"], ["2", "6"]]))
        XCTAssertEqual(found[0].y, found[1].y, accuracy: 0.001)
    }

    func testADateAxisOfOneInstantHasNoTicks() {
        let columns: [Any] = [["name": "when", "type": "date"], ["name": "high", "type": "number"]]
        let mark: [String: Any] = ["type": "PointMark", "x": value("When", "$when"), "y": value("High", "$high")]
        let description: [String: Any] = ["columns": columns, "content": [["type": "ForEach", "content": [mark]]]]
        let found = layout(description, rows: [["2026-02-10", "1"]]).compactMap { primitive -> String? in
            if case .text(let text, _, let alignment, _) = primitive, alignment.y == 0 { return text } else { return nil }
        }
        XCTAssertEqual(found, [])
    }

    func testABandAxisOfNoWidthDoesNotStopTheApp() {
        let scales: [[String: Any]] = [["range": [0, 1e-300]], ["range": [5, 5]], ["range": [0, 1e308]]]
        for scale in scales {
            _ = layout(chart([bar], ["chartXScale": scale]), rows: [["Mon", "3"], ["Tue", "4"]])
            let across: [String: Any] = ["type": "BarMark", "y": value("Day", "$day"), "x": value("High", "$high")]
            _ = layout(chart([across], ["chartYScale": scale]), rows: [["Mon", "3"], ["Tue", "4"]])
        }
    }

    // MARK: - Axis marks

    private func axisMarks(_ y: [String: Any]? = nil, x: [String: Any]? = nil, rows: [[String]] = [["10", "120"], ["90", "180"]]) -> [ChartPrimitive] {
        var extra: [String: Any] = [:]
        if let y { extra["chartYAxis"] = [y.merging(["type": "AxisMarks"]) { $1 }] }
        if let x { extra["chartXAxis"] = [x.merging(["type": "AxisMarks"]) { $1 }] }
        var description = numbers([point])
        description.merge(extra) { $1 }
        return layout(description, rows: rows)
    }

    private func lines(_ primitives: [ChartPrimitive]) -> [(from: ChartPoint, to: ChartPoint, ink: ChartInk, stroke: ChartStroke)] {
        primitives.compactMap { primitive in
            if case .line(let from, let to, let ink, let stroke) = primitive { return (from, to, ink, stroke) } else { return nil }
        }
    }

    func testDefaultMarksDrawAsAnAxisWithoutAnyAxisMarks() {
        XCTAssertEqual(axisMarks(), axisMarks(["preset": "automatic"]), "an AxisMarks that says nothing changes nothing")
    }

    func testExplicitValuesChooseTheTicksAndLeaveTheDomain() throws {
        let plain = axisMarks()
        let chosen = axisMarks(["values": [0, 50, 200, 5000]])
        XCTAssertEqual(Array(texts(chosen).prefix(3)), ["0", "50", "200"], "and 5000 is past the domain")
        XCTAssertEqual(centers(chosen), centers(plain).map { ChartPoint(x: $0.x, y: $0.y) }, "the marks stay where they were")
    }

    func testAStrideTakesTheMultiplesInTheDomain() {
        XCTAssertEqual(Array(texts(axisMarks(x: ["values": ["stride": ["by": 25]]])).suffix(4)), ["0", "25", "50", "75"], "and 100 passes the plot's end")
    }

    func testADesiredCountIsTheTicksAnAxisAimsFor() {
        // Measured: up to 180, eight ticks aimed for is every 25.
        XCTAssertEqual(ChartTicks.step(0, 180, widening: true, ideal: 8), 25)
        XCTAssertEqual(ChartTicks.step(0, 90, widening: true, ideal: 2), 100)
        let found = texts(axisMarks(["values": ["automatic": ["desiredCount": 8]]]))
        XCTAssertEqual(Array(found.prefix(3)), ["0", "25", "50"])
    }

    func testAPositionMovesLabelsAndTheirRoom() throws {
        let plain = axisMarks()
        let leading = axisMarks(["position": "leading"])
        XCTAssertLessThan(centers(plain)[0].x, centers(leading)[0].x, "labels on the leading side push the plot in")
        let top = axisMarks(x: ["position": "top"])
        XCTAssertGreaterThan(centers(top)[0].y, centers(plain)[0].y, "and on top push it down")
    }

    func testAFormatWritesTheLabels() {
        let found = texts(axisMarks(["format": "percent"]))
        XCTAssertTrue(found.contains { $0.hasPrefix("percent") }, "\(found)")
    }

    func testAStrokeAppliesToGridlines() {
        let dashed = ["lineWidth": 1, "dash": [4, 2]] as [String: Any]
        let found = lines(axisMarks(["stroke": dashed]))
        XCTAssertTrue(found.contains { $0.stroke == ChartStroke(dash: [4, 2]) })
    }

    func testMarksWithContentDrawOnlyThat() {
        let labelsOnly = axisMarks(["content": [["type": "AxisValueLabel"]]])
        XCTAssertFalse(lines(labelsOnly).contains { $0.from.y == $0.to.y }, "no gridlines")
        XCTAssertTrue(texts(labelsOnly).contains("200"))
        let linesOnly = axisMarks(["content": [["type": "AxisGridLine"]]])
        XCTAssertFalse(texts(linesOnly).contains("200"), "no labels")
    }

    func testEmptyContentDrawsNothingAndTakesNoRoom() {
        let plain = axisMarks()
        let none = axisMarks(["content": [Any]()])
        XCTAssertFalse(texts(none).contains("200"))
        XCTAssertGreaterThan(centers(none)[0].x, centers(plain)[0].x, "the plot takes the labels' room")
    }

    func testAnItemsStyleIsItsOwn() {
        let mark: [String: Any] = ["type": "BarMark", "x": value("Day", "$day"), "y": value("High", "$high")]
        let axis: [String: Any] = ["type": "AxisMarks", "content": [
            ["type": "AxisGridLine", "stroke": ["lineWidth": 2], "foregroundStyle": "orange"],
            ["type": "AxisTick", "length": 12, "foregroundStyle": "green"],
            ["type": "AxisValueLabel", "foregroundStyle": "red"],
        ]]
        let primitives = layout(chart([mark], ["chartXAxis": [axis]]), rows: [["Mon", "1"], ["Tue", "2"]])
        let found = lines(primitives)
        XCTAssertEqual(found.filter { $0.ink == .color(.named(.orange)) }.count, 3, "at the edges of two bands")
        let ticks = found.filter { $0.ink == .color(.named(.green)) }
        XCTAssertEqual(ticks.count, 3)
        XCTAssertEqual(ticks.first.map { $0.to.y - $0.from.y }, 12)
        let inks = primitives.compactMap { primitive -> ChartInk? in
            if case .text("Mon", _, _, let ink) = primitive { return ink } else { return nil }
        }
        XCTAssertEqual(inks, [.color(.named(.red))])
    }

    func testAnAnchorPlacesALabelInItsBand() throws {
        let mark: [String: Any] = ["type": "BarMark", "x": value("Day", "$day"), "y": value("High", "$high")]
        func labelX(_ anchor: String?) -> Double? {
            var label: [String: Any] = ["type": "AxisValueLabel"]
            label["anchor"] = anchor
            let primitives = layout(chart([mark], ["chartXAxis": [["type": "AxisMarks", "content": [label]]]]), rows: [["Mon", "1"], ["Tue", "2"]])
            return primitives.compactMap { primitive -> Double? in
                if case .text("Mon", let position, let alignment, _) = primitive { return position.x - alignment.x * 18 } else { return nil }
            }.first
        }
        let center = try XCTUnwrap(labelX(nil)), trailing = try XCTUnwrap(labelX("topTrailing")), leading = try XCTUnwrap(labelX("topLeading"))
        XCTAssertEqual(leading, center, "measured on macOS 27: only the trailing corners move it")
        XCTAssertLessThan(center, trailing)
    }

    func testDateFormatsBecomeSkeletons() {
        XCTAssertEqual(ChartDateFormat.fields([.monthAbbreviated, .dayDefaultDigits]).skeleton, "MMMd")
        XCTAssertEqual(ChartDateFormat.styles(date: .long, time: .shortened).skeleton, "yMMMMdjm")
        XCTAssertEqual(ChartDateFormat.styles(date: .omitted, time: .standard).skeleton, "jms")
    }

    func testChosenValuesShareTheDecimalsTheyNeed() {
        XCTAssertEqual(ChartTicks.fractionDigits(of: [0.5, 1.25]), 2, "they show 0.50 and 1.25")
        XCTAssertEqual(ChartTicks.fractionDigits(of: [1, 2]), 0)
        XCTAssertEqual(ChartTicks.fractionDigits(of: [0, 0.25, 0.5]), 2)
        XCTAssertEqual(ChartTicks.fractionDigits(of: [0.1 + 0.2]), 1, "a step's sum is not 17 decimals long")
        XCTAssertEqual(ChartTicks.fractionDigits(of: [1e-30]), 15)
        var digits: [Double: Int] = [:]
        var recording = metrics
        recording.number = { value, places in
            digits[value] = places
            return String(value)
        }
        var description = numbers([point])
        description["chartYScale"] = ["domain": [0, 1]]
        description["chartYAxis"] = [["type": "AxisMarks", "values": ["stride": ["by": 0.25]]]]
        let spec = ChartDescription.parse(description, logger: nil).spec
        _ = ChartLayout.primitives(spec, marks: ChartMarkResolver.resolve(spec, rows: [["1", "0.5"]]), width: 306, height: 220, metrics: recording)
        XCTAssertEqual(digits[0.75], 2, "0.75, where the step's own decimals would write 0.8")
    }

    func testAStrideWithNoMultiplesInTheDomainHasNoTicks() {
        XCTAssertEqual(ChartTicks.multiples(of: 1000, 120, 180), [])
        let found = scaled(["chartYScale": ["domain": [120, 180]], "chartYAxis": [["type": "AxisMarks", "values": ["stride": ["by": 1000]]]]],
                           rows: [["10", "120"], ["90", "180"]])
        XCTAssertEqual(found.compactMap { primitive -> String? in
            if case .text(let text, _, let alignment, _) = primitive, alignment.y == 0.5 { return text } else { return nil }
        }, [], "not the ends of the domain")
    }

    func testAStridePastTheLimitIsAutomatic() {
        // Int(intervals) would stop the app here.
        XCTAssertEqual(ChartTicks.multiples(of: 1e-300, 0, 180), [])
        XCTAssertEqual(ChartTicks.multiples(of: 1e-7, 0, 900), [])
        XCTAssertEqual(ChartTicks.multiples(of: 1, 0, 1000).count, 1001)
        XCTAssertEqual(ChartTicks.multiples(of: 1, 0, 1001), [], "the limit, as Swift Charts' own")
        let tiny = texts(axisMarks(["values": ["stride": ["by": 1e-300]]]))
        XCTAssertEqual(tiny, texts(axisMarks()))
        XCTAssertEqual(texts(axisMarks(["values": ["stride": ["by": 0.01]]])), texts(axisMarks()), "18,000 marks")
        XCTAssertEqual(texts(axisMarks(["values": (0...2000).map { Double($0) * 0.1 }])), texts(axisMarks()), "a list of 2,000 in the domain")
        XCTAssertEqual(Array(texts(axisMarks(["values": (0...1000).map { Double($0) * 100 }])).prefix(3)), ["0", "100", "200"], "2,000 past it are not ticks")
    }

    func testAOneValueDomainHasNoTicksForACountOrAStride() {
        let domain: [String: Any] = ["chartYScale": ["domain": [5, 5]]]
        func yLabels(_ axis: [String: Any]) -> [String] {
            let description = numbers([point]).merging(domain) { $1 }.merging(["chartYAxis": [axis]]) { $1 }
            return layout(description, rows: [["1", "5"]]).compactMap { primitive -> String? in
                if case .text(let text, _, let alignment, _) = primitive, alignment.y == 0.5 { return text } else { return nil }
            }
        }
        XCTAssertEqual(yLabels(["type": "AxisMarks", "values": ["automatic": ["desiredCount": 8]]]), [])
        XCTAssertEqual(yLabels(["type": "AxisMarks", "values": ["stride": ["by": 1]]]), [])
    }

    func testACountOfTicksMeansNothingOnALogScale() {
        let logScale: [String: Any] = ["chartYScale": ["type": "log", "domain": [1, 1000]]]
        func labels(_ extra: [String: Any]) -> [String] {
            texts(layout(numbers([point]).merging(logScale) { $1 }.merging(extra) { $1 }, rows: [["1", "2"], ["2", "900"]]))
        }
        XCTAssertEqual(labels(["chartYAxis": [["type": "AxisMarks", "values": ["automatic": ["desiredCount": 3]]]]]), labels([:]))
    }

    func testAListIsInTheAxissOrder() {
        // Written out of order, 0 would be left out as passing the label before it.
        XCTAssertEqual(Array(texts(axisMarks(x: ["values": [50, 0, 75]])).suffix(3)), ["0", "50", "75"])
    }

    func testTheDomainHoldsEveryAutomaticAxisMarks() throws {
        // Measured: over values to 90, four ticks reach 100 and eight stop at 90, in either order.
        func axis(_ marks: [[String: Any]]) -> [ChartPrimitive] {
            var description = numbers([point])
            description["chartYAxis"] = marks
            return layout(description, rows: [["10", "20"], ["50", "90"]])
        }
        let plain: [String: Any] = ["type": "AxisMarks"]
        let eight: [String: Any] = ["type": "AxisMarks", "values": ["automatic": ["desiredCount": 8]], "position": "leading"]
        let found = texts(axis([plain, eight]))
        XCTAssertEqual(Array(found.prefix(5)), ["0", "25", "50", "75", "100"], "as a plain axis ticks")
        XCTAssertEqual(Array(found.dropFirst(5).prefix(10)), ["0", "10", "20", "30", "40", "50", "60", "70", "80", "90"], "on its own steps")
        XCTAssertEqual(centers(axis([plain, eight]))[1].y, centers(axis([eight, plain]))[1].y, accuracy: 0.001)
        let alone = texts(axis([eight]))
        XCTAssertTrue(alone.contains("90"))
        XCTAssertFalse(alone.contains("100"))
        XCTAssertLessThan(centers(axis([eight]))[1].y, centers(axis([plain]))[1].y, "alone it stops at 90, so that point is higher")
    }

    func testAnEndThatIsNotRoundedStays() {
        // Measured: 125...178 steps by 25 and 20, and by 20 with both ends rounded.
        XCTAssertEqual(ChartTicks.widened(125, 178).ticks, [120, 140, 160, 180])
        let lower = ChartTicks.widened(125, 178, roundLower: false)
        XCTAssertEqual(lower.ticks, [125, 150, 175, 200])
        XCTAssertEqual(lower.lo, 125)
        XCTAssertEqual(lower.hi, 200)
        let upper = ChartTicks.widened(125, 178, roundUpper: false)
        XCTAssertEqual(upper.ticks, [120, 140, 160])
        XCTAssertEqual(upper.lo, 120)
        XCTAssertEqual(upper.hi, 178)
        XCTAssertEqual(ChartTicks.widened(0, 180, roundLower: false, roundUpper: false).ticks, [0, 50, 100, 150])
    }

    func testAnEndThatIsNotRoundedReachesThePlot() throws {
        let found = centers(axisMarks(["values": ["automatic": ["roundUpperBound": false]]]))
        let plain = centers(axisMarks())
        XCTAssertLessThan(try XCTUnwrap(found.map(\.y).min()), try XCTUnwrap(plain.map(\.y).min()), "180 is the top now, not 200")
    }

    func testANameListOnBandsChangesNothing() {
        let mark: [String: Any] = ["type": "BarMark", "x": value("Day", "$day"), "y": value("High", "$high")]
        let rows = [["Mon", "1"], ["Tue", "2"], ["Wed", "3"]]
        let named = layout(chart([mark], ["chartXAxis": [["type": "AxisMarks", "values": ["Tue"]]]]), rows: rows)
        XCTAssertEqual(named, layout(chart([mark]), rows: rows), "measured on macOS 27")
    }

    func testLinesOnBandsStayAtTheEdgesWhenCentered() {
        let mark: [String: Any] = ["type": "BarMark", "x": value("Day", "$day"), "y": value("High", "$high")]
        func positions(_ centered: Bool?) -> [Double] {
            var line: [String: Any] = ["type": "AxisGridLine", "foregroundStyle": "orange"]
            line["centered"] = centered
            let primitives = layout(chart([mark], ["chartXAxis": [["type": "AxisMarks", "content": [line]]]]), rows: [["Mon", "1"], ["Tue", "2"]])
            return lines(primitives).filter { $0.ink == .color(.named(.orange)) }.map(\.from.x)
        }
        XCTAssertEqual(positions(true), positions(nil))
        XCTAssertEqual(positions(false), positions(nil))
    }

    func testCustomLinesAreDashedOnXAndOnBandsAndPlainOnANumberY() {
        let dash = ChartStroke(lineWidth: 1, dash: [2, 2])
        let x = axisMarks(x: ["content": [["type": "AxisGridLine", "foregroundStyle": "orange"], ["type": "AxisTick", "foregroundStyle": "orange"]]])
        XCTAssertTrue(lines(x).filter { $0.ink == .color(.named(.orange)) }.allSatisfy { $0.stroke == dash })
        let y = axisMarks(["content": [["type": "AxisGridLine", "foregroundStyle": "orange"], ["type": "AxisTick", "foregroundStyle": "orange"]]])
        XCTAssertTrue(lines(y).filter { $0.ink == .color(.named(.orange)) }.allSatisfy { $0.stroke == ChartStroke() })
    }

    func testEveryEntryOfAnAxisMarksDraws() {
        let found = texts(axisMarks(["content": [["type": "AxisValueLabel", "format": "percent"], ["type": "AxisValueLabel", "format": "integer"]]]))
        XCTAssertTrue(found.contains { $0.hasPrefix("percent") }, "\(found)")
        XCTAssertTrue(found.contains { $0.hasPrefix("integer") }, "\(found)")
    }

    func testATicksGivenLengthAddsToTheRoomAndMovesNoLabel() throws {
        func marks(_ x: [Any]) -> [ChartPrimitive] { axisMarks(x: ["content": x]) }
        let label: [String: Any] = ["type": "AxisValueLabel"], tick: [String: Any] = ["type": "AxisTick", "length": 12]
        let plain = marks([label]), ticked = marks([tick, label])
        let plainY = try XCTUnwrap(labelY("25", in: plain)), tickedY = try XCTUnwrap(labelY("25", in: ticked))
        XCTAssertEqual(plainY - tickedY, 12, accuracy: 0.001, "the plot ends 12 sooner and the label keeps its place under it")
        XCTAssertLessThanOrEqual(try XCTUnwrap(lines(marks([tick])).map(\.to.y).max()), 220, "a tick alone stays on the chart")
        let onY = axisMarks(["content": [tick]])
        XCTAssertLessThanOrEqual(try XCTUnwrap(lines(onY).map { max($0.from.x, $0.to.x) }.max()), 306)
    }

    func testAnAutomaticTickOnYTakesRoom() throws {
        let tick: [String: Any] = ["type": "AxisTick"], label: [String: Any] = ["type": "AxisValueLabel"]
        let plain = axisMarks(["content": [label]]), ticked = axisMarks(["content": [tick, label]])
        XCTAssertEqual(try XCTUnwrap(centers(plain).first?.x) - (try XCTUnwrap(centers(ticked).first?.x)), 4 * 0.1, accuracy: 0.001, "the marks move as the plot narrows by 4")
    }

    func testATicksLabelLengthCrossesTheLabels() throws {
        let tick: [String: Any] = ["type": "AxisTick", "length": "longestLabel", "foregroundStyle": "orange"]
        let found = lines(axisMarks(["content": [tick, ["type": "AxisValueLabel"]]])).filter { $0.ink == .color(.named(.orange)) }
        let first = try XCTUnwrap(found.first)
        XCTAssertEqual(first.to.x - first.from.x, 18 + 4, accuracy: 0.001, "the width of 200 and the gap, on a y axis")
    }

    func testAnAnchorPlacesANumbersLabel() throws {
        func place(_ axis: [String: Any], _ text: String) -> (position: ChartPoint, alignment: ChartPoint)? {
            let description: [String: Any] = ["chartXAxis": "hidden", "chartYAxis": [axis.merging(["type": "AxisMarks"]) { $1 }]]
            return scaled(description, rows: [["10", "120"], ["90", "180"]]).lazy.compactMap { primitive -> (position: ChartPoint, alignment: ChartPoint)? in
                if case .text(text, let position, let alignment, _) = primitive { return (position, alignment) } else { return nil }
            }.first
        }
        func anchored(_ anchor: String, position: String? = nil) -> [String: Any] {
            var axis: [String: Any] = ["content": [["type": "AxisValueLabel", "anchor": anchor]]]
            axis["position"] = position
            return axis
        }
        let plain = try XCTUnwrap(place(["content": [["type": "AxisValueLabel"]]], "100"))
        let top = try XCTUnwrap(place(anchored("top"), "100"))
        XCTAssertEqual(top.position.y, plain.position.y + 4, accuracy: 0.001)
        XCTAssertEqual(top.alignment.y, 0)
        XCTAssertNil(place(anchored("top"), "0"), "it would pass the plot's bottom")
        XCTAssertNil(place(anchored("bottom"), "200"), "and this its top")
        let inside = try XCTUnwrap(place(anchored("trailing"), "100"))
        XCTAssertEqual(inside.position.x, plain.position.x - 8, accuracy: 0.001, "the other side of the plot's edge")
        XCTAssertEqual(inside.alignment.x, 1)
        XCTAssertEqual(try XCTUnwrap(place(anchored("leading"), "100")).position.x, plain.position.x, "the side away from the plot does nothing")
        let leading = try XCTUnwrap(place(anchored("leading", position: "leading"), "100"))
        XCTAssertEqual(leading.alignment.x, 0, "on the leading edge it is this side that goes in")
    }

    func testAnAnchorOnXMovesOnlyTheCorners() throws {
        func place(_ anchor: String?, _ text: String) -> (position: ChartPoint, alignment: ChartPoint)? {
            var label: [String: Any] = ["type": "AxisValueLabel"]
            label["anchor"] = anchor
            return axisMarks(x: ["content": [label]]).lazy.compactMap { primitive -> (position: ChartPoint, alignment: ChartPoint)? in
                if case .text(text, let position, let alignment, _) = primitive { return (position, alignment) } else { return nil }
            }.first
        }
        let plain = try XCTUnwrap(place(nil, "25"))
        for anchor in ["leading", "top", "center", "trailing", "bottom", "topLeading"] {
            XCTAssertEqual(try XCTUnwrap(place(anchor, "25")).position, plain.position, anchor)
        }
        let trailing = try XCTUnwrap(place("topTrailing", "25"))
        XCTAssertEqual(trailing.position.x, plain.position.x - 8 - 12, accuracy: 0.001, "it ends before its tick")
        let inside = try XCTUnwrap(place("bottomLeading", "25"))
        XCTAssertEqual(inside.position.x, plain.position.x, accuracy: 0.001)
        XCTAssertEqual(inside.position.y, plain.position.y - 8, accuracy: 0.001, "inside the plot")
        XCTAssertEqual(inside.alignment.y, 1)
    }

    func testACenteredLabelSitsBetweenItsTicks() throws {
        func starts(_ centered: Bool) -> [String: Double] {
            let label: [String: Any] = ["type": "AxisValueLabel", "centered": centered]
            let primitives = axisMarks(x: ["values": [0, 10, 60], "content": [label]])
            return Dictionary(primitives.compactMap { primitive -> (String, Double)? in
                if case .text(let text, let position, let alignment, _) = primitive, alignment.y == 0 { return (text, position.x) } else { return nil }
            }, uniquingKeysWith: { first, _ in first })
        }
        let plain = starts(false), centered = starts(true)
        let zero = try XCTUnwrap(plain["0"]), ten = try XCTUnwrap(plain["10"])
        let sixty = try XCTUnwrap(plain["60"])
        XCTAssertEqual(try XCTUnwrap(centered["0"]) + 3, (zero - 4 + ten - 4) / 2, accuracy: 0.001, "the middle of 0 and 10")
        XCTAssertEqual(try XCTUnwrap(centered["10"]) + 6, (ten - 4 + sixty - 4) / 2, accuracy: 0.001, "the middle of 10 and 60")
        XCTAssertEqual(centered["60"], plain["60"], "the last has no next tick")
    }

    func testBothDateStylesOmittedIsANumericDateAndAShortTime() {
        XCTAssertEqual(ChartDateFormat.styles(date: .omitted, time: .omitted).skeleton, "yMdjm")
    }

    func testACalendarStrideTicksOnItsUnit() {
        let dates: [String: Any] = ["columns": [["name": "d", "type": "date"], ["name": "y", "type": "number"]],
                                    "chartXAxis": [["type": "AxisMarks", "values": ["stride": ["by": "weekOfYear", "count": 2]],
                                                    "format": ["dateTime": ["month": "abbreviated", "day": "defaultDigits"]]]],
                                    "content": [["type": "ForEach", "content": [["type": "PointMark", "x": value("D", "$d"), "y": value("Y", "$y")]]]]]
        let found = texts(layout(dates, rows: [["2026-08-03", "3"], ["2026-09-14", "5"]]))
        XCTAssertGreaterThanOrEqual(found.filter { $0 == "dMMM" }.count, 2, "\(found)")
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

    // MARK: - Categories on y

    private var sideways: [String: Any] { ["type": "BarMark", "x": value("High", "$high"), "y": value("Day", "$day")] }

    private func textPosition(_ label: String, in primitives: [ChartPrimitive]) -> ChartPoint? {
        primitives.compactMap { primitive -> ChartPoint? in
            if case .text(label, let position, _, _) = primitive { return position } else { return nil }
        }.first
    }

    func testCategoryLabelsOnYTakeNoRoomAndSitOnTheirBandsTopLine() throws {
        let primitives = layout(chart([sideways]), rows: [["Mon", "1"], ["Tue", "2"]], height: 118)
        let found = rects(primitives)
        XCTAssertEqual(found[1].x + found[1].width, 306, accuracy: 0.001, "the plot takes the whole width: 2 is the top of 0...2")
        let mon = try XCTUnwrap(textPosition("Mon", in: primitives)), tue = try XCTUnwrap(textPosition("Tue", in: primitives))
        XCTAssertEqual(mon.x, 4, accuracy: 0.001, "inside the plot")
        let band = tue.y - mon.y
        XCTAssertEqual(band, 47.5, accuracy: 0.001, "95 of plot in two bands: half a line above it and 18 below")
        XCTAssertEqual(mon.y, 5, accuracy: 0.001, "on the top line")
    }

    func testAPositionOnYMovesCategoryLabelsAndTakesNoRoom() throws {
        let axis: [String: Any] = ["chartYAxis": [["type": "AxisMarks", "position": "trailing"]]]
        let primitives = layout(chart([sideways], axis), rows: [["Mon", "1"], ["Tue", "2"]])
        XCTAssertEqual(try XCTUnwrap(textPosition("Mon", in: primitives)).x, 310, accuracy: 0.001, "past the plot, clipped by the chart")
        let leading: [String: Any] = ["chartYAxis": [["type": "AxisMarks", "position": "leading"]]]
        XCTAssertEqual(layout(chart([sideways], leading), rows: [["Mon", "1"]]), layout(chart([sideways]), rows: [["Mon", "1"]]), "leading is the default")
    }

    func testABarOnYSitsBelowItsLabelsRow() throws {
        // Measured with labels of 14: bands of 37.3 give a bar of 13.5, 27.6 down its band. The row
        // is a label and its gap, here 14.
        let found = rects(layout(chart([sideways]), rows: [["Mon", "1"], ["Tue", "2"], ["Wed", "3"]], height: 130))
        let band = (130 - 23.0) / 3
        XCTAssertEqual(found[0].height, (band - 14) * 0.7, accuracy: 0.001)
        XCTAssertEqual(found[0].y + found[0].height / 2, 5 + 14 + (band - 14) / 2, accuracy: 0.001)
    }

    func testABarOnATightYAxisHasTheSizeOfTheMissingRoomAndRunsPastItsBand() {
        // Measured with a row of 18: bands of 12 give a bar of 4, 15 down; of 16 a bar of 1, 17 down.
        let rows = ["A", "B", "C", "D", "E", "F"].map { [$0, "1"] }
        let found = rects(layout(chart([sideways]), rows: rows, height: 90))
        let band = (90 - 23.0) / 6
        XCTAssertEqual(found[0].height, (14 - band) * 0.7, accuracy: 0.001)
        XCTAssertEqual(found[0].y + found[0].height / 2, 5 + 14 + (band - 14) / 2, accuracy: 0.001)
    }

    func testABarWithNoRoomAtAllHasTheSizeOfOneWithNoBand() {
        // Measured: a band as wide as the row gives the 8 of a bar on a plain axis.
        let found = rects(layout(chart([sideways], ["chartYScale": ["range": [0, 28]]]), rows: [["Mon", "1"], ["Tue", "2"]]))
        XCTAssertEqual(found[0].height, 8, accuracy: 0.001)
    }

    func testAnotherMarkStaysAtTheBandsCenter() {
        let mark: [String: Any] = ["type": "PointMark", "x": value("High", "$high"), "y": value("Day", "$day")]
        let found = centers(layout(chart([mark]), rows: [["Mon", "1"], ["Tue", "2"]], height: 118))
        XCTAssertEqual(found[0].y, 5 + 47.5 / 2, accuracy: 0.001)
    }

    func testABarOfAnyHeightTakesWhatTheRowLeaves() {
        func first(_ height: Any) -> ChartRect {
            var mark = sideways
            mark["height"] = height
            return rects(layout(chart([mark]), rows: [["Mon", "1"], ["Tue", "2"]], height: 118))[0]
        }
        let room = 47.5 - 14, middle = 5 + 14 + room / 2
        let fixed = first(10), ratio = first(["ratio": 0.5]), inset = first(["inset": 2])
        XCTAssertEqual(fixed.height, 10)
        XCTAssertEqual(ratio.height, room / 2, accuracy: 0.001)
        XCTAssertEqual(inset.height, room - 4, accuracy: 0.001)
        for rect in [fixed, ratio, inset] {
            XCTAssertEqual(rect.y + rect.height / 2, middle, accuracy: 0.001, "centered in what is left, whatever its size")
        }
    }

    func testAnInsetPastATightBandsRoomCountsByItsSize() {
        // Measured with a row of 18: an inset of 2 on bands of 12 gives a bar of 10, and on bands of 20 one of 2.
        var mark = sideways
        mark["height"] = ["inset": 2]
        let found = rects(layout(chart([mark], ["chartYScale": ["range": [0, 16]]]), rows: [["Mon", "1"], ["Tue", "2"]]))
        XCTAssertEqual(found[0].height, 10, accuracy: 0.001, "6 less than the row of 14, and 4 of inset")
    }

    func testNoLabelsOnYBandsMeansNoRow() {
        let rows = [["Mon", "1"], ["Tue", "2"]]
        let hidden = rects(layout(chart([sideways], ["chartYAxis": "hidden"]), rows: rows, height: 118))
        XCTAssertEqual(hidden[0].height, 50 * 0.7, accuracy: 0.001)
        XCTAssertEqual(hidden[0].y + hidden[0].height / 2, 25, accuracy: 0.001)
        let lines: [String: Any] = ["chartYAxis": [["type": "AxisMarks", "content": [["type": "AxisGridLine"]]]]]
        let plain = rects(layout(chart([sideways], lines), rows: rows, height: 118))
        XCTAssertEqual(plain[0].height, 50 * 0.7, accuracy: 0.001, "no labels, so no half line above either")
        let onlyLabels: [String: Any] = ["chartYAxis": [["type": "AxisMarks", "content": [["type": "AxisValueLabel"]]]]]
        let labeled = rects(layout(chart([sideways], onlyLabels), rows: rows, height: 118))
        XCTAssertEqual(labeled[0].height, 33.5 * 0.7, accuracy: 0.001)
    }

    func testAnAnchorMovesACategoryLabelOnY() throws {
        func place(_ anchor: String, position: String = "automatic") throws -> ChartPoint {
            let label: [String: Any] = ["type": "AxisValueLabel", "anchor": anchor]
            let axis: [String: Any] = ["chartYAxis": [["type": "AxisMarks", "position": position, "content": [label]]]]
            return try XCTUnwrap(textPosition("Tue", in: layout(chart([sideways], axis), rows: [["Mon", "1"], ["Tue", "2"]], height: 118)))
        }
        let line = 5 + 47.5
        XCTAssertEqual(try place("top").x, 4, accuracy: 0.001)
        XCTAssertEqual(try place("top").y, line + 4, accuracy: 0.001, "under the line")
        XCTAssertEqual(try place("bottom").y, line - 4, accuracy: 0.001, "over the line")
        XCTAssertEqual(try place("leading").x, 4, accuracy: 0.001)
        XCTAssertEqual(try place("trailing").x, -4, accuracy: 0.001, "ending before the plot")
        XCTAssertEqual(try place("leading", position: "trailing").x, 310, accuracy: 0.001)
        XCTAssertEqual(try place("trailing", position: "trailing").x, 302, accuracy: 0.001, "ending inside the plot")
    }

    func testAnAnchorOnYBandsLeavesOutALabelPastThePlot() {
        let label: [String: Any] = ["type": "AxisValueLabel", "anchor": "bottom"]
        let axis: [String: Any] = ["chartYAxis": [["type": "AxisMarks", "content": [label]]]]
        let found = texts(layout(chart([sideways], axis), rows: [["Mon", "1"], ["Tue", "2"]], height: 118))
        XCTAssertFalse(found.contains("Mon"), "over the plot's top line, as on macOS 27")
        XCTAssertTrue(found.contains("Tue"))
    }

    func testTopAndBottomOnYBandsArePastTheTrailingEdge() throws {
        for position in ["top", "bottom"] {
            let axis: [String: Any] = ["chartYAxis": [["type": "AxisMarks", "position": position]]]
            XCTAssertEqual(try XCTUnwrap(textPosition("Mon", in: layout(chart([sideways], axis), rows: [["Mon", "1"]]))).x, 310, accuracy: 0.001)
        }
    }

    func testATickOnYBandsTakesRoomAtTheLeadingEdgeAndRunsIntoThePlot() {
        let axis: [String: Any] = ["chartYAxis": [["type": "AxisMarks", "content": [["type": "AxisTick"]]]]]
        let primitives = layout(chart([sideways], axis), rows: [["Mon", "1"], ["Tue", "2"]])
        let ticks = lines(primitives).filter { $0.from.y == $0.to.y }
        XCTAssertEqual(ticks.count, 3)
        XCTAssertTrue(ticks.allSatisfy { $0.from.x == 4 && $0.to.x == 8 && $0.stroke == ChartStroke() })
        XCTAssertEqual(rects(primitives)[0].x, 4, accuracy: 0.001)
        let trailing: [String: Any] = ["chartYAxis": [["type": "AxisMarks", "position": "trailing", "content": [["type": "AxisTick", "length": 10]]]]]
        let far = lines(layout(chart([sideways], trailing), rows: [["Mon", "1"], ["Tue", "2"]])).filter { $0.from.y == $0.to.y }
        XCTAssertTrue(far.allSatisfy { $0.from.x == 296 && $0.to.x == 286 }, "the plot ends 10 early and the tick runs back in")
    }

    func testAllCategoryLabelsOnYDrawHoweverTight() {
        let rows = (0..<20).map { ["Category \($0)", "1"] }
        XCTAssertEqual(texts(layout(chart([sideways]), rows: rows, height: 118)).filter { $0.hasPrefix("Category") }.count, 20, "Swift Charts lets them overlap")
    }

    func testGridlinesOnYBandsArePlainAndStopAtThePlot() {
        let primitives = layout(chart([sideways]), rows: [["Mon", "1"], ["Tue", "2"]])
        let across = lines(primitives).filter { $0.from.y == $0.to.y && $0.ink == ChartLayout.gridInk }
        XCTAssertEqual(across.count, 3)
        XCTAssertTrue(across.allSatisfy { $0.stroke == ChartStroke() })
        XCTAssertTrue(across.allSatisfy { $0.to.x == 306 })
    }

    func testThousandsOfBandsOnYThin() {
        let rows = (0..<5000).map { ["c\($0)", "1"] }
        let found = lines(layout(chart([sideways]), rows: rows, height: 120)).filter { $0.from.y == $0.to.y }
        XCTAssertLessThan(found.count, 200, "bands under a point apart")
    }

    // MARK: - Axis titles

    private func turned(_ primitives: [ChartPrimitive]) -> (text: String, center: ChartPoint, degrees: Double)? {
        primitives.compactMap { primitive -> (String, ChartPoint, Double)? in
            if case .turnedText(let text, let center, let degrees, _) = primitive { return (text, center, degrees) } else { return nil }
        }.first
    }

    func testAnXTitleSitsUnderTheLabelsAtTheLeadingEnd() throws {
        let primitives = layout(chart([bar], ["chartXAxisLabel": "Days"]), rows: [["Mon", "1"]])
        let title = try XCTUnwrap(textPosition("Days", in: primitives)), label = try XCTUnwrap(textPosition("Mon", in: primitives))
        XCTAssertEqual(title.x, 0, accuracy: 0.001)
        XCTAssertEqual(title.y, label.y + 10 + 4 + 8, accuracy: 0.001, "past the label and its gap, 8 off")
        XCTAssertLessThanOrEqual(title.y + 10, 220, "inside the chart")
    }

    func testAYTitleSitsAboveThePlotAtTheChartsTrailingEdge() throws {
        let plain = rects(layout(chart([bar]), rows: [["Mon", "1"]]))[0]
        let primitives = layout(chart([bar], ["chartYAxisLabel": "Sales"]), rows: [["Mon", "1"]])
        XCTAssertEqual(try XCTUnwrap(textPosition("Sales", in: primitives)).x, 306, accuracy: 0.001)
        XCTAssertGreaterThan(rects(primitives)[0].y, plain.y, "the plot makes room")
    }

    func testAYTitleOnASideIsTurnedAndCentered() throws {
        let leading = layout(chart([bar], ["chartYAxisLabel": ["text": "Sales", "position": "leading"]]), rows: [["Mon", "1"]])
        let left = try XCTUnwrap(turned(leading))
        XCTAssertEqual(left.degrees, 90, "both sides read top to bottom, as measured")
        XCTAssertEqual(left.center.x, 5, accuracy: 0.001, "in the room of 18: the title of 10, then 8 to the plot")
        XCTAssertEqual(rects(leading)[0].x, 18 + (306 - 18 - 26) * 0.15, accuracy: 0.001, "the plot moves over: the bar is 0.7 of it, centered")
        XCTAssertEqual(left.center.y, (5 + 202) / 2, accuracy: 0.001, "the middle of the plot")
        let trailing = layout(chart([bar], ["chartYAxisLabel": ["text": "Sales", "position": "trailing"]]), rows: [["Mon", "1"]])
        let right = try XCTUnwrap(turned(trailing))
        XCTAssertEqual(right.degrees, 90)
        XCTAssertEqual(right.center.x, 306 - 5, accuracy: 0.001, "past the labels")
    }

    func testASideTitleTakesOnlyTheVerticalPartOfAnAlignment() throws {
        func centerY(_ alignment: String) throws -> Double {
            try XCTUnwrap(turned(layout(chart([bar], ["chartYAxisLabel": ["text": "Sales", "position": "leading", "alignment": alignment]]), rows: [["Mon", "1"]]))).center.y
        }
        let top = 5.0, bottom = 202.0, half = 15.0
        for alignment in ["top", "topLeading", "topTrailing"] {
            XCTAssertEqual(try centerY(alignment), top + half, accuracy: 0.001, "\(alignment): its start at the plot's top")
        }
        for alignment in ["bottom", "bottomLeading", "bottomTrailing"] {
            XCTAssertEqual(try centerY(alignment), bottom - half, accuracy: 0.001, "\(alignment): its end at the plot's bottom")
        }
        for alignment in ["center", "leading", "trailing"] {
            XCTAssertEqual(try centerY(alignment), (top + bottom) / 2, accuracy: 0.001, alignment)
        }
    }

    func testATitleBelowOrAboveTakesOnlyTheHorizontalPartOfAnAlignment() throws {
        func x(_ alignment: String) throws -> Double {
            try XCTUnwrap(textPosition("Days", in: layout(chart([bar], ["chartXAxisLabel": ["text": "Days", "alignment": alignment]]), rows: [["Mon", "1"]]))).x
        }
        for alignment in ["leading", "topLeading", "bottomLeading"] {
            XCTAssertEqual(try x(alignment), 0, accuracy: 0.001, alignment)
        }
        for alignment in ["trailing", "topTrailing", "bottomTrailing"] {
            XCTAssertEqual(try x(alignment), 280, accuracy: 0.001, alignment)
        }
        for alignment in ["center", "top", "bottom"] {
            XCTAssertEqual(try x(alignment), 140, accuracy: 0.001, alignment)
        }
    }

    func testAYTitleAlignsAlongTheWholeChartPastLeadingLabels() throws {
        let leadingAxis: [String: Any] = ["chartYAxis": [["type": "AxisMarks", "position": "leading"]]]
        func x(_ alignment: String?) throws -> Double {
            var label: [String: Any] = ["text": "Sales"]
            label["alignment"] = alignment
            var extra = leadingAxis
            extra["chartYAxisLabel"] = label
            return try XCTUnwrap(textPosition("Sales", in: layout(chart([bar], extra), rows: [["Mon", "1"]]))).x
        }
        XCTAssertEqual(try x("leading"), 0, accuracy: 0.001)
        XCTAssertEqual(try x("center"), 153, accuracy: 0.001)
        XCTAssertEqual(try x("trailing"), 306, accuracy: 0.001)
        XCTAssertEqual(try x(nil), 0, accuracy: 0.001, "with its labels on the leading edge, a title starts there")
    }

    func testAYTitleStaysTrailingUnlessTheLabelsTakeRoomOnlyOnTheLeadingEdge() throws {
        func x(_ axis: Any, rows: [[String]], _ mark: [String: Any]) throws -> Double {
            try XCTUnwrap(textPosition("Sales", in: layout(chart([mark], ["chartYAxis": axis, "chartYAxisLabel": "Sales"]), rows: rows))).x
        }
        let both = [["type": "AxisMarks", "position": "leading"], ["type": "AxisMarks", "position": "trailing"]]
        XCTAssertEqual(try x(both, rows: [["Mon", "1"]], bar), 306, accuracy: 0.001)
        let noLabels: [[String: Any]] = [["type": "AxisMarks", "position": "leading", "content": [["type": "AxisGridLine"]]]]
        XCTAssertEqual(try x(noLabels, rows: [["Mon", "1"]], bar), 306, accuracy: 0.001)
        XCTAssertEqual(try x("hidden", rows: [["Mon", "1"]], bar), 306, accuracy: 0.001)
        let bands = [["type": "AxisMarks", "position": "leading"]]
        XCTAssertEqual(try x(bands, rows: [["Mon", "1"]], sideways), 306, accuracy: 0.001, "labels of bands take no room")
    }

    func testAnXTitleTurnsOnASideAsAYTitleDoes() throws {
        let leading = layout(chart([bar], ["chartXAxisLabel": ["text": "Days", "position": "leading"]]), rows: [["Mon", "1"]])
        XCTAssertEqual(try XCTUnwrap(turned(leading)).text, "Days")
        XCTAssertEqual(leading, layout(chart([bar], ["chartYAxisLabel": ["text": "Days", "position": "leading"]]), rows: [["Mon", "1"]]))
    }

    func testTwoTitlesShareAnEdgeEachItsOwnSpacingOff() throws {
        let labels: [String: Any] = ["chartXAxisLabel": ["text": "Days", "position": "top", "spacing": 4], "chartYAxisLabel": ["text": "Sales", "spacing": 20]]
        let primitives = layout(chart([bar], labels), rows: [["Mon", "1"]])
        let plotTop = rects(primitives)[0].y
        XCTAssertEqual(plotTop, 30, accuracy: 0.001, "the larger of the two rooms, 10 + 20")
        XCTAssertEqual(try XCTUnwrap(textPosition("Days", in: primitives)).y, plotTop - 4, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(textPosition("Sales", in: primitives)).y, plotTop - 20, accuracy: 0.001)
    }

    func testASpacingPastTheTitleTakesNoRoomBack() {
        let plain = rects(layout(chart([bar]), rows: [["Mon", "1"]]))[0]
        let bottom = rects(layout(chart([bar], ["chartXAxisLabel": ["text": "Days", "spacing": -60]]), rows: [["Mon", "1"]]))[0]
        XCTAssertEqual(bottom.y + bottom.height, plain.y + plain.height, accuracy: 0.001)
        let side = rects(layout(chart([bar], ["chartYAxisLabel": ["text": "Sales", "position": "leading", "spacing": -60]]), rows: [["Mon", "1"]]))[0]
        XCTAssertEqual(side.x, plain.x, accuracy: 0.001)
    }

    func testATitleDrawsWithNoMarksAtAll() throws {
        let primitives = layout(chart([], ["chartXAxisLabel": "Days", "chartYAxisLabel": "Sales"]))
        XCTAssertEqual(try XCTUnwrap(textPosition("Days", in: primitives)).x, 0, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(textPosition("Sales", in: primitives)).x, 306, accuracy: 0.001)
    }

    func testATopTitleStandsOutsideTopLabels() throws {
        let axis: [String: Any] = ["chartXAxis": [["type": "AxisMarks", "position": "top"]], "chartXAxisLabel": ["text": "Days", "position": "top"]]
        let primitives = layout(chart([bar], axis), rows: [["Mon", "1"]])
        let plotTop = rects(primitives)[0].y
        XCTAssertEqual(plotTop, 36, accuracy: 0.001, "a row of 18, 8 and the title of 10")
        XCTAssertEqual(try XCTUnwrap(textPosition("Days", in: primitives)).y, 10, accuracy: 0.001, "its bottom")
    }

    func testATitlesAlignmentAndSpacing() throws {
        let center = layout(chart([bar], ["chartXAxisLabel": ["text": "Days", "alignment": "center"]]), rows: [["Mon", "1"]])
        XCTAssertEqual(try XCTUnwrap(textPosition("Days", in: center)).x, (306 - 26) / 2, accuracy: 0.001, "the middle of the plot, less labels of 18 and their gaps")
        let far = layout(chart([bar], ["chartXAxisLabel": ["text": "Days", "spacing": 20]]), rows: [["Mon", "1"]])
        let near = layout(chart([bar], ["chartXAxisLabel": "Days"]), rows: [["Mon", "1"]])
        XCTAssertLessThan(try XCTUnwrap(textPosition("Mon", in: far)).y, try XCTUnwrap(textPosition("Mon", in: near)).y, "more room under the plot")
    }

    func testAnXTitleOnTopStandsAboveThePlot() throws {
        let primitives = layout(chart([bar], ["chartXAxisLabel": ["text": "Days", "position": "top"]]), rows: [["Mon", "1"]])
        let title = try XCTUnwrap(textPosition("Days", in: primitives))
        XCTAssertLessThan(title.y, rects(primitives)[0].y)
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
