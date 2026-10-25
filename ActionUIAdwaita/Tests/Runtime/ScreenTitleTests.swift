// Tests/Runtime/ScreenTitleTests.swift
/*
 Tests for a screen's navigationTitle (ScreenTitle): the root's own first, else the first in its
 views depth first; not from a nested navigation container, a sheet or a toolbar; a stack page and
 a split view column titled from a view inside them, a changed title titling them again; a view
 inserted at run time; of a TabView the selected tab.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ScreenTitleTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "screen-title-\(name)"
    }

    override func tearDown() async throws {
        windows.forEach { $0.detach() }
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
    }

    private func load(_ json: String) throws -> WindowModel {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        return try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID])
    }

    private func render(_ json: String) throws -> RenderNode {
        let model = try load(json)
        let window = AdwaitaWindow(windowModel: model)
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    func testInnerTitlesBeforeOuterAndEarlierBeforeLater() throws {
        let model = try load(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "HStack", "id": 2, "children": [{"type": "Text", "id": 3, "properties": {"text": "x", "navigationTitle": "Deep"}}]},
              {"type": "List", "id": 4, "properties": {"navigationTitle": "Later"}}]}
            """#)
        let root = try XCTUnwrap(model.element)
        XCTAssertEqual(ScreenTitle.find(in: root, windowModel: model), "Deep", "the first in order, depth first")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "navigationTitle", value: "Own")
        XCTAssertEqual(ScreenTitle.find(in: root, windowModel: model), "Deep", "an inner title wins over the root's own, as SwiftUI's (measured)")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 3, propertyName: "navigationTitle", value: "")
        XCTAssertEqual(ScreenTitle.find(in: root, windowModel: model), "Later", "an empty title counts as none")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 4, propertyName: "navigationTitle", value: "")
        XCTAssertEqual(ScreenTitle.find(in: root, windowModel: model), "Own", "the root's own when no view inside has one")
    }

    func testABackgroundsTitleCounts() throws {
        let model = try load(#"""
            {"type": "VStack", "id": 1, "background": {"type": "Text", "id": 2, "properties": {"text": "b", "navigationTitle": "Back"}}}
            """#)
        XCTAssertEqual(ScreenTitle.find(in: try XCTUnwrap(model.element), windowModel: model), "Back", "SwiftUI takes it too (measured)")
    }

    func testNotFromANestedContainerASheetOrAToolbar() throws {
        let model = try load(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "NavigationStack", "id": 2, "content": {"type": "Text", "id": 3, "properties": {"text": "x", "navigationTitle": "Inner"}}},
              {"type": "Button", "id": 4, "properties": {"title": "b"},
               "sheet": {"type": "Text", "id": 5, "properties": {"text": "s", "navigationTitle": "Sheet"}},
               "toolbar": [{"type": "ToolbarItem", "id": 6, "content": {"type": "Text", "id": 7, "properties": {"text": "t", "navigationTitle": "Bar"}}}]}]}
            """#)
        XCTAssertNil(ScreenTitle.find(in: try XCTUnwrap(model.element), windowModel: model))
    }

    func testAViewInsertedAtRunTimeAndTheSelectedTab() throws {
        let stack = try render(#"""
            {"type": "NavigationStack", "id": 1, "content": {"type": "VStack", "id": 2, "children": [
              {"type": "TabView", "id": 3, "children": [
                {"type": "Tab", "id": 4, "properties": {"title": "One"}, "content": {"type": "Text", "id": 5, "properties": {"text": "1", "navigationTitle": "First"}}},
                {"type": "Tab", "id": 6, "properties": {"title": "Two"}, "content": {"type": "Text", "id": 7, "properties": {"text": "2", "navigationTitle": "Second"}}}]}]}}
            """#)
        let state = try XCTUnwrap(attached(on: stack.widget, key: navigationStackStateKey))
        let title = { swiftString(adw_navigation_page_get_title(state.rootPage.typed())) }
        XCTAssertEqual(title(), "First")
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 3, value: 1)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(title(), "Second", "the selected tab's")
        _ = try ActionUIModel.shared.insertElement(windowUUID: windowUUID, parentID: 2,
                                                   json: #"{"type": "Text", "id": 8, "properties": {"text": "n", "navigationTitle": "Inserted"}}"#,
                                                   position: .at(0))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(title(), "Inserted", "a view inserted at run time")
    }

    func testAStackPageAndASplitColumnAreTitledFromAViewInside() throws {
        let stack = try render(#"""
            {"type": "NavigationStack", "id": 1, "content": {"type": "VStack", "id": 2, "children": [
              {"type": "List", "id": 3, "properties": {"navigationTitle": "Receivers"}}]}}
            """#)
        let state = try XCTUnwrap(attached(on: stack.widget, key: navigationStackStateKey))
        XCTAssertEqual(swiftString(adw_navigation_page_get_title(state.rootPage.typed())), "Receivers")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 3, propertyName: "navigationTitle", value: "Senders")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(swiftString(adw_navigation_page_get_title(state.rootPage.typed())), "Senders", "a changed title titles the page again")
        windows.forEach { $0.detach() }
        windows = []
        ActionUIModel.shared.windowModels[windowUUID] = nil

        let split = try render(#"""
            {"type": "NavigationSplitView", "id": 1, "sidebar": {"type": "VStack", "id": 2, "children": [
              {"type": "List", "id": 3, "properties": {"navigationTitle": "Folders"}}]},
             "detail": {"type": "Text", "id": 4, "properties": {"text": "d"}}}
            """#)
        let parts = try XCTUnwrap(attached(on: split.widget, key: splitViewPartsKey))
        XCTAssertEqual(swiftString(adw_window_title_get_title(OpaquePointer(parts.sidebar.title))), "Folders")
    }
}
