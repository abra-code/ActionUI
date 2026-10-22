// Tests/Elements/LabeledContentRendererTests.swift
/*
 Tests for the LabeledContent renderer on GTK: the title, then the children in a row, 8 points
 apart (measured on macOS 27); as large as that unless a child fills; an empty title keeps its
 gap, as in SwiftUI.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class LabeledContentRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "labeledcontent-\(name)"
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

    /// x and width of `widget` in `ancestor`.
    private func span(_ widget: WidgetPointer, in ancestor: WidgetPointer) -> [Int] {
        var rect = graphene_rect_t()
        _ = gtk_widget_compute_bounds(widget, ancestor, &rect)
        return [Int(rect.origin.x.rounded()), Int(rect.size.width.rounded())]
    }

    private func width(_ widget: WidgetPointer) -> Int {
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(widget, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &natural, nil, nil)
        return Int(natural)
    }

    func testTheTitleThenTheChildrenInARow() throws {
        let node = try render(##"""
            {"type": "LabeledContent", "id": 1, "properties": {"title": "Name"}, "children": [
              {"type": "Color", "id": 2, "properties": {"color": "#00FF00", "frame": {"width": 20, "height": 20}}},
              {"type": "Color", "id": 3, "properties": {"color": "#0000FF", "frame": {"width": 20, "height": 20}}}]}
            """##)
        let title = try XCTUnwrap(gtk_widget_get_first_child(node.widget))
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(title))), "Name")
        let titleWidth = width(title)
        XCTAssertEqual(width(node.widget), titleWidth + 8 + 20 + 8 + 20)
        XCTAssertEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_HORIZONTAL), 0, "fixed children: it does not grow")
        gtk_widget_allocate(node.outerWidget, Int32(titleWidth + 56), 40, -1, nil)
        XCTAssertEqual(span(try XCTUnwrap(node.childNodes[2]).outerWidget, in: node.widget), [titleWidth + 8, 20])
        XCTAssertEqual(span(try XCTUnwrap(node.childNodes[3]).outerWidget, in: node.widget), [titleWidth + 36, 20])
    }

    func testAFillingChildTakesTheRestAndAnEmptyTitleKeepsItsGap() throws {
        let node = try render(##"""
            {"type": "LabeledContent", "id": 1, "properties": {"title": "Name"}, "children": [
              {"type": "Color", "id": 2, "properties": {"color": "#00FF00", "frame": {"height": 20}}}]}
            """##)
        XCTAssertNotEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_HORIZONTAL), 0)
        let titleWidth = width(try XCTUnwrap(gtk_widget_get_first_child(node.widget)))
        gtk_widget_allocate(node.outerWidget, 400, 40, -1, nil)
        XCTAssertEqual(span(try XCTUnwrap(node.childNodes[2]).outerWidget, in: node.widget), [titleWidth + 8, 400 - titleWidth - 8])

        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "title", value: "")
        AdwaitaTestHost.drainMainLoop()
        gtk_widget_allocate(node.outerWidget, 400, 40, -1, nil)
        XCTAssertEqual(span(try XCTUnwrap(node.childNodes[2]).outerWidget, in: node.widget), [8, 392], "an empty title still has its gap, as in SwiftUI")
    }
}
