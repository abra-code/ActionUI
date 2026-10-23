// Tests/Elements/MenuRendererTests.swift
/*
 Tests for the Menu renderer on GTK: a menu button with the title, or the label element, and an
 arrow; the children as a GMenu (a Divider starts a section, a Section has its header, a nested Menu
 is a submenu, a hidden Button is left out); choosing an item runs the Button's actionID once, a
 disabled Button's item is disabled; the menu is rebuilt only when it changes; children inserted
 into a nested Section or Menu at run time are shown; an underscore in an item's title is not a
 mnemonic; it does not grow. A Toggle is a check item and a Picker a submenu of radio items, their
 marks following the value without rebuilding the menu; a Text, plain or markdown, is an item with
 no action. The built menu holds the only reference to each of its parts.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class MenuRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var fired: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "menu-\(name)"
        fired = []
        for id in ["test.copy", "test.delete", "test.share"] {
            ActionUIModel.shared.registerActionHandler(for: id) { [weak self] actionID, _, _, _, _ in
                MainActor.assumeIsolated { self?.fired.append(actionID) }
            }
        }
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        for id in ["test.copy", "test.delete", "test.share"] {
            ActionUIModel.shared.unregisterActionHandler(for: id)
        }
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private let options = #"""
        {"type": "Menu", "id": 1, "properties": {"title": "Options"}, "children": [
          {"type": "Button", "id": 2, "properties": {"title": "Copy", "actionID": "test.copy"}},
          {"type": "Button", "id": 3, "properties": {"title": "Paste", "disabled": true}},
          {"type": "Button", "id": 4, "properties": {"title": "Secret", "hidden": true}},
          {"type": "Divider", "id": 5},
          {"type": "Button", "id": 6, "properties": {"title": "Delete", "actionID": "test.delete"}},
          {"type": "Section", "id": 7, "properties": {"header": "Send"}, "children": [
            {"type": "Button", "id": 8, "properties": {"title": "Share", "actionID": "test.share"}}]},
          {"type": "Menu", "id": 9, "properties": {"title": "More"}, "children": [
            {"type": "Button", "id": 10, "properties": {"title": "Inner"}}]}]}
        """#

    private func model(_ node: RenderNode) throws -> UnsafeMutablePointer<GMenuModel> {
        try XCTUnwrap(gtk_menu_button_get_menu_model(OpaquePointer(node.widget)))
    }

    private func label(_ model: UnsafeMutablePointer<GMenuModel>, _ index: Int32) -> String? {
        guard let value = g_menu_model_get_item_attribute_value(model, index, "label", nil) else { return nil }
        defer { g_variant_unref(value) }
        return g_variant_get_string(value, nil).map { String(cString: $0) }
    }

    private func link(_ model: UnsafeMutablePointer<GMenuModel>, _ index: Int32, _ name: String) -> UnsafeMutablePointer<GMenuModel>? {
        guard let linked = g_menu_model_get_item_link(model, index, name) else { return nil }
        g_object_unref(linked)
        return linked
    }

    private func actions(_ node: RenderNode) throws -> OpaquePointer {
        try XCTUnwrap(attached(on: node.widget, key: menuStateKey)).actions
    }

    func testTheButtonShowsTheTitleWithAnArrow() throws {
        let node = try render(options)
        XCTAssertEqual(swiftString(gtk_menu_button_get_label(OpaquePointer(node.widget))), "Options")
        XCTAssertNotEqual(gtk_menu_button_get_always_show_arrow(OpaquePointer(node.widget)), 0)
        XCTAssertEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_HORIZONTAL), 0)
        XCTAssertEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_VERTICAL), 0)
    }

    func testTheChildrenBecomeSectionsItemsAndASubmenu() throws {
        let menu = try model(try render(options))
        // Sections in order: Copy and Paste (Secret is hidden); Delete (after the Divider); "Send"
        // with Share; the More submenu (after the Section).
        XCTAssertEqual(g_menu_model_get_n_items(menu), 4)
        guard g_menu_model_get_n_items(menu) == 4 else { return }
        let first = try XCTUnwrap(link(menu, 0, "section"))
        XCTAssertEqual(g_menu_model_get_n_items(first), 2, "a hidden Button is left out")
        XCTAssertEqual([0, 1].map { label(first, $0) }, ["Copy", "Paste"])
        let second = try XCTUnwrap(link(menu, 1, "section"))
        XCTAssertEqual(g_menu_model_get_n_items(second), 1)
        XCTAssertEqual(label(second, 0), "Delete")
        XCTAssertEqual(label(menu, 2), "Send", "a Section's header")
        let send = try XCTUnwrap(link(menu, 2, "section"))
        // Inner menus hold their items in unlabeled sections too (drawn as plain items).
        XCTAssertEqual(label(try XCTUnwrap(link(send, 0, "section")), 0), "Share")
        let last = try XCTUnwrap(link(menu, 3, "section"))
        XCTAssertEqual(label(last, 0), "More")
        let submenu = try XCTUnwrap(link(last, 0, "submenu"))
        XCTAssertEqual(label(try XCTUnwrap(link(submenu, 0, "section")), 0), "Inner")
    }

    func testChoosingAnItemRunsItsButtonOnce() throws {
        let node = try render(options)
        let group = try actions(node)
        g_action_group_activate_action(group, Menu.actionName(2), nil)
        g_action_group_activate_action(group, Menu.actionName(8), nil)
        XCTAssertEqual(fired, ["test.copy", "test.share"])
        XCTAssertEqual(g_action_group_get_action_enabled(group, Menu.actionName(3)), 0, "a disabled Button's item")
        XCTAssertEqual(g_action_group_has_action(group, Menu.actionName(4)), 0, "no action for a hidden Button")
    }

    func testTheMenuIsRebuiltOnlyWhenItChanges() throws {
        let node = try render(options)
        let before = try model(node)
        Menu.update(node.widget, node)
        XCTAssertEqual(try model(node), before, "the same menu: not rebuilt")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 2, propertyName: "title", value: "Copy All")
        AdwaitaTestHost.drainMainLoop()
        let after = try model(node)
        XCTAssertNotEqual(after, before)
        let first = try XCTUnwrap(link(after, 0, "section"))
        XCTAssertEqual(label(first, 0), "Copy All")
    }

    func testChildrenInsertedIntoANestedSectionOrMenuAreShown() throws {
        let node = try render(options)
        _ = try ActionUIModel.shared.insertElement(windowUUID: windowUUID, parentID: 7,
            json: #"{"type": "Button", "id": 20, "properties": {"title": "Mail"}}"#, position: .at(0))
        _ = try ActionUIModel.shared.insertElement(windowUUID: windowUUID, parentID: 9,
            json: #"{"type": "Button", "id": 21, "properties": {"title": "Print"}}"#, position: .at(1))
        AdwaitaTestHost.drainMainLoop()
        let menu = try model(node)
        XCTAssertEqual(g_menu_model_get_n_items(menu), 4)
        guard g_menu_model_get_n_items(menu) == 4 else { return }
        let send = try XCTUnwrap(link(try XCTUnwrap(link(menu, 2, "section")), 0, "section"))
        XCTAssertEqual(g_menu_model_get_n_items(send), 2)
        guard g_menu_model_get_n_items(send) == 2 else { return }
        XCTAssertEqual([0, 1].map { label(send, $0) }, ["Mail", "Share"])
        let submenu = try XCTUnwrap(link(try XCTUnwrap(link(menu, 3, "section")), 0, "submenu"))
        let inner = try XCTUnwrap(link(submenu, 0, "section"))
        XCTAssertEqual(g_menu_model_get_n_items(inner), 2)
        guard g_menu_model_get_n_items(inner) == 2 else { return }
        XCTAssertEqual([0, 1].map { label(inner, $0) }, ["Inner", "Print"])
        let group = try actions(node)
        XCTAssertNotEqual(g_action_group_has_action(group, Menu.actionName(20)), 0)
        XCTAssertNotEqual(g_action_group_has_action(group, Menu.actionName(21)), 0)
    }

    func testAnUnderscoreInATitleIsNotAMnemonic() throws {
        let menu = try model(try render(#"""
            {"type": "Menu", "id": 1, "properties": {"title": "File_Menu"}, "children": [
              {"type": "Button", "id": 2, "properties": {"title": "my_file.txt"}},
              {"type": "Menu", "id": 3, "properties": {"title": "Open_Recent"}, "children": [
                {"type": "Button", "id": 4, "properties": {"title": "a"}}]}]}
            """#))
        XCTAssertEqual(g_menu_model_get_n_items(menu), 1)
        guard g_menu_model_get_n_items(menu) == 1 else { return }
        let section = try XCTUnwrap(link(menu, 0, "section"))
        XCTAssertEqual(g_menu_model_get_n_items(section), 2)
        guard g_menu_model_get_n_items(section) == 2 else { return }
        // Doubled: GTK shows a doubled underscore as one.
        XCTAssertEqual([0, 1].map { label(section, $0) }, ["my__file.txt", "Open__Recent"])
    }

    func testADisabledSectionOrSubmenuDisablesItsItems() throws {
        let node = try render(#"""
            {"type": "Menu", "id": 1, "properties": {"title": "Edit"}, "children": [
              {"type": "Section", "id": 2, "properties": {"header": "", "disabled": true}, "children": [
                {"type": "Button", "id": 3, "properties": {"title": "Cut"}}]},
              {"type": "Menu", "id": 4, "properties": {"title": "More", "disabled": true}, "children": [
                {"type": "Button", "id": 5, "properties": {"title": "Inner"}}]},
              {"type": "Button", "id": 6, "properties": {"title": "Copy"}}]}
            """#)
        let group = try actions(node)
        XCTAssertEqual(g_action_group_get_action_enabled(group, Menu.actionName(3)), 0, "in a disabled Section")
        XCTAssertEqual(g_action_group_get_action_enabled(group, Menu.actionName(5)), 0, "in a disabled submenu")
        XCTAssertNotEqual(g_action_group_get_action_enabled(group, Menu.actionName(6)), 0)
        let menu = try model(node)
        guard g_menu_model_get_n_items(menu) > 0 else { return XCTFail("no sections") }
        XCTAssertNil(label(menu, 0), "an empty header is none")
    }

    func testAnOpenMenuWaitsUntilClosedToRebuild() throws {
        let node = try render(options)
        // A popover needs a shown window to open in.
        let window = gtk_window_new()!
        defer { gtk_window_destroy(typed(window)) }
        gtk_window_set_child(typed(window), node.outerWidget)
        defer { gtk_window_set_child(typed(window), nil) }
        gtk_window_present(typed(window))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.widget) != 0 }))
        let button = OpaquePointer(node.widget)
        gtk_menu_button_set_active(button, 1)
        guard gtk_menu_button_get_active(button) != 0 else { throw XCTSkip("the menu cannot open in this test window") }
        let before = try model(node)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 2, propertyName: "title", value: "Copy All")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 6, propertyName: "disabled", value: true)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try model(node), before, "not rebuilt while open")
        XCTAssertEqual(g_action_group_get_action_enabled(try actions(node), Menu.actionName(6)), 0, "an item disabled at once")
        gtk_menu_button_set_active(button, 0)
        AdwaitaTestHost.drainMainLoop()
        let after = try model(node)
        XCTAssertNotEqual(after, before, "rebuilt once closed")
        let first = try XCTUnwrap(link(after, 0, "section"))
        XCTAssertEqual(label(first, 0), "Copy All")
    }

    func testAMenuDroppedBeforeItsDeferredRebuildIsKeptUntilThen() throws {
        var node: RenderNode? = try render(options)
        let window = gtk_window_new()!
        gtk_window_set_child(typed(window), node!.outerWidget)
        gtk_window_present(typed(window))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node!.widget) != 0 }))
        let button = OpaquePointer(node!.widget)
        gtk_menu_button_set_active(button, 1)
        guard gtk_menu_button_get_active(button) != 0 else {
            gtk_window_destroy(typed(window))
            throw XCTSkip("the menu cannot open in this test window")
        }
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 2, propertyName: "title", value: "Copy All")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNotNil(attached(on: node!.widget, key: menuStateKey)?.pending, "deferred while open")
        // Set to nil when the button is finalized.
        let slot = UnsafeMutablePointer<gpointer?>.allocate(capacity: 1)
        defer { slot.deallocate() }
        slot.pointee = UnsafeMutableRawPointer(node!.widget)
        g_object_add_weak_pointer(typed(OpaquePointer(node!.widget)), slot)
        // Closing schedules the rebuild; the window and the node go before it runs.
        gtk_menu_button_set_active(button, 0)
        gtk_window_set_child(typed(window), nil)
        gtk_window_destroy(typed(window))
        node = nil
        windows = []
        ActionUIModel.shared.windowModels[windowUUID] = nil
        XCTAssertNotNil(slot.pointee, "the button is kept for the scheduled rebuild")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(slot.pointee, "and released once it ran")
        if let alive = slot.pointee {
            g_object_remove_weak_pointer(typed(OpaquePointer(alive)), slot)
        }
    }

    func testALabelElementReplacesTheTitle() throws {
        let node = try render(#"""
            {"type": "Menu", "id": 1, "properties": {"title": "More"}, "label": {"type": "Image", "id": 2, "properties": {"systemName": "ellipsis.circle"}}, "children": [
              {"type": "Button", "id": 3, "properties": {"title": "Share"}}]}
            """#)
        let image = try XCTUnwrap(node.childNodes[2])
        XCTAssertEqual(gtk_menu_button_get_child(OpaquePointer(node.widget)), image.outerWidget)
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(node.widget), GTK_ACCESSIBLE_PROPERTY_LABEL), 0,
                          "still named after the title")
    }

    // MARK: Toggle, Picker and Text items

    private let settings = #"""
        {"type": "Menu", "id": 1, "properties": {"title": "View"}, "children": [
          {"type": "Toggle", "id": 2, "properties": {"title": "Wrap", "isOn": true, "actionID": "test.copy"}},
          {"type": "Picker", "id": 3, "properties": {"title": "Sort", "options": [{"title": "Name", "tag": "name"}, {"title": "Date", "tag": "date"}], "actionID": "test.share"}},
          {"type": "Text", "id": 4, "properties": {"text": "Hint"}}]}
        """#

    private func value(_ id: Int) -> Any? {
        ActionUIModel.shared.windowModels[windowUUID]?.viewModels[id]?.value
    }

    private func state(_ group: OpaquePointer, _ name: String) throws -> OpaquePointer {
        try XCTUnwrap(g_action_group_get_action_state(group, name))
    }

    private func attribute(_ model: UnsafeMutablePointer<GMenuModel>, _ index: Int32, _ name: String) -> OpaquePointer? {
        g_menu_model_get_item_attribute_value(model, index, name, nil)
    }

    func testAToggleIsACheckItemThatSetsItsValue() throws {
        let node = try render(settings)
        let group = try actions(node)
        let name = Menu.toggleActionName(2)
        var on = try state(group, name)
        XCTAssertEqual(g_variant_get_boolean(on), 1, "the check mark follows isOn")
        g_variant_unref(on)

        g_action_group_activate_action(group, name, nil)
        XCTAssertEqual(value(2) as? Bool, false, "choosing it sets the other state")
        XCTAssertEqual(fired, ["test.copy"])
        AdwaitaTestHost.drainMainLoop()
        on = try state(group, name)
        XCTAssertEqual(g_variant_get_boolean(on), 0)
        g_variant_unref(on)

        let menu = try model(node)
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 2, value: true)
        AdwaitaTestHost.drainMainLoop()
        on = try state(group, name)
        XCTAssertEqual(g_variant_get_boolean(on), 1, "a host value moves the check mark")
        g_variant_unref(on)
        XCTAssertEqual(try model(node), menu, "without rebuilding the menu")
        XCTAssertEqual(fired, ["test.copy"], "a host value fires nothing")
    }

    func testAPickerIsASubmenuOfRadioItems() throws {
        let node = try render(settings)
        let menu = try XCTUnwrap(link(try model(node), 0, "section"))
        XCTAssertEqual(label(menu, 1), "Sort")
        let choices = try XCTUnwrap(link(menu, 1, "submenu"), "the options right in the submenu")
        XCTAssertEqual([0, 1].map { label(choices, $0) }, ["Name", "Date"])
        let target = try XCTUnwrap(attribute(choices, 1, "target"))
        XCTAssertEqual(String(cString: g_variant_get_string(target, nil)), "date", "each item targets its tag")
        g_variant_unref(target)

        let group = try actions(node)
        let name = Menu.pickerActionName(3)
        var chosen = try state(group, name)
        XCTAssertEqual(String(cString: g_variant_get_string(chosen, nil)), "name", "the first option by default")
        g_variant_unref(chosen)
        g_action_group_activate_action(group, name, g_variant_new_string("date"))
        XCTAssertEqual(value(3) as? String, "date")
        XCTAssertEqual(fired, ["test.share"])
        AdwaitaTestHost.drainMainLoop()
        chosen = try state(group, name)
        XCTAssertEqual(String(cString: g_variant_get_string(chosen, nil)), "date", "the radio mark follows the value")
        g_variant_unref(chosen)
    }

    func testATextIsAnItemThatDoesNothing() throws {
        let menu = try XCTUnwrap(link(try model(try render(settings)), 0, "section"))
        XCTAssertEqual(label(menu, 2), "Hint")
        XCTAssertNil(attribute(menu, 2, "action"), "no action: GTK shows it dimmed")
    }

    func testAMarkdownTextShowsItsText() throws {
        let node = try render(#"""
            {"type": "Menu", "id": 1, "properties": {"title": "View"}, "children": [
              {"type": "Text", "id": 2, "properties": {"markdown": "Hint"}}]}
            """#)
        let menu = try XCTUnwrap(link(try model(node), 0, "section"))
        XCTAssertEqual(label(menu, 0), "Hint", "its value is an AttributedString")
    }
    func testTheBuiltMenuHoldsTheOnlyReferenceToEachPart() throws {
        let entries: [MenuEntry] = [
            .item(id: 2, title: "Copy", enabled: true),
            .divider,
            .section(header: "More", entries: [.text("Hint")]),
            .submenu(title: "Share", entries: [.item(id: 3, title: "Mail", enabled: true)]),
            .picker(id: 4, title: "Sort", enabled: true, choices: [.init(title: "Name", tag: "name")]),
        ]
        let menu = Menu.makeMenu(entries)
        let count = { (object: UnsafeMutableRawPointer) in object.assumingMemoryBound(to: GObject.self).pointee.ref_count }
        XCTAssertEqual(count(menu.pointer), 1, "the caller's reference only")
        // Each part is held by its parent alone; reading a link adds the reader's own reference,
        // so 2 here means nothing else kept one.
        let first = try XCTUnwrap(g_menu_model_get_item_link(menu.typed(), 0, "section"))
        defer { g_object_unref(first) }
        XCTAssertEqual(count(first), 2)
        let more = try XCTUnwrap(g_menu_model_get_item_link(menu.typed(), 1, "section"))
        defer { g_object_unref(more) }
        XCTAssertEqual(count(more), 2, "a Section's own menu")
        let last = try XCTUnwrap(g_menu_model_get_item_link(menu.typed(), 2, "section"))
        defer { g_object_unref(last) }
        for (index, kind) in [(Int32(0), "submenu"), (Int32(1), "picker")] {
            let submenu = try XCTUnwrap(g_menu_model_get_item_link(last, index, "submenu"), kind)
            XCTAssertEqual(count(submenu), 2, kind)
            g_object_unref(submenu)
        }
    }
}
