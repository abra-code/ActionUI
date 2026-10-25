// Tests/Runtime/NodeHoverTests.swift
/*
 Tests for onHoverActionID on GTK (NodeHover): a motion controller on the element's frame (its
 box's content group, not the box, which can be given more than the frame); the pointer entering
 fires the action with {"isHovering": true} and the element's id, leaving with
 false, on the next turn of the main queue; an element without the action gets no controller.
 (Enter and leave are emitted on the controller here: real pointer motion is the probe's.)
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class NodeHoverTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var fired: [(viewID: Int, hovering: Bool?)] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "node-hover-\(name)"
        fired = []
        ActionUIModel.shared.registerActionHandler(for: "test.hover") { [weak self] _, _, viewID, _, context in
            MainActor.assumeIsolated { self?.fired.append((viewID, (context as? [String: Any])?["isHovering"] as? Bool)) }
        }
    }

    override func tearDown() async throws {
        windows.forEach { $0.detach() }
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIModel.shared.unregisterActionHandler(for: "test.hover")
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    /// The widget's motion controller, if any.
    private func motion(_ widget: WidgetPointer) -> UnsafeMutableRawPointer? {
        let controllers = gtk_widget_observe_controllers(widget)!
        defer { g_object_unref(UnsafeMutableRawPointer(controllers)) }
        for index in 0..<g_list_model_get_n_items(controllers) {
            guard let item = g_list_model_get_item(controllers, index) else { continue }
            g_object_unref(item)
            if g_type_check_instance_is_a(item.assumingMemoryBound(to: GTypeInstance.self), gtk_event_controller_motion_get_type()) != 0 {
                return item
            }
        }
        return nil
    }

    private func emitEnter(_ controller: UnsafeMutableRawPointer) {
        var values = [GValue(), GValue(), GValue()]
        g_value_init(&values[0], gtk_event_controller_motion_get_type())
        g_value_set_object(&values[0], controller)
        g_value_init(&values[1], g_type_from_name("gdouble"))
        g_value_init(&values[2], g_type_from_name("gdouble"))
        g_signal_emitv(&values, g_signal_lookup("enter", gtk_event_controller_motion_get_type()), 0, nil)
        for index in values.indices { g_value_unset(&values[index]) }
    }

    func testEnteringAndLeavingFireWithIsHovering() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [{"type": "Text", "id": 2, "properties": {"text": "x", "onHoverActionID": "test.hover"}}]}
            """#)
        XCTAssertNil(motion(try XCTUnwrap(ModifierBox.content(of: root.outerWidget))), "no action, no controller")
        let controller = try XCTUnwrap(motion(try XCTUnwrap(ModifierBox.content(of: try XCTUnwrap(root.childNodes[2]).outerWidget))))
        emitEnter(controller)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { fired.count == 1 }))
        XCTAssertEqual(fired.first?.viewID, 2)
        XCTAssertEqual(fired.first?.hovering, true)
        AdwaitaTestHost.emit("leave", on: controller)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { fired.count == 2 }))
        XCTAssertEqual(fired.last?.hovering, false)
    }

    /// A box given more than its frame (a window's root) centers the frame in it: the pointer
    /// over the extra space is not over the element, as on macOS.
    func testTheHoverAreaIsTheFrameNotTheSpaceTheBoxIsGiven() throws {
        let root = try render(#"""
            {"type": "Text", "id": 1, "properties": {"text": "x", "frame": {"width": 40, "height": 20}, "onHoverActionID": "test.hover"}}
            """#)
        gtk_widget_measure(root.outerWidget, GTK_ORIENTATION_HORIZONTAL, -1, nil, nil, nil, nil)
        gtk_widget_allocate(root.outerWidget, 200, 100, -1, nil)
        XCTAssertNil(motion(root.outerWidget), "not on the box")
        let controller = try XCTUnwrap(motion(try XCTUnwrap(ModifierBox.content(of: root.outerWidget))))
        let watched = try XCTUnwrap(gtk_event_controller_get_widget(OpaquePointer(controller)))
        var bounds = graphene_rect_t()
        XCTAssertTrue(gtk_widget_compute_bounds(watched, root.outerWidget, &bounds) != 0)
        XCTAssertEqual([bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height], [80, 40, 40, 20])
    }
}
