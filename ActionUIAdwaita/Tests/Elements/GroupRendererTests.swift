// Tests/Elements/GroupRendererTests.swift
/*
 Tests for the Group renderer on GTK: a stack lays out a Group's children as its own (spacing,
 EmptyView, Spacer axis, children inserted and removed at run time), the Group's modifiers go to
 each child's box and not to its own, and a Group no stack lays out is a VStack. (Its layout against
 SwiftUI is in the layout parity fixtures: group-vstack-spacer, group-padding-per-child,
 group-frame-per-child.)
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class GroupRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        ActionUIRegistry.shared.renderers["Rectangle"] = TestBlockRenderer.self
        windowUUID = "group-\(name)"
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

    private func block(_ id: Int, _ width: Int, _ height: Int) -> String {
        #"{"type": "Rectangle", "id": \#(id), "properties": {"w": \#(width), "h": \#(height)}}"#
    }

    /// The node with element id `id` among `root`'s descendants.
    private func node(_ id: Int, in root: RenderNode) -> RenderNode? {
        if root.element.id == id { return root }
        for child in root.childNodes.values {
            if let found = node(id, in: child) { return found }
        }
        return nil
    }

    /// [x, y, width, height] of element `id`'s widget in the root's box, after allocating the root
    /// `width` x `height`.
    private func frame(_ id: Int, in root: RenderNode, _ width: Int32, _ height: Int32) throws -> [Int] {
        gtk_widget_allocate(root.outerWidget, width, height, -1, nil)
        var bounds = graphene_rect_t()
        _ = gtk_widget_compute_bounds(try XCTUnwrap(node(id, in: root)).widget, root.outerWidget, &bounds)
        return [Int(bounds.origin.x), Int(bounds.origin.y), Int(bounds.size.width), Int(bounds.size.height)]
    }

    func testAStackSpacesAGroupsChildrenAsItsOwn() throws {
        // An HStack given no spacing puts 8 between each pair, the Group's children included: a
        // 76-wide row centered in 200.
        let root = try render(#"{"type": "HStack", "id": 1, "children": [\#(block(2, 20, 20)), {"type": "Group", "id": 3, "children": [\#(block(4, 20, 20)), \#(block(5, 20, 20))]}]}"#)
        XCTAssertEqual(try frame(2, in: root, 200, 40), [62, 10, 20, 20])
        XCTAssertEqual(try frame(4, in: root, 200, 40), [90, 10, 20, 20])
        XCTAssertEqual(try frame(5, in: root, 200, 40), [118, 10, 20, 20])
    }

    func testAnEmptyViewInAGroupTakesNoPlace() throws {
        let root = try render(#"{"type": "HStack", "id": 1, "children": [\#(block(2, 20, 20)), {"type": "Group", "id": 3, "children": [{"type": "EmptyView", "id": 4}, \#(block(5, 20, 20))]}]}"#)
        XCTAssertEqual(try frame(2, in: root, 200, 40)[0], 76)
        XCTAssertEqual(try frame(5, in: root, 200, 40)[0], 104, "8 apart, as without the EmptyView")
    }

    func testASpacerInAGroupRunsAlongTheStack() throws {
        let root = try render(#"{"type": "HStack", "id": 1, "children": [{"type": "Group", "id": 2, "children": [{"type": "Spacer", "id": 3}]}]}"#)
        let spacer = try XCTUnwrap(node(3, in: root))
        XCTAssertNotEqual(gtk_widget_get_hexpand(spacer.widget), 0)
        XCTAssertEqual(gtk_widget_get_vexpand(spacer.widget), 0)
    }

    func testChildrenInsertedAndRemovedAtRunTimeJoinAndLeaveTheStack() throws {
        let root = try render(#"{"type": "HStack", "id": 1, "properties": {"spacing": 0}, "children": [{"type": "Group", "id": 2, "children": [\#(block(3, 20, 20))]}, \#(block(4, 20, 20))]}"#)
        _ = try ActionUIModel.shared.insertElement(windowUUID: windowUUID, parentID: 2, json: block(5, 20, 20))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try frame(3, in: root, 100, 20)[0], 20)
        XCTAssertEqual(try frame(5, in: root, 100, 20)[0], 40)
        XCTAssertEqual(try frame(4, in: root, 100, 20)[0], 60)

        try ActionUIModel.shared.removeElement(windowUUID: windowUUID, viewID: 3)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try frame(5, in: root, 100, 20)[0], 30)
        XCTAssertEqual(try frame(4, in: root, 100, 20)[0], 50)
        XCTAssertNil(node(3, in: root))
    }

    func testAGroupsModifiersGoToEachChildNotToItsOwnBox() throws {
        let root = try render(#"{"type": "HStack", "id": 1, "properties": {"spacing": 0}, "children": [{"type": "Group", "id": 2, "properties": {"padding": 10, "opacity": 0.5}, "children": [\#(block(3, 20, 20)), \#(block(4, 20, 20))]}]}"#)
        XCTAssertEqual(try frame(3, in: root, 80, 40), [10, 10, 20, 20], "each child padded 10")
        XCTAssertEqual(try frame(4, in: root, 80, 40), [50, 10, 20, 20])
        let group = try XCTUnwrap(node(2, in: root))
        XCTAssertEqual(gtk_widget_get_opacity(group.outerWidget), 1, "the Group's own box")
        let child = try XCTUnwrap(node(3, in: root))
        let childBox = try XCTUnwrap(gtk_widget_get_parent(gtk_widget_get_parent(child.outerWidget)))
        XCTAssertEqual(gtk_widget_get_opacity(childBox), 0.5, accuracy: 1.0 / 255, "the box around each child")
    }

    func testAGroupsChildStopsAtItsCapLikeTheStacksOwn() throws {
        // HStack(spacing 0)[Group[Rectangle maxWidth 100 filling], Rectangle filling] in 300: the
        // Group's child stops at 100 and the sibling takes the rest, as without the Group.
        let root = try render(#"{"type": "HStack", "id": 1, "properties": {"spacing": 0}, "children": [{"type": "Group", "id": 2, "children": [{"type": "Rectangle", "id": 3, "properties": {"w": 0, "h": 20, "fill": "h", "frame": {"maxWidth": 100}}}]}, {"type": "Rectangle", "id": 4, "properties": {"w": 0, "h": 20, "fill": "h"}}]}"#)
        XCTAssertEqual(try frame(3, in: root, 300, 20), [0, 0, 100, 20])
        XCTAssertEqual(try frame(4, in: root, 300, 20), [100, 0, 200, 20])
    }

    /// Shows `root` in a window and waits until it is mapped and laid out. The caller destroys the
    /// window.
    private func present(_ root: RenderNode) throws -> WidgetPointer {
        let window = gtk_window_new()!
        gtk_window_set_child(typed(window), root.outerWidget)
        gtk_window_present(typed(window))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: {
            gtk_widget_get_mapped(root.outerWidget) != 0 && gtk_widget_get_width(root.widget) > 0
        }))
        AdwaitaTestHost.drainMainLoop()
        return window
    }

    /// The x of element `id`'s widget in the root's widget, as laid out.
    private func x(_ id: Int, in root: RenderNode) -> Int {
        guard let node = node(id, in: root) else { return -1 }
        var bounds = graphene_rect_t()
        _ = gtk_widget_compute_bounds(node.widget, root.widget, &bounds)
        return Int(bounds.origin.x)
    }

    func testAGroupsOwnWidgetsTakeNoInputFromItsStack() throws {
        // The Group's box spans the stack: a click on the sibling before it, or on the stack's
        // empty space, must not land on the Group's widgets, as SwiftUI's Group has no area.
        let root = try render(#"{"type": "HStack", "id": 1, "properties": {"spacing": 0, "frame": {"width": 100, "height": 20}}, "children": [\#(block(2, 20, 20)), {"type": "Group", "id": 3, "children": [\#(block(4, 20, 20))]}]}"#)
        let window = try present(root)
        defer { gtk_window_destroy(typed(window)) }
        let sibling = try XCTUnwrap(node(2, in: root))
        let group = try XCTUnwrap(node(3, in: root))
        let child = try XCTUnwrap(node(4, in: root))
        var bounds = graphene_rect_t()
        _ = gtk_widget_compute_bounds(sibling.widget, root.outerWidget, &bounds)
        let onSibling = gtk_widget_pick(root.outerWidget, Double(bounds.origin.x) + 10, Double(bounds.origin.y) + 10, GTK_PICK_DEFAULT)
        XCTAssertEqual(onSibling, sibling.widget, "the sibling before the Group")
        _ = gtk_widget_compute_bounds(child.widget, root.outerWidget, &bounds)
        let onChild = gtk_widget_pick(root.outerWidget, Double(bounds.origin.x) + 10, Double(bounds.origin.y) + 10, GTK_PICK_DEFAULT)
        XCTAssertEqual(onChild, child.widget, "the Group's child")
        _ = gtk_widget_compute_bounds(root.widget, root.outerWidget, &bounds)
        let onEmpty = try XCTUnwrap(gtk_widget_pick(root.outerWidget, Double(bounds.origin.x) + 2, Double(bounds.origin.y) + 10, GTK_PICK_DEFAULT))
        XCTAssertEqual(gtk_widget_is_ancestor(onEmpty, group.outerWidget), 0, "the stack's empty space is not the Group's")
        XCTAssertNotEqual(onEmpty, group.outerWidget)
    }

    func testAChildsSizeChangeAtRunTimeMovesTheStacksLaterChildren() throws {
        // GTK's own relayout, from the resize the child queues inside the flattened Group.
        let root = try render(#"{"type": "HStack", "id": 1, "properties": {"spacing": 0}, "children": [{"type": "Group", "id": 2, "children": [\#(block(3, 20, 20))]}, \#(block(4, 20, 20))]}"#)
        let window = try present(root)
        defer { gtk_window_destroy(typed(window)) }
        XCTAssertEqual(x(4, in: root) - x(3, in: root), 20)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 3, propertyName: "w", value: 50)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { self.x(4, in: root) - self.x(3, in: root) == 50 }),
                      "the sibling after the Group moves with the child's new width")
    }

    func testAHiddenGroupHidesItsChildrenFromInputAndAssistiveTechnologies() throws {
        let root = try render(#"{"type": "HStack", "id": 1, "children": [{"type": "Group", "id": 2, "properties": {"hidden": true}, "children": [\#(block(3, 20, 20))]}, \#(block(4, 20, 20))]}"#)
        let group = try XCTUnwrap(node(2, in: root))
        let child = try XCTUnwrap(node(3, in: root))
        let childBox = try XCTUnwrap(gtk_widget_get_parent(gtk_widget_get_parent(child.outerWidget)))
        XCTAssertEqual(gtk_widget_get_can_target(childBox), 0)
        XCTAssertEqual(gtk_widget_get_opacity(childBox), 0)
        XCTAssertEqual(try frame(4, in: root, 100, 20)[0], 54, "the hidden child keeps its place")
        XCTAssertTrue(attached(AccessibilityState.self, on: group.widget, key: accessibilityStateKey)?.hidden ?? false,
                      "hidden on the Group's widget takes its children out of the accessibility tree")
    }

    func testAGroupNoStackLaysOutIsAVStack() throws {
        let root = try render(#"{"type": "Group", "id": 1, "children": [\#(block(2, 20, 20)), \#(block(3, 20, 20))]}"#)
        XCTAssertEqual(try frame(2, in: root, 100, 100), [40, 30, 20, 20])
        XCTAssertEqual(try frame(3, in: root, 100, 100), [40, 50, 20, 20])
    }
}
