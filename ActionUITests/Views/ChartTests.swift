// Tests/Views/ChartTests.swift
import XCTest
import SwiftUI
import Charts
@testable import ActionUI

// Records warnings so tests can assert that validation reported a problem (or did not).
private final class RecordingLogger: ActionUILogger, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var warnings: [String] { lock.withLock { recorded } }

    func log(_ message: String, _ level: LoggerLevel) {
        if level == .error {
            XCTFail("[RecordingLogger][ERROR] \(message)")
        }
        if level == .warning {
            lock.withLock { recorded.append(message) }
        }
    }
}

@MainActor
final class ChartTests: XCTestCase {
    private var logger: RecordingLogger!
    private var windowUUID: String!

    override func setUp() async throws {
        try await super.setUp()
        logger = RecordingLogger()
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

    // MARK: - Fixtures

    private let lineContent: [Any] = [
        ["type": "ForEach", "content": [
            ["type": "LineMark",
             "x": ["label": "Week", "value": "$week", "unit": "weekOfYear"],
             "y": ["label": "Users", "value": "$users"],
             "foregroundStyle": ["by": ["label": "Platform", "value": "$platform"]]],
        ]],
    ]

    private var columns: [Any] {
        [["name": "week", "type": "date"], "platform", ["name": "users", "type": "number"]]
    }

    private func description(data: [[Any]]? = nil, content: [Any]? = nil) -> [String: Any] {
        var chart: [String: Any] = ["columns": columns, "content": content ?? lineContent]
        chart["data"] = data
        return chart
    }

    private func loadChart(_ chart: [String: Any]?) throws {
        var properties: [String: Any] = [:]
        properties["chart"] = chart
        let element: [String: Any] = ["id": 10, "type": "Chart", "properties": properties]
        _ = try ActionUIModel.shared.loadDescription(from: element, windowUUID: windowUUID)
    }

    private var model: ViewModel {
        ActionUIModel.shared.windowModels[windowUUID]!.viewModels[10]!
    }

    private var rows: [[String]]? {
        ActionUIModel.shared.getElementRows(windowUUID: windowUUID, viewID: 10)
    }

    private var storedDescription: [String: Any]? {
        ActionUIModel.shared.getElementProperty(windowUUID: windowUUID, viewID: 10, propertyName: "chart") as? [String: Any]
    }

    // MARK: - Data rules

    func testInlineDataSeedsTheRowsAtLoadAndLeavesTheDescription() throws {
        try loadChart(description(data: [["2026-08-03", "iOS", 1180], ["2026-08-03", "macOS", 790.5]]))
        XCTAssertEqual(rows, [["2026-08-03", "iOS", "1180"], ["2026-08-03", "macOS", "790.5"]])
        XCTAssertNotNil(storedDescription)
        XCTAssertNil(storedDescription?["data"], "the stored description keeps no data")
    }

    func testReplacingWithDataReplacesTheRows() throws {
        try loadChart(description(data: [["2026-08-03", "iOS", 1]]))
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 10, propertyName: "chart",
                                                value: description(data: [["2026-09-07", "macOS", 2], ["2026-09-14", "macOS", 3]]))
        XCTAssertEqual(rows, [["2026-09-07", "macOS", "2"], ["2026-09-14", "macOS", "3"]])
        XCTAssertNil(storedDescription?["data"])
    }

    func testReplacingWithoutDataKeepsStreamedRows() throws {
        try loadChart(description())
        let streamed = [["2026-08-03", "iOS", "10"], ["2026-08-10", "iOS", "12"]]
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 10, rows: streamed)
        ActionUIModel.shared.appendElementRows(windowUUID: windowUUID, viewID: 10, rows: [["2026-08-17", "iOS", "15"]])

