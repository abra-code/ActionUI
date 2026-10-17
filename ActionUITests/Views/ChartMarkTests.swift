// Tests/Views/ChartMarkTests.swift
// The marks' initializer forms, the mark modifiers, scale ranges and types, axis label options
// and plot style of the Chart element. Rendering checks compare the element's output with the
// same chart written as typed Swift Charts code.
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
final class ChartMarkTests: XCTestCase {
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

    private let columns: [Any] = ["day", ["name": "low", "type": "number"], ["name": "high", "type": "number"], "team"]
    private let rows: [[String]] = [["Mon", "2", "5", "A"], ["Tue", "3", "7", "A"], ["Mon", "1", "4", "B"], ["Tue", "2", "6", "B"]]

    private func pv(_ label: String, _ value: Any) -> [String: Any] { ["label": label, "value": value] }

    private func chart(_ marks: [[String: Any]], extra: [String: Any] = [:]) -> [String: Any] {
        var description: [String: Any] = ["columns": columns, "content": [["type": "ForEach", "content": marks]]]
        for (key, value) in extra { description[key] = value }
        return description
    }

    // Every mark, in order, through ForEach and Plot groups.
    private func marks(of spec: ChartSpec) -> [ChartMarkSpec] {
        func flatten(_ entries: [ChartEntry]) -> [ChartMarkSpec] {
            entries.flatMap { entry -> [ChartMarkSpec] in
                switch entry {
                case .mark(let mark): return [mark]
                case .forEach(let children), .plot(let children): return flatten(children)
                }
            }
        }
        return flatten(spec.content)
    }

    private func build(_ description: [String: Any]) -> Int {
        let spec = ChartDescription.parse(description, logger: nil).spec
        var builder = ChartContentBuilder(columns: ChartTypedColumns(rows: rows, refs: spec.referencedColumns))
        return builder.build(spec.content).count
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

    // The Chart element's rendering of `description` over `rows`.
    private func renderElement(_ description: [String: Any], rows: [[String]]) throws -> [UInt8] {
        let element: [String: Any] = ["id": 10, "type": "Chart", "properties": ["chart": description]]
        _ = try ActionUIModel.shared.loadDescription(from: element, windowUUID: windowUUID)
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 10, rows: rows)
        let model = ActionUIModel.shared.windowModels[windowUUID]!.viewModels[10]!
        let built = Chart.buildView(ActionUIElement(id: 10, type: "Chart", properties: [:], subviews: nil),
                                    model, windowUUID, model.validatedProperties, logger)
        return render(AnyView(built))
    }

    // A typed reference carries an identity plot style, as the element always applies one.
    private func assertSameRendering(_ description: [String: Any], rows: [[String]], _ reference: some SwiftUI.View,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let element = try renderElement(description, rows: rows)
        let typed = render(reference.chartPlotStyle { plot in plot })
        XCTAssertFalse(element.isEmpty, file: file, line: line)
        XCTAssertEqual(element.count, typed.count, file: file, line: line)
        let differing = zip(element, typed).filter { $0 != $1 }.count
        XCTAssertEqual(differing, 0, "the element draws what the typed chart draws", file: file, line: line)
        XCTAssertEqual(logger.warnings, [], file: file, line: line)
    }

    // MARK: - Initializer forms

