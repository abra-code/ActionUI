// Tests/Elements/LinkRendererTests.swift
/*
 Tests for the Link renderer on GTK: a link button with the title and the URL, named after the
 title (no label relation outranks accessibilityLabel); without a valid URL its box is hidden, so a
 stack gives it no place; a new URL applies.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class LinkRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "link-\(name)"
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

    func testALinkButtonWithTheTitleAndTheURL() throws {
        let node = try render(#"{"type": "Link", "id": 1, "properties": {"title": "Docs", "url": "https://example.com/docs"}}"#)
        XCTAssertEqual(swiftString(gtk_button_get_label(typed(node.widget))), "Docs")
        XCTAssertEqual(swiftString(gtk_link_button_get_uri(OpaquePointer(node.widget))), "https://example.com/docs")
        XCTAssertEqual(gtk_accessible_get_accessible_role(OpaquePointer(node.widget)), GTK_ACCESSIBLE_ROLE_LINK)
        XCTAssertEqual(gtk_test_accessible_has_relation(OpaquePointer(node.widget), GTK_ACCESSIBLE_RELATION_LABELLED_BY), 0)
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(node.widget), GTK_ACCESSIBLE_PROPERTY_LABEL), 0)

        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "url", value: "https://example.com/other")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(swiftString(gtk_link_button_get_uri(OpaquePointer(node.widget))), "https://example.com/other")
    }

    func testWithoutAValidURLItTakesNoPlace() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "Link", "id": 2, "properties": {"title": "Nowhere"}},
              {"type": "Link", "id": 3, "properties": {"title": "Here", "url": "https://example.com"}}]}
            """#)
        XCTAssertEqual(gtk_widget_get_visible(try XCTUnwrap(root.childNodes[2]).outerWidget), 0, "no URL: nothing, as SwiftUI's EmptyView")
        XCTAssertNotEqual(gtk_widget_get_visible(try XCTUnwrap(root.childNodes[3]).outerWidget), 0)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 2, propertyName: "url", value: "https://example.com/found")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNotEqual(gtk_widget_get_visible(try XCTUnwrap(root.childNodes[2]).outerWidget), 0, "a URL arrives: shown")

        // A string URL(string:) refuses hides it again; the old URL coming back shows it.
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 2, propertyName: "url", value: "http://[::1")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_widget_get_visible(try XCTUnwrap(root.childNodes[2]).outerWidget), 0, "an invalid URL: nothing")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 2, propertyName: "url", value: "https://example.com/found")
        AdwaitaTestHost.drainMainLoop()
        let link = try XCTUnwrap(root.childNodes[2])
        XCTAssertNotEqual(gtk_widget_get_visible(link.outerWidget), 0, "valid again: shown")
        XCTAssertEqual(swiftString(gtk_link_button_get_uri(OpaquePointer(link.widget))), "https://example.com/found")
    }
}
