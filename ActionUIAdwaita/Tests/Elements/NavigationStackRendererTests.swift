// Tests/Elements/NavigationStackRendererTests.swift
/*
 Tests for NavigationStack and NavigationLink on GTK, in a window on screen: the content is the
 root page, titled by its navigationTitle, else the stack's; writing navigationPath pushes the
 destinations and pops back; a link with destinationViewId adds to the path and one with an inline
 destination pushes it outside the path; the user's back shortens the path; a selectable List
 pushes the chosen child's destination and backing out (or the host's path) clears its selection;
 a second click before the push shows pushes nothing more; an empty title counts as none; the
 header bars carry the window's buttons only on the window's own stack, which shows no window
 header bar.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class NavigationStackRendererTests: XCTestCase {
    private var windowUUID = ""
    private var gtkWindow: UnsafeMutablePointer<GtkWindow>?
    private var renderTree: AdwaitaWindow?

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "navigation-stack-\(name)"
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

    /// `json` in a window on screen; `nested` puts it in a VStack, so the stack is not the window's root.
    private func present(_ json: String, nested: Bool = false) throws -> RenderNode {
        let document = nested ? #"{"type": "VStack", "id": 900, "children": [\#(json)]}"# : json
        _ = try ActionUIModel.shared.loadDescription(from: Data(document.utf8), format: "json", windowUUID: windowUUID)
        let tree = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        renderTree = tree
        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        gtkWindow = window
        adw_window_set_content(typed(window), tree.contentWidget)
        gtk_window_set_default_size(window, 480, 360)
        gtk_window_present(window)
        AdwaitaTestHost.drainMainLoop()
        let root = try XCTUnwrap(tree.root)
        return nested ? try XCTUnwrap(root.childNodes.values.first) : root
    }

    private func state(_ stack: RenderNode) throws -> NavigationStackState {
        try XCTUnwrap(attached(on: stack.widget, key: navigationStackStateKey))
    }

    /// The titles of the pages in the stack, root first.
    private func titles(_ stack: RenderNode) throws -> [String] {
        NavigationStack.currentPages(try state(stack).view).map { swiftString(adw_navigation_page_get_title($0)) ?? "" }
    }

    private func path(_ stack: RenderNode) -> [Int] {
        stack.model.states["navigationPath"] as? [Int] ?? []
    }

    private func setPath(_ stack: RenderNode, _ path: [Int]) {
        XCTAssertTrue(ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: stack.element.id, key: "navigationPath", value: path))
        AdwaitaTestHost.drainMainLoop()
    }

    private func wait(_ condition: () -> Bool) -> Bool {
        AdwaitaTestHost.runMainLoop(until: condition, timeoutMilliseconds: 3000)
    }

    private static let destinations = #"""
        {"type": "NavigationStack", "id": 1, "properties": {"navigationTitle": "Elements"},
         "content": {"type": "VStack", "id": 2, "children": [
            {"type": "NavigationLink", "id": 3, "properties": {"title": "Ten", "destinationViewId": 10}},
            {"type": "NavigationLink", "id": 4, "properties": {"title": "Inline"},
             "destination": {"type": "Text", "id": 40, "properties": {"text": "Inline view", "navigationTitle": "Inline"}}},
            {"type": "NavigationLink", "id": 5, "properties": {"title": "Nowhere"}}
         ]},
         "destinations": [
            {"type": "VStack", "id": 10, "properties": {"navigationTitle": "Detail 10"}, "children": [
                {"type": "NavigationLink", "id": 12, "properties": {"title": "Eleven", "destinationViewId": 11}}]},
            {"type": "Text", "id": 11, "properties": {"text": "Eleven", "navigationTitle": "Detail 11"}}
         ]}
        """#

    func testARootStackWithSmallContentFillsTheWindow() throws {
        let stack = try present(#"{"type": "NavigationStack", "id": 1, "content": {"type": "Text", "id": 2, "properties": {"text": "Small"}}}"#)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_width(stack.widget) >= 480 }), "as wide as the window")
        XCTAssertGreaterThan(gtk_widget_get_height(stack.widget), 300)
    }

    func testTheContentIsTheRootPageTitledByTheStack() throws {
        let stack = try present(Self.destinations)
        XCTAssertEqual(try titles(stack), ["Elements"], "the content has no title of its own")
        let content = try XCTUnwrap(stack.childNodes[2])
        XCTAssertTrue(gtk_widget_is_ancestor(content.outerWidget, try state(stack).rootPage.widget) != 0)
        XCTAssertTrue(try XCTUnwrap(renderTree).showsOwnHeaderBars, "the window shows no header bar of its own")
    }

    func testWritingThePathPushesAndPops() throws {
        let stack = try present(Self.destinations)
        setPath(stack, [10, 11])
        XCTAssertEqual(try titles(stack), ["Elements", "Detail 10", "Detail 11"])
        XCTAssertNotNil(stack.childNodes[11], "the destination is a child node")
        setPath(stack, [10])
        XCTAssertTrue(wait { (try? self.titles(stack)) == ["Elements", "Detail 10"] })
        XCTAssertNil(stack.childNodes[11], "a popped destination leaves the tree")
        setPath(stack, [])
        XCTAssertTrue(wait { (try? self.titles(stack)) == ["Elements"] })
    }

    func testLinksPushADestinationIntoThePathAndAnInlineViewOutsideIt() throws {
        let stack = try present(Self.destinations)
        let ten = try XCTUnwrap(stack.childNodes[2]?.childNodes[3])
        AdwaitaTestHost.emit("clicked", on: ten.widget)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(path(stack), [10])
        XCTAssertEqual(try titles(stack), ["Elements", "Detail 10"])

        // From the pushed screen, a link pushes further.
        let eleven = try XCTUnwrap(stack.childNodes[10]?.childNodes[12])
        AdwaitaTestHost.emit("clicked", on: eleven.widget)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(path(stack), [10, 11])

        setPath(stack, [])
        XCTAssertTrue(wait { (try? self.titles(stack)) == ["Elements"] })
        let inline = try XCTUnwrap(stack.childNodes[2]?.childNodes[4])
        AdwaitaTestHost.emit("clicked", on: inline.widget)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try titles(stack), ["Elements", "Inline"])
        XCTAssertEqual(path(stack), [], "an inline destination is not in the path")

        let nowhere = try XCTUnwrap(stack.childNodes[2]?.childNodes[5])
        XCTAssertEqual(gtk_widget_get_sensitive(try XCTUnwrap(gtk_button_get_child(typed(nowhere.widget)))), 0, "a link that leads nowhere is dimmed")
        AdwaitaTestHost.emit("clicked", on: nowhere.widget)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try titles(stack), ["Elements", "Inline"], "and does nothing")
    }

    func testTheUsersBackShortensThePath() throws {
        let stack = try present(Self.destinations)
        setPath(stack, [10, 11])
        // As the back button does.
        XCTAssertNotEqual(adw_navigation_view_pop(try state(stack).view), 0)
        XCTAssertTrue(wait { self.path(stack) == [10] })
        XCTAssertTrue(wait { stack.childNodes[11] == nil })
        XCTAssertEqual(try titles(stack), ["Elements", "Detail 10"])
    }

    private static let selectableList = #"""
        {"type": "NavigationStack", "id": 1, "properties": {"navigationTitle": "Pick"},
         "content": {"type": "List", "id": 2, "properties": {"actionID": "test.picked"}, "children": [
            {"type": "Text", "id": 100, "properties": {"text": "A", "destinationViewId": 10}},
            {"type": "Text", "id": 101, "properties": {"text": "B", "destinationViewId": 11}}]},
         "destinations": [
            {"type": "Text", "id": 10, "properties": {"text": "Detail A", "navigationTitle": "A"}},
            {"type": "Text", "id": 11, "properties": {"text": "Detail B", "navigationTitle": "B"}}]}
        """#

    func testAChosenListChildPushesItsDestinationAndBackingOutClearsTheSelection() throws {
        var picked: [Int] = []
        ActionUIModel.shared.registerActionHandler(for: "test.picked") { _, _, _, _, context in
            MainActor.assumeIsolated { picked.append(context as? Int ?? -1) }
        }
        defer { ActionUIModel.shared.unregisterActionHandler(for: "test.picked") }
        let stack = try present(Self.selectableList)
        let list = try XCTUnwrap(stack.childNodes[2])
        // In List+Adwaita's order.
        RowSelection.commitChildSelection(101, model: list.model, actionID: "test.picked", windowUUID: windowUUID, viewID: 2)
        NavigationStack.contentListChose(list, childID: 101)
        XCTAssertTrue(wait { self.path(stack) == [11] })
        XCTAssertTrue(wait { (try? self.titles(stack)) == ["Pick", "B"] })

        XCTAssertNotEqual(adw_navigation_view_pop(try state(stack).view), 0)
        XCTAssertTrue(wait { self.path(stack).isEmpty })
        XCTAssertEqual(list.model.value as? [String], [], "the selection clears at the root")
        XCTAssertEqual(picked, [101])
    }

    func testTheHostsPathBackToTheRootClearsTheListSelection() throws {
        let stack = try present(Self.selectableList)
        let list = try XCTUnwrap(stack.childNodes[2])
        RowSelection.commitChildSelection(100, model: list.model, actionID: nil, windowUUID: windowUUID, viewID: 2)
        NavigationStack.contentListChose(list, childID: 100)
        XCTAssertTrue(wait { (try? self.titles(stack)) == ["Pick", "A"] })
        XCTAssertEqual(list.model.value as? [String], ["100"])
        setPath(stack, [])
        XCTAssertEqual(list.model.value as? [String], [], "the same row can be chosen again")
    }

    func testASecondClickBeforeThePushShowsPushesNothingMore() throws {
        let stack = try present(Self.destinations)
        let ten = try XCTUnwrap(stack.childNodes[2]?.childNodes[3])
        AdwaitaTestHost.emit("clicked", on: ten.widget)
        AdwaitaTestHost.emit("clicked", on: ten.widget)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(path(stack), [10], "the path names the screens shown, once each")
        XCTAssertEqual(try titles(stack), ["Elements", "Detail 10"])
    }

    func testAnEmptyNavigationTitleCountsAsNone() throws {
        let stack = try present(#"""
            {"type": "NavigationStack", "id": 1, "properties": {"navigationTitle": "Stack"},
             "content": {"type": "Text", "id": 2, "properties": {"text": "Home", "navigationTitle": ""}},
             "destinations": [{"type": "Text", "id": 10, "properties": {"text": "Ten", "navigationTitle": ""}}]}
            """#)
        setPath(stack, [10])
        XCTAssertEqual(try titles(stack), ["Stack", "Stack"], "libadwaita warns about a page without a title")
    }

    func testTheWindowsButtonsAreOnlyOnTheWindowsOwnStack() throws {
        let stack = try present(Self.destinations)
        XCTAssertTrue(try state(stack).headerBars.allSatisfy { adw_header_bar_get_show_end_title_buttons(OpaquePointer($0)) != 0 })
        tearDownWindow()
        let nested = try present(Self.destinations, nested: true)
        XCTAssertTrue(try state(nested).headerBars.allSatisfy { adw_header_bar_get_show_end_title_buttons(OpaquePointer($0)) == 0 })
        XCTAssertFalse(try XCTUnwrap(renderTree).showsOwnHeaderBars)
    }

    private func tearDownWindow() {
        renderTree?.detach()
        renderTree = nil
        if let gtkWindow {
            gtk_window_destroy(gtkWindow)
        }
        gtkWindow = nil
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
    }
}
