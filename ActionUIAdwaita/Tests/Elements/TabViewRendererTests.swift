// Tests/Elements/TabViewRendererTests.swift
/*
 Tests for TabView on GTK: each Tab's content is a page of an AdwViewStack under a switcher, its
 title, symbol and badge on the switcher's button; tabs with no symbol at all get a titles-only
 switcher, and gaining or losing one swaps the kind in place; the selection property and the value
 pick the page, a host's write switches it; the user's choice stores the index and fires actionID
 with it; a changed list of tabs rebuilds the pages.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class TabViewRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "tab-view-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func parts(_ node: RenderNode) throws -> TabViewParts {
        try XCTUnwrap(attached(on: node.widget, key: tabViewPartsKey))
    }

    private func visible(_ parts: TabViewParts) -> String? {
        swiftString(adw_view_stack_get_visible_child_name(parts.stack))
    }

    private static let json = #"""
        {"type": "TabView", "id": 1, "properties": {"selection": 1, "actionID": "test.tab"}, "children": [
            {"type": "Tab", "id": 2, "properties": {"title": "Home", "systemImage": "house.fill"},
             "content": {"type": "Text", "id": 20, "properties": {"text": "Home page"}}},
            {"type": "Tab", "id": 3, "properties": {"title": "Settings", "systemImage": "gear", "badge": 3},
             "content": {"type": "Text", "id": 30, "properties": {"text": "Settings page"}}},
            {"type": "Tab", "id": 4, "properties": {"title": "News", "badge": "!"},
             "content": {"type": "Text", "id": 40, "properties": {"text": "News page"}}}
        ]}
        """#

    func testEachTabIsAPageWithItsTitleSymbolAndBadge() throws {
        let node = try render(Self.json)
        let parts = try parts(node)
        XCTAssertEqual(parts.contentIDs, [20, 30, 40])
        let home = try XCTUnwrap(parts.pages[20])
        XCTAssertEqual(swiftString(adw_view_stack_page_get_title(home)), "Home")
        XCTAssertEqual(swiftString(adw_view_stack_page_get_icon_name(home)), SymbolNames.iconName("house.fill"))
        XCTAssertTrue(adw_view_stack_page_get_child(home) == node.childNodes[20]?.outerWidget)
        XCTAssertEqual(adw_view_stack_page_get_badge_number(try XCTUnwrap(parts.pages[30])), 3)
        let news = try XCTUnwrap(parts.pages[40])
        XCTAssertNotEqual(adw_view_stack_page_get_needs_attention(news), 0, "a text badge needs attention")
        XCTAssertEqual(swiftString(adw_view_stack_page_get_icon_name(news)), SymbolNames.iconName("questionmark"), "no symbol: a question mark")
    }

    private static let titlesOnly = #"""
        {"type": "TabView", "id": 1, "children": [
            {"type": "Tab", "id": 2, "properties": {"title": "Name"},
             "content": {"type": "Text", "id": 20, "properties": {"text": "Name page"}}},
            {"type": "Tab", "id": 3, "properties": {"title": "Content"},
             "content": {"type": "Text", "id": 30, "properties": {"text": "Content page"}}}
        ]}
        """#

    private func isA(_ widget: WidgetPointer, _ type: GType) -> Bool {
        g_type_check_instance_is_a(UnsafeMutablePointer<GTypeInstance>(OpaquePointer(widget)), type) != 0
    }

    private func children(of widget: WidgetPointer) -> [WidgetPointer] {
        var result: [WidgetPointer] = []
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            result.append(current)
            child = gtk_widget_get_next_sibling(current)
        }
        return result
    }

    func testTabsWithASymbolGetTheSymbolSwitcher() throws {
        let parts = try parts(render(Self.json))
        XCTAssertTrue(parts.showsSymbols)
        XCTAssertTrue(isA(parts.switcher, adw_view_switcher_get_type()))
    }

    func testTitleOnlyTabsGetATitlesSwitcherAsOnMacOS() throws {
        let parts = try parts(render(Self.titlesOnly))
        XCTAssertFalse(parts.showsSymbols)
        XCTAssertTrue(isA(parts.switcher, adw_inline_view_switcher_get_type()))
        XCTAssertEqual(adw_inline_view_switcher_get_display_mode(OpaquePointer(parts.switcher)), ADW_INLINE_VIEW_SWITCHER_LABELS)
        XCTAssertNotEqual(adw_inline_view_switcher_get_can_shrink(OpaquePointer(parts.switcher)), 0)
        XCTAssertTrue(adw_inline_view_switcher_get_stack(OpaquePointer(parts.switcher)) == parts.stack)
    }

    func testASymbolGainedOrLostSwapsTheSwitcherInPlace() throws {
        let node = try render(Self.titlesOnly)
        let parts = try parts(node)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 3, propertyName: "systemImage", value: "gear")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertTrue(parts.showsSymbols)
        XCTAssertTrue(isA(parts.switcher, adw_view_switcher_get_type()))
        XCTAssertTrue(adw_view_switcher_get_stack(OpaquePointer(parts.switcher)) == parts.stack)
        XCTAssertEqual(children(of: parts.box).count, 2, "the old switcher is gone")
        XCTAssertTrue(children(of: parts.box).first == parts.switcher, "above the pages")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 3, propertyName: "systemImage", value: "")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertFalse(parts.showsSymbols)
        XCTAssertTrue(isA(parts.switcher, adw_inline_view_switcher_get_type()))
        XCTAssertEqual(children(of: parts.box).count, 2)
        XCTAssertTrue(children(of: parts.box).first == parts.switcher)
    }

    func testTheSelectionPicksThePageAndAHostsWriteSwitchesIt() throws {
        let node = try render(Self.json)
        let parts = try parts(node)
        XCTAssertEqual(visible(parts), TabView.pageName(1), "the selection property")
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: 2)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(visible(parts), TabView.pageName(2))
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: 9)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(visible(parts), TabView.pageName(0), "out of range: the first")
    }

    func testTheUsersChoiceStoresTheIndexAndFiresTheAction() throws {
        var fired: [Int] = []
        ActionUIModel.shared.registerActionHandler(for: "test.tab") { _, _, _, _, context in
            MainActor.assumeIsolated { fired.append(context as? Int ?? -1) }
        }
        defer { ActionUIModel.shared.unregisterActionHandler(for: "test.tab") }
        let node = try render(Self.json)
        let parts = try parts(node)
        // As the switcher's button does.
        adw_view_stack_set_visible_child_name(parts.stack, TabView.pageName(0))
        XCTAssertEqual(node.model.value as? Int, 0)
        XCTAssertEqual(fired, [0])
    }

    func testATabsChangedPropertiesRelabelItsButton() throws {
        let node = try render(Self.json)
        let settings = try XCTUnwrap(parts(node).pages[30])
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 3, propertyName: "title", value: "Prefs")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 3, propertyName: "systemImage", value: "star")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 3, propertyName: "badge", value: "new")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(swiftString(adw_view_stack_page_get_title(settings)), "Prefs")
        XCTAssertEqual(swiftString(adw_view_stack_page_get_icon_name(settings)), SymbolNames.iconName("star"))
        XCTAssertEqual(adw_view_stack_page_get_badge_number(settings), 0)
        XCTAssertNotEqual(adw_view_stack_page_get_needs_attention(settings), 0)
    }

    func testATabInsertedAtRunTimeKeepsTheIndexAndFiresNothing() throws {
        var fired: [Int] = []
        ActionUIModel.shared.registerActionHandler(for: "test.tab") { _, _, _, _, context in
            MainActor.assumeIsolated { fired.append(context as? Int ?? -1) }
        }
        defer { ActionUIModel.shared.unregisterActionHandler(for: "test.tab") }
        let node = try render(Self.json)
        let parts = try parts(node)
        _ = try ActionUIModel.shared.insertElement(windowUUID: windowUUID, parentID: 1, json: #"""
            {"type": "Tab", "id": 5, "properties": {"title": "New"},
             "content": {"type": "Text", "id": 50, "properties": {"text": "New page"}}}
            """#, position: .at(0))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(parts.contentIDs, [50, 20, 30, 40])
        // The index stays, as SwiftUI's selection does: the tab now at 1 shows.
        XCTAssertEqual(visible(parts), TabView.pageName(1))
        XCTAssertTrue(adw_view_stack_get_visible_child(parts.stack) == node.childNodes[20]?.outerWidget)
        XCTAssertEqual(fired, [], "the rebuild is no user's choice")
    }

    func testAChangedListOfTabsRebuildsThePages() throws {
        let node = try render(Self.json)
        let parts = try parts(node)
        XCTAssertNoThrow(try ActionUIModel.shared.removeElement(windowUUID: windowUUID, viewID: 2))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(parts.contentIDs, [30, 40])
        XCTAssertEqual(swiftString(adw_view_stack_page_get_name(try XCTUnwrap(parts.pages[30]))), TabView.pageName(0))
        XCTAssertNil(node.childNodes[20])
    }
}
