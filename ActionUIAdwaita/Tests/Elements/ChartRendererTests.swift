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
