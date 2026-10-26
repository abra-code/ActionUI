// Tests/Elements/CanvasRendererTests.swift
/*
 Tests for the Canvas renderer on GTK, by the pixels it draws in a 100 x 100 canvas: Color's size
 and greed; the background; fills, strokes in points, gradients; an arc's clockwise flag and whole
 turns as SwiftUI's; numbers out of range (zero, huge, infinite) drawn without crashing; clip and
 transforms for what follows; a layer's blend mode over what the layer drew; a shadow; text and
 symbols; a click firing actionID. The expected results are what ActionUI's Apple
 code draws (measured on macOS 27 where it is not plain from the code).
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class CanvasRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var fired: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "canvas-\(name)"
        fired = []
        ActionUIModel.shared.registerActionHandler(for: "test.tapped") { [weak self] actionID, _, _, _, _ in
            MainActor.assumeIsolated { self?.fired.append(actionID) }
        }
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIModel.shared.unregisterActionHandler(for: "test.tapped")
    }

    private func render(_ properties: String) throws -> RenderNode {
        let json = #"{"type": "Canvas", "id": 1, "properties": {"# + properties + "}}"
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    /// The pixels of a 100 x 100 canvas drawing `operations` on a white background.
    private struct Pixels {
        let bytes: [UInt8]
        let width: Int

        /// Red, green, blue and alpha at (x, y), 0...255.
        subscript(_ x: Int, _ y: Int) -> [Int] {
            let start = (y * width + x) * 4
            return bytes[start..<start + 4].map(Int.init)
        }
    }

    private func draw(_ operations: String, extra: String = "") throws -> Pixels {
        let node = try render(##""frame": {"width": 100, "height": 100}, "backgroundColor": "#FFFFFF", "operations": ["## + operations + "]" + extra)
        let drawing = try XCTUnwrap(AdwaitaTestHost.drawing(of: node.widget, shownIn: node.outerWidget))
        defer { gsk_render_node_unref(drawing.node) }
        XCTAssertEqual(drawing.width, 100)
        XCTAssertEqual(drawing.height, 100)
        return Pixels(bytes: try XCTUnwrap(AdwaitaTestHost.pixels(of: drawing.node, width: drawing.width, height: drawing.height)), width: 100)
    }

    private func assertColor(_ pixel: [Int], _ expected: [Int], tolerance: Int = 8, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let close = zip(pixel, expected).allSatisfy { abs($0 - $1) <= tolerance }
        XCTAssertTrue(close, "\(pixel) is not \(expected) \(message)", file: file, line: line)
    }

    private let white = [255, 255, 255, 255]
    private let red = [255, 0, 0, 255]
    private let blue = [0, 0, 255, 255]
    private let black = [0, 0, 0, 255]

    func testItIsGreedyWithColorsSize() throws {
        let node = try render(#""operations": []"#)
        XCTAssertEqual(swiftString(G_OBJECT_TYPE_NAME_of(node.widget)), "ActionUICanvas")
        for orientation in [GTK_ORIENTATION_HORIZONTAL, GTK_ORIENTATION_VERTICAL] {
            let size = Gtk.Widget(node.widget).measure(orientation, forSize: -1)
            XCTAssertEqual(size.minimum, 0)
            XCTAssertEqual(size.natural, Int(Color.idealLength))
            XCTAssertNotEqual(gtk_widget_compute_expand(node.widget, orientation), 0)
        }
    }

    func testFillsAndStrokesInPoints() throws {
        let pixels = try draw(#"""
            {"type": "fill", "path": {"type": "circle", "center": [0.5, 0.5], "radius": 0.4}, "color": "#FF0000"},
            {"type": "stroke", "path": {"type": "circle", "center": [0.5, 0.5], "radius": 0.4}, "color": "#0000FF", "lineWidth": 4}
            """#)
        assertColor(pixels[2, 2], white, "background")
        assertColor(pixels[50, 50], red, "fill")
        assertColor(pixels[50, 10], blue, "the stroke on the circle")
        assertColor(pixels[50, 13], red, "4 points wide, not 4 canvases: 3 points in is the fill")
        assertColor(pixels[50, 7], white)
    }

    func testSegmentsWithoutAStartingPointDrawNothing() throws {
        // As SwiftUI's Path: lineTo with no moveTo before it is left out (measured on macOS 27).
        let pixels = try draw(#"""
            {"type": "stroke", "path": {"type": "path", "commands": [["lineTo", 0.1, 0.5], ["lineTo", 0.9, 0.5]]}, "color": "#FF0000", "lineWidth": 6},
            {"type": "stroke", "path": {"type": "path", "commands": [["moveTo", 0.1, 0.8], ["lineTo", 0.9, 0.8]]}, "color": "#0000FF", "lineWidth": 6}
            """#)
        assertColor(pixels[50, 50], white)
        assertColor(pixels[50, 80], blue, "after a moveTo it draws")
    }

    func testAFillWithoutAColorDrawsNothing() throws {
        let pixels = try draw(#"{"type": "fill", "path": {"type": "rect", "x": 0, "y": 0, "width": 1, "height": 1}}"#)
        assertColor(pixels[50, 50], white)
    }

    func testAnArcsClockwiseFlagIsSwiftUIs() throws {
        // 0 to 90 degrees with clockwise 1 runs through the top (measured on macOS 27); with 0, the
        // short way through the bottom right.
        let pixels = try draw(#"""
            {"type": "stroke", "path": {"type": "path", "commands": [["arc", 0.5, 0.5, 0.4, 0, 90, 1]]}, "color": "#FF0000", "lineWidth": 4},
            {"type": "stroke", "path": {"type": "path", "commands": [["arc", 0.5, 0.5, 0.2, 0, 90, 0]]}, "color": "#0000FF", "lineWidth": 4}
            """#)
        assertColor(pixels[50, 10], red, "the long arc passes the top")
        assertColor(pixels[78, 78], white, "and not the bottom right")
        assertColor(pixels[64, 64], blue, "the short arc passes the bottom right")
        assertColor(pixels[50, 30], white, "and not the top")
    }

    func testAnArcWholeTurnsAgainstItsFlagIsACircle() throws {
        // Measured on macOS 27: 0 to 360 clockwise and 0 to -360 counterclockwise are circles, and
        // equal angles draw no arc.
        let pixels = try draw(##"""
            {"type": "stroke", "path": {"type": "path", "commands": [["arc", 0.5, 0.5, 0.4, 0, 360, 1]]}, "color": "#000000", "lineWidth": 4},
            {"type": "stroke", "path": {"type": "path", "commands": [["arc", 0.5, 0.5, 0.2, 0, -360, 0]]}, "color": "#0000FF", "lineWidth": 4},
            {"type": "stroke", "path": {"type": "path", "commands": [["arc", 0.5, 0.5, 0.3, 30, 30, 1]]}, "color": "#FF0000", "lineWidth": 4, "lineCap": "round"}
            """##)
        for (x, y) in [(50, 10), (10, 50), (90, 50), (50, 90)] {
            assertColor(pixels[x, y], black, "on the outer circle")
        }
        for (x, y) in [(50, 30), (30, 50), (70, 50), (50, 70)] {
            assertColor(pixels[x, y], blue, "on the inner circle")
        }
        assertColor(pixels[76, 65], white, "no dot where the empty arc starts")
    }

    func testNumbersOutOfRangeDrawWithoutCrashing() throws {
        // Each would crash (a trap, a NULL from GSK, GTK's GPU renderer), hang (GSK normalizing a
        // huge angle) or warn; what follows each still draws.
        let pixels = try draw(##"""
            {"type": "stroke", "path": {"type": "rect", "x": 0.1, "y": 0.1, "width": 0.8, "height": 0.8}, "color": "#000000", "lineWidth": 0},
            {"type": "stroke", "path": {"type": "path", "commands": [["arc", 0.5, 0.5, 0.3, 0, "inf", 1]]}, "color": "#000000", "lineWidth": 4},
            {"type": "text", "text": "Hello", "frame": [0, 0.85, 1e30, 0.1]},
            {"type": "image", "systemName": "star.fill", "frame": [0, 0, "inf", 1]},
            {"type": "image", "systemName": "star.fill", "frame": [0, 0, 1e8, 1e8], "opacity": 0},
            {"type": "fill", "path": {"type": "rect", "x": 0, "y": 0, "width": 1, "height": 1},
             "gradient": {"type": "radial", "center": [0.5, 0.5], "endRadius": 1e-50, "colors": ["#FFFFFF", "#FFFFFF"]}},
            {"type": "fill", "path": {"type": "rect", "x": 0, "y": 0, "width": 1, "height": 1},
             "gradient": {"type": "linear", "start": ["inf", 0], "end": [1, 0], "colors": ["#FF0000", "#0000FF"]}},
            {"type": "layer", "frame": [0, 0, 1, 1], "operations": [
                {"type": "blur", "radius": "inf"},
                {"type": "fill", "path": {"type": "rect", "x": 0, "y": 0, "width": 1, "height": 1}, "color": "#FFFFFF"}
            ]},
            {"type": "layer", "frame": [0, 0, 1, 1], "operations": [
                {"type": "shadow", "radius": 1e6},
                {"type": "fill", "path": {"type": "rect", "x": 0, "y": 0, "width": 1, "height": 1}, "color": "#FFFFFF"}
            ]},
            {"type": "layer", "frame": [0, 0, 1, 1], "operations": [
                {"type": "rotate", "angle": 1e12},
                {"type": "fill", "path": {"type": "rect", "x": -2, "y": -2, "width": 4, "height": 4}, "color": "#FFFFFF"}
            ]},
            {"type": "fill", "path": {"type": "rect", "x": 0.4, "y": 0.4, "width": 0.2, "height": 0.2}, "color": "#FF0000"},
            {"type": "rotate", "angle": "inf"},
            {"type": "fill", "path": {"type": "rect", "x": -2, "y": -2, "width": 4, "height": 4}, "color": "#0000FF"}
            """##)
        assertColor(pixels[10, 10], white, "a line width of 0 draws nothing")
        assertColor(pixels[50, 50], red, "drawn after them")
        assertColor(pixels[5, 50], white, "nothing after rotating by infinity, as SwiftUI")
    }

    func testALinearGradientRunsFromStartToEnd() throws {
        let pixels = try draw(#"""
            {"type": "fill", "path": {"type": "rect", "x": 0, "y": 0, "width": 1, "height": 1},
             "gradient": {"type": "linear", "start": [0, 0], "end": [1, 0], "colors": ["#FF0000", "#0000FF"]}}
            """#)
        assertColor(pixels[1, 50], red, tolerance: 12)
        assertColor(pixels[98, 50], blue, tolerance: 12)
        assertColor(pixels[50, 50], [128, 0, 128, 255], tolerance: 12)
    }

    func testAClipAndTransformsApplyToWhatFollows() throws {
        let pixels = try draw(#"""
            {"type": "clip", "path": {"type": "rect", "x": 0, "y": 0, "width": 0.5, "height": 1}},
            {"type": "fill", "path": {"type": "rect", "x": 0, "y": 0, "width": 1, "height": 0.5}, "color": "#FF0000"},
            {"type": "translate", "x": 20, "y": 60},
            {"type": "fill", "path": {"type": "rect", "x": 0, "y": 0, "width": 0.2, "height": 0.2}, "color": "#0000FF"}
            """#)
        assertColor(pixels[25, 25], red)
        assertColor(pixels[75, 25], white, "clipped")
        assertColor(pixels[30, 70], blue, "translated by 20, 60 points")
        assertColor(pixels[10, 70], white)
    }

    func testRotationIsClockwiseAboutTheOrigin() throws {
        // A bar along the top edge, moved 50 points right and turned 90 degrees clockwise about
        // its new origin, hangs down from (50, 0) to the left.
        let pixels = try draw(#"""
            {"type": "translate", "x": 50, "y": 0},
            {"type": "rotate", "angle": 90},
            {"type": "fill", "path": {"type": "rect", "x": 0, "y": 0, "width": 1, "height": 0.2}, "color": "#0000FF"}
            """#)
        // Clockwise on the screen: +x turns to +y, +y to -x, so the bar covers x 30...50, y 0...100.
        assertColor(pixels[40, 80], blue, "clockwise: down from the origin")
        assertColor(pixels[60, 80], white)
        assertColor(pixels[80, 10], white, "not along the top")
    }

    func testALayersBlendModeAppliesOverWhatTheLayerDrew() throws {
        // Multiply: red over transparent is red, green over red is black (as Apple's per-operation
        // blend in drawLayer).
        let pixels = try draw(#"""
            {"type": "layer", "frame": [0, 0, 1, 1], "blendMode": "multiply", "operations": [
                {"type": "fill", "path": {"type": "rect", "x": 0, "y": 0, "width": 0.6, "height": 1}, "color": "#FF0000"},
                {"type": "fill", "path": {"type": "rect", "x": 0.4, "y": 0, "width": 0.6, "height": 1}, "color": "#00FF00"}
            ]}
            """#)
        assertColor(pixels[20, 50], red)
        assertColor(pixels[50, 50], black, "green multiplied over red")
        assertColor(pixels[80, 50], [0, 255, 0, 255], "green over nothing in the layer")
    }

    func testAShadowFallsUnderWhatFollows() throws {
        let pixels = try draw(#"""
            {"type": "shadow", "color": "#000000", "radius": 0, "x": 10, "y": 10},
            {"type": "fill", "path": {"type": "rect", "x": 0.2, "y": 0.2, "width": 0.4, "height": 0.4}, "color": "#FF0000"}
            """#)
        assertColor(pixels[40, 40], red)
        assertColor(pixels[65, 65], black, "the shadow 10 points down and right")
        assertColor(pixels[15, 15], white)
    }

    func testTextAndSymbolsDraw() throws {
        let pixels = try draw(#"""
            {"type": "text", "text": "MMMM", "frame": [0, 0, 1, 0.5], "fontSize": 30, "fontWeight": "black"},
            {"type": "image", "systemName": "star.fill", "frame": [0, 0.5, 1, 0.5]}
            """#)
        let top = (0..<50).flatMap { y in (0..<100).map { pixels[$0, y] } }
        XCTAssertTrue(top.contains { $0[0] < 64 }, "black text in its frame")
        let bottom = (50..<100).flatMap { y in (0..<100).map { pixels[$0, y] } }
        XCTAssertTrue(bottom.contains { $0[0] < 128 }, "the symbol in the text color")
    }

    func testAMissingAssetDrawsNothing() throws {
        let pixels = try draw(#"{"type": "image", "assetName": "no-such-icon-anywhere", "frame": [0, 0, 1, 1]}"#)
        XCTAssertTrue((0..<100).allSatisfy { x in (0..<100).allSatisfy { y in pixels[x, y] == white } })
    }

    func testAClickFiresTheAction() throws {
        let node = try render(#""frame": {"width": 100, "height": 100}, "operations": [], "actionID": "test.tapped""#)
        // Shown, so the click at (1, 1) is inside it.
        let window = gtk_window_new()!
        gtk_window_set_child(typed(window), node.outerWidget)
        gtk_window_present(typed(window))
        defer {
            gtk_window_set_child(typed(window), nil)
            gtk_window_destroy(typed(window))
        }
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_width(node.widget) == 100 }))
        let controllers = gtk_widget_observe_controllers(node.widget)!
        defer { g_object_unref(UnsafeMutableRawPointer(controllers)) }
        var gesture: UnsafeMutableRawPointer?
        for index in 0..<g_list_model_get_n_items(controllers) {
            let item = g_list_model_get_item(controllers, index)!
            g_object_unref(item)
            if g_type_check_instance_is_a(item.assumingMemoryBound(to: GTypeInstance.self), gtk_gesture_click_get_type()) != 0 {
                gesture = item
            }
        }
        let click = try XCTUnwrap(gesture)
        var values = [GValue(), GValue(), GValue(), GValue()]
        g_value_init(&values[0], gtk_gesture_click_get_type())
        g_value_set_object(&values[0], click)
        g_value_init(&values[1], GType(6 << 2))  // G_TYPE_INT
        g_value_set_int(&values[1], 1)
        g_value_init(&values[2], GType(15 << 2))  // G_TYPE_DOUBLE
        g_value_set_double(&values[2], 1)
        g_value_init(&values[3], GType(15 << 2))
        g_value_set_double(&values[3], 1)
        g_signal_emitv(&values, g_signal_lookup("released", gtk_gesture_click_get_type()), 0, nil)
        for index in values.indices { g_value_unset(&values[index]) }
        XCTAssertEqual(fired, ["test.tapped"])
    }
}