    func testEveryInitializerFormParsesAndBuilds() {
        let day = pv("Day", "$day"), low = pv("Low", "$low"), high = pv("High", "$high"), team = pv("Team", "$team")
        let cases: [(String, [String: Any], ChartMarkForm)] = [
            ("BarMark", ["x": day, "y": high], .xy),
            ("BarMark", ["x": day, "yStart": 10, "yEnd": 40], .xPoints),
            ("BarMark", ["x": day], .xPoints),
            ("BarMark", ["x": day, "yStart": low, "yEnd": high], .xPair),
            ("BarMark", ["xStart": 0, "xEnd": 20, "y": day], .yPoints),
            ("BarMark", ["xStart": 5, "yStart": low, "yEnd": high], .pointsPair),
            ("BarMark", ["xStart": low, "xEnd": high, "y": day], .pairY),
            ("BarMark", ["xStart": low, "xEnd": high, "yEnd": 30], .pairPoints),
            ("LineMark", ["x": day, "y": high], .xy),
            ("LineMark", ["x": day, "y": high, "series": team], .xySeries),
            ("PointMark", ["x": day, "y": high], .xy),
            ("PointMark", ["x": 12, "y": high], .yPoints),
            ("PointMark", ["x": day, "y": 12], .xPoints),
            ("RuleMark", ["x": 30, "yStart": low, "yEnd": high], .pointsPair),
            ("RuleMark", ["x": day], .xPoints),
            ("RuleMark", ["x": day, "yStart": low, "yEnd": high], .xPair),
            ("RuleMark", ["y": high], .yPoints),
            ("RuleMark", ["xStart": low, "xEnd": high, "y": 4], .pairPoints),
            ("RuleMark", ["xStart": low, "xEnd": high, "y": day], .pairY),
            ("AreaMark", ["x": day, "y": high, "stacking": "normalized"], .xy),
            ("AreaMark", ["xStart": low, "xEnd": high, "y": day], .pairY),
            ("AreaMark", ["x": day, "yStart": low, "yEnd": high], .xPair),
            ("AreaMark", ["x": day, "y": high, "series": team], .xySeries),
            ("AreaMark", ["xStart": low, "xEnd": high, "y": day, "series": team], .pairYSeries),
            ("AreaMark", ["x": day, "yStart": low, "yEnd": high, "series": team], .xPairSeries),
            ("RectangleMark", ["x": day, "y": team, "width": ["ratio": 0.9], "height": 20], .xy),
            ("RectangleMark", ["x": day, "yStart": 10, "width": 8], .xPoints),
            ("RectangleMark", ["xEnd": 40, "y": team, "height": 8], .yPoints),
            ("RectangleMark", ["xStart": low, "xEnd": high, "y": team, "height": 8], .pairY),
            ("RectangleMark", ["xStart": low, "xEnd": high, "yStart": 5], .pairPoints),
            ("RectangleMark", ["x": day, "yStart": low, "yEnd": high, "width": 8], .xPair),
            ("RectangleMark", ["xStart": 5, "yStart": low, "yEnd": high], .pointsPair),
            ("RectangleMark", ["xStart": low, "xEnd": high, "yStart": low, "yEnd": high], .pairPair),
            ("RectangleMark", ["xStart": 10, "yEnd": 30], .pointsOnly),
            ("SectorMark", ["angle": high, "innerRadius": ["ratio": 0.6], "outerRadius": "automatic", "angularInset": 1.5], .angle),
        ]
        for (kind, arguments, form) in cases {
            var mark = arguments
            mark["type"] = kind
            let parsed = ChartDescription.parse(chart([mark]), logger: logger)
            XCTAssertEqual(logger.warnings, [], "\(kind) \(arguments.keys.sorted())")
            XCTAssertEqual(marks(of: parsed.spec).first?.form, form, "\(kind) \(arguments.keys.sorted())")
            XCTAssertEqual(build(parsed.cleaned), rows.count, "\(kind) \(arguments.keys.sorted()) builds one mark per row")
        }
    }

    func testArgumentsThatMatchNoInitializerAreRefusedWithTheAcceptedForms() {
        let parsed = ChartDescription.parse(chart([["type": "LineMark", "x": pv("Day", "$day")]]), logger: logger)
        XCTAssertTrue(marks(of: parsed.spec).isEmpty)
        XCTAssertEqual(logger.warnings.count, 1)
        XCTAssertTrue(logger.warnings[0].contains("Accepted: x + y | x + y + series"), logger.warnings[0])
    }

