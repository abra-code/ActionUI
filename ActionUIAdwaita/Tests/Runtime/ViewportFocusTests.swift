// Tests/Runtime/ViewportFocusTests.swift
/*
 Tests for a scrolled view following keyboard focus (ViewportFocus): focus moving to a row out of
 view scrolls the list to it, and to a text field out of view a ScrollView to it; the window's
 focus handler goes with the viewport from window to window and when its window is destroyed;
 focus moving into a popover parented inside the list (a menu's item) does not scroll it, as from
 GTK 4.20 (before it, GTK scrolled toward the popover's item).
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ViewportFocusTests: XCTestCase {
    private var windowUUID = ""
    private var renderTree: AdwaitaWindow?
    private var gtkWindow: UnsafeMutablePointer<GtkWindow>?

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "viewport-focus-\(name)"
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

    /// A List of 30 rows in a window 200 points tall; returns the list box and its scroller.
    private func presentList() throws -> (listBox: WidgetPointer, scroller: OpaquePointer) {
        let rows = (2...31).map { #"{"type": "Text", "id": \#($0), "properties": {"text": "Row \#($0)"}}"# }
        let root = try present(#"{"type": "List", "id": 1, "children": [\#(rows.joined(separator: ", "))]}"#)
        let listBox = try XCTUnwrap(attached(on: root.widget, key: listStateKey)).box
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_height(listBox) > 200 }), "laid out")
        return (listBox, OpaquePointer(root.widget))
    }

    /// The document in a window 300 x 200 points; returns its root node.
    private func present(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let tree = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        renderTree = tree
        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        gtkWindow = window
        gtk_window_set_default_size(window, 300, 200)
        adw_window_set_content(typed(window), tree.contentWidget)
        gtk_window_present(window)
        AdwaitaTestHost.drainMainLoop()
        return try XCTUnwrap(tree.root)
    }

    private func offset(_ scroller: OpaquePointer) -> Double {
        gtk_adjustment_get_value(gtk_scrolled_window_get_vadjustment(scroller))
    }

    func testFocusOnARowOutOfViewScrollsToIt() throws {
        // GtkListBox also scrolls to its cursor row itself, so this holds without ViewportFocus too:
        // row navigation keeps working (the ScrollView test below needs the viewport's handler).
        let (listBox, scroller) = try presentList()
        XCTAssertEqual(offset(scroller), 0)
        let lastRow: WidgetPointer = typed(try XCTUnwrap(gtk_list_box_get_row_at_index(OpaquePointer(listBox), 29)))
        XCTAssertNotEqual(gtk_widget_grab_focus(lastRow), 0)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { self.offset(scroller) > 0 }), "scrolled to the focused row")
    }

    func testFocusOnAFieldOutOfViewInAScrollViewScrollsToIt() throws {
        // Only the viewport's focus handler scrolls here (a List's row above is also scrolled to by
        // GtkListBox, to its cursor row). The field's GtkText takes the focus; the field is scrolled to.
        let fields = (3...32).map { #"{"type": "TextField", "id": \#($0), "properties": {"title": "Field \#($0)"}}"# }
        let root = try present(#"{"type": "ScrollView", "id": 1, "content": {"type": "VStack", "id": 2, "children": [\#(fields.joined(separator: ", "))]}}"#)
        let scroller = OpaquePointer(root.widget!)
        let viewport = try XCTUnwrap(gtk_scrolled_window_get_child(scroller))
        let field = try XCTUnwrap(root.childNodes[2]?.childNodes[32]).widget!
        let adjustment = try XCTUnwrap(gtk_scrolled_window_get_vadjustment(scroller))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: {
            gtk_adjustment_get_upper(adjustment) > gtk_adjustment_get_page_size(adjustment) + 200
        }), "laid out")
        XCTAssertEqual(offset(scroller), 0)
        XCTAssertNotEqual(gtk_widget_grab_focus(field), 0)
        let gtkWindow = try XCTUnwrap(gtkWindow)
        XCTAssertTrue(Gtk.Widget(try XCTUnwrap(gtk_root_get_focus(OpaquePointer(gtkWindow)))).isA(gtk_text_get_type()))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: {
            var bounds = graphene_rect_t()
            guard gtk_widget_compute_bounds(field, viewport, &bounds) != 0 else { return false }
            return bounds.origin.y >= 0 && bounds.origin.y + bounds.size.height <= Float(gtk_widget_get_height(viewport)) + 0.5
        }), "scrolled until the whole field shows")
    }

    func testTheWindowHandlerGoesWithTheViewportFromWindowToWindow() throws {
        try XCTSkipUnless(ViewportFocus.gtkFollowsPopoverFocus, "GTK 4.20 and later follow focus themselves")
        let scroller = gtk_scrolled_window_new()!
        g_object_ref_sink(scroller)
        defer { g_object_unref(scroller) }
        gtk_scrolled_window_set_child(OpaquePointer(scroller), gtk_box_new(GTK_ORIENTATION_VERTICAL, 0))
        ViewportFocus.follow(scroller)
        let viewport = try XCTUnwrap(gtk_scrolled_window_get_child(OpaquePointer(scroller)))
        let follower = try XCTUnwrap(attached(on: UnsafeMutableRawPointer(viewport), key: ViewportFocus.followerKey))
        XCTAssertNil(follower.root, "nothing before the viewport shows")

        let first: UnsafeMutablePointer<GtkWindow> = typed(gtk_window_new()!)
        defer { gtk_window_destroy(first) }
        gtk_window_set_child(first, scroller)
        gtk_window_present(first)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(viewport) != 0 }), "shown")
        XCTAssertEqual(follower.root, UnsafeMutableRawPointer(first))
        XCTAssertNotEqual(g_signal_handler_is_connected(first, follower.focusHandler), 0)
        let firstHandler = follower.focusHandler
        gtk_window_set_child(first, nil)
        XCTAssertNil(follower.root, "removed from the window: unmapped")
        XCTAssertEqual(g_signal_handler_is_connected(first, firstHandler), 0)

        let second: UnsafeMutablePointer<GtkWindow> = typed(gtk_window_new()!)
        gtk_window_set_child(second, scroller)
        gtk_window_present(second)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(viewport) != 0 }), "shown again")
        XCTAssertEqual(follower.root, UnsafeMutableRawPointer(second))
        gtk_window_destroy(second)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(follower.root, "its window destroyed while it showed")
        XCTAssertEqual(follower.focusHandler, 0)
    }

    func testFocusInAPopoverInsideTheListDoesNotScrollIt() throws {
        let (listBox, scroller) = try presentList()
        // Before GTK 4.20 the viewport's own focus scrolling is off, ViewportFocus's on.
        let viewport = try XCTUnwrap(gtk_widget_get_parent(listBox))
        XCTAssertEqual(gtk_viewport_get_scroll_to_focus(OpaquePointer(viewport)) == 0, ViewportFocus.gtkFollowsPopoverFocus)
        // A menu opens from the tenth row, near the bottom of the visible part, reaching below it;
        // its first item takes the focus (GTK 4.18 scrolled 56 points toward it, measured).
        let row: WidgetPointer = typed(try XCTUnwrap(gtk_list_box_get_row_at_index(OpaquePointer(listBox), 9)))
        let popover = gtk_popover_new()!
        let items = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let first = gtk_button_new_with_label("First")!
        gtk_box_append(typed(items), first)
        gtk_box_append(typed(items), gtk_button_new_with_label("Second")!)
        gtk_popover_set_child(typed(popover), items)
        gtk_widget_set_parent(popover, row)
        defer { gtk_widget_unparent(popover) }
        gtk_popover_popup(typed(popover))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(first) != 0 }), "open")
        gtk_widget_grab_focus(first)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(offset(scroller), 0, "the list stays where it was")
        gtk_popover_popdown(typed(popover))
        AdwaitaTestHost.drainMainLoop()
    }
}
