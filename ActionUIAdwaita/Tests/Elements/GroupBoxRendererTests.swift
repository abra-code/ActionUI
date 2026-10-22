// Tests/Elements/GroupBoxRendererTests.swift
/*
 Tests for the GroupBox and EmptyView renderers on GTK. GroupBox: the title above a card, hidden
 without one; a group named after the title; children added and removed at run time; a Spacer in
 it runs vertically. EmptyView: an invisible box. (Their layout against SwiftUI is in the layout
 parity fixtures: groupbox-children, groupbox-fills, groupbox-capped-hstack,
 groupbox-capped-vstack, hstack-emptyview.)
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class GroupBoxRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "groupbox-\(name)"
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

    private func title(_ node: RenderNode) throws -> WidgetPointer {
        try XCTUnwrap(gtk_widget_get_first_child(node.widget))
    }

    private func content(_ node: RenderNode) throws -> WidgetPointer {
        try XCTUnwrap(gtk_widget_get_last_child(node.widget))
    }

    func testTheTitleIsAboveACardAndNamesTheGroup() throws {
        let node = try render(#"{"type": "GroupBox", "id": 1, "properties": {"title": "Settings"}, "children": [{"type": "Text", "id": 2, "properties": {"text": "Inside"}}]}"#)
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(try title(node)))), "Settings")
        XCTAssertNotEqual(gtk_widget_get_visible(try title(node)), 0)
        XCTAssertNotEqual(gtk_widget_has_css_class(try content(node), "card"), 0)
        XCTAssertEqual(gtk_accessible_get_accessible_role(OpaquePointer(node.widget)), GTK_ACCESSIBLE_ROLE_GROUP)
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(node.widget), GTK_ACCESSIBLE_PROPERTY_LABEL), 0)
        XCTAssertEqual(gtk_accessible_get_accessible_role(OpaquePointer(try title(node))), GTK_ACCESSIBLE_ROLE_PRESENTATION,
                       "the title is read once, as the group's name")
        let child = try XCTUnwrap(node.childNodes[2])
        XCTAssertTrue(gtk_widget_get_parent(child.outerWidget) == (try content(node)), "the children are in the card")

        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "title", value: "")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_widget_get_visible(try title(node)), 0, "no title, no label")
    }

    func testChildrenAddedAtRunTimeGoInTheCard() throws {
        let node = try render(#"{"type": "GroupBox", "id": 1, "children": [{"type": "Text", "id": 2, "properties": {"text": "First"}}]}"#)
        _ = try ActionUIModel.shared.insertElement(windowUUID: windowUUID, parentID: 1,
                                                   json: #"{"type": "Text", "id": 3, "properties": {"text": "Second"}}"#)
        AdwaitaTestHost.drainMainLoop()
        let second = try XCTUnwrap(node.childNodes[3])
        XCTAssertTrue(gtk_widget_get_parent(second.outerWidget) == (try content(node)))
    }

    func testASpacerInAGroupBoxRunsVertically() throws {
        let node = try render(#"{"type": "GroupBox", "id": 1, "children": [{"type": "Spacer", "id": 2}]}"#)
        let spacer = try XCTUnwrap(node.childNodes[2])
        XCTAssertNotEqual(gtk_widget_get_vexpand(spacer.widget), 0)
        XCTAssertEqual(gtk_widget_get_hexpand(spacer.widget), 0)
    }

    func testAnEmptyViewIsAnInvisibleBox() throws {
        let root = try render(#"{"type": "HStack", "id": 1, "children": [{"type": "EmptyView", "id": 2, "properties": {"padding": 20}}]}"#)
        let empty = try XCTUnwrap(root.childNodes[2])
        XCTAssertEqual(gtk_widget_get_visible(empty.outerWidget), 0, "a stack gives it no place and no spacing")
    }
}
