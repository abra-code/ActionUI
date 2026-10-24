// Tests/Elements/GeometryReaderRendererTests.swift
/*
 Tests for the GeometryReader renderer on GTK (its layout against SwiftUI is in the geometry-*
 layout parity fixtures): its size reported in states["size"] after a layout, and again when it
 changes; a minimum of 0 in both axes while it expands; a new alignment moving its content.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class GeometryReaderRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "geometry-\(name)"
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

    private let reader = ##"{"type": "GeometryReader", "id": 1, "content": {"type": "Color", "id": 2, "properties": {"color": "#FF0000", "frame": {"width": 100, "height": 50}}}}"##

    func testItsSizeIsReportedAfterEachLayoutThatChangesIt() throws {
        let node = try render(reader)
        gtk_widget_allocate(node.outerWidget, 400, 300, -1, nil)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(node.model.states["size"] as? [Double], [400, 300])
        gtk_widget_allocate(node.outerWidget, 200, 120, -1, nil)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(node.model.states["size"] as? [Double], [200, 120])
    }

    func testItExpandsFromAMinimumOfZero() throws {
        let node = try render(reader)
        var minimum: Int32 = -1
        var natural: Int32 = 0
        gtk_widget_measure(node.widget, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &natural, nil, nil)
        XCTAssertEqual(minimum, 0)
        XCTAssertEqual(natural, 10, "SwiftUI's ideal size, not its content's")
        XCTAssertNotEqual(gtk_widget_get_hexpand(node.widget), 0)
        XCTAssertNotEqual(gtk_widget_get_vexpand(node.widget), 0)
    }

    func testANewAlignmentMovesTheContent() throws {
        let node = try render(reader)
        gtk_widget_allocate(node.outerWidget, 400, 300, -1, nil)
        let content = try XCTUnwrap(node.childNodes[2]).outerWidget
        var bounds = graphene_rect_t()
        XCTAssertNotEqual(gtk_widget_compute_bounds(content, node.widget, &bounds), 0)
        XCTAssertEqual([bounds.origin.x, bounds.origin.y], [0, 0], "top leading")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "alignment", value: "center")
        AdwaitaTestHost.drainMainLoop()
        gtk_widget_allocate(node.outerWidget, 400, 300, -1, nil)
        XCTAssertNotEqual(gtk_widget_compute_bounds(content, node.widget, &bounds), 0)
        XCTAssertEqual([bounds.origin.x, bounds.origin.y], [150, 125])
    }
}
