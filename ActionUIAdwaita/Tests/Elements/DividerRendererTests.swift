// Tests/Elements/DividerRendererTests.swift
/*
 Tests for the Divider renderer on GTK: a vertical separator spanning the height in an HStack and
 in LabeledContent's row, a horizontal one spanning the width elsewhere. Its size between stacked
 Colors is checked by the layout parity fixtures divider-*.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class DividerRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "divider-\(name)"
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

    func testTheLineCrossesItsParentsAxis() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "Divider", "id": 2},
              {"type": "HStack", "id": 3, "children": [{"type": "Divider", "id": 4}]},
              {"type": "LabeledContent", "id": 5, "properties": {"title": "A"}, "children": [{"type": "Divider", "id": 6}]}]}
            """#)
        let inColumn = try XCTUnwrap(root.childNodes[2]).widget!
        XCTAssertEqual(gtk_orientable_get_orientation(OpaquePointer(inColumn)), GTK_ORIENTATION_HORIZONTAL)
        XCTAssertNotEqual(gtk_widget_get_hexpand(inColumn), 0, "spans the width")
        XCTAssertEqual(gtk_widget_get_vexpand(inColumn), 0)
        for (rowID, id) in [(3, 4), (5, 6)] {
            let inRow = try XCTUnwrap(try XCTUnwrap(root.childNodes[rowID]).childNodes[id]).widget!
            XCTAssertEqual(gtk_orientable_get_orientation(OpaquePointer(inRow)), GTK_ORIENTATION_VERTICAL, "in element \(rowID)")
            XCTAssertEqual(gtk_widget_get_hexpand(inRow), 0)
            XCTAssertNotEqual(gtk_widget_get_vexpand(inRow), 0, "spans the height")
        }
    }

    func testAtTheRootItIsHorizontal() throws {
        let node = try render(#"{"type": "Divider", "id": 1}"#)
        XCTAssertEqual(gtk_orientable_get_orientation(OpaquePointer(node.widget)), GTK_ORIENTATION_HORIZONTAL)
    }
}
