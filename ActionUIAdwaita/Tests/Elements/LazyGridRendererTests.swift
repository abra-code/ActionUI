// Tests/Elements/LazyGridRendererTests.swift
/*
 Tests for LazyVGrid and LazyHGrid on GTK (their layout against SwiftUI is in the lazyvgrid-* and
 lazyhgrid-* layout parity fixtures): the track arithmetic; template mode showing one instance per
 content row, keeping unchanged rows and dropping the ones that go; children added at run time
 taking the next cell; a new column definition relaying the grid out; a grid without columns
 drawing no child.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class LazyGridRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "lazy-grid-\(name)"
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

    private func state(_ node: RenderNode) throws -> LazyGridState {
        try XCTUnwrap(attached(on: node.widget, key: lazyGridStateKey))
    }

    private func origin(_ widget: WidgetPointer?, in node: RenderNode) -> [Float] {
        var rect = graphene_rect_t()
        XCTAssertNotEqual(gtk_widget_compute_bounds(widget, node.widget, &rect), 0)
        return [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]
    }

    func testTrackSizes() {
        XCTAssertEqual(LazyGridLayout.trackSizes([.flexible, .flexible], available: 400), [196, 196])
        XCTAssertEqual(LazyGridLayout.trackSizes([.fixed(100), .flexible], available: 400), [100, 292])
        XCTAssertEqual(LazyGridLayout.trackSizes([.flexible, .flexible, .flexible], available: 401), [129, 128, 128], "the first a pixel more")
        XCTAssertEqual(LazyGridLayout.trackSizes([.fixed(80), .flexible], available: 50), [80, 10], "a flexible track keeps its minimum")
        XCTAssertEqual(LazyGridLayout.minimumLength([.fixed(80), .flexible, .flexible]), 116)
    }

    func testATemplateShowsOneInstancePerRowAndKeepsUnchangedRows() throws {
        let node = try render(#"{"type": "LazyVGrid", "id": 1, "properties": {"columns": [{"flexible": true}, {"flexible": true}]}, "template": {"type": "Text", "properties": {"text": "$1"}}}"#)
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["A"], ["B"], ["C"]])
        AdwaitaTestHost.drainMainLoop()
        let first = try state(node).templateRows.nodes
        XCTAssertEqual(first.map { Gtk.Label($0.widget).text }, ["A", "B", "C"])
        gtk_widget_allocate(node.outerWidget, 400, 300, -1, nil)
        XCTAssertEqual(origin(first[2].outerWidget, in: node)[1], origin(first[0].outerWidget, in: node)[1] + Float(gtk_widget_get_height(first[0].outerWidget)), "the third in the second row")
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["A"], ["X"]])
        AdwaitaTestHost.drainMainLoop()
        let second = try state(node).templateRows.nodes
        XCTAssertTrue(second[0] === first[0], "the unchanged row keeps its instance")
        XCTAssertEqual(second.map { Gtk.Label($0.widget).text }, ["A", "X"])
        XCTAssertFalse(first[2].isAttached, "the row that went is detached")
        XCTAssertEqual(Gtk.Widget(node.widget).children.map(\.pointer).count, 2)
    }

    func testAChildAddedAtRunTimeTakesTheNextCell() throws {
        let node = try render(##"{"type": "LazyVGrid", "id": 1, "properties": {"columns": [{"minimum": 50}, {"minimum": 50}]}, "children": [{"type": "Color", "id": 2, "properties": {"color": "#FF0000", "frame": {"height": 20}}}]}"##)
        _ = try ActionUIModel.shared.insertElement(windowUUID: windowUUID, parentID: 1, json: ##"{"type": "Color", "id": 3, "properties": {"color": "#00FF00", "frame": {"height": 20}}}"##)
        AdwaitaTestHost.drainMainLoop()
        gtk_widget_allocate(node.outerWidget, 200, 100, -1, nil)
        let added = try XCTUnwrap(node.childNodes[3]).outerWidget
        XCTAssertEqual(origin(added, in: node), [104, 0, 50, 20], "the second column of the 108 wide block centered in 200")
    }

    func testANewColumnDefinitionRelaysTheGridOut() throws {
        let node = try render(##"{"type": "LazyVGrid", "id": 1, "properties": {"columns": [{"flexible": true}]}, "children": [{"type": "Color", "id": 2, "properties": {"color": "#FF0000", "frame": {"height": 20}}}, {"type": "Color", "id": 3, "properties": {"color": "#00FF00", "frame": {"height": 20}}}]}"##)
        gtk_widget_allocate(node.outerWidget, 200, 100, -1, nil)
        XCTAssertEqual(origin(try XCTUnwrap(node.childNodes[3]).outerWidget, in: node), [0, 20, 200, 20])
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "columns", value: [["flexible": true], ["flexible": true]])
        AdwaitaTestHost.drainMainLoop()
        gtk_widget_allocate(node.outerWidget, 200, 100, -1, nil)
        XCTAssertEqual(origin(try XCTUnwrap(node.childNodes[3]).outerWidget, in: node), [104, 0, 96, 20])
    }

    func testALazyHGridFillsItsRowsColumnByColumn() throws {
        let node = try render(##"{"type": "LazyHGrid", "id": 1, "properties": {"rows": [{"minimum": 30}, {"minimum": 30}]}, "children": [{"type": "Color", "id": 2, "properties": {"color": "#FF0000", "frame": {"width": 20}}}, {"type": "Color", "id": 3, "properties": {"color": "#00FF00", "frame": {"width": 20}}}, {"type": "Color", "id": 4, "properties": {"color": "#0000FF", "frame": {"width": 20}}}]}"##)
        gtk_widget_allocate(node.outerWidget, 100, 68, -1, nil)
        XCTAssertEqual(origin(try XCTUnwrap(node.childNodes[3]).outerWidget, in: node), [0, 38, 20, 30], "the second row of the first column")
        XCTAssertEqual(origin(try XCTUnwrap(node.childNodes[4]).outerWidget, in: node), [20, 0, 20, 30], "the next column")
    }

    func testAGridWithoutColumnsDrawsNoChild() throws {
        // GTK warns about drawing a child that was never allocated; one shown again is allocated.
        let node = try render(##"{"type": "LazyVGrid", "id": 1, "properties": {"columns": [{"flexible": false}]}, "children": [{"type": "Color", "id": 2, "properties": {"color": "#FF0000", "frame": {"height": 20}}}]}"##)
        let window = gtk_window_new()!
        defer { gtk_window_destroy(typed(window)) }
        gtk_window_set_child(typed(window), node.outerWidget)
        gtk_window_present(typed(window))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.outerWidget) != 0 }))
        AdwaitaTestHost.drainMainLoop()
        let child = try XCTUnwrap(node.childNodes[2]).outerWidget
        XCTAssertEqual(gtk_widget_get_child_visible(child), 0)
        let paintable = gtk_widget_paintable_new(node.outerWidget)!
        defer { g_object_unref(UnsafeMutableRawPointer(paintable)) }
        let snapshot = gtk_snapshot_new()!
        gdk_paintable_snapshot(paintable, snapshot, 40, 20)
        if let rendered = gtk_snapshot_free_to_node(snapshot) { gsk_render_node_unref(rendered) }

        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "columns", value: [["flexible": true]])
        AdwaitaTestHost.drainMainLoop()
        gtk_widget_allocate(node.outerWidget, 200, 100, -1, nil)
        XCTAssertEqual(gtk_widget_get_child_visible(child), 1)
        XCTAssertEqual(origin(child, in: node), [0, 0, 200, 20])
    }
}
