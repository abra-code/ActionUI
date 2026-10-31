// Tests/Elements/ChartRendererTests.swift
/*
 Tests for the Chart renderer on GTK, as pixels: a bar's color, the background between bars, the
 theme's gridlines, a runtime change of rows and of the description, and the size it takes. The
 geometry itself is in Drawing/ChartLayoutTests.swift.
*/

import XCTest
import CAdwaita
@testable import ActionUI

private final class RecordingLogger: ActionUILogger, @unchecked Sendable {
    private let lock = Lock()
    private var recorded: [String] = []

    var warnings: [String] { lock.withLock { recorded } }

    func log(_ message: String, _ level: LoggerLevel) {
        if level == .warning {
            lock.withLock { recorded.append(message) }
        }
    }
}

@MainActor
final class ChartRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        NumberFormatting.localeForTesting = "en_US"
        windowUUID = "chart-\(name)"
    }

    override func tearDown() async throws {
        NumberFormatting.localeForTesting = nil
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
    }

    private let bars = #"""
    "chart": {"columns": ["day", {"name": "n", "type": "number"}], "data": [["Mon", 4], ["Tue", 2]],
              "content": [{"type": "ForEach", "content": [{"type": "BarMark", "x": {"label": "Day", "value": "$day"},
                                                           "y": {"label": "N", "value": "$n"}, "foregroundStyle": "#FF0000"}]}]}
    """#

    private func render(_ properties: String, background: String = "#FFFFFF") throws -> RenderNode {
        let json = ##"{"type": "Chart", "id": 1, "properties": {"## + properties + ##", "frame": {"width": 200, "height": 200}, "background": ""##
            + background + ##""}}"##
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private struct Pixels {
        let bytes: [UInt8]
        let width: Int

        var height: Int { bytes.count / 4 / width }

        subscript(_ x: Int, _ y: Int) -> [Int] {
            let start = (y * width + x) * 4
            return bytes[start..<start + 4].map(Int.init)
        }

        /// How many pixels of the row at `y` are red.
        func redRun(y: Int) -> Int {
            (0..<width).filter { self[$0, y][0] > 200 && self[$0, y][1] < 60 && self[$0, y][2] < 60 }.count
        }
    }

    private func pixels(_ node: RenderNode) throws -> Pixels {
        let drawing = try XCTUnwrap(AdwaitaTestHost.drawing(of: node.widget, shownIn: node.outerWidget))
        defer { gsk_render_node_unref(drawing.node) }
        return Pixels(bytes: try XCTUnwrap(AdwaitaTestHost.pixels(of: drawing.node, width: drawing.width, height: drawing.height)), width: Int(drawing.width))
    }

    private func isRed(_ pixel: [Int]) -> Bool { pixel[0] > 200 && pixel[1] < 60 && pixel[2] < 60 }

    func testItIsGreedyWithColorsSize() throws {
        let node = try render(bars)
        var minimum: gint = -1, natural: gint = -1
        gtk_widget_measure(node.widget, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &natural, nil, nil)
        XCTAssertEqual(minimum, 0)
        XCTAssertEqual(natural, gint(Color.idealLength))
        XCTAssertNotEqual(gtk_widget_get_hexpand(node.widget), 0)
        XCTAssertNotEqual(gtk_widget_get_vexpand(node.widget), 0)
    }

    func testBarsDrawInTheirColorOverTheBackground() throws {
        let image = try pixels(try render(bars))
        // Two bars of two bands: a row near the top crosses only the taller, one lower crosses both.
        let high = image.redRun(y: 60), low = image.redRun(y: 150)
        XCTAssertGreaterThan(high, 30)
        XCTAssertEqual(low, high * 2, accuracy: 4, "two bars of one width")
        XCTAssertFalse(isRed(image[2, 150]), "the room at the leading edge of the band is the background")
    }

    func testLinesAndAreasDrawInTheirColors() throws {
        let columns = #""columns": [{"name": "x", "type": "number"}, {"name": "y", "type": "number"}], "data": [[0, 8], [10, 8]]"#
        let line = ##""chart": {"## + columns + ##", "content": [{"type": "ForEach", "content": [{"type": "LineMark", "x": {"label": "X", "value": "$x"}, "y": {"label": "Y", "value": "$y"}, "foregroundStyle": "#FF0000"}]}]}"##
        let area = ##""chart": {"## + columns + ##", "content": [{"type": "ForEach", "content": [{"type": "AreaMark", "x": {"label": "X", "value": "$x"}, "y": {"label": "Y", "value": "$y"}, "foregroundStyle": "#FF0000"}]}]}"##
        let thin = try pixels(try render(line))
        XCTAssertGreaterThan((0..<thin.height).filter { thin.redRun(y: $0) > 100 }.count, 0, "a level line crosses the plot")
        XCTAssertLessThanOrEqual((0..<thin.height).filter { thin.redRun(y: $0) > 100 }.count, 4, "and is thin")
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let filled = try pixels(try render(area))
        XCTAssertGreaterThan((0..<filled.height).filter { filled.redRun(y: $0) > 100 }.count, 100, "an area fills down to the axis")
    }

    func testAPlotBackgroundDrawsUnderTheMarksAndOverTheGrid() throws {
        let chart = ##""chart": {"columns": ["day", {"name": "n", "type": "number"}], "data": [["Mon", 4]], "chartPlotStyle": {"background": "#0000FF", "cornerRadius": 12, "border": {"color": "#00FF00", "width": 2}}, "content": [{"type": "ForEach", "content": [{"type": "BarMark", "x": {"label": "Day", "value": "$day"}, "y": {"label": "N", "value": "$n"}, "foregroundStyle": "#FF0000"}]}]}"##
        let image = try pixels(try render(chart))
        XCTAssertGreaterThan(image.redRun(y: 100), 50, "the bar is over the background")
        XCTAssertEqual(image[6, 100][2], 255, accuracy: 8, "the background fills beside it")
        XCTAssertTrue((0..<image.width).contains { image[$0, 8][1] > 200 && image[$0, 8][0] < 60 }, "the border runs along the top")
        XCTAssertGreaterThan(image[1, 8][1], 200, "and stays square at the corner, whatever the radius")
    }

    private func markedLine(_ extra: String) -> String {
        let columns = #""columns": [{"name": "x", "type": "number"}, {"name": "y", "type": "number"}], "data": [[2, 5], [5, 5], [8, 5]], "chartYScale": {"domain": [0, 10]}, "chartXScale": {"domain": [0, 10]}"#
        return ##""chart": {"## + columns + ##", "content": ["## + extra + ##"]}"##
    }

    private let ringedLine = ##"{"type": "ForEach", "content": [{"type": "LineMark", "x": {"label": "X", "value": "$x"}, "y": {"label": "Y", "value": "$y"}, "foregroundStyle": "#FF0000", "lineStyle": {"lineWidth": 4}, "symbol": "circle", "symbolSize": 900}]}"##
    private let blueRule = ##"{"type": "RuleMark", "x": {"label": "X", "value": 5}, "foregroundStyle": "#0000FF", "lineStyle": {"lineWidth": 4}}"##

    // The middle of the row with the most solid red: an edge's pixels are red too, but faint.
    private func middleOfTheLine(_ image: Pixels) throws -> (x: Int, y: Int) {
        func solid(_ y: Int) -> [Int] {
            (0..<image.width).filter { image[$0, y][3] > 200 && isRed(image[$0, y]) }
        }
        let y = try XCTUnwrap((0..<image.height).max { solid($0).count < solid($1).count })
        let reds = solid(y)
        return ((reds[0] + reds[reds.count - 1]) / 2, y)
    }

    func testASymbolOnALineIsAHoleInIt() throws {
        let image = try pixels(try render(markedLine(ringedLine)))
        let middle = try middleOfTheLine(image)
        XCTAssertFalse(isRed(image[middle.x, middle.y]), "the line stops at the symbol")
        XCTAssertLessThan(image[middle.x, middle.y][3], 40, "and only the gridlines behind it show there")
        XCTAssertTrue(isRed(image[middle.x + 15, middle.y]), "the outline is 4 inside a box of 34")
        XCTAssertTrue(isRed(image[middle.x, middle.y - 15]), "all around")
        XCTAssertFalse(isRed(image[middle.x, middle.y - 20]), "and ends with the box")
        XCTAssertTrue(isRed(image[middle.x + 30, middle.y]), "the line goes on outside it")
    }

    func testAHoleCutsOnlyItsOwnLine() throws {
        let later = try pixels(try render(markedLine(ringedLine + "," + blueRule)))
        var middle = try middleOfTheLine(later)
        XCTAssertGreaterThan(later[middle.x, middle.y][2], 200, "a later rule crosses the hole")
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let earlier = try pixels(try render(markedLine(blueRule + "," + ringedLine)))
        middle = try middleOfTheLine(earlier)
        XCTAssertGreaterThan(earlier[middle.x, middle.y][2], 200, "and so does an earlier one, which the mask leaves alone")
    }

    func testAnOutlineOfHalfTheBoxLeavesASolidSymbol() throws {
        // A stroke this wide around a smaller shape turns inside out and leaves a spot in the middle.
        let thick = ringedLine.replacingOccurrences(of: #""lineWidth": 4"#, with: #""lineWidth": 18"#)
            .replacingOccurrences(of: #""symbolSize": 900"#, with: #""symbolSize": 400"#)
        let image = try pixels(try render(markedLine(thick)))
        let x = try middleOfTheLine(image).x
        // Many rows tie for the most red in a line this wide, so the symbol's middle comes from a column.
        let column = (0..<image.height).filter { image[x, $0][3] > 200 && isRed(image[x, $0]) }
        let y = try (XCTUnwrap(column.first) + XCTUnwrap(column.last)) / 2
        for (across, down) in [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)] {
            XCTAssertGreaterThan(image[x + across, y + down][3], 200, "no spot at the symbol's middle")
        }
    }

    func testAPlusOnALineIsSolid() throws {
        let solid = ringedLine.replacingOccurrences(of: #""symbol": "circle""#, with: #""symbol": "plus""#)
        let image = try pixels(try render(markedLine(solid)))
        let middle = try middleOfTheLine(image)
        XCTAssertTrue(isRed(image[middle.x, middle.y]))
    }

    func testAutomaticLineStylesDrawTheirDashes() throws {
        func gaps(_ data: String) throws -> Int {
            let chart = ##""chart": {"columns": [{"name": "x", "type": "number"}, {"name": "y", "type": "number"}, "s"], "data": "## + data + ##", "chartLegend": "hidden", "content": [{"type": "ForEach", "content": [{"type": "LineMark", "x": {"label": "X", "value": "$x"}, "y": {"label": "Y", "value": "$y"}, "foregroundStyle": "#FF0000", "lineStyle": {"by": {"label": "S", "value": "$s"}}}]}]}"##
            let image = try pixels(try render(chart))
            let y = try XCTUnwrap((0..<image.height).max { image.redRun(y: $0) < image.redRun(y: $1) })
            let reds = (0..<image.width).map { isRed(image[$0, y]) }
            ActionUIModel.shared.windowModels[windowUUID] = nil
            return zip(reds, reds.dropFirst()).filter { $0 && !$1 }.count
        }
        XCTAssertLessThanOrEqual(try gaps(#"[[0, 5, "A"], [10, 5, "A"]]"#), 1, "the first is solid")
        let dashed = try gaps(#"[[0, 1, "A"], [0, 5, "B"], [10, 5, "B"]]"#)
        XCTAssertGreaterThan(dashed, 10, "the second is not")
    }

    func testALegendDrawsItsDotsInTheSeriesColors() throws {
        let chart = ##""chart": {"columns": ["day", {"name": "n", "type": "number"}], "data": [["Mon", 4]], "chartLegend": {"position": "top"}, "chartForegroundStyleScale": {"domain": ["Mon"], "range": ["#FF0000"]}, "content": [{"type": "ForEach", "content": [{"type": "BarMark", "x": {"label": "Day", "value": "$day"}, "y": {"label": "N", "value": "$n"}, "foregroundStyle": {"by": {"label": "Day", "value": "$day"}}}]}]}"##
        let image = try pixels(try render(chart))
        let row = (0..<10).first { image.redRun(y: $0) > 3 }
        XCTAssertNotNil(row, "a red dot sits in the top row")
        XCTAssertLessThan(image.redRun(y: try XCTUnwrap(row)), 12, "and it is a dot, not a bar")
    }

    func testPlotOpacityFadesTheLayer() throws {
        let chart = ##""chart": {"columns": ["day", {"name": "n", "type": "number"}], "data": [["Mon", 4]], "chartPlotStyle": {"opacity": 0.5}, "content": [{"type": "ForEach", "content": [{"type": "BarMark", "x": {"label": "Day", "value": "$day"}, "y": {"label": "N", "value": "$n"}, "foregroundStyle": "#FF0000"}]}]}"##
        let image = try pixels(try render(chart))
        let bar = try XCTUnwrap((0..<image.width).first { image[$0, 100][0] > 200 })
        XCTAssertEqual(image[bar + 20, 100][3], 127, accuracy: 3, "the pixels keep their color and go half see-through")
    }

    func testNewRowsDrawAtOnce() throws {
        let node = try render(bars)
        let before = try pixels(node).redRun(y: 60)
        // One bar now, in one band twice as wide.
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Mon", "4"]])
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try pixels(node).redRun(y: 60), before * 2, accuracy: 4)
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [])
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(AdwaitaTestHost.drawing(of: node.widget, shownIn: node.outerWidget)?.node, "no rows and no axes: nothing to draw")
    }

    func testANewDescriptionDrawsAtOnce() throws {
        let node = try render(bars)
        XCTAssertGreaterThan(try pixels(node).redRun(y: 150), 0)
        let blue: [String: Any] = ["columns": ["day", ["name": "n", "type": "number"]],
                                   "content": [["type": "ForEach", "content": [["type": "BarMark", "x": ["label": "D", "value": "$day"],
                                                                                "y": ["label": "N", "value": "$n"], "foregroundStyle": "#0000FF"]]]]]
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "chart", value: blue)
        AdwaitaTestHost.drainMainLoop()
        let image = try pixels(node)
        XCTAssertEqual(image.redRun(y: 150), 0)
        XCTAssertTrue((0..<image.width).contains { image[$0, 150][2] > 200 && image[$0, 150][0] < 60 }, "the rows stay, in the new color")
    }

    func testGridlinesFollowTheTheme() throws {
        let manager = adw_style_manager_get_default()
        defer { adw_style_manager_set_color_scheme(manager, ADW_COLOR_SCHEME_DEFAULT) }
        let chart = #""chart": {"columns": ["day", {"name": "n", "type": "number"}], "data": [["Mon", 4]], "content": [{"type": "ForEach", "content": [{"type": "PointMark", "x": {"label": "Day", "value": "$day"}, "y": {"label": "N", "value": "$n"}}]}]}"#
        // The column at x = 150 holds no mark, only the horizontal gridlines.
        func reds(_ image: Pixels) -> [Int] { (0..<image.height).map { image[150, $0][0] } }

        adw_style_manager_set_color_scheme(manager, ADW_COLOR_SCHEME_FORCE_LIGHT)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertLessThan(reds(try pixels(try render(chart))).min() ?? 255, 250, "dark lines on white")

        adw_style_manager_set_color_scheme(manager, ADW_COLOR_SCHEME_FORCE_DARK)
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        XCTAssertGreaterThan(reds(try pixels(try render(chart, background: "#000000"))).max() ?? 0, 5, "light lines on black")
    }

    func testRowsThatDoNotParseAreReportedOnce() throws {
        let logger = RecordingLogger()
        let saved = ActionUIModel.shared.logger
        ActionUIModel.shared.logger = logger
        defer { ActionUIModel.shared.logger = saved }
        let node = try render(bars)
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Mon", "x"], ["Tue", "1"]])
        AdwaitaTestHost.drainMainLoop()
        _ = try pixels(node)
        XCTAssertEqual(logger.warnings.filter { $0.contains("skipped 1 row(s)") }.count, 1, "\(logger.warnings)")
    }

    func testAxisTextIsSmallerThanTheThemes() throws {
        let node = try render(bars)
        let layout = try XCTUnwrap(gtk_widget_create_pango_layout(node.widget, "1,234,567"))
        defer { g_object_unref(UnsafeMutableRawPointer(layout)) }
        var width: gint = 0, height: gint = 0
        pango_layout_get_pixel_size(layout, &width, &height)
        XCTAssertEqual(ChartAxisText(widget: node.widget).size("1,234,567").width, Double(width) * 0.8, accuracy: 2)
    }

    func testNumberLabelsFollowTheLocale() {
        XCTAssertEqual(NumberFormatting.string(1500, format: .decimal(minFraction: nil, maxFraction: nil)), "1,500")
    }
}
