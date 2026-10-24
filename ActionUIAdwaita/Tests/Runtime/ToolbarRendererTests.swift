// Tests/Runtime/ToolbarRendererTests.swift
/*
 Tests for toolbars on GTK (NodeToolbar, ScreenBar): a view's toolbar items show in its screen's
 header bar, the nearest one above it: a NavigationStack page's (the root's and a pushed one's), a
 split view column's (principal items in place of the column's title), the window's once it has
 one. The leading, principal and trailing placements; a ToolbarItemGroup's children in order; a
 changed placement moves the item; secondaryAction items in the screen's "more" menu, which a
 click or Return on an item closes, bottomBar items in a bar below it (trailing without one);
 items leave the bar with their view; a navigation container's persistent items on every screen it
 shows, at the outer edge of the bar, the outer container's first.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ToolbarRendererTests: XCTestCase {
    private var windowUUID = ""
    private var gtkWindow: UnsafeMutablePointer<GtkWindow>?
    private var renderTree: AdwaitaWindow?

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "toolbar-\(name)"
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
        if let gtkWindow {
            gtk_window_destroy(gtkWindow)
        }
        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        gtkWindow = window
        adw_window_set_content(typed(window), tree.contentWidget)
        gtk_window_set_default_size(window, 640, 400)
        gtk_window_present(window)
        AdwaitaTestHost.drainMainLoop()
        return try XCTUnwrap(tree.root)
    }

    /// The ids of the elements whose boxes are in `slot` of `bar`.
    private func ids(_ bar: ScreenBar?, _ slot: ScreenBar.Slot, in root: RenderNode) -> [Int] {
        guard let bar else { return [] }
        return bar.widgets(slot).compactMap { widget in Self.node(showing: widget, from: root)?.element.id }
    }

    /// The node whose box is `widget`, among `root`'s descendants and their toolbar and persistent
    /// toolbar items.
    private static func node(showing widget: WidgetPointer, from root: RenderNode) -> RenderNode? {
        if root.outerWidget == widget { return root }
        for child in root.childNodes.values {
            if let found = node(showing: widget, from: child) { return found }
        }
        return root.toolbar?.itemNode(showing: widget) ?? root.persistentToolbar?.itemNode(showing: widget)
    }

    private static func button(_ id: Int) -> String {
        #"{"type": "Button", "id": \#(id), "properties": {"title": "B\#(id)"}}"#
    }

    private static let stack = #"""
        {"type": "NavigationStack", "id": 1, "toolbar": [
            {"type": "ToolbarItem", "id": 90, "properties": {"placement": "topBarLeading"}, "content": \#(button(91))}],
         "content": {"type": "VStack", "id": 2, "properties": {"navigationTitle": "Inbox"}, "toolbar": [
            {"type": "ToolbarItem", "id": 10, "properties": {"placement": "topBarLeading"}, "content": \#(button(11))},
            {"type": "ToolbarItemGroup", "id": 12, "properties": {"placement": "topBarTrailing"}, "children": [\#(button(13)), \#(button(14))]},
            {"type": "ToolbarItem", "id": 15, "properties": {"placement": "principal"}, "content": {"type": "Text", "id": 16, "properties": {"text": "Middle"}}},
            {"type": "ToolbarItem", "id": 17, "properties": {"placement": "keyboard"}, "content": \#(button(18))}],
          "children": [{"type": "Text", "id": 3, "properties": {"text": "Body"}, "toolbar": [
            {"type": "ToolbarItem", "id": 30, "content": \#(button(31))}]}]},
         "destinations": [{"type": "Text", "id": 5, "properties": {"text": "Detail"}, "toolbar": [
            {"type": "ToolbarItem", "id": 50, "properties": {"placement": "confirmationAction"}, "content": \#(button(51))}]}]}
        """#

    func testAPagesViewsShowTheirItemsInItsHeaderBarBySlot() throws {
        let stack = try present(Self.stack)
        let content = try XCTUnwrap(stack.childNodes[2])
        let bar = try XCTUnwrap(content.screenBar)
        XCTAssertEqual(ids(bar, .leading, in: stack), [91, 11], "the stack's toolbar is its persistent toolbar, at the outer edge")
        XCTAssertEqual(ids(bar, .trailing, in: stack), [13, 14, 31], "a group's children in order, then the view below's items")
        XCTAssertEqual(ids(bar, .principal, in: stack), [16])
        let state = try XCTUnwrap(attached(on: stack.widget, key: navigationStackStateKey))
        XCTAssertTrue(adw_header_bar_get_title_widget(OpaquePointer(state.rootHeader)) == bar.principalWidget, "principal items replace the title")
    }

    func testAPushedPagesItemsShowInItsBarAndLeaveWithIt() throws {
        let stack = try present(Self.stack)
        XCTAssertTrue(ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: 1, key: "navigationPath", value: [5]))
        AdwaitaTestHost.drainMainLoop()
        let detail = try XCTUnwrap(stack.childNodes[5])
        let bar = try XCTUnwrap(detail.screenBar)
        XCTAssertEqual(ids(bar, .trailing, in: stack), [51])
        XCTAssertEqual(ids(bar, .leading, in: stack), [91], "the persistent items on every page")
        XCTAssertTrue(ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: 1, key: "navigationPath", value: [Int]()))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(bar.widgets(.trailing), [], "the screen left the tree, its items the bar")
        XCTAssertEqual(bar.widgets(.leading), [], "and its persistent items")
    }

    func testAChangedPlacementMovesTheItem() throws {
        let stack = try present(Self.stack)
        let bar = try XCTUnwrap(stack.childNodes[2]?.screenBar)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 10, propertyName: "placement", value: "primaryAction")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(ids(bar, .leading, in: stack), [91])
        XCTAssertEqual(ids(bar, .trailing, in: stack), [11, 13, 14, 31])
    }

    func testAnItemMovedToAnEarlierSlotEmptiesTheLaterOne() throws {
        let stack = try present(Self.stack)
        let bar = try XCTUnwrap(stack.childNodes[2]?.screenBar)
        let state = try XCTUnwrap(attached(on: stack.widget, key: navigationStackStateKey))
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 15, propertyName: "placement", value: "topBarLeading")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(ids(bar, .leading, in: stack), [91, 11, 16])
        XCTAssertNil(bar.principalWidget)
        XCTAssertNil(adw_header_bar_get_title_widget(OpaquePointer(state.rootHeader)), "without principal items the bar shows its title again")

        XCTAssertTrue(ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: 1, key: "navigationPath", value: [5]))
        AdwaitaTestHost.drainMainLoop()
        let detailBar = try XCTUnwrap(stack.childNodes[5]?.screenBar)
        let endBox = try XCTUnwrap(detailBar.widgets(.trailing).first.flatMap { gtk_widget_get_parent($0) })
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 50, propertyName: "placement", value: "cancellationAction")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(ids(detailBar, .leading, in: stack), [91, 51])
        XCTAssertEqual(gtk_widget_get_visible(endBox), 0, "an empty slot takes no room")
    }

    func testATemplateRowsItemsShowTheRowsData() throws {
        let stack = try present(#"""
            {"type": "NavigationStack", "id": 1, "content": {"type": "List", "id": 2, "template": {"type": "HStack", "toolbar": [
                {"type": "ToolbarItem", "content": {"type": "Button", "properties": {"title": "$1"}}}]}}}
            """#)
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 2, rows: [["Apple"]])
        AdwaitaTestHost.drainMainLoop()
        let list = try XCTUnwrap(stack.childNodes[2])
        let row = try XCTUnwrap(attached(on: list.widget, key: listStateKey)?.rowNodes.first)
        let item = try XCTUnwrap(row.toolbar?.nodes.first)
        XCTAssertEqual(item.model.templateContext?.rowIndex, 0, "a template row's item is a blueprint too, as its children are")
        XCTAssertEqual(swiftString(gtk_button_get_label(typed(item.widget))), "Apple")
    }

    func testTheItemsInheritTheDeclaringViewsEnvironment() throws {
        let stack = try present(Self.stack)
        let content = try XCTUnwrap(stack.childNodes[2])
        let edit = try XCTUnwrap(content.toolbar?.nodes.first { $0.element.id == 11 })
        XCTAssertNil(edit.environment.buttonStyle)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 2, propertyName: "buttonStyle", value: "borderless")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(edit.environment.buttonStyle, .borderless, "a changed environment reaches the toolbar items")
    }

    func testTheWindowsBarShowsTheDocumentsToolbarOnceItHasOne() throws {
        let root = try present(#"{"type": "VStack", "id": 1, "toolbar": [{"type": "ToolbarItem", "id": 10, "content": \#(Self.button(11))}]}"#)
        let header = adw_header_bar_new()!
        let holder = OwnedObject(retaining: header)
        root.screenBar = ScreenBar(header: holder.widget, toolbarView: nil)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(ids(root.screenBar, .trailing, in: root), [11])
        let shown = try XCTUnwrap(root.screenBar?.widgets(.trailing).first)
        root.screenBar = nil
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(gtk_widget_get_parent(shown), "a bar that goes takes its items out")
    }

    func testABarAttachedLaterReachesToolbarsInTemplateRows() throws {
        let root = try present(#"""
            {"type": "VStack", "id": 1, "children": [{"type": "List", "id": 2, "template": {"type": "Text", "id": 3,
              "properties": {"text": "$1"}, "toolbar": [{"type": "ToolbarItem", "id": 10, "content": \#(Self.button(11))}]}}]}
            """#)
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 2, rows: [["Apple"]])
        AdwaitaTestHost.drainMainLoop()
        let holder = OwnedObject(retaining: adw_header_bar_new()!)
        root.screenBar = ScreenBar(header: holder.widget, toolbarView: nil)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(root.screenBar?.widgets(.trailing).count, 1, "the row's toolbar found the bar set after its first sync")
    }

    func testASplitViewColumnsPrincipalItemsTakeItsTitlesPlace() throws {
        let split = try present(#"""
            {"type": "NavigationSplitView", "id": 1,
             "sidebar": {"type": "VStack", "id": 2, "properties": {"navigationTitle": "Side"}},
             "detail": {"type": "VStack", "id": 3, "toolbar": [
                {"type": "ToolbarItem", "id": 10, "properties": {"placement": "principal"}, "content": {"type": "Text", "id": 11, "properties": {"text": "Middle"}}},
                {"type": "ToolbarItem", "id": 12, "content": \#(Self.button(13))}]}}
            """#)
        let parts = try XCTUnwrap(attached(on: split.widget, key: splitViewPartsKey))
        let bar = try XCTUnwrap(split.childNodes[3]?.screenBar)
        XCTAssertEqual(ids(bar, .trailing, in: split), [13])
        XCTAssertTrue(adw_header_bar_get_title_widget(OpaquePointer(parts.detail.header)) == bar.principalWidget)
        XCTAssertNotNil(bar.principalWidget)
        XCTAssertTrue(adw_header_bar_get_title_widget(OpaquePointer(parts.sidebar.header)) == parts.sidebar.title, "the sidebar keeps its title")
    }

    func testTrailingPersistentItemsFollowTheScreensOwn() throws {
        let stack = try present(#"""
            {"type": "NavigationStack", "id": 1, "persistentToolbar": [{"type": "ToolbarItem", "id": 90, "content": \#(Self.button(91))}],
             "content": {"type": "VStack", "id": 2, "toolbar": [{"type": "ToolbarItem", "id": 10, "content": \#(Self.button(11))}]}}
            """#)
        XCTAssertEqual(ids(stack.childNodes[2]?.screenBar, .trailing, in: stack), [11, 91])
    }

    func testASplitViewsPersistentItemsShowOnTheDetailOrOnItsStacksPages() throws {
        let plain = try present(#"""
            {"type": "NavigationSplitView", "id": 1, "persistentToolbar": [{"type": "ToolbarItem", "id": 90, "content": \#(Self.button(91))}],
             "sidebar": {"type": "VStack", "id": 2}, "detail": {"type": "VStack", "id": 3}}
            """#)
        XCTAssertEqual(ids(plain.childNodes[3]?.screenBar, .trailing, in: plain), [91])
        XCTAssertEqual(try XCTUnwrap(plain.childNodes[2]?.screenBar).widgets(.trailing), [], "not on the sidebar")
        renderTree?.detach()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let split = try present(#"""
            {"type": "NavigationSplitView", "id": 1, "persistentToolbar": [{"type": "ToolbarItem", "id": 90, "content": \#(Self.button(91))}],
             "sidebar": {"type": "VStack", "id": 2},
             "detail": {"type": "NavigationStack", "id": 4, "persistentToolbar": [{"type": "ToolbarItem", "id": 80, "content": \#(Self.button(81))}],
               "content": {"type": "VStack", "id": 5}}}
            """#)
        let stack = try XCTUnwrap(split.childNodes[4])
        XCTAssertEqual(ids(stack.childNodes[5]?.screenBar, .trailing, in: split), [91, 81], "the split view's, then the stack's own, as on Apple")
    }

    func testSecondaryActionsShareTheScreensMoreMenu() throws {
        let stack = try present(#"""
            {"type": "NavigationStack", "id": 1, "persistentToolbar": [
                {"type": "ToolbarItem", "id": 90, "properties": {"placement": "secondaryAction"}, "content": \#(Self.button(91))}],
             "content": {"type": "VStack", "id": 2, "toolbar": [
                {"type": "ToolbarItem", "id": 10, "properties": {"placement": "secondaryAction"}, "content": \#(Self.button(11))},
                {"type": "ToolbarItem", "id": 12, "content": \#(Self.button(13))}]}}
            """#)
        let bar = try XCTUnwrap(stack.childNodes[2]?.screenBar)
        XCTAssertEqual(ids(bar, .overflow, in: stack), [11, 91], "one menu, the screen's items, then the persistent ones")
        XCTAssertEqual(ids(bar, .trailing, in: stack), [13])
        XCTAssertTrue(Gtk.Widget(bar.overflowButton).isVisible)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 10, propertyName: "placement", value: "automatic")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 90, propertyName: "placement", value: "automatic")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertFalse(Gtk.Widget(bar.overflowButton).isVisible, "no menu without secondary actions")
    }

    func testAClickInTheMoreMenuClosesIt() throws {
        let stack = try present(#"""
            {"type": "NavigationStack", "id": 1, "content": {"type": "VStack", "id": 2, "toolbar": [
                {"type": "ToolbarItem", "id": 10, "properties": {"placement": "secondaryAction"}, "content": \#(Self.button(11))}]}}
            """#)
        let bar = try XCTUnwrap(stack.childNodes[2]?.screenBar)
        let popover = try XCTUnwrap(gtk_menu_button_get_popover(OpaquePointer(bar.overflowButton)))
        let menu = try XCTUnwrap(gtk_popover_get_child(popover))
        gtk_menu_button_popup(OpaquePointer(bar.overflowButton))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_visible(typed(popover)) != 0 }))
        try Self.releaseClick(in: menu)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_visible(typed(popover)) == 0 }), "a click on an item closes the menu")
    }

    func testReturnOnAnItemInTheMoreMenuClosesIt() throws {
        let stack = try present(#"""
            {"type": "NavigationStack", "id": 1, "content": {"type": "VStack", "id": 2, "toolbar": [
                {"type": "ToolbarItem", "id": 10, "properties": {"placement": "secondaryAction"}, "content": \#(Self.button(11))}]}}
            """#)
        let bar = try XCTUnwrap(stack.childNodes[2]?.screenBar)
        let popover = try XCTUnwrap(gtk_menu_button_get_popover(OpaquePointer(bar.overflowButton)))
        let menu = try XCTUnwrap(gtk_popover_get_child(popover))
        gtk_menu_button_popup(OpaquePointer(bar.overflowButton))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_visible(typed(popover)) != 0 }))
        let keys = try XCTUnwrap(Self.controller(of: menu, type: gtk_event_controller_key_get_type()))
        var handled = GValue()
        g_value_init(&handled, g_type_from_name("gboolean"))
        var values = [GValue](repeating: GValue(), count: 4)
        g_value_init(&values[0], gtk_event_controller_key_get_type())
        g_value_set_object(&values[0], keys)
        g_value_init(&values[1], g_type_from_name("guint"))
        g_value_set_uint(&values[1], guint(GDK_KEY_Return))
        g_value_init(&values[2], g_type_from_name("guint"))
        g_value_init(&values[3], gdk_modifier_type_get_type())
        g_signal_emitv(&values, g_signal_lookup("key-pressed", gtk_event_controller_key_get_type()), 0, &handled)
        for index in values.indices { g_value_unset(&values[index]) }
        g_value_unset(&handled)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_visible(typed(popover)) == 0 }), "Return on an item closes the menu")
    }

    /// The first event controller of `type` on `widget`.
    private static func controller(of widget: WidgetPointer, type: GType) -> UnsafeMutableRawPointer? {
        let controllers = gtk_widget_observe_controllers(widget)!
        defer { g_object_unref(UnsafeMutableRawPointer(controllers)) }
        for index in 0..<g_list_model_get_n_items(controllers) {
            guard let item = g_list_model_get_item(controllers, index) else { continue }
            g_object_unref(item)
            if g_type_check_instance_is_a(item.assumingMemoryBound(to: GTypeInstance.self), type) != 0 {
                return item
            }
        }
        return nil
    }

    /// As a click's release in the "more" menu `menu`: its capture-phase click gesture's "released".
    private static func releaseClick(in menu: WidgetPointer) throws {
        let controllers = gtk_widget_observe_controllers(menu)!
        defer { g_object_unref(UnsafeMutableRawPointer(controllers)) }
        var gesture: UnsafeMutableRawPointer?
        for index in 0..<g_list_model_get_n_items(controllers) {
            guard let item = g_list_model_get_item(controllers, index) else { continue }
            g_object_unref(item)
            if g_type_check_instance_is_a(item.assumingMemoryBound(to: GTypeInstance.self), gtk_gesture_click_get_type()) != 0 {
                gesture = item
            }
        }
        var values = [GValue(), GValue(), GValue(), GValue()]
        g_value_init(&values[0], gtk_gesture_click_get_type())
        g_value_set_object(&values[0], try XCTUnwrap(gesture))
        g_value_init(&values[1], g_type_from_name("gint"))
        g_value_set_int(&values[1], 1)
        g_value_init(&values[2], g_type_from_name("gdouble"))
        g_value_init(&values[3], g_type_from_name("gdouble"))
        g_signal_emitv(&values, g_signal_lookup("released", gtk_gesture_click_get_type()), 0, nil)
        for index in values.indices { g_value_unset(&values[index]) }
    }

    /// The first descendant of `widget` of type `type`, depth first.
    private static func descendant(of widget: WidgetPointer, type: GType) -> WidgetPointer? {
        for child in Array(Gtk.Widget(widget).children) {
            if g_type_check_instance_is_a(UnsafeMutableRawPointer(child.pointer).assumingMemoryBound(to: GTypeInstance.self), type) != 0 {
                return child.pointer
            }
            if let found = descendant(of: child.pointer, type: type) { return found }
        }
        return nil
    }

    func testAMenuInTheMoreMenuOpensItsOwnMenu() throws {
        let stack = try present(#"""
            {"type": "NavigationStack", "id": 1, "content": {"type": "VStack", "id": 2, "toolbar": [
                {"type": "ToolbarItem", "id": 10, "properties": {"placement": "secondaryAction"}, "content":
                    {"type": "Menu", "id": 20, "properties": {"title": "Sort"}, "children": [\#(Self.button(21))]}}]}}
            """#)
        let bar = try XCTUnwrap(stack.childNodes[2]?.screenBar)
        let popover = try XCTUnwrap(gtk_menu_button_get_popover(OpaquePointer(bar.overflowButton)))
        let menu = try XCTUnwrap(gtk_popover_get_child(popover))
        gtk_menu_button_popup(OpaquePointer(bar.overflowButton))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_visible(typed(popover)) != 0 }))
        let nested = try XCTUnwrap(Self.descendant(of: menu, type: gtk_menu_button_get_type()))
        let nestedPopover = try XCTUnwrap(gtk_menu_button_get_popover(OpaquePointer(nested)))
        // A click on the Menu: the "more" menu's gesture sees the release first (capture phase, from
        // the outside in), then the Menu's button opens its own menu.
        try Self.releaseClick(in: menu)
        gtk_menu_button_popup(OpaquePointer(nested))
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: 200)
        XCTAssertNotEqual(gtk_widget_get_mapped(typed(nestedPopover)), 0, "the Menu's own menu stays open")
        XCTAssertNotEqual(gtk_widget_get_visible(typed(popover)), 0)
    }

    func testBottomBarItemsGoBelowTheScreenOrTrailWithoutABottomBar() throws {
        let stack = try present(#"""
            {"type": "NavigationStack", "id": 1, "content": {"type": "VStack", "id": 2, "toolbar": [
                {"type": "ToolbarItemGroup", "id": 10, "properties": {"placement": "bottomBar"}, "children": [\#(Self.button(11)), \#(Self.button(12))]}]}}
            """#)
        let bar = try XCTUnwrap(stack.childNodes[2]?.screenBar)
        XCTAssertEqual(ids(bar, .bottom, in: stack), [11, 12])
        XCTAssertTrue(Gtk.Widget(try XCTUnwrap(bar.bottomBar)).isVisible)
        XCTAssertEqual(ids(bar, .trailing, in: stack), [])
        let header = OwnedObject(retaining: adw_header_bar_new()!)
        stack.childNodes[2]?.screenBar = ScreenBar(header: header.widget, toolbarView: nil)
        AdwaitaTestHost.drainMainLoop()
        let plain = try XCTUnwrap(stack.childNodes[2]?.screenBar)
        XCTAssertNil(plain.bottomBar)
        XCTAssertEqual(ids(plain, .trailing, in: stack), [11, 12], "no bottom bar: they trail")
    }

    func testASearchableViewsFieldIsInItsScreensBarAndFiresEachQuery() throws {
        var queries: [String] = []
        ActionUIModel.shared.registerActionHandler(for: "test.search") { _, _, _, _, context in
            MainActor.assumeIsolated { queries.append(context as? String ?? "?") }
        }
        defer { ActionUIModel.shared.unregisterActionHandler(for: "test.search") }
        let stack = try present(#"""
            {"type": "NavigationStack", "id": 1, "content": {"type": "VStack", "id": 2, "children": [
                {"type": "List", "id": 3, "properties": {"searchable": {"prompt": "Find", "actionID": "test.search"}}}]}}
            """#)
        AdwaitaTestHost.drainMainLoop()
        let list = try XCTUnwrap(stack.childNodes[2]?.childNodes[3])
        let entry = try XCTUnwrap(list.toolbar?.searchWidget)
        let bar = try XCTUnwrap(stack.childNodes[2]?.screenBar)
        XCTAssertEqual(bar.widgets(.search), [entry], "in the page's bar")
        XCTAssertTrue(Gtk.Widget(try XCTUnwrap(gtk_widget_get_parent(entry))).isVisible, "its slot is shown")
        XCTAssertEqual(swiftString(gtk_search_entry_get_placeholder_text(OpaquePointer(entry))), "Find")
        XCTAssertEqual(queries, [], "nothing fires before the user types")
        gtk_editable_set_text(OpaquePointer(entry), "ad")
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { queries == ["ad"] }), "the query as the context: \(queries)")
        gtk_editable_set_text(OpaquePointer(entry), "")
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { queries == ["ad", ""] }), "a cleared query fires too: \(queries)")
        gtk_editable_set_text(OpaquePointer(entry), "al")
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { queries.last == "al" }))
        AdwaitaTestHost.emit("stop-search", on: UnsafeMutableRawPointer(entry))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { queries == ["ad", "", "al", ""] }), "Escape clears the field: \(queries)")
        XCTAssertEqual(Gtk.Editable(entry).text, "")
    }

    func testASearchFieldWithoutAPromptSaysSearch() throws {
        let stack = try present(#"""
            {"type": "NavigationStack", "id": 1, "content": {"type": "List", "id": 2, "properties": {"searchable": {"actionID": "test.search"}}}}
            """#)
        let entry = try XCTUnwrap(stack.childNodes[2]?.toolbar?.searchWidget)
        XCTAssertEqual(swiftString(gtk_search_entry_get_placeholder_text(OpaquePointer(entry))), "Search", "as macOS's field")
    }

    func testABarWithoutASearchFieldShowsNoEmptySearchSlot() throws {
        let stack = try present(#"""
            {"type": "NavigationStack", "id": 1, "content": {"type": "VStack", "id": 2, "children": [{"type": "Text", "id": 3, "properties": {"text": "x"}}]}}
            """#)
        let bar = try XCTUnwrap(stack.childNodes[2]?.screenBar)
        // The slots packed at the end of the header bar, beside the menu button and the window controls.
        let end = try XCTUnwrap(gtk_widget_get_parent(bar.overflowButton))
        let emptyShown = Gtk.Widget(end).children.filter { $0.isVisible && $0.firstChild == nil }
        XCTAssertEqual(emptyShown.count, 0, "an empty slot takes no room")
    }

    func testPlacementsMapToSlots() {
        XCTAssertEqual(NodeToolbar.slot("secondaryAction"), .overflow)
        XCTAssertEqual(NodeToolbar.slot("bottomBar"), .bottom)
        XCTAssertEqual(NodeToolbar.slot("topBarLeading"), .leading)
        XCTAssertEqual(NodeToolbar.slot("cancellationAction"), .leading)
        XCTAssertEqual(NodeToolbar.slot("navigation"), .leading)
        XCTAssertEqual(NodeToolbar.slot("principal"), .principal)
        XCTAssertEqual(NodeToolbar.slot("automatic"), .trailing)
        XCTAssertEqual(NodeToolbar.slot("primaryAction"), .trailing)
        XCTAssertEqual(NodeToolbar.slot("confirmationAction"), .trailing)
        XCTAssertEqual(NodeToolbar.slot("nonsense"), .trailing)
        XCTAssertNil(NodeToolbar.slot("keyboard"))
    }
}
