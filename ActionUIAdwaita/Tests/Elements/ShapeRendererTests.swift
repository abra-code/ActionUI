// Tests/Elements/ShapeRendererTests.swift
/*
 Tests for the shape renderers on GTK (Rectangle, RoundedRectangle, Circle, Ellipse, Capsule, all
 drawn by ShapeWidget), from the pixels they paint: each outline fitted to the frame as SwiftUI
 fits it (a centered circle, a corner radius clamped to half the shorter side); fill before stroke,
 a stroke centered on the outline, the foreground color without either; a property change redraws;
 every shape grows in both axes.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ShapeRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "shape-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIRegistry.shared.loadBuiltIns()
    }

    /// A shape of `type` in a `width` x `height` frame, with extra properties (JSON members).
    private func render(_ type: String, _ properties: String, width: Int = 60, height: Int = 20) throws -> RenderNode {
        let json = #"{"type": "\#(type)", "id": 1, "properties": {"frame": {"width": \#(width), "height": \#(height)}, \#(properties)}}"#
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    /// The pixels the shape paints in its frame: 4 bytes per pixel, RGBA, rows top to bottom.
    private func paint(_ node: RenderNode) throws -> (pixels: [UInt8], width: Int) {
        let drawing = try XCTUnwrap(AdwaitaTestHost.drawing(of: node.widget, shownIn: node.outerWidget), "the shape drew nothing")
        defer { gsk_render_node_unref(drawing.node) }
        let pixels = try XCTUnwrap(AdwaitaTestHost.pixels(of: drawing.node, width: drawing.width, height: drawing.height))
        return (pixels, Int(drawing.width))
    }

    /// The red, green, blue and alpha at x, y.
    private func at(_ paint: (pixels: [UInt8], width: Int), _ x: Int, _ y: Int) -> [UInt8] {
        let offset = (y * paint.width + x) * 4
        return Array(paint.pixels[offset..<offset + 4])
    }

    private func isPainted(_ paint: (pixels: [UInt8], width: Int), _ x: Int, _ y: Int) -> Bool {
        at(paint, x, y)[3] > 200
    }

    func testARectangleFillsItsFrame() throws {
        let painted = try paint(try render("Rectangle", ##""fill": "#FF0000""##))
        for (x, y) in [(0, 0), (59, 19), (30, 10)] {
            XCTAssertEqual(at(painted, x, y), [255, 0, 0, 255], "at \(x), \(y)")
        }
    }

    func testACircleIsCenteredInItsFrame() throws {
        let painted = try paint(try render("Circle", ##""fill": "#0000FF""##))
        XCTAssertEqual(at(painted, 30, 10), [0, 0, 255, 255])
        XCTAssertTrue(isPainted(painted, 30, 1), "the diameter is the frame's height")
        XCTAssertFalse(isPainted(painted, 5, 10), "outside the centered circle")
        XCTAssertFalse(isPainted(painted, 55, 10), "outside the centered circle")
    }

    func testAnEllipseTouchesAllFourSides() throws {
        let painted = try paint(try render("Ellipse", ##""fill": "#0000FF""##))
        XCTAssertTrue(isPainted(painted, 1, 10))
        XCTAssertTrue(isPainted(painted, 58, 10))
        XCTAssertTrue(isPainted(painted, 30, 1))
        XCTAssertFalse(isPainted(painted, 3, 3), "the corners stay empty")
    }

    func testACornerRadiusIsClampedToHalfTheShorterSideAsACapsulesIs() throws {
        let rounded = try paint(try render("RoundedRectangle", ##""fill": "#0000FF", "cornerRadius": 100"##))
        let capsule = try paint(try render("Capsule", ##""fill": "#0000FF""##))
        for painted in [rounded, capsule] {
            XCTAssertFalse(isPainted(painted, 1, 1), "a round corner")
            XCTAssertTrue(isPainted(painted, 10, 1), "the straight side starts at the radius, 10")
            XCTAssertTrue(isPainted(painted, 30, 10))
        }
        let small = try paint(try render("RoundedRectangle", ##""fill": "#0000FF", "cornerRadius": 4"##))
        XCTAssertFalse(isPainted(small, 0, 0))
        XCTAssertTrue(isPainted(small, 5, 1), "a radius of 4")
    }

    func testAStrokeIsCenteredOnTheOutlineAndAFillWins() throws {
        let stroked = try paint(try render("Rectangle", ##""stroke": "#00FF00", "strokeLineWidth": 4"##))
        XCTAssertEqual(at(stroked, 1, 10), [0, 255, 0, 255], "the inner half of the line")
        XCTAssertFalse(isPainted(stroked, 3, 10), "only 2 of the 4 points are inside")
        XCTAssertFalse(isPainted(stroked, 30, 10), "a stroke leaves the inside empty")

        let both = try paint(try render("Rectangle", ##""fill": "#FF0000", "stroke": "#00FF00""##))
        XCTAssertEqual(at(both, 30, 10), [255, 0, 0, 255], "fill takes priority")
    }

    func testWithoutFillOrStrokeTheForegroundColorFills() throws {
        let painted = try paint(try render("Circle", ##""foregroundStyle": "#FF0000""##))
        XCTAssertEqual(at(painted, 30, 10), [255, 0, 0, 255])
        // The window's text color: in the test session's light style, a dark one (Adwaita's is
        // 80% opaque).
        let plain = try paint(try render("Rectangle", ##""opacity": 1"##))
        let pixel = at(plain, 30, 10)
        XCTAssertGreaterThan(pixel[3], 128, "the foreground color, not nothing")
        XCTAssertLessThan(pixel[0], 64)
        XCTAssertLessThan(pixel[1], 64)
        XCTAssertLessThan(pixel[2], 64)
    }

    func testAFillOrStrokeWinsOverTheForegroundStyle() throws {
        // SwiftUI: Circle().fill(.red).foregroundStyle(.blue) is red; a semantic fill is taken
        // from the foreground style.
        let filled = try paint(try render("Circle", ##""fill": "#FF0000", "foregroundStyle": "#0000FF""##))
        XCTAssertEqual(at(filled, 30, 10), [255, 0, 0, 255])
        let stroked = try paint(try render("Rectangle", ##""stroke": "#FF0000", "strokeLineWidth": 4, "foregroundStyle": "#0000FF""##))
        XCTAssertEqual(at(stroked, 1, 10), [255, 0, 0, 255])
        let semantic = try paint(try render("Rectangle", ##""fill": "foreground", "foregroundStyle": "#0000FF""##))
        XCTAssertEqual(at(semantic, 30, 10), [0, 0, 255, 255])
    }

    func testAPropertyChangeRedraws() throws {
        let node = try render("Rectangle", ##""fill": "#FF0000""##)
        XCTAssertEqual(at(try paint(node), 30, 10), [255, 0, 0, 255])
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "fill", value: "#0000FF")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(at(try paint(node), 30, 10), [0, 0, 255, 255])
        XCTAssertEqual(ShapeWidget.drawing(of: node.widget), ShapeDrawing(outline: .rectangle, strokeWidth: nil))
    }

    func testEveryShapeGrowsInBothAxes() throws {
        for type in ["Rectangle", "RoundedRectangle", "Circle", "Ellipse", "Capsule"] {
            let json = #"{"type": "\#(type)", "id": 1}"#
            _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
            let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
            windows.append(window)
            let node = try XCTUnwrap(window.root)
            XCTAssertNotEqual(gtk_widget_get_hexpand(node.widget), 0, type)
            XCTAssertNotEqual(gtk_widget_get_vexpand(node.widget), 0, type)
            var minimum: Int32 = -1
            var natural: Int32 = -1
            gtk_widget_measure(node.widget, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &natural, nil, nil)
            XCTAssertEqual([minimum, natural], [0, 10], "\(type): SwiftUI's ideal 10 x 10, no minimum")
        }
    }
}
