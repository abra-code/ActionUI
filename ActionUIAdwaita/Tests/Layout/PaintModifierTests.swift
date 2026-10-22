// Tests/Layout/PaintModifierTests.swift
/*
 Tests for the painting half of ModifierBox: a background fills the frame, not the space the box
 is given; cornerRadius and clipShape round and clip; border; font, foregroundStyle and tint on
 the element; offset, rotation and scale move what is drawn without changing the layout; a shadow
 is drawn as GTK's shadow node around the content.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class PaintModifierTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        ActionUIRegistry.shared.renderers["Rectangle"] = TestBlockRenderer.self
        windowUUID = "paint-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIRegistry.shared.loadBuiltIns()
    }

    /// A test Rectangle 40 x 20 with these extra properties (JSON members).
    private func render(_ modifiers: String) throws -> RenderNode {
        let json = ##"{"type": "Rectangle", "id": 1, "properties": {"w": 40, "h": 20, "## + modifiers + "}}"
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func content(_ node: RenderNode) throws -> WidgetPointer {
        try XCTUnwrap(ModifierBox.content(of: node.outerWidget))
    }

    private func classes(_ widget: WidgetPointer) -> Set<String> {
        guard let list = gtk_widget_get_css_classes(widget) else { return [] }
        defer { g_strfreev(list) }
        var result: Set<String> = []
        var index = 0
        while let entry = list[index] {
            result.insert(String(cString: entry))
            index += 1
        }
        return result
    }

    /// Whether `widget` has the generated class for exactly these declarations.
    private func has(_ widget: WidgetPointer, _ declarations: [String]) -> Bool {
        guard let name = StyleSheet.shared.className(for: declarations) else { return false }
        return classes(widget).contains(name)
    }

    /// [x, y, width, height] of `widget`'s bounds in `ancestor` (transformed bounds' box).
    private func bounds(_ widget: WidgetPointer, in ancestor: WidgetPointer) -> [Int] {
        var rect = graphene_rect_t()
        _ = gtk_widget_compute_bounds(widget, ancestor, &rect)
        return [Int(rect.origin.x.rounded()), Int(rect.origin.y.rounded()), Int(rect.size.width.rounded()), Int(rect.size.height.rounded())]
    }

    func testABackgroundFillsTheFrameNotTheBox() throws {
        let node = try render(##""background": "#FF0000", "frame": {"width": 100, "height": 50}"##)
        let group = try content(node)
        XCTAssertTrue(has(group, ["background-color: rgba(255, 0, 0, 1);"]))
        // Given more than the frame takes, the box centers the frame; the background is the frame.
        gtk_widget_allocate(node.outerWidget, 300, 200, -1, nil)
        XCTAssertEqual(bounds(group, in: node.outerWidget), [100, 75, 100, 50])
    }

    func testCornerRadiusAndClipShapeRoundAndClip() throws {
        let rounded = try render(#""cornerRadius": 8"#)
        XCTAssertTrue(has(try content(rounded), ["border-radius: 8px;"]))
        XCTAssertEqual(gtk_widget_get_overflow(try content(rounded)), GTK_OVERFLOW_HIDDEN)
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let circle = try render(#""clipShape": "circle""#)
        XCTAssertTrue(has(try content(circle), ["border-radius: 50%;"]))
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let plain = try render(#""opacity": 1"#)
        XCTAssertEqual(gtk_widget_get_overflow(try content(plain)), GTK_OVERFLOW_VISIBLE, "no clip without a shape")
    }

    func testABorderIsDrawnInsideTheFrame() throws {
        let node = try render(#""border": {"color": "blue", "width": 3}"#)
        XCTAssertTrue(has(try content(node), ["outline: 3px solid var(--blue-3);", "outline-offset: -3px;"]))
        // The layout is unchanged.
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(node.outerWidget, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &natural, nil, nil)
        XCTAssertEqual(natural, 40)
    }

    func testFontForegroundAndTintGoOnTheElement() throws {
        let node = try render(#""font": "title", "foregroundStyle": "secondary", "tint": "orange""#)
        XCTAssertTrue(classes(node.widget).contains("title-2"))
        XCTAssertTrue(has(node.widget, ["color: alpha(currentColor, 0.55);"]))
        XCTAssertTrue(has(node.widget, ["--accent-bg-color: var(--orange-3);", "--accent-color: var(--orange-3);"]))
        // Removed at run time, they leave the element.
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "font", value: "body")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertFalse(classes(node.widget).contains("title-2"))
    }

    func testEffectsMoveWhatIsDrawnNotTheLayout() throws {
        let offset = try render(#""offset": {"x": 10, "y": -5}"#)
        gtk_widget_allocate(offset.outerWidget, 40, 20, -1, nil)
        XCTAssertEqual(bounds(try content(offset), in: offset.outerWidget), [10, -5, 40, 20])
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(offset.outerWidget, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &natural, nil, nil)
        XCTAssertEqual(natural, 40, "the layout keeps the size")

        ActionUIModel.shared.windowModels[windowUUID] = nil
        let rotated = try render(#""rotationEffect": 90"#)
        gtk_widget_allocate(rotated.outerWidget, 40, 20, -1, nil)
        XCTAssertEqual(bounds(try content(rotated), in: rotated.outerWidget), [10, -10, 20, 40], "turned around the center")

        ActionUIModel.shared.windowModels[windowUUID] = nil
        let scaled = try render(#""scaleEffect": {"x": 2, "y": 2, "anchor": "topLeading"}"#)
        gtk_widget_allocate(scaled.outerWidget, 40, 20, -1, nil)
        XCTAssertEqual(bounds(try content(scaled), in: scaled.outerWidget), [0, 0, 80, 40])
    }

    func testAShadowIsDrawnAroundTheContent() throws {
        let node = try render(#""background": "white", "shadow": {"radius": 4, "x": 2, "y": 3}"#)
        let window = gtk_window_new()!
        defer { gtk_window_destroy(typed(window)) }
        gtk_window_set_child(typed(window), node.outerWidget)
        gtk_window_present(typed(window))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.outerWidget) != 0 }))
        AdwaitaTestHost.drainMainLoop()

        let paintable = gtk_widget_paintable_new(node.outerWidget)!
        defer { g_object_unref(UnsafeMutableRawPointer(paintable)) }
        let snapshot = gtk_snapshot_new()!
        gdk_paintable_snapshot(paintable, snapshot, 40, 20)
        let rendered = try XCTUnwrap(gtk_snapshot_free_to_node(snapshot), "the box drew nothing")
        defer { gsk_render_node_unref(rendered) }
        XCTAssertTrue(AdwaitaTestHost.contains(rendered, GSK_SHADOW_NODE), "no shadow node in what the box drew")
    }
}
