// Tests/Views/ChartAnnotationTests.swift
// Chart annotations: the "annotation" modifier's keys, its element with references resolved to
// positions, the mistakes it refuses, and its rendering against typed Swift Charts annotations.
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
final class ChartAnnotationTests: XCTestCase {
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

    private let days = ["Mon", "Tue", "Wed"]
    private let highs: [Double] = [5, 7, 4]
    private var rows: [[String]] { days.indices.map { [days[$0], String(highs[$0])] } }

    private func pv(_ label: String, _ value: Any) -> [String: Any] { ["label": label, "value": value] }

    private func text(_ text: String) -> [String: Any] { ["type": "Text", "properties": ["text": text]] }

    // Bars over the days, the bar mark carrying `annotation`, plus optional top-level marks and keys.
    private func bars(annotation: Any?, topLevel: [[String: Any]] = [], extra: [String: Any] = [:]) -> [String: Any] {
        var bar: [String: Any] = ["type": "BarMark", "x": pv("Day", "$day"), "y": pv("High", "$high")]
        bar["annotation"] = annotation
        var description: [String: Any] = [
            "columns": ["day", ["name": "high", "type": "number"]],
            "content": [["type": "ForEach", "content": [bar]]] + topLevel,
        ]
        for (key, value) in extra { description[key] = value }
        return description
    }