    func testAPointArgumentWhereAValueIsRequiredIsRefused() {
        // RuleMark(x:yStart:yEnd:) takes yStart/yEnd as points only with a plottable x.
        let parsed = ChartDescription.parse(chart([["type": "RuleMark", "x": 3, "y": 4]]), logger: logger)
        XCTAssertTrue(marks(of: parsed.spec).isEmpty)
        XCTAssertEqual(logger.warnings.count, 1)
    }

    func testAStartAndEndMustShareAType() {
        let parsed = ChartDescription.parse(chart([["type": "BarMark", "x": pv("Day", "$day"),
                                                    "yStart": pv("Low", "$low"), "yEnd": pv("Team", "$team")]]), logger: logger)
        XCTAssertTrue(marks(of: parsed.spec).isEmpty)
        XCTAssertTrue(logger.warnings.contains { $0.contains("a start and end must have one type") }, "\(logger.warnings)")
    }

    func testDimensionsOnlyWhereTheInitializerTakesThem() {
        let bar: [String: Any] = ["type": "BarMark", "x": pv("Day", "$day"), "y": pv("High", "$high"),
                                  "width": ["ratio": 0.5], "height": "automatic", "stacking": "normalized"]
        let line: [String: Any] = ["type": "LineMark", "x": pv("Day", "$day"), "y": pv("High", "$high"), "width": 10]
        let parsed = ChartDescription.parse(chart([bar, line]), logger: logger)
        XCTAssertEqual(logger.warnings.count, 1, "\(logger.warnings)")
        XCTAssertTrue(logger.warnings[0].contains("takes no 'width'"))
        let cleanedMarks = ((parsed.cleaned["content"] as? [Any])?.first as? [String: Any])?["content"] as? [[String: Any]]
        XCTAssertEqual(cleanedMarks?[0]["stacking"] as? String, "normalized")
        XCTAssertNil(cleanedMarks?[1]["width"])
    }

    // MARK: - Modifiers

    private var everyModifier: [String: Any] {
        [
            "type": "PointMark", "x": pv("Day", "$day"), "y": pv("High", "$high"),
            "foregroundStyle": ["by": pv("Team", "$team")],
            "symbol": "diamond",
            "symbolSize": ["width": 8, "height": 8],
            "lineStyle": ["lineWidth": 2, "lineCap": "round", "dash": [4, 2]],
            "interpolationMethod": ["catmullRom": ["alpha": 0.5]],
            "position": ["by": pv("Team", "$team"), "axis": "horizontal", "span": ["ratio": 0.8]],
            "cornerRadius": ["radius": 3, "style": "circular"],
            "opacity": 0.8, "zIndex": 1,
            "offset": ["x": 1, "yStart": -2, "yEnd": 2],
            "blur": 0.5,
            "shadow": ["color": "gray", "radius": 2, "x": 1, "y": 1],
            "alignsMarkStylesWithPlotArea": true,
            "accessibilityLabel": "$day, team $team",
            "accessibilityValue": "$high units",
            "accessibilityIdentifier": "point",
            "accessibilityHidden": false,
        ]
    }

    func testEveryModifierParsesAndCleansIdempotently() {
        let parsed = ChartDescription.parse(chart([everyModifier]), logger: logger)
        XCTAssertEqual(logger.warnings, [])
        let mark = try? XCTUnwrap(marks(of: parsed.spec).first)
        XCTAssertEqual(mark?.modifiers.count, 17)
        let again = ChartDescription.parse(parsed.cleaned, logger: logger)
        XCTAssertEqual(logger.warnings, [])
        XCTAssertTrue((parsed.cleaned as NSDictionary).isEqual(to: again.cleaned))
        XCTAssertEqual(build(parsed.cleaned), rows.count)
        // Columns read by modifiers are parsed with the rest.
        XCTAssertTrue(parsed.spec.referencedColumns.contains(ChartColumnRef(index: 3, type: .string)))
    }

