// Tests/Runtime/NodeDecorationsTests.swift
/*
 Tests for background and overlay views on GTK (NodeDecorations): a background view lies behind
 the element in its content group, filling the frame when it expands; an overlay view lies over it
 in the outer box, aligned in the frame at its place in the layout (not moved by offset); neither
 changes the element's size or expansion; an alignment set at run time places it again; the
 element's text style, disabled state and environment reach the views; a Group shows none; the views
 leave with their node.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class NodeDecorationsTests: XCTestCase {
    private var windowUUID = ""
    private var renderTree: AdwaitaWindow?
    private var gtkWindow: UnsafeMutablePointer<GtkWindow>?

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "node-decorations-\(name)"
    }

    override func tearDown() async throws {
        renderTree?.detach()
        renderTree = nil
        if let gtkWindow {
            gtk_window_destroy(gtkWindow)
        }
        gtkWindow = nil
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
    }

    private func present(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let tree = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        renderTree = tree
        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        gtkWindow = window
        gtk_window_set_default_size(window, 400, 300)
        adw_window_set_content(typed(window), tree.contentWidget)
        gtk_window_present(window)
        AdwaitaTestHost.drainMainLoop()
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: 100)
        return try XCTUnwrap(tree.root)
    }

    private func bounds(_ widget: WidgetPointer, in ancestor: WidgetPointer) -> (x: Int, y: Int, width: Int, height: Int) {
        var rect = graphene_rect_t()
        _ = gtk_widget_compute_bounds(widget, ancestor, &rect)
        return (Int(rect.origin.x), Int(rect.origin.y), Int(rect.size.width), Int(rect.size.height))
    }

    func testABackgroundViewFillsTheFrameBehindTheElement() throws {
        let root = try present(#"""
            {"type": "VStack", "id": 1, "properties": {"alignment": "leading"}, "children": [
              {"type": "Text", "id": 2, "properties": {"text": "New", "padding": 8}, "background": {"type": "Capsule", "id": 5, "properties": {"fill": "blue"}}},
              {"type": "Text", "id": 3, "properties": {"text": "New", "padding": 8}}]}
            """#)
        let decorated = try XCTUnwrap(root.childNodes[2])
        let plain = try XCTUnwrap(root.childNodes[3])
        let content = try XCTUnwrap(ModifierBox.content(of: decorated.outerWidget))
        // Behind the element: first in the content group; the element is still the content's element.
        let background = try XCTUnwrap(Gtk.Widget(content).firstChild?.pointer)
        XCTAssertNotEqual(background, decorated.outerWidget)
        XCTAssertNotNil(attached(on: UnsafeMutableRawPointer(background), key: decorationMarkerKey))
        XCTAssertEqual(ModifierBox.element(inContent: content), decorated.widget)
        // The capsule expands: it fills the frame (padding included); the element keeps its size and does not expand.
        let frame = bounds(content, in: content)
        XCTAssertEqual(bounds(background, in: content).width, frame.width)
        XCTAssertEqual(bounds(background, in: content).height, frame.height)
        XCTAssertEqual(Gtk.Widget(decorated.outerWidget).measure(GTK_ORIENTATION_HORIZONTAL, forSize: -1).natural,
                       Gtk.Widget(plain.outerWidget).measure(GTK_ORIENTATION_HORIZONTAL, forSize: -1).natural)
        XCTAssertFalse(Gtk.Widget(decorated.outerWidget).expands(GTK_ORIENTATION_HORIZONTAL))
    }

    func testAnOverlayViewIsAlignedInTheFrameAndNotMovedByOffset() throws {
        let root = try present(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "Color", "id": 2, "properties": {"color": "gray", "frame": {"width": 100, "height": 60}, "offset": {"x": 30, "y": 0}, "overlayAlignment": "topTrailing"},
               "overlay": {"type": "Circle", "id": 5, "properties": {"fill": "red", "frame": {"width": 12, "height": 12}}}}]}
            """#)
        let node = try XCTUnwrap(root.childNodes[2])
        let overlay = try XCTUnwrap(Gtk.Widget(node.outerWidget).lastChild?.pointer)
        XCTAssertNotEqual(overlay, ModifierBox.content(of: node.outerWidget))
        // Top trailing in the 100 x 60 frame at its place in the layout, not 30 to the right with the offset.
        let place = bounds(overlay, in: node.outerWidget)
        XCTAssertEqual(place.x + place.width, 100)
        XCTAssertEqual(place.y, 0)
        XCTAssertEqual(place.width, 12)
        // An alignment set at run time places it again.
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 2, propertyName: "overlayAlignment", value: "bottomLeading")
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: 100)
        let moved = bounds(overlay, in: node.outerWidget)
        XCTAssertEqual(moved.x, 0)
        XCTAssertEqual(moved.y + moved.height, 60)
    }

    func testTheElementsTextStyleDisabledAndEnvironmentReachTheViews() throws {
        // As SwiftUI's environment reaches a background or overlay applied after these modifiers;
        // on GTK they sit on the element's widget, which the views are not inside.
        let root = try present(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "Button", "id": 2, "properties": {"title": "Main", "disabled": true, "foregroundStyle": "red", "multilineTextAlignment": "leading"},
               "background": {"type": "Text", "id": 5, "properties": {"text": "Back"}},
               "overlay": {"type": "Button", "id": 6, "properties": {"title": "Over"}}}]}
            """#)
        let node = try XCTUnwrap(root.childNodes[2])
        let content = try XCTUnwrap(ModifierBox.content(of: node.outerWidget))
        let background = try XCTUnwrap(Gtk.Widget(content).firstChild?.pointer)
        let overlay = try XCTUnwrap(Gtk.Widget(node.outerWidget).lastChild?.pointer)
        var label: WidgetPointer = background
        while let child = gtk_widget_get_first_child(label) {
            label = child
        }
        var color = GdkRGBA()
        gtk_widget_get_color(label, &color)
        XCTAssertGreaterThan(color.red, 0.5)
        XCTAssertLessThan(color.green, 0.5)
        XCTAssertEqual(gtk_widget_is_sensitive(overlay), 0)
        // An environment change on the element reaches the views' nodes.
        XCTAssertEqual(gtk_label_get_justify(OpaquePointer(label)), GTK_JUSTIFY_LEFT)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 2, propertyName: "multilineTextAlignment", value: "center")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 2, propertyName: "disabled", value: false)
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: 100)
        XCTAssertEqual(gtk_label_get_justify(OpaquePointer(label)), GTK_JUSTIFY_CENTER)
        XCTAssertEqual(gtk_widget_is_sensitive(overlay), 1)
    }

    func testAGroupShowsNoViewsAndItsSiblingsKeepTheirClicks() throws {
        // A Group's modifiers apply to each child on Apple, and its box spans the stack: one view
        // there would be neither placed nor drawn, and would take the sibling's clicks.
        let root = try present(#"""
            {"type": "HStack", "id": 1, "properties": {"spacing": 0}, "children": [
              {"type": "Color", "id": 2, "properties": {"color": "red", "frame": {"width": 40, "height": 40}}},
              {"type": "Group", "id": 3, "background": {"type": "Color", "id": 5, "properties": {"color": "yellow"}},
               "overlay": {"type": "Color", "id": 6, "properties": {"color": "blue"}},
               "children": [{"type": "Color", "id": 4, "properties": {"color": "green", "frame": {"width": 40, "height": 40}}}]}]}
            """#)
        let group = try XCTUnwrap(root.childNodes[3])
        XCTAssertNil(group.decorations)
        let sibling = try XCTUnwrap(root.childNodes[2])
        let place = bounds(sibling.widget, in: root.outerWidget)
        let picked = gtk_widget_pick(root.outerWidget, Double(place.x + 10), Double(place.y + 10), GTK_PICK_DEFAULT)
        XCTAssertEqual(picked, sibling.widget)
    }

    func testTheViewsLeaveWithTheirNode() throws {
        let root = try present(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "Text", "id": 2, "properties": {"text": "Hi"},
               "background": {"type": "Color", "id": 5, "properties": {"color": "yellow"}},
               "overlay": {"type": "Text", "id": 6, "properties": {"text": "!"}}}]}
            """#)
        let node = try XCTUnwrap(root.childNodes[2])
        let content = try XCTUnwrap(ModifierBox.content(of: node.outerWidget))
        XCTAssertEqual(layoutChildren(content).count, 2)
        XCTAssertEqual(layoutChildren(node.outerWidget).count, 2)
        node.detach()
        XCTAssertEqual(layoutChildren(content).count, 1)
        XCTAssertEqual(layoutChildren(node.outerWidget).count, 1)
    }
}
