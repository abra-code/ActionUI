// Tests/Runtime/NodeDropTests.swift
/*
 Tests for onDropActionID on GTK (NodeDrop): a drop target on the element's frame for the kinds its
 onDropTypes name, files asked for before text; a text drop fires the action, on the main queue's
 next turn, with the text and the point; a file drop with the files' paths (a file without one by
 its URI); the targeted state is reported only when it changes; types Linux does not take, or no
 drop, give no target. (The drop is emitted on the target: a real drag is the probe's.)
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class NodeDropTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var fired: [(actionID: String, context: [String: Any]?)] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "node-drop-\(name)"
        fired = []
        for actionID in ["test.drop", "test.targeted"] {
            ActionUIModel.shared.registerActionHandler(for: actionID) { [weak self] id, _, _, _, context in
                MainActor.assumeIsolated { self?.fired.append((id, context as? [String: Any])) }
            }
        }
    }

    override func tearDown() async throws {
        windows.forEach { $0.detach() }
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIModel.shared.unregisterActionHandler(for: "test.drop")
        ActionUIModel.shared.unregisterActionHandler(for: "test.targeted")
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func zone(_ types: String) -> String {
        #"{"type": "ZStack", "id": 1, "properties": {"onDropTypes": \#(types), "onDropActionID": "test.drop", "onDropTargetedActionID": "test.targeted"}, "children": [{"type": "Text", "id": 2, "properties": {"text": "Drop here"}}]}"#
    }

    /// The drop target on the node's frame, if any.
    private func dropTarget(_ node: RenderNode) -> UnsafeMutableRawPointer? {
        guard let frame = ModifierBox.content(of: node.outerWidget) else { return nil }
        let controllers = gtk_widget_observe_controllers(frame)!
        defer { g_object_unref(UnsafeMutableRawPointer(controllers)) }
        for index in 0..<g_list_model_get_n_items(controllers) {
            guard let item = g_list_model_get_item(controllers, index) else { continue }
            g_object_unref(item)
            if g_type_check_instance_is_a(item.assumingMemoryBound(to: GTypeInstance.self), gtk_drop_target_get_type()) != 0 {
                return item
            }
        }
        return nil
    }

    /// Emits the target's "drop" with `dropped` at (x, y); returns whether it was taken.
    private func drop(_ target: UnsafeMutableRawPointer, _ dropped: inout GValue, x: Double, y: Double) -> Bool {
        var handled = GValue()
        g_value_init(&handled, g_type_from_name("gboolean"))
        var values = [GValue](repeating: GValue(), count: 4)
        g_value_init(&values[0], gtk_drop_target_get_type())
        g_value_set_object(&values[0], target)
        g_value_init(&values[1], g_value_get_type())
        withUnsafeMutablePointer(to: &dropped) { g_value_set_boxed(&values[1], $0) }
        g_value_init(&values[2], g_type_from_name("gdouble"))
        g_value_set_double(&values[2], x)
        g_value_init(&values[3], g_type_from_name("gdouble"))
        g_value_set_double(&values[3], y)
        g_signal_emitv(&values, g_signal_lookup("drop", gtk_drop_target_get_type()), 0, &handled)
        for index in values.indices { g_value_unset(&values[index]) }
        defer { g_value_unset(&handled) }
        return g_value_get_boolean(&handled) != 0
    }

    /// The gtypes `target` asks a drag for, in its order.
    private func gtypes(_ target: UnsafeMutableRawPointer) throws -> [GType] {
        var count: gsize = 0
        let gtypes = try XCTUnwrap(gtk_drop_target_get_gtypes(OpaquePointer(target), &count))
        return Array(UnsafeBufferPointer(start: gtypes, count: Int(count)))
    }

    func testATextDropFiresTheActionWithTheTextAndThePoint() throws {
        let root = try render(zone(#"["public.utf8-plain-text"]"#))
        let target = try XCTUnwrap(dropTarget(root))
        XCTAssertNil(dropTarget(try XCTUnwrap(root.childNodes[2])), "no drop, no target")
        var text = GValue()
        g_value_init(&text, g_type_from_name("gchararray"))
        g_value_set_string(&text, "Hello")
        defer { g_value_unset(&text) }
        // y not a float: the frame's point is reported as GTK gives it.
        XCTAssertTrue(drop(target, &text, x: 5, y: 7.3))
        XCTAssertTrue(fired.isEmpty, "not while GTK is in the drop")
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { !fired.isEmpty }))
        XCTAssertEqual(fired.map(\.actionID), ["test.drop"])
        XCTAssertEqual(fired.first?.context?["items"] as? [String], ["Hello"])
        let location = try XCTUnwrap(fired.first?.context?["location"] as? [String: Double])
        XCTAssertEqual(location, ["x": 5, "y": 7.3])
    }

    func testAFileDropFiresTheActionWithThePaths() throws {
        let root = try render(zone(#"["public.file-url"]"#))
        let target = try XCTUnwrap(dropTarget(root))
        var files: [OpaquePointer?] = [g_file_new_for_path("/tmp/report.txt"), g_file_new_for_uri("https://example.com/remote.txt")]
        defer { files.forEach { g_object_unref(UnsafeMutableRawPointer($0)) } }
        var list = GValue()
        g_value_init(&list, gdk_file_list_get_type())
        g_value_take_boxed(&list, UnsafeRawPointer(gdk_file_list_new_from_array(&files, gsize(files.count))))
        defer { g_value_unset(&list) }
        XCTAssertTrue(drop(target, &list, x: 1, y: 2))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { !fired.isEmpty }))
        XCTAssertEqual(fired.first?.context?["items"] as? [String], ["/tmp/report.txt", "https://example.com/remote.txt"])
    }

    func testTheTargetedStateIsReportedOnlyWhenItChanges() throws {
        let root = try render(zone(#"["public.plain-text", "public.folder"]"#))
        let target = try XCTUnwrap(dropTarget(root))
        // Both kinds, files first: a GTK file drag also offers its paths as one text.
        XCTAssertEqual(try gtypes(target), [gdk_file_list_get_type(), g_type_from_name("gchararray")])
        // No drag over it: a notification without a drag (as a drag moving from the frame onto the
        // overlay view makes on the frame) changes nothing, so nothing is reported. (A real drag's
        // true, then false, is the probe's: a current drop cannot be set here.)
        g_object_notify(target.assumingMemoryBound(to: GObject.self), "current-drop")
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: 100)
        XCTAssertEqual(fired.map(\.actionID), [])
    }

    func testAURLTakesAURIListAndAnItemBothKinds() throws {
        // On Apple a file URL is a URL and text is not; every type is an item.
        let url = try render(zone(#"["public.url"]"#))
        XCTAssertEqual(try gtypes(try XCTUnwrap(dropTarget(url))), [gdk_file_list_get_type()])
        let item = try render(zone(#"["public.item"]"#))
        XCTAssertEqual(try gtypes(try XCTUnwrap(dropTarget(item))), [gdk_file_list_get_type(), g_type_from_name("gchararray")])
    }

    func testTypesLinuxDoesNotTakeGiveNoTarget() throws {
        let root = try render(zone(#"["public.png"]"#))
        XCTAssertNil(dropTarget(root))
    }
}
