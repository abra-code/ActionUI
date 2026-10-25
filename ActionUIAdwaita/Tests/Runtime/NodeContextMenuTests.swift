// Tests/Runtime/NodeContextMenuTests.swift
/*
 Tests for contextMenu on GTK (NodeContextMenu): a right click on the element's box opens a popover
 menu built from the contextMenu elements as a Menu's children are; choosing a Button item fires
 its action; a changed item changes the menu; an element without a contextMenu gets none; a
 disabled view opens none. (The click is emitted on the gesture: claiming and propagation need
 real pointer input.)
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class NodeContextMenuTests: XCTestCase {
    private var windowUUID = ""
    private var renderTree: AdwaitaWindow?
    private var gtkWindow: UnsafeMutablePointer<GtkWindow>?
    private var fired: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "context-menu-\(name)"
        fired = []
        for id in ["test.rename", "test.delete"] {
            ActionUIModel.shared.registerActionHandler(for: id) { [weak self] actionID, _, _, _, _ in
                MainActor.assumeIsolated { self?.fired.append(actionID) }
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
        for id in ["test.rename", "test.delete"] {
            ActionUIModel.shared.unregisterActionHandler(for: id)
        }
    }

    private func present(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let tree = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        renderTree = tree
        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        gtkWindow = window
        adw_window_set_content(typed(window), tree.contentWidget)
        gtk_window_present(window)
        AdwaitaTestHost.drainMainLoop()
        return try XCTUnwrap(tree.root)
    }

    /// The box's click gesture for the secondary button.
    private func rightClickGesture(_ box: WidgetPointer) -> UnsafeMutableRawPointer? {
        let controllers = gtk_widget_observe_controllers(box)!
        defer { g_object_unref(UnsafeMutableRawPointer(controllers)) }
        for index in 0..<g_list_model_get_n_items(controllers) {
            guard let item = g_list_model_get_item(controllers, index) else { continue }
            g_object_unref(item)
            if g_type_check_instance_is_a(item.assumingMemoryBound(to: GTypeInstance.self), gtk_gesture_click_get_type()) != 0,
               gtk_gesture_single_get_button(OpaquePointer(item)) == guint(GDK_BUTTON_SECONDARY) {
                return item
            }
        }
        return nil
    }

    private func press(_ gesture: UnsafeMutableRawPointer, x: Double, y: Double) {
        var values = [GValue(), GValue(), GValue(), GValue()]
        g_value_init(&values[0], gtk_gesture_click_get_type())
        g_value_set_object(&values[0], gesture)
        g_value_init(&values[1], g_type_from_name("gint"))
        g_value_set_int(&values[1], 1)
        g_value_init(&values[2], g_type_from_name("gdouble"))
        g_value_set_double(&values[2], x)
        g_value_init(&values[3], g_type_from_name("gdouble"))
        g_value_set_double(&values[3], y)
        g_signal_emitv(&values, g_signal_lookup("pressed", gtk_gesture_click_get_type()), 0, nil)
        for index in values.indices { g_value_unset(&values[index]) }
    }

    private let document = #"""
        {"type": "VStack", "id": 1, "children": [{"type": "Text", "id": 2, "properties": {"text": "A row"},
          "contextMenu": [
            {"type": "Button", "id": 10, "properties": {"title": "Rename", "actionID": "test.rename"}},
            {"type": "Divider", "id": 11},
            {"type": "Button", "id": 12, "properties": {"title": "Delete", "role": "destructive", "actionID": "test.delete"}}]}]}
        """#

    func testARightClickOpensTheMenuAndAnItemFiresItsAction() throws {
        let root = try present(document)
        let text = try XCTUnwrap(root.childNodes[2])
        XCTAssertNil(root.contextMenu, "no contextMenu, no menu")
        let contextMenu = try XCTUnwrap(text.contextMenu)
        XCTAssertNil(contextMenu.menuWidget, "made on the first opening")
        press(try XCTUnwrap(rightClickGesture(try XCTUnwrap(ModifierBox.content(of: text.outerWidget)))), x: 5, y: 5)
        let menu = try XCTUnwrap(contextMenu.menuWidget)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_visible(menu) != 0 }), "open")
        // The model: two sections (the Divider), the items' actions in the box's group.
        let model = try XCTUnwrap(gtk_popover_menu_get_menu_model(OpaquePointer(menu)))
        XCTAssertEqual(g_menu_model_get_n_items(model), 2)
        // Choosing Rename, as the menu activates it.
        XCTAssertNotEqual(gtk_widget_activate_action_variant(menu, "\(Menu.actionPrefix).\(Menu.actionName(10))", nil), 0)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired, ["test.rename"])
    }

    func testAChangedItemChangesTheMenu() throws {
        let root = try present(document)
        let text = try XCTUnwrap(root.childNodes[2])
        let contextMenu = try XCTUnwrap(text.contextMenu)
        press(try XCTUnwrap(rightClickGesture(try XCTUnwrap(ModifierBox.content(of: text.outerWidget)))), x: 5, y: 5)
        let menu = try XCTUnwrap(contextMenu.menuWidget)
        gtk_popover_popdown(typed(menu))
        AdwaitaTestHost.drainMainLoop()
        let before = gtk_popover_menu_get_menu_model(OpaquePointer(menu))
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 10, propertyName: "title", value: "Rename...")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertFalse(gtk_popover_menu_get_menu_model(OpaquePointer(menu)) == before, "a new model for the new title")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 12, propertyName: "disabled", value: true)
        AdwaitaTestHost.drainMainLoop()
        // GTK reports a disabled action as found, and does not activate it.
        gtk_widget_activate_action_variant(menu, "\(Menu.actionPrefix).\(Menu.actionName(12))", nil)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired, [], "a disabled item's action does nothing")
    }

    func testADisabledViewOpensNoMenu() throws {
        // GTK picks the box, which is not insensitive, when a right click lands on a disabled view.
        let root = try present(document)
        let text = try XCTUnwrap(root.childNodes[2])
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 2, propertyName: "disabled", value: true)
        AdwaitaTestHost.drainMainLoop()
        let contextMenu = try XCTUnwrap(text.contextMenu)
        press(try XCTUnwrap(rightClickGesture(try XCTUnwrap(ModifierBox.content(of: text.outerWidget)))), x: 5, y: 5)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(contextMenu.menuWidget, "no menu for a disabled view")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 2, propertyName: "disabled", value: false)
        AdwaitaTestHost.drainMainLoop()
        press(try XCTUnwrap(rightClickGesture(try XCTUnwrap(ModifierBox.content(of: text.outerWidget)))), x: 5, y: 5)
        XCTAssertNotNil(contextMenu.menuWidget, "enabled again, it opens")
    }
}