    func testAccessibilityTextResolvesNamesToPositions() {
        let parsed = ChartDescription.parse(chart([everyModifier]), logger: nil)
        let mark = marks(of: parsed.spec).first
        let texts = mark?.modifiers.compactMap { modifier -> String? in
            switch modifier {
            case .accessibilityLabel(.perRow(let text)), .accessibilityValue(.perRow(let text)): return text
            case .accessibilityIdentifier(.literal(let text)): return text
            default: return nil
            }
        }
        XCTAssertEqual(texts, ["$1, team $4", "$3 units", "point"])
    }

    func testInvalidModifierValuesAreDroppedWithOneWarningEach() {
        let mark: [String: Any] = [
            "type": "BarMark", "x": pv("Day", "$day"), "y": pv("High", "$high"),
            "symbol": "hexagon", "symbolSize": "big", "lineStyle": ["lineCap": "pointy"], "interpolationMethod": "wiggly",
            "position": ["axis": "horizontal"], "cornerRadius": ["radius": 2, "style": "square"], "opacity": "half",
            "offset": ["x": 1, "xStart": 2], "shadow": ["color": "gray"], "accessibilityHidden": "no", "accessibilityLabel": 5,
        ]
        let parsed = ChartDescription.parse(chart([mark]), logger: logger)
        XCTAssertEqual(logger.warnings.count, 11, "\(logger.warnings)")
        XCTAssertEqual(marks(of: parsed.spec).first?.modifiers.count, 0, "the mark stays, without the invalid modifiers")
        let quiet = CollectingLogger()
        _ = ChartDescription.parse(parsed.cleaned, logger: quiet)
        XCTAssertEqual(quiet.warnings, [])
    }

    func testAMalformedByFormIsDroppedWithAWarning() {
        let mark: [String: Any] = [
            "type": "BarMark", "x": pv("Day", "$day"), "y": pv("High", "$high"),
            "foregroundStyle": ["by": pv("Team", "$team"), "extra": 1], "symbol": ["by": "team"],
        ]
        let parsed = ChartDescription.parse(chart([mark]), logger: logger)
        XCTAssertEqual(logger.warnings.count, 2, "\(logger.warnings)")
        XCTAssertEqual(marks(of: parsed.spec).first?.modifiers.count, 0)
    }

    // MARK: - Scales, labels, plot style

    // Swift Charts stops the app for these (measured), so validation refuses them.
    func testScaleTypesThatStopSwiftChartsAreRefused() {
        let line: [[String: Any]] = [["type": "LineMark", "x": pv("Day", "$day"), "y": pv("High", "$high")]]
        let refused: [[String: Any]] = [
            ["type": "category"], ["type": "date"], ["type": "log"], ["type": "log", "domain": [0, 10]],
            ["type": "squareRoot", "domain": [-1, 10]], ["type": ["power": ["exponent": 0]], "domain": [1, 10]],
            ["type": ["power": ["exponent": -1]], "domain": [0, 10]], ["type": "log", "domain": ["automatic": ["includesZero": true]]],
        ]
        for scale in refused {
            let quiet = CollectingLogger()
            let parsed = ChartDescription.parse(chart(line, extra: ["chartYScale": scale]), logger: quiet)
            XCTAssertNil(parsed.spec.y.scaleType, "\(scale)")
            XCTAssertEqual(quiet.warnings.count, 1, "\(scale): \(quiet.warnings)")
            let again = CollectingLogger()
            _ = ChartDescription.parse(parsed.cleaned, logger: again)
            XCTAssertEqual(again.warnings, [], "\(scale)")
        }
        let accepted: [[String: Any]] = [
            ["type": "log", "domain": [0.5, 10]], ["type": "squareRoot", "domain": [0, 10]],
            ["type": ["power": ["exponent": 2]], "domain": [0, 10]], ["type": "symmetricLog"], ["type": "linear"],
        ]
        for scale in accepted {
            let quiet = CollectingLogger()
            let parsed = ChartDescription.parse(chart(line, extra: ["chartYScale": scale]), logger: quiet)
            XCTAssertNotNil(parsed.spec.y.scaleType, "\(scale)")
            XCTAssertEqual(quiet.warnings, [], "\(scale)")
        }
        // A string axis takes any type unharmed.
        let quiet = CollectingLogger()
        let parsed = ChartDescription.parse(chart(line, extra: ["chartXScale": ["type": "category"]]), logger: quiet)
        XCTAssertNotNil(parsed.spec.x.scaleType)
        XCTAssertEqual(quiet.warnings, [])
    }

