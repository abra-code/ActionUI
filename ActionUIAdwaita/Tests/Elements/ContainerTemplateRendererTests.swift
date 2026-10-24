// Tests/Elements/ContainerTemplateRendererTests.swift
/*
 Tests for the template form of the containers other than List and the lazy grids (syncContent):
 VStack, HStack, ZStack, LazyVStack, LazyHStack, Group, Section, GroupBox and DisclosureGroup show
 one template instance per content row, the template with the row's data, in row order; a row
 shown with the same data at the same place keeps its widgets, rows that go are taken out; a
 Group's and a Section's rows are laid out as their stack's own, a Section's after its header.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ContainerTemplateRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "container-template-\(name)"
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

    private func setRows(_ viewID: Int, _ rows: [[String]]) {
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: viewID, rows: rows)
        AdwaitaTestHost.drainMainLoop()
    }

    /// The labels under `widget`, depth first, in widget order.
    private func labels(_ widget: WidgetPointer) -> [WidgetPointer] {
        Gtk.Widget(widget).children.flatMap { child -> [WidgetPointer] in
            child.isA(gtk_label_get_type()) ? [child.pointer] : labels(child.pointer)
        }
    }

    private func texts(_ widget: WidgetPointer) -> [String] {
        labels(widget).map { Gtk.Label($0).text }
    }

    private func textTemplate(_ type: String) -> String {
        #"{"type": "\#(type)", "id": 1, "template": {"type": "Text", "properties": {"text": "$1 ($2)"}}}"#
    }

    func testEachStackShowsATemplateInstancePerRow() throws {
        for type in ["VStack", "HStack", "ZStack", "LazyVStack", "LazyHStack"] {
            let node = try render(textTemplate(type))
            setRows(1, [["Apple", "red"], ["Cherry", "dark red"]])
            XCTAssertEqual(texts(node.widget), ["Apple (red)", "Cherry (dark red)"], type)
            ActionUIModel.shared.windowModels[windowUUID] = nil
        }
    }

    func testAKeptRowKeepsItsWidgetsAndRowsThatGoAreTakenOut() throws {
        let node = try render(textTemplate("VStack"))
        setRows(1, [["Apple", "red"], ["Cherry", "dark red"], ["Plum", "purple"]])
        let first = try XCTUnwrap(labels(node.widget).first)
        setRows(1, [["Apple", "red"], ["Banana", "yellow"]])
        XCTAssertEqual(texts(node.widget), ["Apple (red)", "Banana (yellow)"])
        XCTAssertTrue(labels(node.widget).first == first, "the same row at the same place keeps its widgets")
        setRows(1, [])
        XCTAssertEqual(texts(node.widget), [])
    }

    func testAContainerInTheTemplateShowsItsChildrenWithTheRowsData() throws {
        let node = try render(#"""
            {"type": "VStack", "id": 1, "template": {"type": "HStack", "children": [
              {"type": "Text", "properties": {"text": "$1"}}, {"type": "Text", "properties": {"text": "$2"}}]}}
            """#)
        setRows(1, [["Apple", "red"], ["Cherry", "dark red"]])
        XCTAssertEqual(texts(node.widget), ["Apple", "red", "Cherry", "dark red"])
    }

    func testAGroupsRowsAreItsStacksOwn() throws {
        let node = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "Text", "id": 2, "properties": {"text": "Top"}},
              {"type": "Group", "id": 3, "template": {"type": "Text", "properties": {"text": "$1"}}},
              {"type": "Text", "id": 4, "properties": {"text": "Bottom"}}]}
            """#)
        setRows(3, [["Apple"], ["Cherry"]])
        XCTAssertEqual(texts(node.widget), ["Top", "Apple", "Cherry", "Bottom"])
        let group = try XCTUnwrap(node.childNodes[3])
        XCTAssertTrue(Group.isFlattened(group.widget))
        XCTAssertEqual(Array(Gtk.Widget(group.widget).children).count, 2, "a child box per row")
    }

    func testASectionsRowsFollowItsHeader() throws {
        let node = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "Section", "id": 2, "properties": {"header": "Fruits"}, "template": {"type": "Text", "properties": {"text": "$1"}}}]}
            """#)
        setRows(2, [["Apple"], ["Cherry"]])
        XCTAssertEqual(texts(node.widget), ["Fruits", "Apple", "Cherry"])
    }

    func testAGroupBoxAndAnExpandedDisclosureGroupShowTheRowsAsTheirContent() throws {
        let box = try render(#"{"type": "GroupBox", "id": 1, "properties": {"title": "Fruits"}, "template": {"type": "Text", "properties": {"text": "$1"}}}"#)
        setRows(1, [["Apple"], ["Cherry"]])
        XCTAssertEqual(texts(box.widget), ["Fruits", "Apple", "Cherry"])
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let group = try render(#"{"type": "DisclosureGroup", "id": 1, "properties": {"title": "Fruits", "isExpanded": true}, "template": {"type": "Text", "properties": {"text": "$1"}}}"#)
        setRows(1, [["Apple"], ["Cherry"]])
        XCTAssertEqual(texts(group.widget), ["Fruits", "Apple", "Cherry"])
    }
}
