// Tests/Runtime/NodeDecorationsTests.swift
/*
 Tests for background and overlay views on GTK (NodeDecorations): a background view lies behind
 the element in its content group, filling the frame when it expands; an overlay view lies over it
 in the outer box, aligned in the frame at its place in the layout (not moved by offset); neither
 changes the element's size or expansion; an alignment set at run time places it again; only the
 settings SwiftUI applies after the views reach them (not the element's text style or disabled),
 and its hidden state; the overlay carries the element's context menu, hover, drop and container
 tap; a Group shows none; the views leave with their node.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class NodeDecorationsTests: XCTestCase {
    private var windowUUID = ""
    private var renderTree: AdwaitaWindow?
    private var gtkWindow: UnsafeMutablePointer<GtkWindow>?
    private var fired: [(actionID: String, context: [String: Any]?)] = []
    private let actionIDs = ["test.tap", "test.hover", "test.drop", "test.menu"]

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "node-decorations-\(name)"
        fired = []
        for actionID in actionIDs {
            ActionUIModel.shared.registerActionHandler(for: actionID) { [weak self] id, _, _, _, context in
                MainActor.assumeIsolated { self?.fired.append((id, context as? [String: Any])) }
            }
        }
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
        actionIDs.forEach { ActionUIModel.shared.unregisterActionHandler(for: $0) }
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

    func testOnlyWhatSwiftUIAppliesAfterTheViewsReachesThem() throws {
        // SwiftUI applies font, foregroundStyle, tint and disabled before a background or overlay
        // view, and they do not reach it (measured: an overlay after foregroundStyle draws in the
        // default style, one after disabled is enabled); multilineTextAlignment comes after the
        // background and before the overlay.
        let root = try present(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "Button", "id": 2, "properties": {"title": "Main", "disabled": true, "foregroundStyle": "red", "multilineTextAlignment": "center"},
               "background": {"type": "Text", "id": 5, "properties": {"text": "Back"}},
               "overlay": {"type": "Text", "id": 6, "properties": {"text": "Over"}}}]}
            """#)
        let node = try XCTUnwrap(root.childNodes[2])
        let views = try XCTUnwrap(node.decorations?.nodes)
        let background = try XCTUnwrap(views.first { $0.decoration == .background })
        let overlay = try XCTUnwrap(views.first { $0.decoration == .overlay })
        var color = GdkRGBA()
        gtk_widget_get_color(background.widget, &color)
        XCTAssertLessThan(color.red, 0.5, "not the element's red")
        XCTAssertEqual(gtk_widget_is_sensitive(overlay.widget), 1, "not the element's disabled")
        XCTAssertEqual(gtk_widget_is_sensitive(background.widget), 1)
        XCTAssertEqual(gtk_label_get_justify(OpaquePointer(background.widget)), GTK_JUSTIFY_CENTER)
        XCTAssertEqual(gtk_label_get_justify(OpaquePointer(overlay.widget)), GTK_JUSTIFY_LEFT)
        // A change to the element's setting reaches the background view.
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 2, propertyName: "multilineTextAlignment", value: "trailing")
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: 100)
        XCTAssertEqual(gtk_label_get_justify(OpaquePointer(background.widget)), GTK_JUSTIFY_RIGHT)
        XCTAssertEqual(gtk_label_get_justify(OpaquePointer(overlay.widget)), GTK_JUSTIFY_LEFT)
    }

    func testAChangeToTheElementsParentReachesTheViews() throws {
        // The overlay view inherits the parent's multilineTextAlignment, not the element's (applied
        // before it), so a change on the parent reaches it though the element's environment stays.
        let root = try present(#"""
            {"type": "VStack", "id": 1, "properties": {"multilineTextAlignment": "leading"}, "children": [
              {"type": "Text", "id": 2, "properties": {"text": "Main", "multilineTextAlignment": "trailing"},
               "overlay": {"type": "Text", "id": 6, "properties": {"text": "Over"}}}]}
            """#)
        let node = try XCTUnwrap(root.childNodes[2])
        let overlay = try XCTUnwrap(node.decorations?.overlay)
        XCTAssertEqual(gtk_label_get_justify(OpaquePointer(overlay.widget)), GTK_JUSTIFY_LEFT)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "multilineTextAlignment", value: "center")
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: 100)
        XCTAssertEqual(gtk_label_get_justify(OpaquePointer(overlay.widget)), GTK_JUSTIFY_CENTER)
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

    /// The controllers of `type` on `widget` (a click gesture for `button`, when given).
    private func controllers(_ widget: WidgetPointer, _ type: GType, button: Int? = nil) -> [UnsafeMutableRawPointer] {
        let list = gtk_widget_observe_controllers(widget)!
        defer { g_object_unref(UnsafeMutableRawPointer(list)) }
        var result: [UnsafeMutableRawPointer] = []
        for index in 0..<g_list_model_get_n_items(list) {
            guard let item = g_list_model_get_item(list, index) else { continue }
            g_object_unref(item)
            guard g_type_check_instance_is_a(item.assumingMemoryBound(to: GTypeInstance.self), type) != 0 else { continue }
            if let button, gtk_gesture_single_get_button(OpaquePointer(item)) != guint(button) { continue }
            result.append(item)
        }
        return result
    }

    /// Emits a click gesture's `signal` ("pressed", "released") at (x, y).
    private func click(_ gesture: UnsafeMutableRawPointer, _ signal: String, x: Double, y: Double) {
        var values = [GValue(), GValue(), GValue(), GValue()]
        g_value_init(&values[0], gtk_gesture_click_get_type())
        g_value_set_object(&values[0], gesture)
        g_value_init(&values[1], g_type_from_name("gint"))
        g_value_set_int(&values[1], 1)
        g_value_init(&values[2], g_type_from_name("gdouble"))
        g_value_set_double(&values[2], x)
        g_value_init(&values[3], g_type_from_name("gdouble"))
        g_value_set_double(&values[3], y)
        g_signal_emitv(&values, g_signal_lookup(signal, gtk_gesture_click_get_type()), 0, nil)
        for index in values.indices { g_value_unset(&values[index]) }
    }

    private func enter(_ motion: UnsafeMutableRawPointer) {
        var values = [GValue(), GValue(), GValue()]
        g_value_init(&values[0], gtk_event_controller_motion_get_type())
        g_value_set_object(&values[0], motion)
        g_value_init(&values[1], g_type_from_name("gdouble"))
        g_value_init(&values[2], g_type_from_name("gdouble"))
        g_signal_emitv(&values, g_signal_lookup("enter", gtk_event_controller_motion_get_type()), 0, nil)
        for index in values.indices { g_value_unset(&values[index]) }
    }

    func testTheOverlayCarriesTheElementsPointerHandlers() throws {
        let root = try present(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "VStack", "id": 2, "properties": {"frame": {"width": 100, "height": 60}, "actionID": "test.tap", "onHoverActionID": "test.hover",
                 "onDropTypes": ["public.plain-text"], "onDropActionID": "test.drop", "overlayAlignment": "topTrailing"},
               "contextMenu": [{"type": "Button", "id": 10, "properties": {"title": "Act", "actionID": "test.menu"}}],
               "overlay": {"type": "Circle", "id": 9, "properties": {"fill": "red", "frame": {"width": 12, "height": 12}}},
               "children": [{"type": "Text", "id": 3, "properties": {"text": "Card"}}]}]}
            """#)
        let node = try XCTUnwrap(root.childNodes[2])
        let frame = try XCTUnwrap(ModifierBox.content(of: node.outerWidget))
        let overlay = try XCTUnwrap(node.decorations?.overlay?.outerWidget)
        // The context menu: a right click on the overlay opens it.
        click(try XCTUnwrap(controllers(overlay, gtk_gesture_click_get_type(), button: 3).first), "pressed", x: 2, y: 2)
        let menu = try XCTUnwrap(node.contextMenu?.menuWidget, "the element's menu, from the overlay")
        gtk_popover_popdown(typed(menu))
        AdwaitaTestHost.drainMainLoop()
        // The container tap: a click released on the overlay fires the element's action.
        let tap = try XCTUnwrap(controllers(overlay, gtk_gesture_click_get_type(), button: 1).first)
        click(tap, "pressed", x: 2, y: 2)
        click(tap, "released", x: 2, y: 2)
        XCTAssertEqual(fired.map(\.actionID), ["test.tap"])
        fired = []
        // Hover: the pointer moving from the frame onto the overlay stays hovering.
        let frameMotion = try XCTUnwrap(controllers(frame, gtk_event_controller_motion_get_type()).first)
        let overlayMotion = try XCTUnwrap(controllers(overlay, gtk_event_controller_motion_get_type()).first)
        enter(frameMotion)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { self.fired.count == 1 }))
        AdwaitaTestHost.emit("leave", on: frameMotion)
        enter(overlayMotion)
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: 100)
        XCTAssertEqual(fired.map { $0.context?["isHovering"] as? Bool }, [true], "no leave between the two")
        AdwaitaTestHost.emit("leave", on: overlayMotion)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { self.fired.count == 2 }))
        XCTAssertEqual(fired.last?.context?["isHovering"] as? Bool, false)
        fired = []
        // A drop on the overlay, at its point in the frame.
        let target = try XCTUnwrap(controllers(overlay, gtk_drop_target_get_type()).first)
        var text = GValue()
        g_value_init(&text, g_type_from_name("gchararray"))
        g_value_set_string(&text, "Hello")
        defer { g_value_unset(&text) }
        var dropped = GValue()
        g_value_init(&dropped, g_value_get_type())
        withUnsafeMutablePointer(to: &text) { g_value_set_boxed(&dropped, $0) }
        defer { g_value_unset(&dropped) }
        var values = [GValue(), GValue(), GValue(), GValue()]
        g_value_init(&values[0], gtk_drop_target_get_type())
        g_value_set_object(&values[0], target)
        values[1] = dropped
        g_value_init(&values[2], g_type_from_name("gdouble"))
        g_value_set_double(&values[2], 1)
        g_value_init(&values[3], g_type_from_name("gdouble"))
        g_value_set_double(&values[3], 2)
        var handled = GValue()
        g_value_init(&handled, g_type_from_name("gboolean"))
        g_signal_emitv(&values, g_signal_lookup("drop", gtk_drop_target_get_type()), 0, &handled)
        g_value_unset(&handled)
        for index in [0, 2, 3] { g_value_unset(&values[index]) }
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { !self.fired.isEmpty }))
        let place = bounds(overlay, in: frame)
        XCTAssertEqual(fired.first?.context?["location"] as? [String: Double], ["x": Double(place.x + 1), "y": Double(place.y + 2)])
    }

    /// Whether GTK holds `widget` hidden from assistive technologies. gtk_test_accessible_check_state
    /// is variadic, which Swift cannot call; with one integer argument after the state it is called
    /// as a plain function (the C calling conventions of aarch64 and x86_64 Linux pass it alike).
    private func isHiddenInGTK(_ widget: WidgetPointer) throws -> Bool {
        typealias CheckState = @convention(c) (OpaquePointer, GtkAccessibleState, gboolean) -> UnsafeMutablePointer<CChar>?
        let symbol = try XCTUnwrap(dlsym(dlopen(nil, RTLD_NOW), "gtk_test_accessible_check_state"))
        let check = unsafeBitCast(symbol, to: CheckState.self)
        // nil when the state has the value, else a message to free.
        guard let mismatch = check(OpaquePointer(widget), GTK_ACCESSIBLE_STATE_HIDDEN, 1) else { return true }
        g_free(mismatch)
        return false
    }

    func testTheElementsHiddenStateReachesTheViews() throws {
        let root = try present(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "Text", "id": 2, "properties": {"text": "Card", "accessibilityHidden": true},
               "background": {"type": "Color", "id": 5, "properties": {"color": "yellow"}},
               "overlay": {"type": "Text", "id": 6, "properties": {"text": "!"}}}]}
            """#)
        let node = try XCTUnwrap(root.childNodes[2])
        let boxes = try XCTUnwrap(node.decorations?.nodes).map { $0.outerWidget! }
        XCTAssertEqual(boxes.count, 2)
        // GTK's own state, which it sets to shown whenever a widget maps; hiding a box keeps its
        // descendants (the overlay's Text) out of the accessibility tree too.
        let hidden = { try boxes.map { try self.isHiddenInGTK($0) } }
        let remap = {
            gtk_widget_set_visible(root.outerWidget, 0)
            AdwaitaTestHost.drainMainLoop()
            gtk_widget_set_visible(root.outerWidget, 1)
            AdwaitaTestHost.drainMainLoop()
        }
        XCTAssertEqual(boxes.map { gtk_widget_get_mapped($0) }, [1, 1])
        XCTAssertEqual(try hidden(), [true, true], "declared hidden, shown in a window")
        remap()
        XCTAssertEqual(try hidden(), [true, true], "still hidden once mapped again")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 2, propertyName: "accessibilityHidden", value: false)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try hidden(), [false, false])
        remap()
        XCTAssertEqual(try hidden(), [false, false], "shown once mapped again")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 2, propertyName: "hidden", value: true)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try hidden(), [true, true], "hidden hides them too")
        remap()
        XCTAssertEqual(try hidden(), [true, true])
    }


    func testAViewIsNotInItsElementsStackOrList() throws {
        let root = try present(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "VStack", "id": 2, "properties": {"alignment": "leading"},
               "overlay": {"type": "Text", "id": 5, "properties": {"text": "Over"}},
               "children": [{"type": "Text", "id": 3, "properties": {"text": "In"}}]},
              {"type": "HStack", "id": 4, "background": {"type": "Spacer", "id": 6},
               "children": [{"type": "Text", "id": 7, "properties": {"text": "Row"}}]},
              {"type": "List", "id": 8, "overlay": {"type": "Text", "id": 9, "properties": {"text": "Badge"},
                 "swipeActions": [{"type": "Button", "id": 10, "properties": {"title": "Pin"}}]},
               "children": [{"type": "Text", "id": 11, "properties": {"text": "Item"}}]}]}
            """#)
        let leading = try XCTUnwrap(root.childNodes[2])
        XCTAssertEqual(Text.boxPosition(try XCTUnwrap(leading.childNodes[3])), 0, "a child of the leading VStack")
        XCTAssertEqual(Text.boxPosition(try XCTUnwrap(leading.decorations?.overlay)), 0.5, "the overlay is not in the stack")
        let row = try XCTUnwrap(root.childNodes[4])
        let spacer = try XCTUnwrap(row.decorations?.nodes.first)
        XCTAssertNil(Spacer.parentAxis(spacer), "the background is not in the HStack")
        let list = try XCTUnwrap(root.childNodes[8])
        XCTAssertNil(list.decorations?.overlay?.contextMenu, "the overlay is not a List row: no swipe actions")
    }
}
