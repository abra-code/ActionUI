// Core/ChartDescriptionTests.swift
/*
 Tests for the chart description in Core, on every host: parsing into a ChartSpec, cleaning and its
 warnings, numbers against booleans, rows and inline data, replacing a description at runtime, and
 the selection as the element's value. Drawing is tested per renderer (Views/Chart*Tests.swift on
 Apple).
*/

import XCTest
@testable import ActionUI

private final class RecordingLogger: ActionUILogger, @unchecked Sendable {
    private let lock = Lock()
    private var recorded: [String] = []

    var warnings: [String] { lock.withLock { recorded } }

    func log(_ message: String, _ level: LoggerLevel) {
        if level == .warning || level == .error {
            lock.withLock { recorded.append(message) }
        }
    }
}

@MainActor
final class ChartDescriptionTests: XCTestCase {
    private var logger: RecordingLogger!
    private var windowUUID: String!

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        logger = RecordingLogger()
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = nil
        logger = nil
    }

    // MARK: - Fixtures

    private let columns: [Any] = ["day", ["name": "high", "type": "number"], ["name": "low", "type": "integer"],
                                  ["name": "when", "type": "date"], "team"]

    private func value(_ label: String, _ value: Any) -> [String: Any] { ["label": label, "value": value] }

    private var bar: [String: Any] { ["type": "BarMark", "x": value("Day", "$day"), "y": value("High", "$high")] }

    private func chart(_ marks: [[String: Any]], _ extra: [String: Any] = [:]) -> [String: Any] {
        var description: [String: Any] = ["columns": columns, "content": [["type": "ForEach", "content": marks]]]
        description.merge(extra) { $1 }
        return description
    }

    private func marks(_ spec: ChartSpec) -> [ChartMarkSpec] {
        func flatten(_ entries: [ChartEntry]) -> [ChartMarkSpec] {
            entries.flatMap { entry -> [ChartMarkSpec] in
                switch entry {
                case .mark(let mark): return [mark]
                case .forEach(let children, _), .plot(let children): return flatten(children)
                }
            }
        }
        return flatten(spec.content)
    }

    private func load(_ description: [String: Any]) throws -> ViewModel {
        let element: [String: Any] = ["id": 10, "type": "Chart", "properties": ["chart": description]]
        _ = try ActionUIModel.shared.loadDescription(from: element, windowUUID: windowUUID)
        return try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[10])
    }

    // MARK: - Parsing and cleaning

    func testChartIsAPortableBuiltIn() {
        XCTAssertTrue(ActionUIRegistry.builtInSpecs.contains { $0.name == "Chart" })
        XCTAssertTrue(ActionUIRegistry.shared.getElementValueType(forElementType: "Chart") == String.self)
    }

    func testAMarkParsesIntoItsFormAndColumns() {
        let parsed = ChartDescription.parse(chart([bar]), logger: logger)
        XCTAssertEqual(logger.warnings, [])
        let mark = marks(parsed.spec).first
        XCTAssertEqual(mark?.kind, .BarMark)
        XCTAssertEqual(mark?.form, .xy)
        XCTAssertEqual(parsed.spec.referencedColumns, [ChartColumnRef(index: 0, type: .string), ChartColumnRef(index: 1, type: .number)])
    }

    func testCleaningDropsWhatItWarnsAboutAndIsIdempotent() throws {
        var description = chart([bar], ["bogus": 1, "chartLegend": "sideways"])
        description["data"] = "not rows"
        let parsed = ChartDescription.parse(description, logger: logger)
        XCTAssertEqual(logger.warnings.count, 3, "\(logger.warnings)")
        XCTAssertNil(parsed.cleaned["bogus"])
        XCTAssertNil(parsed.cleaned["chartLegend"])
        XCTAssertNil(parsed.cleaned["data"])
        let quiet = RecordingLogger()
        let again = ChartDescription.parse(parsed.cleaned, logger: quiet)
        XCTAssertEqual(quiet.warnings, [])
        XCTAssertNotNil(JSONValue(any: parsed.cleaned))
        XCTAssertEqual(JSONValue(any: again.cleaned), JSONValue(any: parsed.cleaned))
    }

    func testAColumnGivenByNameIsAStringColumnAndAnUntypedObjectStaysAnObject() {
        let cleaned = ChartDescription.parse(["columns": ["day", ["name": "n"]] as [Any]], logger: logger).cleaned
        let columns = cleaned["columns"] as? [Any] ?? []
        XCTAssertEqual(columns.first as? String, "day")
        XCTAssertEqual((columns.last as? [String: Any])?["name"] as? String, "n")
    }

    func testAnIdentifierIsASCIILettersDigitsAndUnderscores() {
        for name in ["a", "_", "a1", "A_9"] {
            XCTAssertTrue(ChartDescription.isIdentifier(name), name)
        }
        for name in ["", "1a", "a-b", "\u{e9}", "a\u{e9}", "\u{FF21}", "a\u{0661}"] {
            XCTAssertFalse(ChartDescription.isIdentifier(name), name)
        }
    }

    func testANameInTextBecomesItsColumnNumberPerRow() {
        var mark = bar
        mark["accessibilityLabel"] = "$day of $team, $nope $5 $$"
        let parsed = ChartDescription.parse(chart([mark]), logger: logger)
        let texts = marks(parsed.spec).first?.modifiers.compactMap { modifier -> String? in
            guard case .accessibilityLabel(.perRow(let text)) = modifier else { return nil }
            return text
        }
        XCTAssertEqual(texts, ["$1 of $5, $nope $5 $$"])
    }

    func testANameInTextIsFoundByScalarsNotByCharacters() {
        // The combining mark is one Character with the "y" before it, U+0600 one with the "$" after it.
        var mark = bar
        mark["accessibilityLabel"] = "$day\u{301} \u{600}$team"
        let parsed = ChartDescription.parse(chart([mark]), logger: logger)
        let texts = marks(parsed.spec).first?.modifiers.compactMap { modifier -> [Unicode.Scalar]? in
            guard case .accessibilityLabel(.perRow(let text)) = modifier else { return nil }
            return Array(text.unicodeScalars)
        }
        XCTAssertEqual(texts, [Array("$1\u{301} \u{600}$5".unicodeScalars)])
    }

    // MARK: - Numbers and booleans

    func testABooleanIsNotANumberWhereTheVerifierSaysSo() {
        var mark = bar
        mark["width"] = true
        mark["opacity"] = false
        let parsed = ChartDescription.parse(chart([mark]), logger: logger)
        XCTAssertEqual(logger.warnings.count, 2, "\(logger.warnings)")
        XCTAssertEqual(marks(parsed.spec).first?.width, .automatic)
    }

    func testNumbersOfEveryIntegerAndFloatingForm() {
        for number in [2 as Any, 2.0 as Any, Int64(2) as Any, Float(2) as Any, Int32(2) as Any, UInt8(2) as Any, UInt64(2) as Any] {
            var mark = bar
            mark["width"] = number
            let parsed = ChartDescription.parse(chart([mark]), logger: logger)
            XCTAssertEqual(marks(parsed.spec).first?.width, .fixed(2), "\(type(of: number))")
        }
        XCTAssertEqual(logger.warnings, [])
    }

    func testAScaleRangeReadsABooleanAsOneOrZero() {
        let parsed = ChartDescription.parse(chart([bar], ["chartXScale": ["range": ["padding": true]]]), logger: logger)
        XCTAssertEqual(parsed.spec.x.range, .plotDimension(startPadding: 1, endPadding: 1))
    }

    // MARK: - Neutral values

    func testStyleValuesParseIntoTheNeutralModel() {
        var mark: [String: Any] = ["type": "LineMark", "x": value("Day", "$day"), "y": value("High", "$high")]
        mark["foregroundStyle"] = "red"
        mark["lineStyle"] = ["lineWidth": 2, "lineCap": "round", "lineJoin": "bevel", "dash": [3, 1] as [Any]]
        mark["interpolationMethod"] = ["cardinal": ["tension": 0.5]]
        let parsed = ChartDescription.parse(chart([mark]), logger: logger)
        XCTAssertEqual(logger.warnings, [])
        var found = 0
        for modifier in marks(parsed.spec).first?.modifiers ?? [] {
            switch modifier {
            case .foregroundStyle(let color):
                XCTAssertEqual(color, .named(.red))
                found += 1
            case .lineStyle(let stroke):
                XCTAssertEqual(stroke, ChartStroke(lineWidth: 2, lineCap: .round, lineJoin: .bevel, dash: [3, 1]))
                found += 1
            case .interpolationMethod(let method):
                XCTAssertEqual(method, .cardinal(tension: 0.5))
                found += 1
            default:
                break
            }
        }
        XCTAssertEqual(found, 3)
    }

    func testDateFormatsAreSortedAndOnlyKnownPairsParse() {
        XCTAssertEqual(ChartDescription.parseDateFormat(["dateTime": ["year": "twoDigits", "month": "wide"]]), .fields([.monthWide, .yearTwoDigits]))
        XCTAssertNil(ChartDescription.parseDateFormat(["dateTime": ["year": "wide"]]))
        XCTAssertEqual(ChartDescription.parseDateFormat(["date": "long"]), .styles(date: .long, time: .omitted))
        XCTAssertNil(ChartDescription.parseDateFormat(["date": "short"]))
    }

    func testAScaleTypeSwiftChartsStopsTheAppForIsRefused() {
        let point: [String: Any] = ["type": "PointMark", "x": value("High", "$high"), "y": value("Low", "$low")]
        let refused = ChartDescription.parse(chart([point], ["chartYScale": ["type": "log"]]), logger: logger)
        XCTAssertNil(refused.spec.y.scaleType)
        XCTAssertEqual(logger.warnings.count, 1)
        let kept = ChartDescription.parse(chart([point], ["chartYScale": ["type": "log", "domain": [1, 100]]]), logger: logger)
        XCTAssertEqual(kept.spec.y.scaleType, .log)
    }

    func testAxisMarksParseAndAStrideThatWouldDrawTooManyFallsBack() throws {
        let description = chart([bar], ["chartYAxis": [["type": "AxisMarks", "values": ["stride": ["by": 0.001]],
                                                        "content": [["type": "AxisValueLabel", "format": "decimal", "font": "caption", "anchor": "top"]]]]])
        let spec = ChartDescription.parse(description, logger: logger).spec
        XCTAssertEqual(logger.warnings, [])
        let marks = try XCTUnwrap(spec.y.marks)
        guard case .numberStride(0.001) = marks[0].values else { return XCTFail("expected a stride") }
        XCTAssertEqual(marks[0].items?.first?.font, .textStyle(.caption))
        let limited = ChartAxisStrideLimit.limited(marks, domain: .numbers(0...100), extent: nil, key: "chartYAxis", viewID: 1, logger: logger)
        guard case .automatic = limited?[0].values else { return XCTFail("expected automatic values") }
        XCTAssertEqual(logger.warnings.count, 1)
    }

    // Swift Charts stops the app on these two strides, so a description never reaches it with one.
    func testACalendarStrideSwiftChartsStopsTheAppForIsRefused() throws {
        let dates: [Any] = [["name": "when", "type": "date"], ["name": "high", "type": "number"]]
        func description(_ unit: String) -> [String: Any] {
            ["columns": dates, "chartXAxis": [["type": "AxisMarks", "values": ["stride": ["by": unit]]]],
             "content": [["type": "ForEach", "content": [["type": "PointMark", "x": value("When", "$when"), "y": value("High", "$high")]]]]]
        }
        func parsed(_ unit: String) -> ChartAxisValues? {
            ChartDescription.parse(description(unit), logger: logger).spec.x.marks?.first?.values
        }
        for unit in ["quarter", "weekOfMonth"] {
            guard case .automatic? = parsed(unit) else { return XCTFail("\(unit) must fall back to automatic values") }
            // The cleaned description has dropped the stride, so a second parse has nothing to say.
            let quiet = RecordingLogger()
            _ = ChartDescription.parse(ChartDescription.parse(description(unit), logger: nil).cleaned, logger: quiet)
            XCTAssertEqual(quiet.warnings, [])
        }
        XCTAssertEqual(logger.warnings.count, 2, "\(logger.warnings)")
        for unit in ["year", "month", "weekOfYear", "day", "hour", "minute", "second"] {
            guard case .calendarStride? = parsed(unit) else { return XCTFail("\(unit) stays a stride") }
        }
        XCTAssertEqual(logger.warnings.count, 2, "\(logger.warnings)")
    }

    func testAScrollLengthThatWouldLayOutTooManyMarksIsLengthened() {
        let point: [String: Any] = ["type": "PointMark", "x": value("High", "$high"), "y": value("Low", "$low")]
        let spec = ChartDescription.parse(chart([point], ["chartScrollableAxes": "horizontal", "chartXVisibleDomain": ["length": 1]]), logger: logger).spec
        XCTAssertEqual(spec.scroll.axes, .horizontal)
        XCTAssertEqual(spec.scroll.xLength, .amount(1))
        let limited = ChartVisibleLengthLimit.limited(spec.scroll, x: spec.x, y: spec.y, xExtent: 0...1000, yExtent: nil, viewID: 1, logger: logger)
        XCTAssertEqual(limited.xLength, .amount(25))
    }

    func testAnAnnotationDecodesItsElementAndCannotHoldAChart() {
        let text: [String: Any] = ["type": "VStack", "children": [["type": "Text", "properties": ["text": "$team", "size": 1.5]]]]
        var mark = bar
        mark["annotation"] = ["content": text, "position": "top", "overflowResolution": ["x": ["fit": "plot"]]]
        let parsed = ChartDescription.parse(chart([mark]), logger: logger)
        XCTAssertEqual(logger.warnings, [])
        let annotations = marks(parsed.spec).first?.modifiers.compactMap { modifier -> ChartAnnotationSpec? in
            guard case .annotation(let annotation) = modifier else { return nil }
            return annotation
        }
        let annotation = annotations?.first
        XCTAssertEqual(annotation?.content.type, "VStack")
        XCTAssertEqual(annotation?.position, .top)
        XCTAssertEqual(annotation?.overflow, ChartOverflowResolution(x: .fitTo(.plot), y: .automatic))
        let children = annotation?.content.subviews?["children"] as? [ActionUIElement]
        XCTAssertEqual(children?.first?.properties["text"] as? String, "$5")
        XCTAssertEqual(children?.first?.properties["size"] as? Double, 1.5)

        mark["annotation"] = ["content": ["type": "VStack", "children": [["type": "Chart"]]]]
        let refused = ChartDescription.parse(chart([mark]), logger: logger)
        XCTAssertEqual(marks(refused.spec).first?.modifiers.count, 0)
        XCTAssertEqual(logger.warnings.count, 1)
    }

    // MARK: - Rows

    func testRowStringsFollowOneRuleForEveryValue() {
        let row: [Any] = [1, 2.5, "a", true, false, ActionUIJSONNull(), 0, -0.0, 1e21, 0.1]
        XCTAssertTrue(ChartDescription.isDataRow(row))
        XCTAssertEqual(ChartDescription.rowStrings([row]), [["1", "2.5", "a", "true", "false", "", "0", "0", "1e+21", "0.1"]])
    }

    func testADataRowHoldsOnlyJSONScalars() {
        XCTAssertFalse(ChartDescription.isDataRow("row"))
        XCTAssertFalse(ChartDescription.isDataRow([["nested"]] as [Any]))
        XCTAssertFalse(ChartDescription.isDataRow([["a": 1]] as [Any]))
        XCTAssertFalse(ChartDescription.isDataRow([Date()] as [Any]))
    }

    func testANumberCellAllowsSpacesButNotLineBreaksAroundIt() {
        XCTAssertEqual(ChartTypedColumns.parse(" 12\t", as: .number), .number(12))
        XCTAssertEqual(ChartTypedColumns.parse("\u{A0}7\u{200B}", as: .integer), .integer(7))
        XCTAssertNil(ChartTypedColumns.parse("12\n", as: .number))
        XCTAssertNil(ChartTypedColumns.parse("\n7", as: .integer))
        XCTAssertEqual(ChartTypedColumns.parse(" 12 ", as: .string), .string(" 12 "))
    }

    func testInlineDataBecomesTheRowsAndLeavesTheDescription() throws {
        let model = try load(chart([bar], ["data": [["Mon", 3], ["Tue", 4.5]] as [Any]]))
        XCTAssertEqual(ActionUIModel.shared.getElementRows(windowUUID: windowUUID, viewID: 10), [["Mon", "3"], ["Tue", "4.5"]])
        XCTAssertNil((model.properties["chart"] as? [String: Any])?["data"])
    }

    func testRowsChangeWithoutTouchingTheDescription() throws {
        let model = try load(chart([bar]))
        XCTAssertEqual(ActionUIModel.shared.getElementRows(windowUUID: windowUUID, viewID: 10), [])
        let before = try XCTUnwrap(JSONValue(any: model.properties["chart"] as Any))
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 10, rows: [["Mon", "3"]])
        ActionUIModel.shared.appendElementRows(windowUUID: windowUUID, viewID: 10, rows: [["Tue", "4"]])
        XCTAssertEqual(ActionUIModel.shared.getElementRows(windowUUID: windowUUID, viewID: 10), [["Mon", "3"], ["Tue", "4"]])
        XCTAssertEqual(JSONValue(any: model.properties["chart"] as Any), before)
    }

    func testADescriptionSetAtRuntimeIsCleanedAndItsDataBecomesTheRows() throws {
        let model = try load(chart([bar]))
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 10, propertyName: "chart",
                                                value: chart([bar], ["bogus": 1, "data": [["Wed", 5]] as [Any]]))
        let stored = try XCTUnwrap(model.properties["chart"] as? [String: Any])
        XCTAssertNil(stored["bogus"])
        XCTAssertNil(stored["data"])
        XCTAssertEqual(logger.warnings.count, 1, "\(logger.warnings)")
        XCTAssertEqual(ActionUIModel.shared.getElementRows(windowUUID: windowUUID, viewID: 10), [["Wed", "5"]])
    }

    func testADescriptionThatIsNotAnObjectIsDropped() throws {
        let model = try load(chart([bar]))
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 10, propertyName: "chart", value: "not a chart")
        XCTAssertNil(model.properties["chart"])
        XCTAssertEqual(logger.warnings.count, 1, "\(logger.warnings)")
    }

    // MARK: - Selection

    private func selection(_ extra: [String: Any]) -> ChartSelectionSpec {
        let point: [String: Any] = ["type": "PointMark", "x": value("High", "$high"), "y": value("Day", "$day")]
        return ChartDescription.parse(chart([point], extra), logger: nil).spec.selection
    }

    func testASelectionReadsBackAndWritesSortedShortestText() {
        let spec = selection(["chartXSelection": "value", "chartYSelection": "value"])
        let decoded = ChartSelection.decode(#"{"y":"a/b","x":0.1}"#, spec: spec)
        XCTAssertEqual(decoded.x, .value(.number(0.1)))
        XCTAssertEqual(decoded.y, .value(.string("a/b")))
        XCTAssertEqual(decoded.encode(spec: spec), #"{"x":0.1,"y":"a/b"}"#)
    }

    func testAnEmptySelectionIsAnEmptyValue() {
        let spec = selection(["chartXSelection": "value"])
        XCTAssertTrue(ChartSelection.decode("", spec: spec).isEmpty)
        XCTAssertEqual(ChartSelection().encode(spec: spec), "")
    }

    func testAPartThatDoesNotFitReadsAsNothing() {
        let spec = selection(["chartXSelection": "range"])
        XCTAssertNil(ChartSelection.decode(#"{"x":[4,1]}"#, spec: spec).x, "a reversed range")
        XCTAssertNil(ChartSelection.decode(#"{"x":3}"#, spec: spec).x, "a value for a range")
        XCTAssertNil(ChartSelection.decode(#"{"x":[true,false]}"#, spec: spec).x, "booleans")
        XCTAssertNil(ChartSelection.decode(#"{"y":1}"#, spec: spec).y, "no such selection")
        XCTAssertTrue(ChartSelection.decode("{", spec: spec).isEmpty, "not JSON")
        XCTAssertEqual(ChartSelection.decode(#"{"x":[1,4.5]}"#, spec: spec).x, .range(.number(1), .number(4.5)))
    }

    func testAnAngleSelectionKeepsItsRowAsGiven() {
        let sector: [String: Any] = ["type": "SectorMark", "angle": value("High", "$high")]
        let spec = ChartDescription.parse(chart([sector], ["chartAngleSelection": "value"]), logger: nil).spec.selection
        let decoded = ChartSelection.decode(#"{"angle":12.5,"row":3}"#, spec: spec)
        XCTAssertEqual(decoded.angle, 12.5)
        XCTAssertEqual(decoded.row, 3)
        XCTAssertEqual(decoded.encode(spec: spec), #"{"angle":12.5,"row":3}"#)
        XCTAssertNil(ChartSelection.decode(#"{"angle":12,"row":1.5}"#, spec: spec).row)
    }

    func testADescriptionThatCannotHoldTheSelectionClearsIt() throws {
        let model = try load(chart([bar], ["chartXSelection": "value"]))
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 10, value: #"{"x":"Mon"}"#)
        XCTAssertEqual(model.value as? String, #"{"x":"Mon"}"#)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 10, propertyName: "chart", value: chart([bar], ["chartXSelection": "value"]))
        XCTAssertEqual(model.value as? String, #"{"x":"Mon"}"#, "a description that can hold it keeps it")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 10, propertyName: "chart", value: chart([bar]))
        XCTAssertEqual(model.value as? String, "")
    }
}