    private func marks(of spec: ChartSpec) -> [ChartMarkSpec] {
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

    private func annotations(of mark: ChartMarkSpec?) -> [ChartAnnotationSpec] {
        (mark?.modifiers ?? []).compactMap { modifier in
            if case .annotation(let annotation) = modifier { return annotation } else { return nil }
        }
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

    // The Chart element's rendering of `description` over `rows`, with an optional selection.
    private func renderElement(_ description: [String: Any], rows: [[String]], selection: String? = nil) throws -> [UInt8] {
        let element: [String: Any] = ["id": 10, "type": "Chart", "properties": ["chart": description]]
        _ = try ActionUIModel.shared.loadDescription(from: element, windowUUID: windowUUID)
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 10, rows: rows)
        let model = ActionUIModel.shared.windowModels[windowUUID]!.viewModels[10]!
        if let selection {
            model.value = selection
        }
        let built = Chart.buildView(ActionUIElement(id: 10, type: "Chart", properties: [:], subviews: nil),
                                    model, windowUUID, model.properties, logger)
        return render(AnyView(built))
    }

    // A typed reference carries an identity plot style, as the element always applies one.
    private func assertSameRendering(_ description: [String: Any], rows: [[String]], selection: String? = nil,
                                     _ reference: some SwiftUI.View, file: StaticString = #filePath, line: UInt = #line) throws {
        let element = try renderElement(description, rows: rows, selection: selection)
        let typed = render(reference.chartPlotStyle { plot in plot })
        XCTAssertFalse(element.isEmpty, file: file, line: line)
        XCTAssertEqual(element.count, typed.count, file: file, line: line)
        let differing = zip(element, typed).filter { $0 != $1 }.count
        XCTAssertEqual(differing, 0, "the element draws what the typed chart draws", file: file, line: line)
        XCTAssertEqual(logger.warnings, [], file: file, line: line)
    }

    // MARK: - Parsing

    func testAnAnnotationParsesAndCleansIdempotently() throws {
        let annotation: [String: Any] = [
            "position": "top", "alignment": "leading", "spacing": 4,
            "overflowResolution": ["x": "fit", "y": ["fit": "plot"]],
            "content": text("$high"),
        ]
        let parsed = ChartDescription.parse(bars(annotation: annotation), logger: logger)
        XCTAssertEqual(logger.warnings, [])
        let found = annotations(of: marks(of: parsed.spec).first)
        XCTAssertEqual(found.count, 1)
        let spec = try XCTUnwrap(found.first)
        XCTAssertEqual(spec.position, .top)
        XCTAssertEqual(spec.alignment, .leading)
        XCTAssertEqual(spec.spacing, 4)
        XCTAssertEqual(spec.content.type, "Text")
        XCTAssertEqual(spec.content.properties["text"] as? String, "$2")
        let again = ChartDescription.parse(parsed.cleaned, logger: logger)
        XCTAssertEqual(logger.warnings, [])
        XCTAssertTrue((parsed.cleaned as NSDictionary).isEqual(to: again.cleaned))
        // The cleaned description keeps the element as written, names included.
        let cleanedBar = (((parsed.cleaned["content"] as? [Any])?.first as? [String: Any])?["content"] as? [Any])?.first as? [String: Any]
        let cleanedContent = (cleanedBar?["annotation"] as? [String: Any])?["content"] as? [String: Any]
        XCTAssertEqual((cleanedContent?["properties"] as? [String: Any])?["text"] as? String, "$high")
    }

    func testNamesResolveToPositionsInsideAForEachOnly() throws {
        let stack: [String: Any] = ["type": "VStack", "properties": ["spacing": 2],
                                    "children": [text("$day: $high units"), text("$nothing and $2")]]
        let goal: [String: Any] = ["type": "RuleMark", "y": pv("Goal", 6), "annotation": ["content": text("$day $1")]]
        let parsed = ChartDescription.parse(bars(annotation: ["content": stack], topLevel: [goal]), logger: logger)
        XCTAssertEqual(logger.warnings, [])
        let all = marks(of: parsed.spec)
        let children = try XCTUnwrap(annotations(of: all.first).first?.content.subviews?["children"] as? [ActionUIElement])
        XCTAssertEqual(children.map { $0.properties["text"] as? String }, ["$1: $2 units", "$nothing and $2"])
        // Outside a ForEach a "$..." is literal text, as for any text there.
        XCTAssertEqual(annotations(of: all.last).first?.content.properties["text"] as? String, "$day $1")
        // Template ids: the same description parses to the same element.
        let again = ChartDescription.parse(parsed.cleaned, logger: nil)
        XCTAssertEqual(annotations(of: marks(of: again.spec).first).first?.content, annotations(of: all.first).first?.content)
    }

    func testAPlotAppendsItsAnnotationToEveryMarkInside() {
        let plot: [String: Any] = ["type": "Plot", "annotation": ["position": "top", "content": text("$high")], "content": [
            ["type": "BarMark", "x": pv("Day", "$day"), "y": pv("High", "$high")],
            ["type": "PointMark", "x": pv("Day", "$day"), "y": pv("High", "$high"), "annotation": ["content": text("own")]],
        ]]
        let description: [String: Any] = ["columns": ["day", ["name": "high", "type": "number"]],
                                          "content": [["type": "ForEach", "content": [plot]]]]
        let parsed = ChartDescription.parse(description, logger: logger)
        XCTAssertEqual(logger.warnings, [])
        let all = marks(of: parsed.spec)
        XCTAssertEqual(all.map { annotations(of: $0).count }, [1, 2])
        // The mark's own annotation first, then the Plot's, as Swift applies them.
        XCTAssertEqual(annotations(of: all.last).map { $0.content.properties["text"] as? String }, ["own", "$2"])
    }

    func testAnnotationMistakesAreReported() {
        func warnings(_ annotation: Any) -> (count: Int, warnings: [String]) {
            let collecting = CollectingLogger()
            let parsed = ChartDescription.parse(bars(annotation: annotation), logger: collecting)
            return (annotations(of: marks(of: parsed.spec).first).count, collecting.warnings)
        }
        // The annotation is dropped.
        for refused: Any in ["Top", ["position": "top"], ["content": "Mon"], ["content": ["properties": ["text": "x"]]],
                             ["content": ["type": "NoSuchView"]], ["content": ["type": "Chart", "properties": [:]]],
                             ["content": ["type": "VStack", "children": [["type": "Chart"]]]]] {
            let result = warnings(refused)
            XCTAssertEqual(result.count, 0, "\(refused)")
            XCTAssertEqual(result.warnings.count, 1, "\(refused): \(result.warnings)")
        }
        // Only the key is dropped.
        for (key, value): (String, Any) in [("position", "above"), ("alignment", "middle"), ("spacing", "4"),
                                            ("overflowResolution", ["x": "clip"]), ("overflowResolution", ["z": "fit"]),
                                            ("overflowResolution", ["x": ["fit": "window"]]), ("tooltip", true)] {
            let result = warnings(["content": text("x"), key: value])
            XCTAssertEqual(result.count, 1, "\(key)")
            XCTAssertEqual(result.warnings.count, 1, "\(key): \(result.warnings)")
        }
        XCTAssertTrue(warnings(["content": ["type": "Chart"]]).warnings.first?.contains("cannot hold a Chart") ?? false)
    }

    // MARK: - Rendering

    func testAnnotationsRenderLikeTypedAnnotations() throws {
        let days = self.days, highs = self.highs, rows = self.rows
        let description = bars(annotation: ["position": "top", "spacing": 2, "content": text("$high")])
        let reference = Charts.Chart {
            ForEach(days.indices, id: \.self) { i in
                Charts.BarMark(x: .value("Day", days[i]), y: .value("High", highs[i]))
                    .annotation(position: .top, alignment: .center, spacing: 2, overflowResolution: .automatic) {
                        SwiftUI.Text(rows[i][1])
                    }
            }
        }
        try assertSameRendering(description, rows: rows, reference)
    }

    func testAContainerOverflowAndAGoalLabelRenderLikeTypedAnnotations() throws {
        let days = self.days, highs = self.highs, rows = self.rows
        let stack: [String: Any] = ["type": "VStack", "properties": ["spacing": 1], "children": [text("$day"), text("$high")]]
        let goal: [String: Any] = ["type": "RuleMark", "y": pv("Goal", 6),
                                   "annotation": ["position": "topLeading", "alignment": "leading", "content": text("Goal")]]
        let description = bars(annotation: ["position": "overlay", "overflowResolution": ["y": "padScale"], "content": stack],
                               topLevel: [goal])
        let reference = Charts.Chart {
            ForEach(days.indices, id: \.self) { i in
                Charts.BarMark(x: .value("Day", days[i]), y: .value("High", highs[i]))
                    .annotation(position: .overlay, alignment: .center,
                                overflowResolution: AnnotationOverflowResolution(x: .automatic, y: .padScale)) {
                        SwiftUI.VStack(spacing: 1) {
                            SwiftUI.Text(rows[i][0])
                            SwiftUI.Text(rows[i][1])
                        }
                    }
            }
            Charts.RuleMark(y: .value("Goal", 6.0))
                .annotation(position: .topLeading, alignment: .leading, overflowResolution: .automatic) {
                    SwiftUI.Text("Goal")
                }
        }
        try assertSameRendering(description, rows: rows, reference)
    }

    // Its annotation is appended to marks drawn per row, but a Plot outside a ForEach reads no row.
    func testAPlotOutsideAForEachAnnotatesWithoutReadingRows() throws {
        let days = self.days, highs = self.highs
        let plot: [String: Any] = ["type": "Plot", "annotation": ["position": "top", "content": text("$2")], "content": [
            ["type": "ForEach", "content": [["type": "BarMark", "x": pv("Day", "$day"), "y": pv("High", "$high")]]],
        ]]
        let description: [String: Any] = ["columns": ["day", ["name": "high", "type": "number"]], "content": [plot]]
        let reference = Charts.Chart {
            ForEach(days.indices, id: \.self) { i in
                Charts.BarMark(x: .value("Day", days[i]), y: .value("High", highs[i]))
                    .annotation(position: .top, overflowResolution: .automatic) { SwiftUI.Text(verbatim: "$2") }
            }
        }
        try assertSameRendering(description, rows: rows, reference)
    }

    func testASelectionMarksAnnotationIsDrawnWithTheSelection() throws {
        let days = self.days, highs = self.highs
        let rule: [String: Any] = ["type": "RuleMark", "x": pv("Selected", "$selection"),
                                   "annotation": ["position": "top", "content": text("Selected")]]
        let description = bars(annotation: nil, topLevel: [rule], extra: ["chartXSelection": "value"])
        let reference = Charts.Chart {
            ForEach(days.indices, id: \.self) { i in
                Charts.BarMark(x: .value("Day", days[i]), y: .value("High", highs[i]))
            }
            Charts.RuleMark(x: .value("Selected", "Tue"))
                .annotation(position: .top, overflowResolution: .automatic) { SwiftUI.Text("Selected") }
        }
        .chartXSelection(value: .constant(String?.none))
        try assertSameRendering(description, rows: rows, selection: "{\"x\":\"Tue\"}", reference)
    }

    func testPastTheLimitTheMarksAreDrawnWithoutAnnotations() {
        let limit = ChartRenderCache.maxAnnotations
        let many = (0...limit).map { ["\($0)", "\(Double($0 % 7))"] }
        let point: [String: Any] = ["type": "PointMark", "x": ["label": "I", "value": "$1", "type": "number"],
                                    "y": ["label": "V", "value": "$2", "type": "number"]]
        var annotated = point
        annotated["annotation"] = ["content": text("$2")]
        func differing(_ rows: [[String]]) -> Int {
            func draw(_ mark: [String: Any]) -> [UInt8] {
                let description: [String: Any] = ["content": [["type": "ForEach", "content": [mark]]]]
                let items = ChartRenderCache().render(description: description, rows: rows, viewID: 10, logger: logger).items
                return render(Charts.Chart(items, id: \.id) { $0.content })
            }
            return zip(draw(annotated), draw(point)).filter { $0 != $1 }.count
        }
        XCTAssertEqual(differing(many), 0, "one past the limit, no annotation is drawn")
        XCTAssertEqual(logger.warnings.count, 1)
        XCTAssertTrue(logger.warnings.first?.contains("\(limit + 1) annotations") ?? false, "\(logger.warnings)")
        XCTAssertNotEqual(differing(Array(many.dropLast())), 0, "at the limit, the annotations are drawn")
        XCTAssertEqual(logger.warnings.count, 1)
        // A selection mark's annotation is left out too.
        func drawSelected(ruleAnnotated: Bool) -> [UInt8] {
            var rule: [String: Any] = ["type": "RuleMark", "x": pv("Selected", "$selection")]
            if ruleAnnotated { rule["annotation"] = ["position": "top", "content": text("Selected")] }
            let description: [String: Any] = ["content": [["type": "ForEach", "content": [annotated]], rule], "chartXSelection": "value"]
            let items = ChartRenderCache().render(description: description, rows: many, selectionValue: "{\"x\":5}", viewID: 10,
                                                  logger: SilentChartLogger.shared).items
            return render(Charts.Chart(items, id: \.id) { $0.content })
        }
        XCTAssertEqual(zip(drawSelected(ruleAnnotated: true), drawSelected(ruleAnnotated: false)).filter { $0 != $1 }.count, 0)
        // A ForEach with its own data counts its rows; a mark outside one counts once.
        let literal: [String: Any] = ["type": "PointMark", "x": pv("I", 1), "y": pv("V", 2), "annotation": ["content": text("own")]]
        let spec = ChartDescription.parse(["content": [["type": "ForEach", "data": [["1", "2"], ["3", "4"]], "content": [annotated]],
                                                       ["type": "Plot", "annotation": ["content": text("x")], "content": [literal]]]],
                                          logger: logger).spec
        XCTAssertEqual(logger.warnings.count, 1)
        XCTAssertEqual(ChartSpec.annotationCount(in: spec.content, rowCount: 50), 2 + 2)
    }

    // As a template row's: each row's instance reads its substituted properties as given (a
    // spacing that is not a number is no spacing, without a warning on every render), and the
    // render cache is kept from one render to the next.
    func testEachRowsInstanceReadsItsPropertiesQuietlyAndTheCacheIsKept() throws {
        let description = bars(annotation: ["content": ["type": "VStack", "properties": ["spacing": "$day"], "children": [text("$high")]]])
        _ = try renderElement(description, rows: rows)
        XCTAssertEqual(logger.warnings, [])
        let model = ActionUIModel.shared.windowModels[windowUUID]!.viewModels[10]!
        let cache = try XCTUnwrap(model.elementCache)
        _ = Chart.buildView(ActionUIElement(id: 10, type: "Chart", properties: [:], subviews: nil), model, windowUUID,
                            model.properties, logger)
        XCTAssertTrue(model.elementCache === cache)
        XCTAssertEqual(logger.warnings, [])
    }
}
