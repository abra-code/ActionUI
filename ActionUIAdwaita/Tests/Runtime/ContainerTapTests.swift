// Tests/Runtime/ContainerTapTests.swift
/*
 Tests for the whole-container tap on GTK (ContainerTap): a VStack, HStack or ZStack with an
 actionID has a click gesture on its box that fires the action with its own id and 0, or inside a
 template row with the container's id and the row index; a release outside the box does nothing;
 a disabled container, one without an action and an element of another type get no tap; removing
 the actionID takes the tap away.
 The tests emit the gesture's "released" without an event sequence, so claiming does nothing here:
 the innermost-wins, drag-out and List-row cases were checked with real pointer input (the review,
 Mutter's remote desktop interface).
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ContainerTapTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var fired: [(viewID: Int, viewPartID: Int)] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "container-tap-\(name)"
        fired = []
        ActionUIModel.shared.registerActionHandler(for: "test.cell") { [weak self] _, _, viewID, viewPartID, _ in
            MainActor.assumeIsolated { self?.fired.append((viewID, viewPartID)) }
        }
    }

    override func tearDown() async throws {
        windows.forEach { $0.detach() }
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIModel.shared.unregisterActionHandler(for: "test.cell")
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func tap(_ node: RenderNode) -> ContainerTap.Installed? {
        ModifierBox.content(of: node.outerWidget).flatMap { attached(on: UnsafeMutableRawPointer($0), key: ContainerTap.installedKey) }
    }

    /// Emits the gesture's "released" at (x, y), as a click's release there.
    private func release(_ installed: ContainerTap.Installed, x: Double, y: Double) {
        var values = [GValue(), GValue(), GValue(), GValue()]
        g_value_init(&values[0], gtk_gesture_click_get_type())
        g_value_set_object(&values[0], UnsafeMutableRawPointer(installed.gesture))
        g_value_init(&values[1], g_type_from_name("gint"))
        g_value_set_int(&values[1], 1)
        g_value_init(&values[2], g_type_from_name("gdouble"))
        g_value_set_double(&values[2], x)
        g_value_init(&values[3], g_type_from_name("gdouble"))
        g_value_set_double(&values[3], y)
        g_signal_emitv(&values, g_signal_lookup("released", gtk_gesture_click_get_type()), 0, nil)
        for index in values.indices { g_value_unset(&values[index]) }
    }

    func testAClickInTheBoxFiresWithTheContainersID() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "properties": {"actionID": "test.cell", "frame": {"width": 100, "height": 40}},
             "children": [{"type": "Text", "id": 2, "properties": {"text": "x"}}]}
            """#)
        // Allocated as a window would, so the box has its size.
        gtk_widget_measure(root.outerWidget, GTK_ORIENTATION_HORIZONTAL, -1, nil, nil, nil, nil)
        gtk_widget_allocate(root.outerWidget, 100, 40, -1, nil)
        let installed = try XCTUnwrap(tap(root))
        release(installed, x: 90, y: 35)
        XCTAssertEqual(fired.map(\.viewID), [1])
        XCTAssertEqual(fired.first?.viewPartID, 0)
        release(installed, x: 150, y: 10)
        XCTAssertEqual(fired.count, 1, "released outside the box: dragged off, no click")
    }

    func testATemplateRowsCellFiresWithItsContainerAndRow() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "template": {"type": "HStack", "properties": {"actionID": "test.cell", "frame": {"width": 50, "height": 20}},
              "children": [{"type": "Text", "properties": {"text": "$1"}}]}}
            """#)
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["a"], ["b"]])
        AdwaitaTestHost.drainMainLoop()
        let second = try XCTUnwrap(Gtk.Widget(root.widget).children.map(\.pointer).dropFirst().first)
        gtk_widget_measure(second, GTK_ORIENTATION_HORIZONTAL, -1, nil, nil, nil, nil)
        gtk_widget_allocate(second, 50, 20, -1, nil)
        let installed = try XCTUnwrap(attached(on: UnsafeMutableRawPointer(try XCTUnwrap(ModifierBox.content(of: second))), key: ContainerTap.installedKey))
        release(installed, x: 5, y: 5)
        XCTAssertEqual(fired.map(\.viewID), [1], "the template container's id, as a Button in the row reports")
        XCTAssertEqual(fired.first?.viewPartID, 1, "the row index")
    }

    func testTheTapIsTheFrameNotTheSpaceTheBoxIsGiven() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "properties": {"actionID": "test.cell", "frame": {"width": 40, "height": 20}}}
            """#)
        gtk_widget_measure(root.outerWidget, GTK_ORIENTATION_HORIZONTAL, -1, nil, nil, nil, nil)
        gtk_widget_allocate(root.outerWidget, 200, 100, -1, nil)
        XCTAssertNil(attached(on: UnsafeMutableRawPointer(root.outerWidget), key: ContainerTap.installedKey),
                     "not on the box, which a window's root fills")
        let content = try XCTUnwrap(ModifierBox.content(of: root.outerWidget))
        XCTAssertNotNil(attached(on: UnsafeMutableRawPointer(content), key: ContainerTap.installedKey))
        XCTAssertEqual(gtk_widget_get_width(content), 40, "the frame")
    }

    func testOnlyAnEnabledStackWithAnActionIsTappable() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "HStack", "id": 2, "properties": {"actionID": "test.cell", "disabled": true}},
              {"type": "ZStack", "id": 3, "properties": {"actionID": "  "}},
              {"type": "Text", "id": 4, "properties": {"text": "x", "actionID": "test.cell"}},
              {"type": "ZStack", "id": 5, "properties": {"actionID": "test.cell"}}]}
            """#)
        XCTAssertNil(tap(root), "no actionID")
        XCTAssertNil(tap(try XCTUnwrap(root.childNodes[2])), "disabled")
        XCTAssertNil(tap(try XCTUnwrap(root.childNodes[3])), "a blank actionID")
        XCTAssertNil(tap(try XCTUnwrap(root.childNodes[4])), "not a stack")
        let zstack = try XCTUnwrap(root.childNodes[5])
        XCTAssertNotNil(tap(zstack))
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 5, propertyName: "actionID", value: "")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(tap(zstack), "the action taken away, the tap goes")
    }
}
