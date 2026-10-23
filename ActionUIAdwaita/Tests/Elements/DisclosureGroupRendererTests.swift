// Tests/Elements/DisclosureGroupRendererTests.swift
/*
 Tests for the DisclosureGroup renderer on GTK: a GtkExpander titled after the title, expanded as
 states["isExpanded"] says, and a host change fires nothing; expanding sets the state and fires
 valueChangeActionID once; the children are a centered column 8 apart, offered only their own
 height (measured on macOS 27); it takes the width, not the height.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class DisclosureGroupRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var fired: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "disclosure-\(name)"
        fired = []
        ActionUIModel.shared.registerActionHandler(for: "test.disclosed") { [weak self] actionID, _, _, _, _ in
            MainActor.assumeIsolated { self?.fired.append(actionID) }
        }
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIModel.shared.unregisterActionHandler(for: "test.disclosed")
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func expanded(_ node: RenderNode) -> Bool {
        gtk_expander_get_expanded(OpaquePointer(node.widget)) != 0
    }

    private func state() -> Bool? {
        ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1]?.states["isExpanded"] as? Bool
    }

    private let twoColors = ##"""
        {"type": "DisclosureGroup", "id": 1, "properties": {"title": "Details", "isExpanded": true, "valueChangeActionID": "test.disclosed"}, "children": [
          {"type": "Color", "id": 2, "properties": {"color": "#FF0000", "frame": {"width": 30, "height": 20}}},
          {"type": "Color", "id": 3, "properties": {"color": "#0000FF", "frame": {"width": 40, "height": 20}}}]}
        """##

    func testTitleAndExpandedStateFollowTheModel() throws {
        let node = try render(twoColors)
        XCTAssertEqual(swiftString(gtk_expander_get_label(OpaquePointer(node.widget))), "Details")
        XCTAssertTrue(expanded(node), "the isExpanded property")
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(node.widget), GTK_ACCESSIBLE_PROPERTY_LABEL), 0,
                          "named after its title, not its content, which takes in the children")
        ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: 1, key: "isExpanded", value: false)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertFalse(expanded(node))
        XCTAssertTrue(fired.isEmpty, "a host change fires nothing")
    }

    func testExpandingSetsTheStateAndFiresOnce() throws {
        let node = try render(#"{"type": "DisclosureGroup", "id": 1, "properties": {"title": "More", "valueChangeActionID": "test.disclosed"}, "children": []}"#)
        XCTAssertFalse(expanded(node))
        gtk_expander_set_expanded(OpaquePointer(node.widget), 1)
        XCTAssertEqual(state(), true)
        XCTAssertEqual(fired, ["test.disclosed"])
        AdwaitaTestHost.drainMainLoop()
        XCTAssertTrue(expanded(node))
        XCTAssertEqual(fired.count, 1, "the sync after the change fires nothing")
    }

    func testChildrenAreACenteredColumnEightApart() throws {
        let node = try render(twoColors)
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(node.widget, GTK_ORIENTATION_VERTICAL, 300, &minimum, &natural, nil, nil)
        gtk_widget_allocate(node.widget, 300, natural, -1, nil)
        let column = try XCTUnwrap(gtk_expander_get_child(OpaquePointer(node.widget)))
        func frame(_ id: Int) throws -> [Int] {
            var bounds = graphene_rect_t()
            _ = gtk_widget_compute_bounds(try XCTUnwrap(node.childNodes[id]).outerWidget, column, &bounds)
            return [Int(bounds.origin.x), Int(bounds.origin.y), Int(bounds.size.width), Int(bounds.size.height)]
        }
        let columnWidth = Int(gtk_widget_get_width(column))
        XCTAssertEqual(try frame(2), [(columnWidth - 30) / 2, 0, 30, 20])
        XCTAssertEqual(try frame(3), [(columnWidth - 40) / 2, 28, 40, 20])
    }

    func testNoSpacingNextToASpacer() throws {
        let node = try render(##"""
            {"type": "DisclosureGroup", "id": 1, "properties": {"title": "Gap", "isExpanded": true}, "children": [
              {"type": "Color", "id": 2, "properties": {"color": "#FF0000", "frame": {"width": 30, "height": 20}}},
              {"type": "Spacer", "id": 3},
              {"type": "Color", "id": 4, "properties": {"color": "#0000FF", "frame": {"width": 30, "height": 20}}}]}
            """##)
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(node.widget, GTK_ORIENTATION_VERTICAL, 300, &minimum, &natural, nil, nil)
        gtk_widget_allocate(node.widget, 300, natural, -1, nil)
        let column = try XCTUnwrap(gtk_expander_get_child(OpaquePointer(node.widget)))
        var bounds = graphene_rect_t()
        _ = gtk_widget_compute_bounds(try XCTUnwrap(node.childNodes[4]).outerWidget, column, &bounds)
        XCTAssertEqual(Int(bounds.origin.y), 28, "the Spacer's 8 points and no spacing beside it, as on macOS 27")
    }

    func testTakesTheWidthButOnlyItsHeight() throws {
        let node = try render(#"""
            {"type": "DisclosureGroup", "id": 1, "properties": {"title": "Fill", "isExpanded": true}, "children": [
              {"type": "Color", "id": 2, "properties": {"color": "#FF0000"}}]}
            """#)
        XCTAssertNotEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_HORIZONTAL), 0)
        XCTAssertEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_VERTICAL), 0, "a filling child does not make it grow")
        // Its box, as a parent lays it out, offered far more height than it needs.
        gtk_widget_allocate(node.outerWidget, 300, 600, -1, nil)
        let color = try XCTUnwrap(node.childNodes[2])
        XCTAssertEqual(gtk_widget_get_height(color.outerWidget), 10, "a filling Color is its ideal 10, as on macOS")
    }
}
