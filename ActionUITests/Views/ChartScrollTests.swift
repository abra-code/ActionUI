// Tests/Views/ChartScrollTests.swift
// Chart scrolling: chartScrollableAxes, the visible lengths and the initial scroll position.
// The initial position only shows in a window (an offscreen render ignores it), so that check
// draws a real window.
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
final class ChartScrollTests: XCTestCase {
    private var logger: CollectingLogger!

    override func setUp() async throws {
        try await super.setUp()
        logger = CollectingLogger()
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        try await super.tearDown()
    }

    private func pv(_ label: String, _ value: Any, _ extra: [String: Any] = [:]) -> [String: Any] {
        var object: [String: Any] = ["label": label, "value": value]
        for (key, item) in extra { object[key] = item }
        return object
    }

    private let days = (1...12).map { ["D\($0)", "\($0)"] }

    // Bars over twelve days, plus scroll keys.
    private func bars(_ extra: [String: Any] = [:]) -> [String: Any] {
        var description: [String: Any] = [
            "columns": ["day", ["name": "n", "type": "number"]],
            "content": [["type": "ForEach", "content": [["type": "BarMark", "x": pv("Day", "$day"), "y": pv("N", "$n")]]]],
        ]
        for (key, value) in extra { description[key] = value }
        return description
    }

    private func dates(_ extra: [String: Any] = [:]) -> [String: Any] {
        var description: [String: Any] = [
            "columns": [["name": "day", "type": "date"], ["name": "n", "type": "integer"]],
            "content": [["type": "ForEach", "content": [["type": "LineMark", "x": pv("Day", "$day", ["unit": "day"]), "y": pv("N", "$n")]]]],
        ]
        for (key, value) in extra { description[key] = value }
        return description
    }

    private func scroll(_ description: [String: Any]) -> ChartScrollSpec {
        ChartDescription.parse(description, logger: logger).spec.scroll
    }

