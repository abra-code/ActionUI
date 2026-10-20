// Tests/Views/ChartSelectionTests.swift
// Chart selection: the description keys, the JSON value, "$selection" marks, the angle row, the
// value after a replacement, and the action timing. Real gestures cannot be driven from a test
// (synthetic events reach no SwiftUI gesture), so the bindings are exercised directly.
import XCTest
import SwiftUI
import Charts
@testable import ActionUI

private final class CollectingLogger: ActionUILogger, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var warnings: [String] { lock.withLock { recorded } }
    func log(_ message: String, _ level: LoggerLevel) {
        if level == .error { XCTFail("[CollectingLogger][ERROR] \(message)") }
        if level == .warning { lock.withLock { recorded.append(message) } }
    }
}

@MainActor
final class ChartSelectionTests: XCTestCase {
    private var logger: CollectingLogger!
    private var windowUUID: String!

    override func setUp() async throws {
        try await super.setUp()
        logger = CollectingLogger()
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func pv(_ label: String, _ value: Any, _ extra: [String: Any] = [:]) -> [String: Any] {
        var object: [String: Any] = ["label": label, "value": value]
        for (key, item) in extra { object[key] = item }
        return object
    }

    // Bars over days, plus optional top-level marks and keys.
    private func bars(_ topLevel: [[String: Any]] = [], extra: [String: Any] = [:]) -> [String: Any] {
        var description: [String: Any] = [
            "columns": ["day", ["name": "n", "type": "number"]],
            "data": [["Mon", 3], ["Tue", 5], ["Wed", 4]],
            "content": [["type": "ForEach", "content": [["type": "BarMark", "x": pv("Day", "$day"), "y": pv("N", "$n")]]]] + topLevel,
        ]
        for (key, value) in extra { description[key] = value }
        return description
    }

    private var donut: [String: Any] {
        [
            "columns": ["language", ["name": "count", "type": "number"]],
            "data": [["Swift", 42], ["Kotlin", 31], ["JavaScript", 27]],
            "content": [["type": "ForEach", "content": [
                ["type": "SectorMark", "angle": pv("Count", "$count"), "innerRadius": ["ratio": 0.6],
                 "foregroundStyle": ["by": pv("Language", "$language")]],
            ]]],
            "chartAngleSelection": "value",
        ]
    }

    private func spec(_ description: [String: Any]) -> ChartSpec {
        ChartDescription.parse(description, logger: logger).spec
    }

    private func load(_ description: [String: Any], properties extra: [String: Any] = [:]) throws {
        var properties: [String: Any] = ["chart": description]
        for (key, value) in extra { properties[key] = value }
        let element: [String: Any] = ["id": 10, "type": "Chart", "properties": properties]
        _ = try ActionUIModel.shared.loadDescription(from: element, windowUUID: windowUUID)
    }

    private var model: ViewModel {
        ActionUIModel.shared.windowModels[windowUUID]!.viewModels[10]!
    }

    private var value: String? {
        ActionUIModel.shared.getElementValue(windowUUID: windowUUID, viewID: 10) as? String
    }

    private func render(_ view: some SwiftUI.View) -> [UInt8] {
        let renderer = ImageRenderer(content: view.frame(width: 320, height: 200).background(SwiftUI.Color.white))
        renderer.scale = 2
        guard let image = renderer.cgImage else { return [] }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    // The loaded element as drawn now.
    private func renderElement() -> [UInt8] {
        let built = Chart.buildView(ActionUIElement(id: 10, type: "Chart", properties: [:], subviews: nil),
                                    model, windowUUID, model.properties, logger)
        return render(AnyView(built))
    }

    private func binder(continuous: Bool = false, actionID: String? = "picked", cache: ChartRenderCache? = nil) -> ChartSelectionBinder {
        let description = model.properties["chart"] as? [String: Any] ?? [:]
        let cache = cache ?? (model.elementCache as? ChartRenderCache) ?? ChartRenderCache()
        let rows = model.states["content"] as? [[String]] ?? []
        _ = cache.render(description: description, rows: rows, viewID: 10, logger: logger)
        return ChartSelectionBinder(model: model, spec: ChartDescription.parse(description, logger: nil).spec.selection,
                                    cache: cache, windowUUID: windowUUID, viewID: 10, actionID: actionID, continuous: continuous)
    }

    // Runs the main queue until the deferred writes (and any due actions) have landed.
    private func drain(_ seconds: TimeInterval = 0.02) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: - Description keys

    func testSelectionKeysAreTypedByTheirAxis() {
        var parsed = spec(bars(extra: ["chartXSelection": "value", "chartYSelection": "range"]))
        XCTAssertEqual(parsed.selection.x, .value)
        XCTAssertEqual(parsed.selection.xType, .string)
        XCTAssertEqual(parsed.selection.y, .range)
        XCTAssertEqual(parsed.selection.yType, .number)
        XCTAssertFalse(parsed.selection.angle)
        parsed = spec(donut)
        XCTAssertTrue(parsed.selection.angle)
        XCTAssertEqual(parsed.selection.angleType, .number)
        XCTAssertEqual(logger.warnings, [])
    }

    func testInvalidSelectionKeysAreReported() {
        let parsed = spec(bars(extra: ["chartXSelection": "hover", "chartAngleSelection": "value"]))
        XCTAssertTrue(parsed.selection.isEmpty)
        XCTAssertTrue(logger.warnings.contains { $0.contains("'chartXSelection' must be") }, "\(logger.warnings)")
        XCTAssertTrue(logger.warnings.contains { $0.contains("'chartAngleSelection' needs a SectorMark") }, "\(logger.warnings)")
        let empty = ChartDescription.parse(["chartXSelection": "value"], logger: logger).spec
        XCTAssertNil(empty.selection.x)
        XCTAssertTrue(logger.warnings.contains { $0.contains("needs a mark that plots a value on the x axis") }, "\(logger.warnings)")
    }

    func testDateSelectionsPrintDaysForDayUnits() {
        func dateChart(_ unit: String?) -> [String: Any] {
            var x = pv("Week", "$week", ["type": "date"])
            x["unit"] = unit
            return ["columns": ["week", ["name": "n", "type": "number"]],
                    "content": [["type": "ForEach", "content": [["type": "LineMark", "x": x, "y": pv("N", "$n")]]]],
                    "chartXSelection": "value"]
        }
        XCTAssertTrue(spec(dateChart("weekOfYear")).selection.xDateOnly)
        XCTAssertTrue(spec(dateChart("day")).selection.xDateOnly)
        XCTAssertFalse(spec(dateChart("hour")).selection.xDateOnly)
        XCTAssertFalse(spec(dateChart(nil)).selection.xDateOnly)
    }

    // MARK: - The value

    func testValueRoundTrips() throws {
        let selection = spec(bars(extra: ["chartXSelection": "value", "chartYSelection": "range"])).selection
        let decoded = ChartSelection.decode(#"{"x":"Tue","y":[1,4.5]}"#, spec: selection)
        XCTAssertEqual(decoded.x, .value(.string("Tue")))
        XCTAssertEqual(decoded.y, .range(.number(1), .number(4.5)))
        XCTAssertEqual(decoded.encode(spec: selection), #"{"x":"Tue","y":[1,4.5]}"#)
        XCTAssertEqual(ChartSelection().encode(spec: selection), "")
    }

    func testValuesThatDoNotFitReadAsNothing() {
        let selection = spec(bars(extra: ["chartXSelection": "value", "chartYSelection": "range"])).selection
        XCTAssertNil(ChartSelection.decode(#"{"x":3}"#, spec: selection).x, "a number on a string axis")
        XCTAssertNil(ChartSelection.decode(#"{"y":[true,4]}"#, spec: selection).y, "a boolean is not a number")
        XCTAssertNil(ChartSelection.decode(#"{"y":[5,1]}"#, spec: selection).y, "a range runs low to high")
        XCTAssertNil(ChartSelection.decode(#"{"y":3}"#, spec: selection).y, "a range selection needs a pair")
        XCTAssertNil(ChartSelection.decode(#"{"angle":3}"#, spec: selection).angle, "no angle selection declared")
        XCTAssertTrue(ChartSelection.decode("not json", spec: selection).isEmpty)
    }

    func testDatesAndIntegersEncode() {
        let chart: [String: Any] = [
            "columns": [["name": "day", "type": "date"], ["name": "n", "type": "integer"]],
            "content": [["type": "ForEach", "content": [["type": "BarMark", "x": pv("Day", "$day", ["unit": "day"]), "y": pv("N", "$n")]]]],
            "chartXSelection": "value", "chartYSelection": "value",
        ]
        let selection = spec(chart).selection
        let decoded = ChartSelection.decode(#"{"x":"2026-09-01","y":7}"#, spec: selection)
        XCTAssertEqual(decoded.y, .value(.integer(7)))
        XCTAssertEqual(decoded.encode(spec: selection), #"{"x":"2026-09-01","y":7}"#)
        XCTAssertNil(ChartSelection.decode(#"{"y":7.5}"#, spec: selection).y, "an integer axis takes whole numbers")
    }

    func testSetElementValueSelectsAndReadsBack() throws {
        try load(bars(extra: ["chartXSelection": "value"]))
        XCTAssertEqual(value, "")
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 10, value: #"{"x":"Wed"}"#)
        XCTAssertEqual(value, #"{"x":"Wed"}"#)
    }

    // MARK: - "$selection" marks

    private var selectionRule: [String: Any] {
        ["type": "RuleMark", "x": pv("Selected", "$selection"), "foregroundStyle": "gray"]
    }

    func testSelectionMarksTakeTheAxisType() {
        // The selection mark comes first and still does not decide the axis type.
        let description: [String: Any] = [
            "columns": ["day", ["name": "n", "type": "number"]],
            "content": [selectionRule, ["type": "ForEach", "content": [["type": "BarMark", "x": pv("Day", "$day"), "y": pv("N", "$n")]]]],
            "chartXSelection": "value",
        ]
        let parsed = spec(description)
        XCTAssertEqual(parsed.selection.xType, .string)
        guard case .mark(let rule)? = parsed.content.first, let x = rule.values["x"] else {
            return XCTFail("the selection rule was dropped")
        }
        XCTAssertTrue(x.isSelection)
        XCTAssertEqual(x.type, .string)
        XCTAssertEqual(logger.warnings, [])
    }

    func testSelectionMarkMisuseIsReported() {
        _ = spec(bars([selectionRule]))
        XCTAssertTrue(logger.warnings.contains { $0.contains("has no chartXSelection") }, "\(logger.warnings)")
        _ = spec(["columns": [["name": "x", "type": "number"], ["name": "n", "type": "number"]],
                  "content": [["type": "ForEach", "content": [["type": "LineMark", "x": pv("X", "$x"), "y": pv("N", "$n")]]], selectionRule],
                  "chartXSelection": "range"])
        XCTAssertTrue(logger.warnings.contains { $0.contains("which only xStart and xEnd can read") }, "\(logger.warnings)")
        _ = spec(bars([["type": "SectorMark", "angle": pv("A", "$selection")]]))
        XCTAssertTrue(logger.warnings.contains { $0.contains("reads the selection only as a plotted x or y value") }, "\(logger.warnings)")
    }

    func testSelectionMarksAreDrawnOnlyWhileSelected() {
        let description = bars([selectionRule], extra: ["chartXSelection": "value"])
        let cleaned = ChartDescription.parse(description, logger: logger).cleaned
        let rows = [["Mon", "3"], ["Tue", "5"], ["Wed", "4"]]
        let cache = ChartRenderCache()
        var rendered = cache.render(description: cleaned, rows: rows, viewID: 10, logger: logger)
        XCTAssertEqual(rendered.items.map(\.id), [0, 1, 2])
        rendered = cache.render(description: cleaned, rows: rows, selectionValue: #"{"x":"Tue"}"#, viewID: 10, logger: logger)
        XCTAssertEqual(rendered.items.map(\.id), [0, 1, 2, -1])
        XCTAssertEqual(cache.buildCount, 1, "a selection change rebuilds only the selection marks")
        XCTAssertEqual(cache.selectionBuildCount, 1)
        _ = cache.render(description: cleaned, rows: rows, selectionValue: #"{"x":"Tue"}"#, viewID: 10, logger: logger)
        XCTAssertEqual(cache.selectionBuildCount, 1, "an unchanged selection rebuilds nothing")
    }

    func testASelectedCategoryOutsideTheDataIsNotDrawn() {
        let description = bars([selectionRule], extra: ["chartXSelection": "value"])
        let cleaned = ChartDescription.parse(description, logger: logger).cleaned
        let cache = ChartRenderCache()
        let rendered = cache.render(description: cleaned, rows: [["Mon", "3"], ["Tue", "5"]], selectionValue: #"{"x":"Sun"}"#,
                                    viewID: 10, logger: logger)
        XCTAssertEqual(rendered.items.map(\.id), [0, 1], "Sun would add a category")
    }

    func testARangeOverCategoriesIsRefused() {
        let parsed = spec(bars(extra: ["chartXSelection": "range"]))
        XCTAssertNil(parsed.selection.x)
        XCTAssertTrue(logger.warnings.contains { $0.contains("needs a number or date axis") }, "\(logger.warnings)")
    }

    func testRangeSelectionMarksReadStartAndEnd() {
        let band: [String: Any] = ["type": "RectangleMark", "xStart": pv("From", "$selection"), "xEnd": pv("To", "$selection"),
                                   "opacity": 0.2]
        let description: [String: Any] = [
            "columns": [["name": "x", "type": "number"], ["name": "n", "type": "number"]],
            "content": [["type": "ForEach", "content": [["type": "LineMark", "x": pv("X", "$x"), "y": pv("N", "$n")]]], band],
            "chartXSelection": "range",
        ]
        let cleaned = ChartDescription.parse(description, logger: logger).cleaned
        let cache = ChartRenderCache()
        let rendered = cache.render(description: cleaned, rows: [["1", "2"], ["5", "3"]], selectionValue: #"{"x":[2,4]}"#,
                                    viewID: 10, logger: logger)
        XCTAssertEqual(rendered.items.count, 3, "two line points and the band")
        XCTAssertEqual(logger.warnings, [])
    }

    func testSelectedRuleDrawsLikeALiteralRule() throws {
        try load(bars([selectionRule], extra: ["chartXSelection": "value"]))
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 10, value: #"{"x":"Tue"}"#)
        let selected = renderElement()
        windowUUID = UUID().uuidString
        try load(bars([["type": "RuleMark", "x": pv("Selected", "Tue"), "foregroundStyle": "gray"]], extra: ["chartXSelection": "value"]))
        let literal = renderElement()
        XCTAssertFalse(selected.isEmpty)
        XCTAssertEqual(zip(selected, literal).filter { $0 != $1 }.count, 0)
        windowUUID = UUID().uuidString
        try load(bars(extra: ["chartXSelection": "value"]))
        XCTAssertNotEqual(zip(selected, renderElement()).filter { $0 != $1 }.count, 0, "the rule is visible")
    }

    // MARK: - Angle row

    func testAngleSelectionFindsItsRow() throws {
        try load(donut)
        let cache = ChartRenderCache()
        _ = cache.render(description: model.properties["chart"] as? [String: Any] ?? [:],
                         rows: model.states["content"] as? [[String]] ?? [], viewID: 10, logger: logger)
        XCTAssertEqual(cache.sectorRow(at: 10), 0)
        XCTAssertEqual(cache.sectorRow(at: 42), 0)
        XCTAssertEqual(cache.sectorRow(at: 50), 1)
        XCTAssertEqual(cache.sectorRow(at: 99), 2)
        XCTAssertNil(cache.sectorRow(at: 101))
    }

    func testAngleBindingWritesAngleAndRow() throws {
        try load(donut)
        let binding = binder(actionID: nil).angle(as: Double.self)
        binding.wrappedValue = 55.5
        drain()
        XCTAssertEqual(value, #"{"angle":55.5,"row":1}"#)
        XCTAssertEqual(binding.wrappedValue, 55.5)
    }

    func testIntegerAngleBindingReadsAnyHostAngle() throws {
        var integers = donut
        integers["columns"] = ["language", ["name": "count", "type": "integer"]]
        try load(integers)
        let binding = binder(actionID: nil).angle(as: Int.self)
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 10, value: #"{"angle":41.6}"#)
        XCTAssertEqual(binding.wrappedValue, 42)
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 10, value: #"{"angle":1e300}"#)
        XCTAssertNil(binding.wrappedValue, "an angle past Int's range reads as nothing, without a trap")
    }

    // MARK: - Replacement

    func testReplacementClearsASelectionThatNoLongerFits() throws {
        try load(bars(extra: ["chartXSelection": "value"]))
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 10, value: #"{"x":"Tue"}"#)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 10, propertyName: "chart",
                                                value: bars(extra: ["chartXSelection": "value", "chartLegend": "hidden"]))
        XCTAssertEqual(value, #"{"x":"Tue"}"#, "the same axes keep the selection")
        let numbers: [String: Any] = [
            "columns": [["name": "x", "type": "number"], ["name": "n", "type": "number"]],
            "content": [["type": "ForEach", "content": [["type": "LineMark", "x": pv("X", "$x"), "y": pv("N", "$n")]]]],
            "chartXSelection": "value",
        ]
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 10, propertyName: "chart", value: numbers)
        XCTAssertEqual(value, "", "a string selection does not fit a number axis")
    }

    // MARK: - Bindings and action timing

    func testBindingsWriteOnTheNextTurnAndMerge() throws {
        try load(bars(extra: ["chartXSelection": "value", "chartYSelection": "value"]))
        let binder = binder(actionID: nil)
        binder.value(.horizontal, as: String.self).wrappedValue = "Wed"
        binder.value(.vertical, as: Double.self).wrappedValue = 2.5
        XCTAssertEqual(value, "", "the write is deferred")
        drain()
        XCTAssertEqual(value, #"{"x":"Wed","y":2.5}"#)
        binder.value(.horizontal, as: String.self).wrappedValue = nil
        drain()
        XCTAssertEqual(value, #"{"y":2.5}"#)
    }

    private func countActions(_ body: () -> Void) -> () -> Int {
        var count = 0
        ActionUIModel.shared.registerActionHandler(for: "picked") { _, _, viewID, _, _ in
            XCTAssertEqual(viewID, 10)
            count += 1
        }
        body()
        return { count }
    }

    func testSettledActionFiresOnceAfterRest() throws {
        try load(bars(extra: ["chartXSelection": "value"]), properties: ["valueChangeActionID": "picked"])
        let binder = binder()
        let count = countActions {
            for day in ["Mon", "Tue", "Wed"] {
                binder.value(.horizontal, as: String.self).wrappedValue = day
                drain()
            }
        }
        XCTAssertEqual(count(), 0, "no action while the selection moves")
        drain(ChartSelectionBinder.settleDelay + 0.1)
        XCTAssertEqual(count(), 1)
        XCTAssertEqual(value, #"{"x":"Wed"}"#)
        binder.value(.horizontal, as: String.self).wrappedValue = nil
        drain()
        XCTAssertEqual(count(), 2, "a cleared selection fires at once")
    }

    func testContinuousActionFiresOnEveryChange() throws {
        try load(bars(extra: ["chartXSelection": "value"]), properties: ["valueChangeActionID": "picked", "selectionActionTiming": "continuous"])
        let binder = binder(continuous: true)
        let count = countActions {
            for day in ["Mon", "Tue", "Tue", "Wed"] {
                binder.value(.horizontal, as: String.self).wrappedValue = day
                drain()
            }
        }
        XCTAssertEqual(count(), 3, "an unchanged value fires nothing")
    }

    func testInvalidTimingIsSettled() throws {
        try load(bars(), properties: ["selectionActionTiming": "often"])
        // Stored as given; the chart reads a name it does not know as "settled".
        XCTAssertEqual(model.properties["selectionActionTiming"] as? String, "often")
        XCTAssertEqual(Chart.Props(model.properties).selectionActionTiming, .settled)
    }
}
