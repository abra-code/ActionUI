// Tests/Elements/ControlGroupRendererTests.swift
/*
 Tests for the ControlGroup renderer on GTK: its children side by side with no gap, their buttons
 joined by the fixed linked rules (each button after the first, a toggle button too, overlaps the one before by a pixel,
 as libadwaita's linked buttons do); it does not grow.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ControlGroupRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "controlgroup-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    /// [x, width] of `widget` in `ancestor`.
    private func span(_ widget: WidgetPointer, in ancestor: WidgetPointer) -> [Int] {
        var bounds = graphene_rect_t()
        _ = gtk_widget_compute_bounds(widget, ancestor, &bounds)
        return [Int(bounds.origin.x), Int(bounds.size.width)]
    }

    private let threeButtons = #"""
        {"type": "ControlGroup", "id": 1, "properties": {"title": "Style"}, "children": [
          {"type": "Button", "id": 2, "properties": {"title": "Bold"}},
          {"type": "Button", "id": 3, "properties": {"title": "Italic"}},
          {"type": "Toggle", "id": 4, "properties": {"title": "Underline", "style": "button"}}]}
        """#

    func testChildrenSitSideBySideWithTheirButtonsJoined() throws {
        let group = try render(threeButtons)
        XCTAssertNotEqual(gtk_widget_has_css_class(group.widget, ControlGroup.linkedClass), 0)
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(group.widget, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &natural, nil, nil)
        gtk_widget_allocate(group.widget, natural, 40, -1, nil)
        let buttons = try [2, 3, 4].map { try XCTUnwrap(group.childNodes[$0]) }
        let boxes = buttons.map { span($0.outerWidget, in: group.widget) }
        XCTAssertEqual(boxes[0][0], 0)
        XCTAssertEqual(boxes[1][0], boxes[0][0] + boxes[0][1], "no gap between the boxes")
        XCTAssertEqual(boxes[2][0], boxes[1][0] + boxes[1][1])
        let widgets = buttons.map { span($0.widget, in: group.widget) }
        XCTAssertEqual(widgets[0][0], 0, "the first button keeps its edge")
        XCTAssertEqual(widgets[1][0], boxes[1][0] - 1, "a later button overlaps the one before, as linked buttons do")
        XCTAssertEqual(widgets[2][0], boxes[2][0] - 1)
    }

    func testDoesNotGrowWhenOfferedMore() throws {
        let group = try render(threeButtons)
        XCTAssertEqual(gtk_widget_compute_expand(group.widget, GTK_ORIENTATION_HORIZONTAL), 0)
        XCTAssertEqual(gtk_widget_compute_expand(group.widget, GTK_ORIENTATION_VERTICAL), 0)
    }
}
