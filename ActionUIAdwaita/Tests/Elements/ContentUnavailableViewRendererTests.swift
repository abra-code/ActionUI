// Tests/Elements/ContentUnavailableViewRendererTests.swift
/*
 Tests for the ContentUnavailableView renderer on GTK: the icon, the title and the description one
 above the other; the value as the title; no icon without systemImage and no description without
 one; the search variant's magnifying glass and texts, with the query from the value; greedy in
 width only, and about as tall as on macOS.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ContentUnavailableViewRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "cuv-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ properties: String) throws -> RenderNode {
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let json = #"{"type": "ContentUnavailableView", "id": 1, "properties": {"# + properties + "}}"
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    /// The icon, the title and the description.
    private func parts(_ node: RenderNode) throws -> (icon: WidgetPointer, title: WidgetPointer, description: WidgetPointer) {
        let icon = try XCTUnwrap(gtk_widget_get_first_child(node.widget))
        let title = try XCTUnwrap(gtk_widget_get_next_sibling(icon))
        return (icon, title, try XCTUnwrap(gtk_widget_get_next_sibling(title)))
    }

    private func text(_ label: WidgetPointer) -> String? {
        swiftString(gtk_label_get_text(opaque(label)))
    }

    func testTheIconTitleAndDescription() throws {
        let node = try render(#""title": "No Mail", "systemImage": "tray", "description": "New messages appear here.""#)
        let (icon, title, description) = try parts(node)
        XCTAssertEqual(text(title), "No Mail")
        XCTAssertEqual(text(description), "New messages appear here.")
        XCTAssertEqual(swiftString(gtk_image_get_icon_name(opaque(icon))), Image.iconName(.symbol("tray")))
        XCTAssertEqual(gtk_accessible_get_accessible_role(OpaquePointer(icon)), GTK_ACCESSIBLE_ROLE_PRESENTATION, "the icon is decoration, as in SwiftUI's tree")
        XCTAssertNotEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_HORIZONTAL), 0, "greedy in width")
        XCTAssertEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_VERTICAL), 0, "its own height, as on macOS")

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "Inbox Zero")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(text(title), "Inbox Zero", "the value is the title")
    }

    func testAboutAsTallAsOnMacOS() throws {
        // Measured on macOS 27: 126 points with an icon and a title (112 here).
        let node = try render(#""title": "Empty", "systemImage": "tray""#)
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(node.widget, GTK_ORIENTATION_VERTICAL, 300, &minimum, &natural, nil, nil)
        XCTAssertLessThan(abs(Int(natural) - 126), 30, "natural height \(natural), margins included")
    }

    func testNarrowWidthBreaksInsideAWord() throws {
        // SwiftUI breaks a word wider than the view (measured on macOS 27: a long query in 120 points).
        let node = try render(#""search": true, "query": "supercalifragilisticexpialidocious""#)
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(node.widget, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &natural, nil, nil)
        XCTAssertLessThan(minimum, 120, "minimum width \(minimum), margins included")
    }

    func testNoIconOrDescriptionWithoutThem() throws {
        let node = try render(#""title": "Nothing""#)
        let (icon, _, description) = try parts(node)
        XCTAssertEqual(gtk_widget_get_visible(icon), 0)
        XCTAssertEqual(gtk_widget_get_visible(description), 0)
    }

    func testTheSearchVariant() throws {
        let node = try render(#""search": true, "title": "Ignored""#)
        let (icon, title, description) = try parts(node)
        XCTAssertEqual(text(title), "No Results")
        XCTAssertEqual(text(description), "Check the spelling or try a new search.")
        XCTAssertEqual(swiftString(gtk_image_get_icon_name(opaque(icon))), Image.iconName(.symbol("magnifyingglass")))
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "planets")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(text(title), "No Results for \u{201C}planets\u{201D}")
    }
}