    func testScaleRangeTypeLabelOptionsAndPlotStyleParse() {
        let description = chart([["type": "LineMark", "x": pv("Day", "$day"), "y": pv("High", "$high")]], extra: [
            "chartXScale": ["range": ["startPadding": 12, "endPadding": 4]],
            "chartYScale": ["domain": [1, 100], "type": "log"],
            "chartXAxisLabel": ["text": "Day", "position": "bottom", "alignment": "trailing", "spacing": 6],
            "chartPlotStyle": ["background": "gray", "cornerRadius": 4],
        ])
        let parsed = ChartDescription.parse(description, logger: logger)
        XCTAssertEqual(logger.warnings, [])
        XCTAssertEqual(parsed.spec.x.label, "Day")
        XCTAssertEqual(parsed.spec.x.labelSpacing, 6)
        XCTAssertNotNil(parsed.spec.y.scaleType)
        XCTAssertEqual(parsed.spec.plotStyle["background"] as? String, "gray")
        guard case .plotDimension(let start, let end) = parsed.spec.x.range.kind else { return XCTFail("expected padding") }
        XCTAssertEqual([start, end], [12, 4])
        let again = ChartDescription.parse(parsed.cleaned, logger: logger)
        XCTAssertEqual(logger.warnings, [])
        XCTAssertTrue((parsed.cleaned as NSDictionary).isEqual(to: again.cleaned))
    }

    func testPlotStyleTakesOnlyVisualViewProperties() {
        let description = chart([["type": "LineMark", "x": pv("Day", "$day"), "y": pv("High", "$high")]], extra: [
            "chartPlotStyle": ["background": "gray", "onHoverActionID": "plot.hover", "bogus": 1],
        ])
        let parsed = ChartDescription.parse(description, logger: logger)
        XCTAssertEqual(logger.warnings.count, 2, "\(logger.warnings)")
        XCTAssertEqual(parsed.spec.plotStyle["background"] as? String, "gray")
        XCTAssertNil(parsed.spec.plotStyle["onHoverActionID"])
        XCTAssertNil(parsed.spec.plotStyle["bogus"])
    }

    func testInvalidScaleParts() {
        let description = chart([["type": "LineMark", "x": pv("Day", "$day"), "y": pv("High", "$high")]], extra: [
            "chartYScale": ["range": ["middle": 3], "type": "cubic", "zoom": 2],
        ])
        _ = ChartDescription.parse(description, logger: logger)
        XCTAssertEqual(logger.warnings.count, 3, "\(logger.warnings)")
    }

    // MARK: - Rendering against typed Swift Charts code

    private let days = ["Mon", "Tue", "Wed"]
    private let lows: [Double] = [2, 3, 1]
    private let highs: [Double] = [5, 7, 4]
    private var simpleRows: [[String]] { days.indices.map { [days[$0], String(lows[$0]), String(highs[$0]), "A"] } }