    // The Chart element's view for `description` over `rows`.
    private func chartView(_ description: [String: Any], rows: [[String]]) throws -> AnyView {
        let windowUUID = UUID().uuidString
        let element: [String: Any] = ["id": 10, "type": "Chart", "properties": ["chart": description]]
        _ = try ActionUIModel.shared.loadDescription(from: element, windowUUID: windowUUID)
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 10, rows: rows)
        let model = ActionUIModel.shared.windowModels[windowUUID]!.viewModels[10]!
        let built = Chart.buildView(ActionUIElement(id: 10, type: "Chart", properties: [:], subviews: nil),
                                    model, windowUUID, model.properties, logger)
        return AnyView(built)
    }

    // MARK: - Description keys

    func testScrollKeysParse() {
        var spec = scroll(bars(["chartScrollableAxes": "horizontal", "chartXVisibleDomain": ["length": 4],
                                "chartScrollPosition": ["initialX": "D7"]]))
        XCTAssertEqual(spec.axes, .horizontal)
        XCTAssertEqual(spec.xLength, .categories(4))
        XCTAssertEqual(spec.initialX, .string("D7"))
        spec = scroll(dates(["chartScrollableAxes": ["horizontal", "vertical"], "chartXVisibleDomain": ["length": 604800],
                             "chartYVisibleDomain": ["length": 5], "chartScrollPosition": ["initialX": "2026-09-10", "initialY": 2]]))
        XCTAssertEqual(spec.axes, [.horizontal, .vertical])
        XCTAssertEqual(spec.xLength, .amount(604800))
        XCTAssertEqual(spec.yLength, .amount(5))
        XCTAssertEqual(spec.initialY, .integer(2))
        guard case .date? = spec.initialX else { return XCTFail("a date axis scrolls to a date") }
        XCTAssertEqual(logger.warnings, [])
    }

    func testARepeatedAxisMerges() {
        XCTAssertEqual(scroll(bars(["chartScrollableAxes": ["horizontal", "horizontal"]])).axes, .horizontal)
        XCTAssertEqual(logger.warnings, [])
    }

    func testScrollMistakesAreReported() {
        var spec = scroll(bars(["chartScrollableAxes": ["sideways"]]))
        XCTAssertTrue(spec.isEmpty)
        XCTAssertTrue(logger.warnings.contains { $0.contains("'chartScrollableAxes' must be") }, "\(logger.warnings)")
        spec = scroll(bars(["chartXVisibleDomain": ["length": 4], "chartScrollPosition": ["initialX": "D7"]]))
        XCTAssertNil(spec.xLength)
        XCTAssertNil(spec.initialX)
        XCTAssertTrue(logger.warnings.contains { $0.contains("'chartXVisibleDomain' needs chartScrollableAxes") }, "\(logger.warnings)")
        XCTAssertTrue(logger.warnings.contains { $0.contains("chartScrollPosition.initialX needs chartScrollableAxes") }, "\(logger.warnings)")
        spec = scroll(bars(["chartScrollableAxes": "horizontal", "chartXVisibleDomain": ["length": 2.5],
                            "chartScrollPosition": ["initialX": 3, "zoom": 2]]))
        XCTAssertNil(spec.xLength, "a count of categories is whole")
        XCTAssertNil(spec.initialX, "a category axis scrolls to a category")
        XCTAssertTrue(logger.warnings.contains { $0.contains("a whole count of categories") }, "\(logger.warnings)")
        XCTAssertTrue(logger.warnings.contains { $0.contains("must be a value of the axis's type (string)") }, "\(logger.warnings)")
        XCTAssertTrue(logger.warnings.contains { $0.contains("chartScrollPosition.zoom is not supported") }, "\(logger.warnings)")
        spec = scroll(dates(["chartScrollableAxes": "horizontal", "chartXVisibleDomain": ["length": true]]))
        XCTAssertNil(spec.xLength, "a boolean is not a length")
        spec = scroll(dates(["chartScrollableAxes": "horizontal", "chartXVisibleDomain": ["length": 1e19]]))
        XCTAssertNil(spec.xLength, "Swift Charts stops the app at a date length of about 1e19 seconds")
        XCTAssertTrue(logger.warnings.contains { $0.contains("a number of seconds above 0 and at most 1e15") }, "\(logger.warnings)")
        spec = scroll(dates(["chartScrollableAxes": "horizontal", "chartXVisibleDomain": ["length": 86400, "zoom": 2]]))
        XCTAssertEqual(spec.xLength, .amount(86400))
        XCTAssertTrue(logger.warnings.contains { $0.contains("chartXVisibleDomain.zoom is not supported") }, "\(logger.warnings)")
    }

    // A visible length that would lay out more than 100 automatic axis marks (the main thread's
    // cost grows to seconds and minutes past that) is lengthened when the marks are built; a
    // hidden axis draws none.
    func testATinyVisibleLengthIsLengthened() {
        let rows = (1...30).map { [String(format: "2026-09-%02d", $0), "\($0 % 5)"] }
        func drawn(_ keys: [String: Any]) -> ChartScrollSpec {
            ChartRenderCache().render(description: dates(keys), rows: rows, viewID: 10, logger: logger).spec.scroll
        }
        var keys: [String: Any] = ["chartScrollableAxes": "horizontal", "chartXVisibleDomain": ["length": 7]]
        XCTAssertEqual(drawn(keys).xLength, .amount(2505600 * 2.5 / 100), "7 seconds of 29 days: 100 default marks at most")
        XCTAssertEqual(logger.warnings.count, 1)
        XCTAssertTrue(logger.warnings.contains { $0.contains("'chartXVisibleDomain' length 7.0 of an axis span of 2505600.0") },
                      "\(logger.warnings)")
        keys["chartXVisibleDomain"] = ["length": 86400]
        XCTAssertEqual(drawn(keys).xLength, .amount(86400), "a day of 29 days")
        keys["chartXAxis"] = [["type": "AxisMarks", "values": ["automatic": ["desiredCount": 20]]]]
        XCTAssertEqual(drawn(keys).xLength, .amount(2505600 * 20 / 100), "20 marks a day for 29 days")
        XCTAssertEqual(logger.warnings.count, 2)
        keys["chartXVisibleDomain"] = ["length": 7]
        keys["chartXAxis"] = "hidden"
        XCTAssertEqual(drawn(keys).xLength, .amount(7), "a hidden axis draws no marks")
        XCTAssertEqual(logger.warnings.count, 2)
    }

    // MARK: - Drawing
    // A scrolling chart draws its marks only in a window: an offscreen render shows the grid alone.

    #if os(macOS)
    // Draws `view` in a borderless window and reads back its pixels as RGBA.
    private func windowed(_ view: AnyView, width: CGFloat = 320) -> [UInt8] {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: width, height: 200), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        let host = NSHostingView(rootView: view.frame(width: width, height: 200).background(SwiftUI.Color.white))
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        defer { window.orderOut(nil) }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return [] }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let image = rep.cgImage else { return [] }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    // Pixels with a dark red channel: marks and text, not the white background or gray grid.
    private func inked(_ pixels: [UInt8]) -> Int {
        stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] < 150 }.count
    }

    func testAVisibleLengthShowsPartOfTheAxis() throws {
        let plain = windowed(try chartView(bars(), rows: days))
        let scrolled = windowed(try chartView(bars(["chartScrollableAxes": "horizontal", "chartXVisibleDomain": ["length": 4]]), rows: days))
        XCTAssertEqual(plain.count, scrolled.count)
        XCTAssertGreaterThan(inked(scrolled), 2_000, "the bars are drawn")
        XCTAssertGreaterThan(zip(plain, scrolled).filter { $0 != $1 }.count, 10_000, "four of twelve bars fill the plot")
        XCTAssertEqual(logger.warnings, [])
    }

    func testTheInitialPositionScrolls() throws {
        let keys: [String: Any] = ["chartScrollableAxes": "horizontal", "chartXVisibleDomain": ["length": 4]]
        var positioned = keys
        positioned["chartScrollPosition"] = ["initialX": "D7"]
        let start = windowed(try chartView(bars(keys), rows: days))
        let again = windowed(try chartView(bars(keys), rows: days))
        let scrolled = windowed(try chartView(bars(positioned), rows: days))
        XCTAssertFalse(start.isEmpty)
        XCTAssertEqual(zip(start, again).filter { $0 != $1 }.count, 0, "the same chart draws the same")
        XCTAssertGreaterThan(zip(start, scrolled).filter { $0 != $1 }.count, 10_000, "the chart starts at D7")
    }

    func testTheScrollExampleDrawsWithoutWarnings() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("ActionUISwiftTestApp/Resources/Chart.scroll.json"))
        let windowUUID = UUID().uuidString
        let document = try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
        func charts(_ element: any ActionUIElementBase) -> [any ActionUIElementBase] {
            (element.type == "Chart" ? [element] : []) + element.childElements.flatMap(charts)
        }
        let found = charts(document)
        XCTAssertEqual(found.count, 2)
        for chart in found {
            let model = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[chart.id])
            let view = AnyView(ActionUIView(element: chart, model: model, windowUUID: windowUUID))
            XCTAssertGreaterThan(inked(windowed(view, width: 560)), 2_000, "chart \(chart.id) drew its bars")
        }
        XCTAssertEqual(logger.warnings, [])
    }
    #endif
}
