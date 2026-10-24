// Tests/Elements/SplitViewRendererTests.swift
/*
 Tests for HSplitView and VSplitView on GTK, against what macOS 27 draws: flexible panes sharing
 the space with 1 pixel dividers between them; the first pane's frame ideal size setting the first
 divider; panes that are not flexible hugged by the split view; a drag moving space between two
 panes within their ranges; after a drag, a change of size going to the last pane; a Group's
 children as panes of their own; VSplitView the same stacked. The size arithmetic is tested on its
 own too.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class SplitViewRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "split-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    /// Each child's bounds in the split view, by element id.
    private func bounds(_ node: RenderNode, _ ids: [Int]) throws -> [graphene_rect_t] {
        try ids.map { id in
            var rect = graphene_rect_t()
            XCTAssertNotEqual(gtk_widget_compute_bounds(try XCTUnwrap(node.childNodes[id]).outerWidget, node.widget, &rect), 0)
            return rect
        }
    }

    private func state(_ node: RenderNode) throws -> SplitState {
        try XCTUnwrap(attached(on: node.widget, key: splitStateKey))
    }

    private let threeColors = ##"{"type": "HSplitView", "id": 1, "children": [{"type": "Color", "id": 2, "properties": {"color": "#FF0000"}}, {"type": "Color", "id": 3, "properties": {"color": "#00FF00"}}, {"type": "Color", "id": 4, "properties": {"color": "#0000FF"}}]}"##

    func testFlexiblePanesShareTheSpaceWithDividers() throws {
        let node = try render(threeColors)
        gtk_widget_allocate(node.outerWidget, 302, 60, -1, nil)
        let panes = try bounds(node, [2, 3, 4])
        XCTAssertEqual(panes.map(\.origin.x), [0, 101, 202])
        XCTAssertEqual(panes.map(\.size.width), [100, 100, 100])
        XCTAssertEqual(panes.map(\.size.height), [60, 60, 60])
        XCTAssertEqual(try state(node).dividers.count, 2)
    }

    func testTheFirstPanesIdealWidthSetsTheFirstDivider() throws {
        let node = try render(##"{"type": "HSplitView", "id": 1, "children": [{"type": "Color", "id": 2, "properties": {"color": "#FF0000", "frame": {"minWidth": 100, "idealWidth": 150, "maxWidth": 300}}}, {"type": "Color", "id": 3, "properties": {"color": "#00FF00", "frame": {"maxWidth": "infinity"}}}]}"##)
        gtk_widget_allocate(node.outerWidget, 600, 60, -1, nil)
        let panes = try bounds(node, [2, 3])
        XCTAssertEqual(panes.map(\.size.width), [150, 449], "the ideal, not the even split up to the maximum")
        gtk_widget_allocate(node.outerWidget, 900, 60, -1, nil)
        XCTAssertEqual(try bounds(node, [2, 3]).map(\.size.width), [150, 749])
    }

    func testPanesThatAreNotFlexibleAreHugged() throws {
        let node = try render(#"{"type": "HSplitView", "id": 1, "children": [{"type": "Text", "id": 2, "properties": {"text": "Left text"}}, {"type": "Text", "id": 3, "properties": {"text": "Right"}}]}"#)
        var natural: Int32 = 0
        gtk_widget_measure(node.widget, GTK_ORIENTATION_HORIZONTAL, -1, nil, &natural, nil, nil)
        let left = Gtk.Widget(try XCTUnwrap(node.childNodes[2]).outerWidget).measure(GTK_ORIENTATION_HORIZONTAL).natural
        let right = Gtk.Widget(try XCTUnwrap(node.childNodes[3]).outerWidget).measure(GTK_ORIENTATION_HORIZONTAL).natural
        XCTAssertEqual(Int(natural), left + right + 1)
        XCTAssertEqual(gtk_widget_get_hexpand(node.outerWidget), 0)
    }

    func testAfterADragTheLastPaneTakesASizeChange() throws {
        let node = try render(threeColors)
        gtk_widget_allocate(node.outerWidget, 302, 60, -1, nil)
        let state = try state(node)
        let panes = state.panes.map { _ in StackChild.expanding(minimum: 0) }
        state.userSizes = SplitLayout.dragged(state.allocatedSizes, panes, index: 0, delta: 40)
        gtk_widget_allocate(node.outerWidget, 402, 60, -1, nil)
        XCTAssertEqual(try bounds(node, [2, 3, 4]).map(\.size.width), [140, 60, 200])
    }

    func testAVSplitViewStacksItsPanes() throws {
        let node = try render(##"{"type": "VSplitView", "id": 1, "children": [{"type": "Color", "id": 2, "properties": {"color": "#FF0000", "frame": {"idealHeight": 40}}}, {"type": "Color", "id": 3, "properties": {"color": "#00FF00"}}]}"##)
        gtk_widget_allocate(node.outerWidget, 200, 201, -1, nil)
        let panes = try bounds(node, [2, 3])
        XCTAssertEqual(panes.map(\.origin.y), [0, 41])
        XCTAssertEqual(panes.map(\.size.height), [40, 160])
        XCTAssertEqual(panes.map(\.size.width), [200, 200])
    }

    func testADividerIsGrabbedNearIt() throws {
        let node = try render(threeColors)
        gtk_widget_allocate(node.outerWidget, 302, 60, -1, nil)
        let state = try state(node)
        XCTAssertEqual(SplitLayout.divider(at: 100.5, state), 0)
        XCTAssertEqual(SplitLayout.divider(at: 97, state), 0)
        XCTAssertEqual(SplitLayout.divider(at: 205, state), 1)
        XCTAssertNil(SplitLayout.divider(at: 150, state))
    }

    func testAVSplitViewMeasuresWrappingTextAtItsWidth() throws {
        let words = Array(repeating: "word", count: 80).joined(separator: " ")
        let node = try render(##"{"type": "VSplitView", "id": 1, "children": [{"type": "Text", "id": 2, "properties": {"text": "\##(words)"}}, {"type": "Color", "id": 3, "properties": {"color": "#00FF00"}}]}"##)
        let text: WidgetPointer = try XCTUnwrap(node.childNodes[2]).outerWidget
        let wrapped = Gtk.Widget(text).measure(GTK_ORIENTATION_VERTICAL, forSize: 200).natural
        var minimum: Int32 = 0
        gtk_widget_measure(node.widget, GTK_ORIENTATION_VERTICAL, 200, &minimum, nil, nil, nil)
        XCTAssertEqual(Int(minimum), wrapped + 1, "the text's height at the split view's width, and the divider")
        gtk_widget_allocate(node.outerWidget, 200, 400, -1, nil)
        XCTAssertEqual(try bounds(node, [2, 3]).map(\.size.height), [Float(wrapped), Float(400 - 1 - wrapped)])
    }

    func testAPaneThatIsNotShownGetsNoDivider() throws {
        let node = try render(##"{"type": "HSplitView", "id": 1, "children": [{"type": "Color", "id": 2, "properties": {"color": "#FF0000"}}, {"type": "EmptyView", "id": 3}, {"type": "Color", "id": 4, "properties": {"color": "#0000FF"}}]}"##)
        gtk_widget_allocate(node.outerWidget, 302, 60, -1, nil)
        let panes = try bounds(node, [2, 4])
        XCTAssertEqual(panes.map(\.origin.x), [0, 151])
        XCTAssertEqual(panes.map(\.size.width), [150, 151])
        let shown = try state(node).dividers.filter { gtk_widget_get_child_visible($0) != 0 }
        XCTAssertEqual(shown.count, 1)
        XCTAssertEqual(SplitLayout.divider(at: 150.5, try state(node)), 0)
    }

    func testTheFirstPanesIdealGivesWayToTheOthersMinimums() throws {
        let node = try render(##"{"type": "HSplitView", "id": 1, "children": [{"type": "Color", "id": 2, "properties": {"color": "#FF0000", "frame": {"minWidth": 100, "idealWidth": 150, "maxWidth": 300}}}, {"type": "Color", "id": 3, "properties": {"color": "#00FF00", "frame": {"minWidth": 10, "maxWidth": "infinity"}}}]}"##)
        var minimum: Int32 = 0
        gtk_widget_measure(node.widget, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, nil, nil, nil)
        XCTAssertEqual(minimum, 111)
        gtk_widget_allocate(node.outerWidget, 131, 60, -1, nil)
        XCTAssertEqual(try bounds(node, [2, 3]).map(\.size.width), [120, 10], "no overflow above the minimums")
    }

    func testADragMeasuresTheHeightAgain() throws {
        let words = Array(repeating: "word", count: 80).joined(separator: " ")
        let node = try render(##"{"type": "HSplitView", "id": 1, "children": [{"type": "Text", "id": 2, "properties": {"text": "\##(words)"}}, {"type": "Color", "id": 3, "properties": {"color": "#00FF00"}}]}"##)
        let text: WidgetPointer = try XCTUnwrap(node.childNodes[2]).outerWidget
        var minimum: Int32 = 0
        gtk_widget_measure(node.outerWidget, GTK_ORIENTATION_VERTICAL, 302, &minimum, nil, nil, nil)
        gtk_widget_allocate(node.outerWidget, 302, Int32(minimum), -1, nil)
        let state = try state(node)
        let width = state.allocatedSizes[0]
        XCTAssertEqual(Int(minimum), Gtk.Widget(text).measure(GTK_ORIENTATION_VERTICAL, forSize: width).minimum)
        state.drag = (0, state.allocatedSizes)
        SplitLayout.moveDivider(node.widget, state, delta: -50)
        state.drag = nil
        gtk_widget_measure(node.outerWidget, GTK_ORIENTATION_VERTICAL, 302, &minimum, nil, nil, nil)
        XCTAssertEqual(Int(minimum), Gtk.Widget(text).measure(GTK_ORIENTATION_VERTICAL, forSize: width - 50).minimum, "the text's height at its narrower width")
    }

    func testAPaneIsPlacedAcrossAsAZStackPlacesItsChild() throws {
        let node = try render(##"{"type": "HSplitView", "id": 1, "children": [{"type": "Color", "id": 2, "properties": {"color": "#FF0000"}}, {"type": "Color", "id": 3, "properties": {"color": "#00FF00", "frame": {"maxHeight": 30}}}]}"##)
        gtk_widget_allocate(node.outerWidget, 201, 60, -1, nil)
        let panes = try bounds(node, [2, 3])
        XCTAssertEqual(panes.map(\.size.height), [60, 30], "up to the frame's maximum")
        XCTAssertEqual(panes.map(\.origin.y), [0, 15])
    }

    func testPanesInsertedAndRemovedAtRunTimeKeepADividerBetweenEachPair() throws {
        let node = try render(threeColors)
        try ActionUIModel.shared.removeElement(windowUUID: windowUUID, viewID: 3)
        _ = try ActionUIModel.shared.insertElement(windowUUID: windowUUID, parentID: 1, json: ##"{"type": "Color", "id": 5, "properties": {"color": "#FFFF00"}}"##, position: .prepend)
        AdwaitaTestHost.drainMainLoop()
        let state = try state(node)
        let pane: (Int) throws -> WidgetPointer = { try XCTUnwrap(node.childNodes[$0]).outerWidget }
        XCTAssertEqual(Gtk.Widget(node.widget).children.map(\.pointer), [try pane(5), state.dividers[0], try pane(2), state.dividers[1], try pane(4)])
        gtk_widget_allocate(node.outerWidget, 302, 60, -1, nil)
        XCTAssertEqual(try bounds(node, [5, 2, 4]).map(\.origin.x), [0, 101, 202])
    }

    func testAGroupsChildrenArePanesOfTheirOwn() throws {
        let node = try render(##"{"type": "HSplitView", "id": 1, "children": [{"type": "Group", "id": 5, "children": [{"type": "Color", "id": 2, "properties": {"color": "#FF0000"}}, {"type": "Color", "id": 3, "properties": {"color": "#00FF00"}}]}, {"type": "Color", "id": 4, "properties": {"color": "#0000FF"}}]}"##)
        gtk_widget_allocate(node.outerWidget, 302, 60, -1, nil)
        let group = try XCTUnwrap(node.childNodes[5])
        let panes = try [2, 3].map { id -> graphene_rect_t in
            var rect = graphene_rect_t()
            XCTAssertNotEqual(gtk_widget_compute_bounds(try XCTUnwrap(group.childNodes[id]).outerWidget, node.widget, &rect), 0)
            return rect
        } + bounds(node, [4])
        XCTAssertEqual(panes.map(\.origin.x), [0, 101, 202], "three panes, as on macOS")
        XCTAssertEqual(panes.map(\.size.width), [100, 100, 100])
        XCTAssertEqual(try state(node).dividers.count, 2)
    }

    func testAGroupPaneTakesNoInputBesideItsChildrenAndGetsDividersWhenItGrows() throws {
        let node = try render(##"{"type": "HSplitView", "id": 1, "properties": {"frame": {"width": 302, "height": 40}}, "children": [{"type": "Color", "id": 4, "properties": {"color": "#0000FF"}}, {"type": "Group", "id": 5, "children": [{"type": "Color", "id": 2, "properties": {"color": "#FF0000"}}, {"type": "Color", "id": 3, "properties": {"color": "#00FF00"}}]}]}"##)
        let window = gtk_window_new()!
        defer { gtk_window_destroy(typed(window)) }
        gtk_window_set_child(typed(window), node.outerWidget)
        gtk_window_present(typed(window))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_width(node.widget) > 0 }))
        AdwaitaTestHost.drainMainLoop()
        // The Group's box spans the split view and comes after the first pane.
        var rect = graphene_rect_t()
        _ = gtk_widget_compute_bounds(try XCTUnwrap(node.childNodes[4]).widget, node.outerWidget, &rect)
        let picked = try XCTUnwrap(gtk_widget_pick(node.outerWidget, Double(rect.origin.x) + 10, Double(rect.origin.y) + 10, GTK_PICK_DEFAULT))
        let first: WidgetPointer = try XCTUnwrap(node.childNodes[4]).outerWidget
        XCTAssertTrue(picked == first || gtk_widget_is_ancestor(picked, first) != 0, "the first pane, not the Group")

        let group = try XCTUnwrap(node.childNodes[5])
        _ = try ActionUIModel.shared.insertElement(windowUUID: windowUUID, parentID: 5, json: ##"{"type": "Color", "id": 6, "properties": {"color": "#FFFF00"}}"##)
        AdwaitaTestHost.drainMainLoop()
        let panes = try [4].map { try XCTUnwrap(node.childNodes[$0]).outerWidget } + [2, 3, 6].map { try XCTUnwrap(group.childNodes[$0]).outerWidget }
        let currentFrames = { panes.map { pane -> graphene_rect_t in
            var rect = graphene_rect_t()
            _ = gtk_widget_compute_bounds(pane, node.widget, &rect)
            return rect
        } }
        // The divider the Group's new child needs comes on a later turn (SplitLayout.allocate).
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { currentFrames().last?.origin.x == 227 }))
        let frames = currentFrames()
        XCTAssertEqual(frames.map(\.origin.x), [0, 75, 151, 227])
        XCTAssertEqual(frames.map(\.size.width), [74, 75, 75, 75])
        XCTAssertEqual(try state(node).dividers.filter { gtk_widget_get_child_visible($0) != 0 }.count, 3)
    }

    // MARK: Size arithmetic

    func testInitialSizesMatchAStackWithDividers() {
        XCTAssertEqual(SplitLayout.initialSizes([.expanding(minimum: 0), .expanding(minimum: 0)], available: 201, firstIdeal: nil), [100, 100])
        XCTAssertEqual(SplitLayout.initialSizes([.fixed(minimum: 0, natural: 30), .expanding(minimum: 0)], available: 201, firstIdeal: nil), [30, 170])
        XCTAssertEqual(SplitLayout.initialSizes([.expanding(minimum: 100, cap: 300), .expanding(minimum: 0)], available: 601, firstIdeal: 50), [100, 500], "the ideal within the first pane's range")
    }

    func testADragKeepsBothPanesInTheirRanges() {
        let panes: [StackChild] = [.expanding(minimum: 50, cap: 120), .expanding(minimum: 30)]
        XCTAssertEqual(SplitLayout.dragged([100, 100], panes, index: 0, delta: 10), [110, 90])
        XCTAssertEqual(SplitLayout.dragged([100, 100], panes, index: 0, delta: 100), [120, 80], "the first pane's maximum")
        XCTAssertEqual(SplitLayout.dragged([100, 100], panes, index: 0, delta: -100), [50, 150], "its minimum")
        XCTAssertEqual(SplitLayout.dragged([60, 40], panes, index: 0, delta: 30), [70, 30], "the second pane's minimum")
    }

    func testAFittedSizeChangeGoesToTheLastPaneFirst() {
        let panes: [StackChild] = [.expanding(minimum: 20), .expanding(minimum: 20), .expanding(minimum: 20, cap: 60)]
        XCTAssertEqual(SplitLayout.fitted([50, 50, 50], panes, available: 172), [50, 60, 60], "the last pane to its maximum, then the one before")
        XCTAssertEqual(SplitLayout.fitted([50, 50, 50], panes, available: 82), [40, 20, 20], "shrinking from the last, each down to its minimum")
    }
}