        // Read the description back, change one thing, set it again.
        var chart = try XCTUnwrap(storedDescription)
        chart["chartLegend"] = "hidden"
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 10, propertyName: "chart", value: chart)

        XCTAssertEqual(rows, streamed + [["2026-08-17", "iOS", "15"]])
        XCTAssertEqual(storedDescription?["chartLegend"] as? String, "hidden")
    }

    func testRowsAPINeverChangesTheDescription() throws {
        try loadChart(description())
        let before = try XCTUnwrap(storedDescription) as NSDictionary
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 10, rows: [["2026-08-03", "iOS", "1"]])
        ActionUIModel.shared.clearElementRows(windowUUID: windowUUID, viewID: 10)
        XCTAssertTrue(before.isEqual(to: try XCTUnwrap(storedDescription)))
    }

    func testSettingAnotherPropertyLeavesTheRows() throws {
        try loadChart(description(data: [["2026-08-03", "iOS", 1]]))
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 10, propertyName: "hidden", value: true)
        XCTAssertEqual(rows, [["2026-08-03", "iOS", "1"]])
    }

    func testAChartWithoutADescriptionHasEmptyRows() throws {
        try loadChart(nil)
        XCTAssertEqual(rows, [])
    }

    func testCellStrings() {
        XCTAssertEqual(ChartDescription.cellString(1180), "1180")
        XCTAssertEqual(ChartDescription.cellString(1180.0), "1180")
        XCTAssertEqual(ChartDescription.cellString(12.5), "12.5")
        XCTAssertEqual(ChartDescription.cellString(-0.0), "0")
        XCTAssertEqual(ChartDescription.cellString(NSNumber(value: true)), "true")
        XCTAssertEqual(ChartDescription.cellString(NSNumber(value: false)), "false")
        XCTAssertEqual(ChartDescription.cellString(NSNull()), "")
        XCTAssertEqual(ChartDescription.cellString("iOS"), "iOS")
        // From JSONSerialization, as a host's JSON arrives: booleans must not become 1 / 0.
        let decoded = try! JSONSerialization.jsonObject(with: Data("[true, 7, 0.25]".utf8)) as! [Any]
        XCTAssertEqual(decoded.map(ChartDescription.cellString), ["true", "7", "0.25"])
    }

    // MARK: - Validation

    func testValidationKeepsAValidDescriptionAndIsIdempotent() {
        let chart = description(data: [["2026-08-03", "iOS", 1]])
        let cleaned = ChartDescription.parse(chart, logger: logger).cleaned
        XCTAssertEqual(logger.warnings, [])
        let again = ChartDescription.parse(cleaned, logger: logger).cleaned
        XCTAssertTrue((cleaned as NSDictionary).isEqual(to: again))
        XCTAssertNotNil(cleaned["data"], "validation keeps data; seeding removes it")
    }

    func testValidationDropsWhatItCannotUse() {
        let chart: [String: Any] = [
            "columns": columns,
            "content": [
                ["type": "ForEach", "content": [
                    ["type": "ForEach", "content": []],                                  // nested ForEach
                    ["type": "BarMark", "x": ["label": "Week", "value": "$week"]],       // no y
                    ["type": "AreaMark", "x": ["label": "a", "value": 1], "y": ["label": "b", "value": 2]], // unsupported here
                    ["type": "LineMark", "x": ["label": "Platform", "value": "$platform"], // the one valid mark
                     "y": ["label": "Users", "value": "$users"]],
                ]],
            ],
            "chartFoo": 1,
        ]
        let parsed = ChartDescription.parse(chart, logger: logger)
        let forEach = (parsed.cleaned["content"] as? [Any])?.first as? [String: Any]
        XCTAssertEqual((forEach?["content"] as? [Any])?.count, 1)
        XCTAssertNil(parsed.cleaned["chartFoo"])
        XCTAssertEqual(logger.warnings.count, 4, "\(logger.warnings)")
    }

    func testAxisTypeMismatchDropsTheLaterMark() {
        let chart: [String: Any] = [
            "columns": columns,
            "content": [
                ["type": "ForEach", "content": [
                    ["type": "LineMark", "x": ["label": "Week", "value": "$week"], "y": ["label": "Users", "value": "$users"]],
                    ["type": "LineMark", "x": ["label": "Platform", "value": "$platform"], "y": ["label": "Users", "value": "$users"]],
                ]],
            ],
        ]
        let parsed = ChartDescription.parse(chart, logger: logger)
        let forEach = (parsed.cleaned["content"] as? [Any])?.first as? [String: Any]
        XCTAssertEqual((forEach?["content"] as? [Any])?.count, 1)
        XCTAssertTrue(logger.warnings.contains { $0.contains("x axis of date values") }, "\(logger.warnings)")
    }

    func testUntypedReferenceIsPlottedAsTextWithAWarning() {
        let chart: [String: Any] = [
            "columns": [["name": "a"], "b"],   // "a" has no type; a bare name would be a string column
            "content": [["type": "ForEach", "content": [
                ["type": "BarMark", "x": ["label": "A", "value": "$a"], "y": ["label": "B", "value": "$2", "type": "integer"]],
            ]]],
        ]
        let parsed = ChartDescription.parse(chart, logger: logger)
        XCTAssertEqual(logger.warnings.count, 1, "\(logger.warnings)")
        guard case .forEach(let children, _)? = parsed.spec.content.first, case .mark(let mark)? = children.first else {
            return XCTFail("expected one mark in a ForEach")
        }
        XCTAssertEqual(mark.values["x"]?.type, .string)
        XCTAssertEqual(mark.values["y"]?.type, .integer, "the value's own type is used")
        // Validation writes the default type, so the cleaned description parses without a warning.
        let quiet = RecordingLogger()
        _ = ChartDescription.parse(parsed.cleaned, logger: quiet)
        XCTAssertEqual(quiet.warnings, [])
    }

    func testReferenceShapedTextOutsideAForEachIsLiteralWithAWarning() {
        let chart: [String: Any] = [
            "columns": ["platform"],
            "content": [["type": "BarMark", "x": ["label": "P", "value": "$platform"], "y": ["label": "N", "value": 3]]],
        ]
        let parsed = ChartDescription.parse(chart, logger: logger)
        XCTAssertEqual(logger.warnings.count, 1)
        guard case .mark(let mark)? = parsed.spec.content.first, case .literal(.string(let text))? = mark.values["x"]?.source else {
            return XCTFail("expected a literal mark")
        }
        XCTAssertEqual(text, "$platform")
    }

    func testDomainsAreTypedByTheAxis() {
        var chart = description()
        chart["chartXScale"] = ["domain": ["2026-08-01", "2026-09-30"]]
        chart["chartYScale"] = ["domain": [0, 2000]]
        let spec = ChartDescription.parse(chart, logger: logger).spec
        XCTAssertEqual(logger.warnings, [])
        guard case .dates = spec.x.domain.kind, case .numbers(let range) = spec.y.domain.kind else {
            return XCTFail("expected a date x domain and a number y domain")
        }
        XCTAssertEqual(range, 0...2000)

        chart["chartYScale"] = ["domain": ["a", "b"]]   // strings on a number axis
        _ = ChartDescription.parse(chart, logger: logger)
        XCTAssertEqual(logger.warnings.count, 1)
    }

    func testAnUntypedObjectColumnStaysUntypedWhenCleaned() {
        let chart: [String: Any] = [
            "columns": [["name": "when"], ["name": "n", "type": "number"]],
            "content": [["type": "ForEach", "content": [
                ["type": "LineMark", "x": ["label": "When", "value": "$when", "unit": "day"], "y": ["label": "N", "value": "$n"]],
            ]]],
        ]
        // An untyped {"name"} column must not come back as a bare name (a string column): the
        // unit makes "$when" a date, and re-validation must keep it one.
        let first = ChartDescription.parse(chart, logger: logger)
        let second = ChartDescription.parse(first.cleaned, logger: logger)
        guard case .forEach(let a, _)? = first.spec.content.first, case .mark(let m1)? = a.first,
              case .forEach(let b, _)? = second.spec.content.first, case .mark(let m2)? = b.first else { return XCTFail("shape") }
        XCTAssertEqual(m1.values["x"]?.type, .date)
        XCTAssertEqual(m2.values["x"]?.type, .date)
        XCTAssertTrue((first.cleaned as NSDictionary).isEqual(to: second.cleaned), "\(first.cleaned) vs \(second.cleaned)")
    }

    func testALiteralReferenceWarnsOnceNotOnEverySetElementProperty() throws {
        try loadChart(["columns": ["platform"],
                       "content": [["type": "BarMark", "x": ["label": "P", "value": "$platform"], "y": ["label": "N", "value": 3]]]])
        let before = logger.warnings.count
        XCTAssertEqual(before, 1, "the load warns once: \(logger.warnings)")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 10, propertyName: "hidden", value: false)
        XCTAssertEqual(logger.warnings.count, before, "\(logger.warnings)")
    }

    func testCleaningAMessyDescriptionIsIdempotentAndQuiet() throws {
        let cases: [[String: Any]] = [
            ["columns": [["name": "a", "type": "bogus"], "b", "b", "9x", 5, ["name": "c", "type": "date"]],
             "content": [["type": "ForEach", "id": 1, "content": [
                ["type": "LineMark", "x": ["label": "A", "value": "$a", "unit": "day"], "y": ["label": "B", "value": "$2", "type": "integer", "unit": "day"],
                 "foregroundStyle": ["by": ["label": "Q", "value": "$4"]]],
                ["type": "LineMark", "x": ["label": "A", "value": "$1"], "y": ["label": "B", "value": "$zz"]],
                ["type": "BarMark", "x": ["label": "A", "value": "$c", "unit": "bogus"], "y": ["label": "B", "value": 1.5, "type": "integer"]],
                ["type": "BarMark", "x": ["label": "A", "value": "2026-01-01", "type": "number", "unit": "day"], "y": ["label": "B", "value": "$0", "type": "number"],
                 "foregroundStyle": "notacolor"],
             ]], ["type": "BarMark", "x": ["label": "x", "value": "$a"], "y": ["label": "y", "value": 3], "foregroundStyle": "red"]],
             "chartXScale": ["domain": [5, 1]], "chartYScale": ["domain": ["automatic": ["includesZero": 1]], "range": 3],
             "chartXAxis": "bogus", "chartYAxisLabel": 3, "chartLegend": ["position": "bottom", "x": 1],
             "data": [[1, "a", true, NSNull()]], "extra:ios": 1, "content:macos": []],
            ["columns": "x", "content": "y", "data": [1], "chartLegend": 3],
        ]
        // Re-validation runs on every setElementProperty: the cleaned description must parse
        // to itself without a warning.
        for chart in cases {
            let first = ChartDescription.parse(chart, logger: logger)
            let quiet = RecordingLogger()
            let second = ChartDescription.parse(first.cleaned, logger: quiet)
            XCTAssertEqual(quiet.warnings, [], "first: \(logger.warnings)")
            XCTAssertTrue((first.cleaned as NSDictionary).isEqual(to: second.cleaned), "\(first.cleaned)\n vs \(second.cleaned)")
        }
    }

    // MARK: - Building

    func testRowsWithUnparsableCellsAreSkippedWithOneWarning() throws {
        try loadChart(description(data: [["2026-08-03", "iOS", 1], ["not a date", "iOS", 2], ["2026-08-10", "iOS", "many"]]))
        let cache = ChartRenderCache()
        let rendered = cache.render(description: try XCTUnwrap(storedDescription), rows: try XCTUnwrap(rows), viewID: 10, logger: logger)
        XCTAssertEqual(rendered.items.count, 1)
        XCTAssertEqual(logger.warnings.filter { $0.contains("skipped 2 row(s)") }.count, 1, "\(logger.warnings)")
    }

    func testIntegerColumnsBuild() {
        let chart: [String: Any] = [
            "columns": ["day", ["name": "count", "type": "integer"]],
            "content": [["type": "ForEach", "content": [
                ["type": "BarMark", "x": ["label": "Day", "value": "$day"], "y": ["label": "Count", "value": "$count"]],
            ]]],
        ]
        let spec = ChartDescription.parse(chart, logger: logger).spec
        let cache = ChartRenderCache()
        let rendered = cache.render(description: chart, rows: [["Mon", "1"], ["Tue", "3"], ["Wed", "2.5"]], viewID: 10, logger: logger)
        XCTAssertEqual(spec.referencedColumns, [ChartColumnRef(index: 0, type: .string), ChartColumnRef(index: 1, type: .integer)])
        XCTAssertEqual(rendered.items.count, 2, "2.5 is not an integer")
    }

    func testUnchangedInputsRebuildNothing() throws {
        let chart = ChartDescription.parse(description(), logger: logger).cleaned
        let cache = ChartRenderCache()
        let data = [["2026-08-03", "iOS", "1"], ["2026-08-10", "iOS", "2"]]
        _ = cache.render(description: chart, rows: data, viewID: 10, logger: logger)
        _ = cache.render(description: chart, rows: data.map { $0.map { String($0) } }, viewID: 10, logger: logger)
        XCTAssertEqual(cache.buildCount, 1)
        _ = cache.render(description: chart, rows: data + [["2026-08-17", "iOS", "3"]], viewID: 10, logger: logger)
        XCTAssertEqual(cache.buildCount, 2)
        var legendHidden = chart
        legendHidden["chartLegend"] = "hidden"
        _ = cache.render(description: legendHidden, rows: data, viewID: 10, logger: logger)
        XCTAssertEqual(cache.buildCount, 3)
    }

    // MARK: - Rendering

    private func render(_ view: some SwiftUI.View) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: 320, height: 200).background(SwiftUI.Color.white))
        // 2x: at 1x, layout rounding shifts pixels even for a pass-through modifier.
        renderer.scale = 2
        return renderer.cgImage
    }

    private func pixels(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    func testTheChartRendersAndItsNeutralModifiersDrawNothingExtra() throws {
        try loadChart(description(data: [["2026-08-03", "iOS", 10], ["2026-08-10", "iOS", 14], ["2026-08-03", "macOS", 7], ["2026-08-10", "macOS", 9]]))
        let built = Chart.buildView(ActionUIElement(id: 10, type: "Chart", properties: [:], subviews: nil),
                                    model, windowUUID, model.validatedProperties, logger)
        let chartImage = try XCTUnwrap(render(AnyView(built)))

        // The same marks, typed, with only an identity plot style: Swift Charts itself shifts a few
        // pixels of antialiasing whenever chartPlotStyle is present, even as { $0 }, and the
        // chart always applies it so its type never changes.
        let weeks = ["2026-08-03", "2026-08-10", "2026-08-03", "2026-08-10"].map { DateHelper.parseDate(from: $0)! }
        let platforms = ["iOS", "iOS", "macOS", "macOS"]
        let users: [Double] = [10, 14, 7, 9]
        let reference = Charts.Chart(weeks.indices, id: \.self) { i in
            Charts.LineMark(x: .value("Week", weeks[i], unit: .weekOfYear), y: .value("Users", users[i]))
                .foregroundStyle(by: .value("Platform", platforms[i]))
        }
        let referenceImage = try XCTUnwrap(render(reference.chartPlotStyle { plot in plot }))

        let a = pixels(chartImage)
        XCTAssertGreaterThan(a.enumerated().filter { $0.offset % 4 == 0 && $0.element < 200 }.count, 500, "the chart drew something")
        let differing = zip(a, pixels(referenceImage)).filter { $0 != $1 }.count
        XCTAssertEqual(differing, 0, "erased marks plus neutral modifiers draw exactly what typed marks draw")
    }

    // MARK: - Rendering smoke tests

    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func loadDocument(_ relativePath: String) throws -> ActionUIElement {
        let data = try Data(contentsOf: Self.repositoryRoot.appendingPathComponent(relativePath))
        return try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
    }

    private func chartElements(in element: any ActionUIElementBase) -> [ActionUIElement] {
        let own = element.type == "Chart" ? [element as? ActionUIElement].compactMap { $0 } : []
        return own + element.childElements.flatMap { chartElements(in: $0) }
    }

    // Renders one Chart through ActionUIView, as a window would, and counts the pixels it drew.
    private func renderChart(_ element: ActionUIElement) throws -> (image: CGImage, inked: Int) {
        let viewModel = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id])
        let image = try XCTUnwrap(render(ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)))
        let inked = pixels(image).enumerated().filter { $0.offset % 4 == 0 && $0.element < 200 }.count
        return (image, inked)
    }

    // Chart.scroll.json is drawn in a window by ChartScrollTests: offscreen, a scrolling chart
    // draws no marks.
    func testEveryChartExampleRendersWithoutWarnings() throws {
        for path in ["ActionUISwiftTestApp/Resources/Chart.json", "ActionUISwiftTestApp/Resources/Chart.selection.json",
                     "ActionUISwiftTestApp/Resources/Chart.annotation.json", "Documentation/Elements/Chart.json"] {
            let charts = chartElements(in: try loadDocument(path))
            XCTAssertFalse(charts.isEmpty, path)
            for chart in charts {
                XCTAssertGreaterThan(try renderChart(chart).inked, 500, "\(path): chart \(chart.id) drew something")
            }
        }
        XCTAssertEqual(logger.warnings, [], "the examples load and render without warnings")
    }

    func testTheDynamicExampleTakesSeveralDescriptionsInARow() throws {
        let chart = try XCTUnwrap(chartElements(in: try loadDocument("ActionUISwiftTestApp/Resources/Chart.dynamic.json")).first)
        XCTAssertLessThan(try renderChart(chart).inked, 500, "no description yet: an empty plot area")

        // What the test app's buttons do: lines, rows, bars, another week, lines again.
        func described(_ mark: String) -> [String: Any] {
            var chart = description(content: [["type": "ForEach", "content": [
                ["type": mark,
                 "x": ["label": "Week", "value": "$week", "unit": "weekOfYear"],
                 "y": ["label": "Users", "value": "$users"],
                 "foregroundStyle": ["by": ["label": "Platform", "value": "$platform"]]],
            ]]])
            chart["chartLegend"] = ["position": "bottom"]
            return chart
        }
        let model = ActionUIModel.shared
        model.setElementProperty(windowUUID: windowUUID, viewID: chart.id, propertyName: "chart", value: described("LineMark"))
        model.setElementRows(windowUUID: windowUUID, viewID: chart.id, rows: [
            ["2026-08-03", "iOS", "1100"], ["2026-08-03", "macOS", "760"],
            ["2026-08-10", "iOS", "1200"], ["2026-08-10", "macOS", "765"],
        ])
        let lines = try renderChart(chart)
        XCTAssertGreaterThan(lines.inked, 500, "lines")

        model.setElementProperty(windowUUID: windowUUID, viewID: chart.id, propertyName: "chart", value: described("BarMark"))
        let bars = try renderChart(chart)
        XCTAssertGreaterThan(bars.inked, lines.inked, "bars fill more of the plot than lines")
        XCTAssertEqual(rows?.count, 4, "replacing the description kept the streamed rows")

        model.appendElementRows(windowUUID: windowUUID, viewID: chart.id, rows: [["2026-08-17", "iOS", "1300"], ["2026-08-17", "macOS", "780"]])
        let threeWeeks = try renderChart(chart)
        XCTAssertGreaterThan(threeWeeks.inked, 500)
        XCTAssertNotEqual(pixels(threeWeeks.image), pixels(bars.image), "an appended week redraws the bars")
        XCTAssertEqual(rows?.count, 6)

        model.setElementProperty(windowUUID: windowUUID, viewID: chart.id, propertyName: "chart", value: described("LineMark"))
        XCTAssertGreaterThan(try renderChart(chart).inked, 500, "lines again")
        XCTAssertEqual(logger.warnings, [])
    }

    // Swift Charts draws marks beyond a fixed domain outside the plot area; the plot style's
    // clipShape (as the head comment says) cuts them off.
    func testAClipShapeKeepsMarksBeyondAFixedDomainInsideThePlot() throws {
        func inkAbovePlot(clipped: Bool) throws -> Int {
            var chart = description(data: [["2026-08-03", "iOS", 1500], ["2026-08-03", "macOS", 900]],
                                    content: [["type": "ForEach", "content": [
                                        ["type": "BarMark",
                                         "x": ["label": "Week", "value": "$week", "unit": "weekOfYear"],
                                         "y": ["label": "Users", "value": "$users"],
                                         "foregroundStyle": ["by": ["label": "Platform", "value": "$platform"]]],
                                    ]]])
            chart["chartYScale"] = ["domain": [0, 2000]]
            chart["chartLegend"] = "hidden"
            if clipped { chart["chartPlotStyle"] = ["clipShape": "rectangle"] }
            ActionUIModel.resetForTesting()
            try loadChart(chart)
            let built = Chart.buildView(ActionUIElement(id: 10, type: "Chart", properties: [:], subviews: nil),
                                        model, windowUUID, model.validatedProperties, logger)
            // The chart sits 40 points below an empty band; a bar that leaves the plot draws into it.
            let image = try XCTUnwrap(render(AnyView(built).padding(.top, 40)))
            let bandBytes = image.width * 4 * 60    // the top 30 points at 2x
            return pixels(image).prefix(bandBytes).enumerated().filter { $0.offset % 4 == 0 && $0.element < 200 }.count
        }
        XCTAssertGreaterThan(try inkAbovePlot(clipped: false), 100, "the stacked bar (2400) leaves a 0...2000 plot")
        XCTAssertEqual(try inkAbovePlot(clipped: true), 0, "clipped to the plot area")
    }
}