    func testRangeBarsAndARuleRenderLikeTypedMarks() throws {
        let days = self.days, lows = self.lows, highs = self.highs, rows = self.rows
        _ = (days, lows, highs, rows)
        let description = chart([["type": "BarMark", "x": pv("Day", "$day"), "yStart": pv("Low", "$low"), "yEnd": pv("High", "$high"),
                                  "width": ["ratio": 0.4], "cornerRadius": 3, "foregroundStyle": "teal"]])
        var withRule = description
        withRule["content"] = (description["content"] as! [Any]) + [["type": "RuleMark", "y": pv("Goal", 6),
                                                                     "lineStyle": ["lineWidth": 1, "dash": [4, 3]], "foregroundStyle": "red"]]
        let reference = Charts.Chart {
            ForEach(days.indices, id: \.self) { i in
                Charts.BarMark(x: .value("Day", days[i]), yStart: .value("Low", lows[i]), yEnd: .value("High", highs[i]), width: .ratio(0.4))
                    .foregroundStyle(SwiftUI.Color.teal)
                    .cornerRadius(3)
            }
            Charts.RuleMark(y: .value("Goal", 6.0))
                .foregroundStyle(SwiftUI.Color.red)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        try assertSameRendering(withRule, rows: simpleRows, reference)
    }

    func testPointsWithSymbolsAndSizesRenderLikeTypedMarks() throws {
        let days = self.days, lows = self.lows, highs = self.highs
        _ = (days, lows, highs)
        let teams = ["A", "B", "A"]
        let rows = days.indices.map { [days[$0], String(lows[$0]), String(highs[$0]), teams[$0]] }
        let description = chart([["type": "PointMark", "x": pv("Day", "$day"), "y": pv("High", "$high"),
                                  "foregroundStyle": ["by": pv("Team", "$team")], "symbol": ["by": pv("Team", "$team")], "symbolSize": 120]])
        let reference = Charts.Chart(days.indices, id: \.self) { i in
            Charts.PointMark(x: .value("Day", days[i]), y: .value("High", highs[i]))
                .foregroundStyle(by: .value("Team", teams[i]))
                .symbol(by: .value("Team", teams[i]))
                .symbolSize(120)
        }
        try assertSameRendering(description, rows: rows, reference)
    }

    func testGroupedNormalizedAndSmoothedMarksRenderLikeTypedMarks() throws {
        let days = self.days, lows = self.lows, highs = self.highs, rows = self.rows
        _ = (days, lows, highs, rows)
        let grouped = chart([["type": "BarMark", "x": pv("Day", "$day"), "y": pv("High", "$high"),
                              "foregroundStyle": ["by": pv("Team", "$team")], "position": ["by": pv("Team", "$team")]]])
        let groupedReference = Charts.Chart(rows.indices, id: \.self) { i in
            Charts.BarMark(x: .value("Day", rows[i][0]), y: .value("High", Double(rows[i][2])!))
                .foregroundStyle(by: .value("Team", rows[i][3]))
                .position(by: .value("Team", rows[i][3]))
        }
        try assertSameRendering(grouped, rows: rows, groupedReference)

        let normalized = chart([["type": "BarMark", "x": pv("Day", "$day"), "y": pv("High", "$high"), "stacking": "normalized",
                                 "foregroundStyle": ["by": pv("Team", "$team")]]])
        let normalizedReference = Charts.Chart(rows.indices, id: \.self) { i in
            Charts.BarMark(x: .value("Day", rows[i][0]), y: .value("High", Double(rows[i][2])!), stacking: .normalized)
                .foregroundStyle(by: .value("Team", rows[i][3]))
        }
        ActionUIModel.resetForTesting()
        try assertSameRendering(normalized, rows: rows, normalizedReference)

        let smooth = chart([["type": "LineMark", "x": pv("Day", "$day"), "y": pv("High", "$high"), "series": pv("Team", "$team"),
                             "interpolationMethod": "catmullRom"]])
        let smoothReference = Charts.Chart(rows.indices, id: \.self) { i in
            Charts.LineMark(x: .value("Day", rows[i][0]), y: .value("High", Double(rows[i][2])!), series: .value("Team", rows[i][3]))
                .interpolationMethod(.catmullRom)
        }
        ActionUIModel.resetForTesting()
        try assertSameRendering(smooth, rows: rows, smoothReference)
    }

    func testScaleTypeRangeAndLabelOptionsRenderLikeTypedModifiers() throws {
        let days = self.days, lows = self.lows, highs = self.highs, rows = self.rows
        _ = (days, lows, highs, rows)
        let description = chart([["type": "LineMark", "x": pv("Day", "$day"), "y": pv("High", "$high")]], extra: [
            "chartYScale": ["domain": [1, 10], "type": "log"],
            "chartXScale": ["range": ["startPadding": 20, "endPadding": 20]],
            "chartXAxisLabel": ["text": "Day", "alignment": "trailing"],
        ])
        let reference = Charts.Chart(days.indices, id: \.self) { i in
            Charts.LineMark(x: .value("Day", days[i]), y: .value("High", highs[i]))
        }
        .chartYScale(domain: 1.0...10.0, type: .log)
        .chartXScale(range: .plotDimension(startPadding: 20, endPadding: 20))
        .chartXAxisLabel("Day", alignment: .trailing)
        try assertSameRendering(description, rows: simpleRows, reference)
    }

    // MARK: - SectorMark and Plot

    func testASectorAngleMustBeAQuantity() {
        let parsed = ChartDescription.parse(chart([["type": "SectorMark", "angle": pv("Day", "$day")]]), logger: logger)
        XCTAssertTrue(marks(of: parsed.spec).isEmpty)
        XCTAssertEqual(logger.warnings.count, 1)
        XCTAssertTrue(logger.warnings[0].contains("SectorMark.angle must be a number or integer value"), logger.warnings[0])
    }

    func testAPlotAppendsItsModifiersToEveryMarkInside() {
        let point = pv("Day", "$day"), high = pv("High", "$high")
        let description = chart([["type": "Plot", "foregroundStyle": ["by": pv("Team", "$team")], "opacity": 0.5, "content": [
            ["type": "LineMark", "x": point, "y": high, "zIndex": 1],
            ["type": "PointMark", "x": point, "y": high],
        ]]])
        let parsed = ChartDescription.parse(description, logger: logger)
        XCTAssertEqual(logger.warnings, [])
        let built = marks(of: parsed.spec)
        XCTAssertEqual(built.map(\.kind), [.LineMark, .PointMark])
        // The mark's own modifiers first, then the Plot's, as Swift applies them.
        XCTAssertEqual(built.map { $0.modifiers.map { "\($0)".prefix(while: { $0 != "(" }) } },
                       [["zIndex", "foregroundStyleBy", "opacity"], ["foregroundStyleBy", "opacity"]])
        XCTAssertEqual(build(parsed.cleaned), rows.count * 2, "two marks per row")

        // The cleaned description keeps the Plot, and cleaning it again changes nothing.
        let plot = ((parsed.cleaned["content"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])?.first
        XCTAssertEqual(plot?["type"] as? String, "Plot")
        XCTAssertEqual((plot?["content"] as? [Any])?.count, 2)
        let again = ChartDescription.parse(parsed.cleaned, logger: logger)
        XCTAssertEqual(again.cleaned as NSDictionary, parsed.cleaned as NSDictionary)
        XCTAssertEqual(logger.warnings, [])
    }

    func testAPlotMayHoldAForEachButNotInsideOne() {
        let line: [String: Any] = ["type": "LineMark", "x": pv("Day", "$day"), "y": pv("High", "$high")]
        let outer: [String: Any] = ["columns": columns, "content": [
            ["type": "Plot", "foregroundStyle": "red", "content": [["type": "ForEach", "content": [line]]]],
        ]]
        let parsed = ChartDescription.parse(outer, logger: logger)
        XCTAssertEqual(logger.warnings, [])
        XCTAssertEqual(build(parsed.cleaned), rows.count)

        // A Plot inside a ForEach is still inside it: a ForEach in that Plot is nested.
        _ = ChartDescription.parse(chart([["type": "Plot", "content": [["type": "ForEach", "content": [line]]]]]), logger: logger)
        XCTAssertEqual(logger.warnings.count, 1)
        XCTAssertTrue(logger.warnings[0].contains("cannot be inside another ForEach"), logger.warnings[0])

        // Outside a ForEach, a Plot's by-value has no row to read: "$team" is literal text, with a warning.
        let quiet = CollectingLogger()
        _ = ChartDescription.parse(["columns": columns, "content": [
            ["type": "Plot", "foregroundStyle": ["by": pv("Team", "$team")], "content": [["type": "ForEach", "content": [line]]]],
        ]], logger: quiet)
        XCTAssertEqual(quiet.warnings.count, 1, "\(quiet.warnings)")
    }

    func testStackedAreasRenderLikeTypedMarks() throws {
        let rows = self.rows
        let description = chart([["type": "AreaMark", "x": pv("Day", "$day"), "y": pv("High", "$high"),
                                  "foregroundStyle": ["by": pv("Team", "$team")]]])
        let reference = Charts.Chart(rows.indices, id: \.self) { i in
            Charts.AreaMark(x: .value("Day", rows[i][0]), y: .value("High", Double(rows[i][2])!))
                .foregroundStyle(by: .value("Team", rows[i][3]))
        }
        try assertSameRendering(description, rows: rows, reference)
    }

    func testAHeatMapOfRectanglesRendersLikeTypedMarks() throws {
        let rows = self.rows
        let description = chart([["type": "RectangleMark", "x": pv("Day", "$day"), "y": pv("Team", "$team"), "height": ["ratio": 0.8],
                                  "foregroundStyle": ["by": pv("High", "$high")]]])
        let reference = Charts.Chart(rows.indices, id: \.self) { i in
            Charts.RectangleMark(x: .value("Day", rows[i][0]), y: .value("Team", rows[i][3]), height: .ratio(0.8))
                .foregroundStyle(by: .value("High", Double(rows[i][2])!))
        }
        try assertSameRendering(description, rows: rows, reference)
    }

    func testADonutRendersLikeTypedMarks() throws {
        let rows = self.rows
        let description = chart([["type": "SectorMark", "angle": pv("High", "$high"), "innerRadius": ["ratio": 0.6], "angularInset": 1.5,
                                  "cornerRadius": 4, "foregroundStyle": ["by": pv("Day", "$day")]]])
        let reference = Charts.Chart(rows.indices, id: \.self) { i in
            Charts.SectorMark(angle: .value("High", Double(rows[i][2])!), innerRadius: .ratio(0.6), angularInset: 1.5)
                .cornerRadius(4)
                .foregroundStyle(by: .value("Day", rows[i][0]))
        }
        try assertSameRendering(description, rows: rows, reference)
    }

    func testAPlotPerRowRendersLikeATypedPlot() throws {
        let rows = self.rows
        let day = pv("Day", "$day"), high = pv("High", "$high")
        let description = chart([["type": "Plot", "foregroundStyle": ["by": pv("Team", "$team")], "content": [
            ["type": "LineMark", "x": day, "y": high],
            ["type": "PointMark", "x": day, "y": high],
        ]]])
        let reference = Charts.Chart(rows.indices, id: \.self) { i in
            Charts.Plot {
                Charts.LineMark(x: .value("Day", rows[i][0]), y: .value("High", Double(rows[i][2])!))
                Charts.PointMark(x: .value("Day", rows[i][0]), y: .value("High", Double(rows[i][2])!))
            }
            .foregroundStyle(by: .value("Team", rows[i][3]))
        }
        try assertSameRendering(description, rows: rows, reference)
    }
}
