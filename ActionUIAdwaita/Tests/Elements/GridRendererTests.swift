// Tests/Elements/GridRendererTests.swift
/*
 Tests for the Grid renderer on GTK: a row inserted at run time adds a row below and a removed
 cell leaves its row shorter; spacing and alignment change at run time; a cell's wrapping text is
 measured at its column's width; an empty Grid takes no space. (Its layout against SwiftUI is in
 the layout parity fixtures: grid-*, also for EmptyView cells and Spacer columns and rows.)
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class GridRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "grid-\(name)"
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

    /// Lays the Grid out at its natural size and returns `id`'s frame in it.
    private func frame(_ id: Int, in node: RenderNode) throws -> [Double] {
        let width = Gtk.Widget(node.outerWidget).measure(GTK_ORIENTATION_HORIZONTAL).natural
        let height = Gtk.Widget(node.outerWidget).measure(GTK_ORIENTATION_VERTICAL, forSize: width).natural
        gtk_widget_allocate(node.outerWidget, Int32(width), Int32(height), -1, nil)
        let child = try XCTUnwrap(node.childNodes[id])
        var bounds = graphene_rect_t()
        XCTAssertNotEqual(gtk_widget_compute_bounds(child.widget, node.outerWidget, &bounds), 0)
        return [Double(bounds.origin.x), Double(bounds.origin.y), Double(bounds.size.width), Double(bounds.size.height)]
    }

    private let twoByTwo = ##"""
        {"type": "Grid", "id": 1, "rows": [
          [{"type": "Color", "id": 2, "properties": {"color": "#FF0000", "frame": {"width": 50, "height": 20}}},
           {"type": "Color", "id": 3, "properties": {"color": "#00FF00", "frame": {"width": 100, "height": 40}}}],
          [{"type": "Color", "id": 4, "properties": {"color": "#0000FF", "frame": {"width": 80, "height": 30}}}]
        ]}
        """##

    func testARowInsertedAtRunTimeGoesBelow() throws {
        let node = try render(twoByTwo)
        _ = try ActionUIModel.shared.insertRow(windowUUID: windowUUID, parentID: 1,
                                               json: ##"[{"type": "Color", "id": 5, "properties": {"color": "#FFFF00", "frame": {"width": 30, "height": 10}}}]"##)
        AdwaitaTestHost.drainMainLoop()
        // Rows of 40 and 30 with 8 between: the third starts at 86; the 80-wide column centers 30.
        XCTAssertEqual(try frame(5, in: node), [25, 86, 30, 10])
    }

    func testARemovedCellLeavesItsRowShorter() throws {
        let node = try render(twoByTwo)
        try ActionUIModel.shared.removeElement(windowUUID: windowUUID, viewID: 3)
        AdwaitaTestHost.drainMainLoop()
        // One column now, as wide as its widest cell (80); the second row follows the first's 20.
        XCTAssertEqual(try frame(4, in: node), [0, 28, 80, 30])
        XCTAssertEqual(Gtk.Widget(node.widget).measure(GTK_ORIENTATION_HORIZONTAL).natural, 80)
    }

    func testSpacingAndAlignmentChangeAtRunTime() throws {
        let node = try render(twoByTwo)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "horizontalSpacing", value: 0.0)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "verticalSpacing", value: 0.0)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "alignment", value: "bottomTrailing")
        AdwaitaTestHost.drainMainLoop()
        // The first column is 80 wide and the first row 40 tall: the 50 x 20 cell at its bottom right.
        XCTAssertEqual(try frame(2, in: node), [30, 20, 50, 20])
        XCTAssertEqual(try frame(3, in: node), [80, 0, 100, 40])
    }

    func testWrappingTextIsMeasuredAtItsColumnsWidth() throws {
        let words = Array(repeating: "word", count: 60).joined(separator: " ")
        let node = try render(##"""
            {"type": "Grid", "id": 1, "properties": {"frame": {"width": 300}}, "rows": [
              [{"type": "Color", "id": 2, "properties": {"color": "#FF0000", "frame": {"width": 100, "height": 20}}},
               {"type": "Text", "id": 3, "properties": {"text": "\##(words)"}}],
              [{"type": "Color", "id": 4, "properties": {"color": "#0000FF", "frame": {"width": 100, "height": 20}}}]
            ]}
            """##)
        gtk_widget_allocate(node.outerWidget, 300, Int32(Gtk.Widget(node.outerWidget).measure(GTK_ORIENTATION_VERTICAL, forSize: 300).natural), -1, nil)
        let text = try XCTUnwrap(node.childNodes[3])
        let textHeight = Double(gtk_widget_get_height(text.widget))
        let wrapped = Double(Gtk.Widget(text.widget).measure(GTK_ORIENTATION_VERTICAL, forSize: gtk_widget_get_width(text.widget).toInt).natural)
        XCTAssertGreaterThan(textHeight, 20, "several lines in a 192-wide column")
        XCTAssertEqual(textHeight, wrapped, accuracy: 1, "its height at its column's width")
        let below = try XCTUnwrap(node.childNodes[4])
        var bounds = graphene_rect_t()
        XCTAssertNotEqual(gtk_widget_compute_bounds(below.widget, node.outerWidget, &bounds), 0)
        XCTAssertGreaterThanOrEqual(Double(bounds.origin.y), textHeight, "the next row starts below the text")
    }

    func testAnEmptyGridTakesNoSpace() throws {
        let node = try render(#"{"type": "Grid", "id": 1, "rows": []}"#)
        XCTAssertEqual(Gtk.Widget(node.widget).measure(GTK_ORIENTATION_HORIZONTAL).natural, 0)
        XCTAssertEqual(Gtk.Widget(node.widget).measure(GTK_ORIENTATION_VERTICAL).natural, 0)
    }
}

private extension Int32 {
    var toInt: Int { Int(self) }
}
