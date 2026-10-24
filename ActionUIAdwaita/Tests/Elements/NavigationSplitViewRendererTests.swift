// Tests/Elements/NavigationSplitViewRendererTests.swift
/*
 Tests for NavigationSplitView on GTK, in a window on screen: two columns sit in one overlay split
 view and three in two; columnVisibility shows and hides the columns and the sidebar toggle writes
 it and fires valueChangeActionID; a column takes its ideal width; a chosen sidebar child shows its
 destination in the detail, as does the host's write; a column that is a NavigationStack shows no
 header bar of its own; a column's title is its navigationTitle; the window shows no header bar.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class NavigationSplitViewRendererTests: XCTestCase {
    private var windowUUID = ""
    private var gtkWindow: UnsafeMutablePointer<GtkWindow>?
    private var renderTree: AdwaitaWindow?

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "navigation-split-view-\(name)"
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
        adw_window_set_content(typed(window), tree.contentWidget)
        gtk_window_set_default_size(window, 900, 500)
        gtk_window_present(window)
        AdwaitaTestHost.drainMainLoop()
        return try XCTUnwrap(tree.root)
    }

    private func parts(_ split: RenderNode) throws -> SplitViewParts {
        try XCTUnwrap(attached(on: split.widget, key: splitViewPartsKey))
    }

    private func content(_ column: SplitViewColumn) -> WidgetPointer? {
        adw_toolbar_view_get_content(OpaquePointer(column.toolbar))
    }

    private func setState(_ split: RenderNode, _ key: String, _ value: Any) {
        XCTAssertTrue(ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: split.element.id, key: key, value: value))
        AdwaitaTestHost.drainMainLoop()
    }

    private static let twoColumns = #"""
        {"type": "NavigationSplitView", "id": 1, "properties": {"valueChangeActionID": "test.visibility"},
         "sidebar": {"type": "List", "id": 2, "properties": {"actionID": "test.chosen", "navigationSplitViewColumnWidth": {"min": 200, "ideal": 280, "max": 400}},
            "children": [{"type": "Text", "id": 100, "properties": {"text": "A", "destinationViewId": 10}},
                         {"type": "Text", "id": 101, "properties": {"text": "B"}}]},
         "detail": {"type": "Text", "id": 3, "properties": {"text": "Pick one"}},
         "destinations": [{"type": "Text", "id": 10, "properties": {"text": "Detail A", "navigationTitle": "A"}}]}
        """#

    func testTwoColumnsSitInOneSplitViewAndTheWindowShowsNoHeaderBar() throws {
        let split = try present(Self.twoColumns)
        let parts = try parts(split)
        XCTAssertNil(parts.inner)
        XCTAssertTrue(content(parts.sidebar) == split.childNodes[2]?.outerWidget)
        XCTAssertTrue(content(parts.detail) == split.childNodes[3]?.outerWidget)
        XCTAssertTrue(try XCTUnwrap(renderTree).showsOwnHeaderBars)
        XCTAssertEqual(adw_overlay_split_view_get_min_sidebar_width(parts.outer), 280, "the ideal width")
        XCTAssertEqual(adw_overlay_split_view_get_max_sidebar_width(parts.outer), 280)
        XCTAssertEqual(adw_header_bar_get_show_title(OpaquePointer(parts.sidebar.header)), 0, "a leading column without a title shows none")
        XCTAssertNotEqual(adw_header_bar_get_show_title(OpaquePointer(parts.detail.header)), 0, "the detail shows the window's")
    }

    func testColumnVisibilityAndTheSidebarToggle() throws {
        var fired = 0
        ActionUIModel.shared.registerActionHandler(for: "test.visibility") { _, _, _, _, _ in
            MainActor.assumeIsolated { fired += 1 }
        }
        defer { ActionUIModel.shared.unregisterActionHandler(for: "test.visibility") }
        let split = try present(Self.twoColumns)
        let parts = try parts(split)
        XCTAssertNotEqual(adw_overlay_split_view_get_show_sidebar(parts.outer), 0)
        setState(split, "columnVisibility", "detail")
        XCTAssertEqual(adw_overlay_split_view_get_show_sidebar(parts.outer), 0)
        XCTAssertEqual(gtk_toggle_button_get_active(typed(parts.sidebarToggle)), 0, "the toggle follows")
        XCTAssertEqual(fired, 0, "a host's write fires nothing")

        gtk_toggle_button_set_active(typed(parts.sidebarToggle), 1)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(split.model.states["columnVisibility"] as? String, "all")
        XCTAssertNotEqual(adw_overlay_split_view_get_show_sidebar(parts.outer), 0)
        XCTAssertEqual(fired, 1)
        gtk_toggle_button_set_active(typed(parts.sidebarToggle), 0)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(split.model.states["columnVisibility"] as? String, "detail", "two columns: the detail alone")
        XCTAssertEqual(fired, 2)
    }

    func testThreeColumnsNestAndDoubleColumnHidesTheSidebar() throws {
        let split = try present(#"""
            {"type": "NavigationSplitView", "id": 1,
             "sidebar": {"type": "Text", "id": 2, "properties": {"text": "Side", "navigationTitle": "Library"}},
             "content": {"type": "Text", "id": 3, "properties": {"text": "Middle", "navigationSplitViewColumnWidth": 320}},
             "detail": {"type": "Text", "id": 4, "properties": {"text": "Detail"}}}
            """#)
        let parts = try parts(split)
        let inner = try XCTUnwrap(parts.inner)
        XCTAssertTrue(content(try XCTUnwrap(parts.content)) == split.childNodes[3]?.outerWidget)
        XCTAssertEqual(adw_overlay_split_view_get_min_sidebar_width(inner), 320, "a fixed width")
        XCTAssertEqual(swiftString(adw_window_title_get_title(OpaquePointer(parts.sidebar.title))), "Library")
        XCTAssertTrue(adw_header_bar_get_title_widget(OpaquePointer(parts.sidebar.header)) == parts.sidebar.title)

        setState(split, "columnVisibility", "doubleColumn")
        XCTAssertEqual(adw_overlay_split_view_get_show_sidebar(parts.outer), 0)
        XCTAssertNotEqual(adw_overlay_split_view_get_show_sidebar(inner), 0)
        setState(split, "columnVisibility", "detail")
        XCTAssertEqual(adw_overlay_split_view_get_show_sidebar(inner), 0)
    }

    func testTheSplitViewFillsTheWindowWithItsSidebarHidden() throws {
        // At its natural width a hidden sidebar would be laid out at width 0 (GTK warns).
        let split = try present(#"""
            {"type": "NavigationSplitView", "id": 1, "properties": {"columnVisibility": "detail"},
             "sidebar": {"type": "Text", "id": 2, "properties": {"text": "Side", "navigationTitle": "Side"}},
             "detail": {"type": "Text", "id": 3, "properties": {"text": "Detail"}}}
            """#)
        let window = try XCTUnwrap(gtkWindow)
        XCTAssertEqual(gtk_widget_get_width(split.widget), gtk_widget_get_width(typed(window)))
        XCTAssertEqual(gtk_widget_get_height(split.widget), gtk_widget_get_height(typed(window)))
    }

    func testAChosenSidebarChildShowsItsDestinationInTheDetail() throws {
        let split = try present(Self.twoColumns)
        let parts = try parts(split)
        let list = try XCTUnwrap(split.childNodes[2])
        RowSelection.commitChildSelection(100, model: list.model, actionID: "test.chosen", windowUUID: windowUUID, viewID: 2)
        NavigationSplitView.sidebarListChose(list, childID: 100)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { split.model.states["selectedDestination"] as? Int == 10 }))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertTrue(content(parts.detail) == split.childNodes[10]?.outerWidget)
        XCTAssertNil(split.childNodes[3], "the default detail left")

        // A child with no destination stores its own id, as on Apple: no such destination, the default detail.
        NavigationSplitView.sidebarListChose(list, childID: 101)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { split.model.states["selectedDestination"] as? Int == 101 }))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertTrue(content(parts.detail) == split.childNodes[3]?.outerWidget)

        setState(split, "selectedDestination", 10)
        XCTAssertTrue(content(parts.detail) == split.childNodes[10]?.outerWidget, "the host's write too")
    }

    func testAColumnThatIsANavigationStackBringsItsOwnHeaderBars() throws {
        let split = try present(#"""
            {"type": "NavigationSplitView", "id": 1,
             "sidebar": {"type": "Text", "id": 2, "properties": {"text": "Side"}},
             "detail": {"type": "NavigationStack", "id": 3, "properties": {"navigationTitle": "Inner"},
                "content": {"type": "Text", "id": 4, "properties": {"text": "Root"}}}}
            """#)
        let parts = try parts(split)
        XCTAssertFalse(Gtk.Widget(parts.detail.header).isVisible)
        let stack = try XCTUnwrap(split.childNodes[3])
        XCTAssertTrue(stack.isWindowRoot, "the stack's header bars carry the window's buttons")
        XCTAssertGreaterThan(gtk_widget_get_height(stack.widget), 300, "the stack fills its column")
    }

    func testADeselectShowsTheDefaultDetailAndASidebarNeedsNoActionID() throws {
        let split = try present(#"""
            {"type": "NavigationSplitView", "id": 1,
             "sidebar": {"type": "List", "id": 2, "children": [{"type": "Text", "id": 100, "properties": {"text": "A", "destinationViewId": 10}}]},
             "detail": {"type": "Text", "id": 3, "properties": {"text": "Pick one"}},
             "destinations": [{"type": "Text", "id": 10, "properties": {"text": "Detail A"}}]}
            """#)
        let parts = try parts(split)
        let list = try XCTUnwrap(split.childNodes[2])
        XCTAssertTrue(NavigationSplitView.isDestinationSidebar(list), "choosable without an actionID")
        NavigationSplitView.sidebarListChose(list, childID: 100)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { split.model.states["selectedDestination"] as? Int == 10 }))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertTrue(content(parts.detail) == split.childNodes[10]?.outerWidget)
        NavigationSplitView.sidebarListChose(list, childID: nil)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { split.model.states["selectedDestination"] == nil }))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertTrue(content(parts.detail) == split.childNodes[3]?.outerWidget, "a deselect shows the default detail")
    }
}
