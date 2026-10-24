// Tests/Elements/ScrollViewRendererTests.swift
/*
 Tests for the ScrollView renderer on GTK: it scrolls along its axis only and expands there;
 showsIndicators false keeps scrolling without a scrollbar; the axis changes at run time; content
 taller than the ScrollView scrolls over all of it, at its own height; without content it is
 empty; a horizontal one measures its content's height at the width the content gets (wrapping
 text). (Its layout against SwiftUI is in the layout parity fixtures: scrollview-*.)
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ScrollViewRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "scrollview-\(name)"
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

    private func policies(_ node: RenderNode) -> (horizontal: GtkPolicyType, vertical: GtkPolicyType) {
        var horizontal = GTK_POLICY_NEVER
        var vertical = GTK_POLICY_NEVER
        gtk_scrolled_window_get_policy(OpaquePointer(node.widget), &horizontal, &vertical)
        return (horizontal, vertical)
    }

    private let tallContent = ##"{"type": "Color", "id": 2, "properties": {"color": "#FF0000", "frame": {"width": 100, "height": 1000}}}"##

    func testAVerticalScrollViewScrollsAndExpandsVerticallyOnly() throws {
        let node = try render(#"{"type": "ScrollView", "id": 1, "content": "# + tallContent + "}")
        XCTAssertEqual(policies(node).horizontal, GTK_POLICY_NEVER)
        XCTAssertEqual(policies(node).vertical, GTK_POLICY_AUTOMATIC)
        XCTAssertTrue(Gtk.Widget(node.widget).expands(GTK_ORIENTATION_VERTICAL))
        XCTAssertFalse(Gtk.Widget(node.widget).expands(GTK_ORIENTATION_HORIZONTAL), "as wide as its fixed content")
    }

    func testHiddenIndicatorsKeepScrollingWithoutAScrollbar() throws {
        let node = try render(#"{"type": "ScrollView", "id": 1, "properties": {"showsIndicators": false}, "content": "# + tallContent + "}")
        XCTAssertEqual(policies(node).vertical, GTK_POLICY_EXTERNAL)
    }

    func testTheAxisChangesAtRunTime() throws {
        let node = try render(#"{"type": "ScrollView", "id": 1, "content": "# + tallContent + "}")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "axis", value: "horizontal")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(policies(node).horizontal, GTK_POLICY_AUTOMATIC)
        XCTAssertEqual(policies(node).vertical, GTK_POLICY_NEVER)
        XCTAssertTrue(Gtk.Widget(node.widget).expands(GTK_ORIENTATION_HORIZONTAL))
        XCTAssertFalse(Gtk.Widget(node.widget).expands(GTK_ORIENTATION_VERTICAL), "as tall as its fixed content")
    }

    func testTallContentScrollsOverAllOfIt() throws {
        let node = try render(#"{"type": "ScrollView", "id": 1, "properties": {"frame": {"width": 200, "height": 300}}, "content": "# + tallContent + "}")
        gtk_widget_allocate(node.outerWidget, 200, 300, -1, nil)
        let adjustment = try XCTUnwrap(gtk_scrolled_window_get_vadjustment(OpaquePointer(node.widget)))
        XCTAssertEqual(gtk_adjustment_get_upper(adjustment), 1000, accuracy: 1, "the whole content")
        XCTAssertEqual(gtk_adjustment_get_page_size(adjustment), 300, accuracy: 1, "one ScrollView high")
        let content = try XCTUnwrap(node.childNodes[2])
        var bounds = graphene_rect_t()
        XCTAssertNotEqual(gtk_widget_compute_bounds(content.widget, node.outerWidget, &bounds), 0)
        XCTAssertEqual(Double(bounds.origin.y), 0, accuracy: 1, "at the top")
        XCTAssertEqual(Double(bounds.size.height), 1000, accuracy: 1, "at its own height, not the ScrollView's")
    }

    private func frame(_ widget: WidgetPointer, in ancestor: WidgetPointer) -> [Int] {
        var bounds = graphene_rect_t()
        _ = gtk_widget_compute_bounds(widget, ancestor, &bounds)
        return [bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height].map { Int($0.rounded()) }
    }

    private let words = Array(repeating: "wrap", count: 80).joined(separator: " ")

    func testAHorizontalScrollViewIsAsTallAsItsContentAtItsNaturalWidth() throws {
        // The text is one line at its natural width, where the content sits, so the ScrollView
        // stops at the text plus 50, not at the text wrapped at the 150 the stack offers.
        let column = ##"{"type": "VStack", "id": 3, "properties": {"spacing": 0}, "children": [{"type": "Text", "id": 4, "properties": {"text": "\##(words)"}}, {"type": "Color", "id": 5, "properties": {"color": "#FF0000", "frame": {"maxHeight": 50}}}]}"##
        let node = try render(#"{"type": "VStack", "id": 1, "properties": {"spacing": 0, "frame": {"width": 150, "height": 800}}, "children": [{"type": "ScrollView", "id": 2, "properties": {"axis": "horizontal"}, "content": \#(column)}]}"#)
        gtk_widget_allocate(node.outerWidget, 150, 800, -1, nil)
        let scroll = try XCTUnwrap(node.childNodes[2])
        let content = try XCTUnwrap(scroll.childNodes[3])
        let contentHeight = frame(content.outerWidget, in: node.outerWidget)[3]
        XCTAssertLessThan(contentHeight, 100, "one line of text and the Color")
        XCTAssertEqual(frame(scroll.outerWidget, in: node.outerWidget)[3], contentHeight)
    }

    func testAHorizontalScrollViewGivesItsContentItsHeightForItsWidth() throws {
        // The column is at most 150 wide, so the text wraps there: the column is as tall as all its
        // lines plus the Color's 50, not squeezed to the text's one-line height.
        let column = ##"{"type": "VStack", "id": 3, "properties": {"spacing": 0, "frame": {"maxWidth": 150}}, "children": [{"type": "Text", "id": 4, "properties": {"text": "\##(words)"}}, {"type": "Color", "id": 5, "properties": {"color": "#FF0000", "frame": {"maxHeight": 50}}}]}"##
        let node = try render(#"{"type": "VStack", "id": 1, "properties": {"spacing": 0, "frame": {"width": 400, "height": 800}}, "children": [{"type": "ScrollView", "id": 2, "properties": {"axis": "horizontal"}, "content": \#(column)}]}"#)
        gtk_widget_allocate(node.outerWidget, 400, 800, -1, nil)
        let scroll = try XCTUnwrap(node.childNodes[2])
        let content = try XCTUnwrap(scroll.childNodes[3])
        let text = frame(try XCTUnwrap(content.childNodes[4]).widget, in: node.outerWidget)
        XCTAssertEqual(text[2], 150)
        XCTAssertGreaterThan(text[3], 100, "the text wraps to many lines")
        XCTAssertEqual(frame(try XCTUnwrap(content.childNodes[5]).widget, in: node.outerWidget)[3], 50, "the Color keeps its cap under the text")
        XCTAssertEqual(frame(content.outerWidget, in: node.outerWidget)[3], text[3] + 50)
        XCTAssertEqual(frame(scroll.outerWidget, in: node.outerWidget)[3], text[3] + 50)
    }

    func testAScrollViewWithoutContentIsEmpty() throws {
        let node = try render(#"{"type": "ScrollView", "id": 1}"#)
        let configuration = try XCTUnwrap(attached(on: node.widget, key: scrollConfigurationKey))
        XCTAssertNil(Gtk.Widget(configuration.content).firstChild)
        XCTAssertEqual(Gtk.Widget(node.outerWidget).measure(GTK_ORIENTATION_HORIZONTAL).natural, 0, "no width of its own")
    }
}
