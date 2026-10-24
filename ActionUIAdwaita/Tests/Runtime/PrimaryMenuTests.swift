// Tests/Runtime/PrimaryMenuTests.swift
/*
 Tests for where the primary menu (AppCommands) goes in a window whose document brings its own
 header bars (RenderNode.showsPrimaryMenu): a NavigationStack's root page shows it, not its pushed
 pages; a NavigationSplitView's sidebar shows it, or passes it to a sidebar that is a
 NavigationStack, and the detail only while the sidebar is hidden; nothing shows it unless the
 window's document asks.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class PrimaryMenuTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "primary-menu-\(name)"
    }

    override func tearDown() async throws {
        for window in windows { window.detach() }
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

    func testAPlainDetailShowsTheMenuWhileTheSidebarIsHidden() throws {
        let split = try render(#"""
            {"type": "NavigationSplitView", "id": 1, "sidebar": {"type": "Text", "id": 2, "properties": {"text": "s"}},
             "detail": {"type": "Text", "id": 3, "properties": {"text": "d"}}}
            """#)
        split.showsPrimaryMenu = true
        AdwaitaTestHost.drainMainLoop()
        let parts = try XCTUnwrap(attached(on: split.widget, key: splitViewPartsKey))
        XCTAssertTrue(Gtk.Widget(parts.primaryMenu).isVisible)
        XCTAssertFalse(Gtk.Widget(parts.detailMenu).isVisible)
        XCTAssertTrue(ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: 1, key: "columnVisibility", value: "detail"))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertFalse(Gtk.Widget(parts.primaryMenu).isVisible)
        XCTAssertTrue(Gtk.Widget(parts.detailMenu).isVisible, "on the detail while the sidebar is hidden")
    }

    func testAStacksRootPageShowsTheMenuWhenTheWindowAsks() throws {
        let stack = try render(#"{"type": "NavigationStack", "id": 1, "content": {"type": "Text", "id": 2, "properties": {"text": "x"}}}"#)
        let state = try XCTUnwrap(attached(on: stack.widget, key: navigationStackStateKey))
        XCTAssertFalse(Gtk.Widget(state.primaryMenu).isVisible, "not unless the window asks")
        stack.showsPrimaryMenu = true
        AdwaitaTestHost.drainMainLoop()
        XCTAssertTrue(Gtk.Widget(state.primaryMenu).isVisible)
        XCTAssertTrue(gtk_widget_get_parent(state.primaryMenu).map { gtk_widget_is_ancestor($0, state.rootHeader) != 0 } ?? false,
                      "in the root page's header bar")
    }

    func testASplitViewsSidebarShowsTheMenuOrPassesItToItsStack() throws {
        let plain = try render(#"""
            {"type": "NavigationSplitView", "id": 1, "sidebar": {"type": "Text", "id": 2, "properties": {"text": "s"}},
             "detail": {"type": "NavigationStack", "id": 3, "content": {"type": "Text", "id": 4, "properties": {"text": "d"}}}}
            """#)
        plain.showsPrimaryMenu = true
        AdwaitaTestHost.drainMainLoop()
        let parts = try XCTUnwrap(attached(on: plain.widget, key: splitViewPartsKey))
        XCTAssertTrue(Gtk.Widget(parts.primaryMenu).isVisible, "in the sidebar's header bar")
        let detailStack = try XCTUnwrap(plain.childNodes[3])
        XCTAssertFalse(detailStack.showsPrimaryMenu, "not in the detail while the sidebar shows")
        XCTAssertFalse(Gtk.Widget(try XCTUnwrap(attached(on: detailStack.widget, key: navigationStackStateKey)).primaryMenu).isVisible)
        // The sidebar hidden: the detail stack carries the menu, so it stays within reach.
        XCTAssertTrue(ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: 1, key: "columnVisibility", value: "detail"))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertFalse(Gtk.Widget(parts.primaryMenu).isVisible)
        XCTAssertTrue(detailStack.showsPrimaryMenu)
        XCTAssertTrue(Gtk.Widget(try XCTUnwrap(attached(on: detailStack.widget, key: navigationStackStateKey)).primaryMenu).isVisible)
        windows.forEach { $0.detach() }
        windows = []
        ActionUIModel.shared.windowModels[windowUUID] = nil

        let nested = try render(#"""
            {"type": "NavigationSplitView", "id": 1, "sidebar": {"type": "NavigationStack", "id": 2, "content": {"type": "Text", "id": 5, "properties": {"text": "s"}}},
             "detail": {"type": "Text", "id": 3, "properties": {"text": "d"}}}
            """#)
        nested.showsPrimaryMenu = true
        AdwaitaTestHost.drainMainLoop()
        let nestedParts = try XCTUnwrap(attached(on: nested.widget, key: splitViewPartsKey))
        XCTAssertFalse(Gtk.Widget(nestedParts.primaryMenu).isVisible, "the sidebar stack brings its own bars")
        let sidebarStack = try XCTUnwrap(nested.childNodes[2])
        XCTAssertTrue(sidebarStack.showsPrimaryMenu)
        let state = try XCTUnwrap(attached(on: sidebarStack.widget, key: navigationStackStateKey))
        XCTAssertTrue(Gtk.Widget(state.primaryMenu).isVisible, "on the sidebar stack's root page")
    }
}
