// Tests/Runtime/ToolbarRendererTests.swift
/*
 Tests for toolbars on GTK (NodeToolbar, ScreenBar): a view's toolbar items show in its screen's
 header bar, the nearest one above it: a NavigationStack page's (the root's and a pushed one's), a
 split view column's (principal items in place of the column's title), the window's once it has
 one. The leading, principal and trailing placements; a ToolbarItemGroup's children in order; a
 changed placement moves the item; items leave the bar with their view; a navigation container's
 persistent items on every screen it shows, at the outer edge of the bar, the outer container's
 first.
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
        root.screenBar = ScreenBar(header: holder.widget)
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
        root.screenBar = ScreenBar(header: holder.widget)
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

    func testPlacementsMapToSlots() {
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
