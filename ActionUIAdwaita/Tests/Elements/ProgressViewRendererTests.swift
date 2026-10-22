// Tests/Elements/ProgressViewRendererTests.swift
/*
 Tests for the ProgressView renderer on GTK: a bar for a known progress, with the title above it,
 greedy in width; a spinner for an unknown one, 32 x 32 with the title under it; "linear" without a
 progress is a pulsing bar; "circular" with a progress is a ring, a progress bar for assistive
 technologies; states["progress"] moves the bar and can switch the form; the indicator is named
 after the title, which is read once; a click fires actionID.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ProgressViewRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var fired: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "progress-\(name)"
        fired = []
        ActionUIModel.shared.registerActionHandler(for: "test.tapped") { [weak self] actionID, _, _, _, _ in
            MainActor.assumeIsolated { self?.fired.append(actionID) }
        }
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIModel.shared.unregisterActionHandler(for: "test.tapped")
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ properties: String) throws -> RenderNode {
        let json = #"{"type": "ProgressView", "id": 1, "properties": {"# + properties + "}}"
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func indicator(_ node: RenderNode) -> WidgetPointer {
        ProgressView.accessibleWidget(node.widget)
    }

    /// The pixels `widget` paints now, where it is (its window shown).
    private func pixels(of widget: WidgetPointer) throws -> [UInt8] {
        let width = gtk_widget_get_width(widget)
        let height = gtk_widget_get_height(widget)
        let paintable = gtk_widget_paintable_new(widget)!
        defer { g_object_unref(UnsafeMutableRawPointer(paintable)) }
        let snapshot = gtk_snapshot_new()!
        gdk_paintable_snapshot(paintable, snapshot, Double(width), Double(height))
        let node = try XCTUnwrap(gtk_snapshot_free_to_node(snapshot))
        defer { gsk_render_node_unref(node) }
        return try XCTUnwrap(AdwaitaTestHost.pixels(of: node, width: width, height: height))
    }

    private func isA(_ widget: WidgetPointer, _ type: GType) -> Bool {
        g_type_check_instance_is_a(UnsafeMutablePointer<GTypeInstance>(OpaquePointer(widget)), type) != 0
    }

    private func typeName(_ widget: WidgetPointer) -> String {
        String(cString: g_type_name(UnsafeMutablePointer<GTypeInstance>(OpaquePointer(widget)).pointee.g_class.pointee.g_type))
    }

    func testAKnownProgressIsABarUnderItsTitle() throws {
        let node = try render(#""value": 0.25, "title": "Copying""#)
        let bar = indicator(node)
        XCTAssertTrue(isA(bar, gtk_progress_bar_get_type()))
        XCTAssertEqual(gtk_progress_bar_get_fraction(OpaquePointer(bar)), 0.25)
        let title = try XCTUnwrap(gtk_widget_get_first_child(node.widget))
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(title))), "Copying", "the title above the bar")
        XCTAssertNotEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_HORIZONTAL), 0, "greedy in width")

        _ = ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: 1, key: "progress", value: 0.5)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_progress_bar_get_fraction(OpaquePointer(indicator(node))), 0.5)
    }

    func testAnUnknownProgressIsASpinnerAboveItsTitle() throws {
        let node = try render(#""title": "Loading""#)
        let spinner = indicator(node)
        XCTAssertEqual(typeName(spinner), "AdwSpinner")
        var width: Int32 = 0
        var height: Int32 = 0
        gtk_widget_get_size_request(spinner, &width, &height)
        XCTAssertEqual([width, height], [32, 32])
        let title = try XCTUnwrap(gtk_widget_get_last_child(node.widget))
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(title))), "Loading", "the title under the spinner")
        XCTAssertEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_HORIZONTAL), 0)

        _ = ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: 1, key: "progress", value: 0.5)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertTrue(isA(indicator(node), gtk_progress_bar_get_type()), "a progress arrives: a bar")
    }

    func testLinearWithoutAProgressPulses() throws {
        let node = try render(#""progressViewStyle": "linear""#)
        let bar = indicator(node)
        XCTAssertTrue(isA(bar, gtk_progress_bar_get_type()))
        let window = gtk_window_new()!
        defer { gtk_window_destroy(typed(window)) }
        gtk_window_set_child(typed(window), node.outerWidget)
        defer { gtk_window_set_child(typed(window), nil) }
        gtk_window_present(typed(window))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(bar) != 0 }))
        AdwaitaTestHost.drainMainLoop()
        // The pulse moves the activity block: two drawings 300 ms apart differ.
        let first = try pixels(of: bar)
        let deadline = g_get_monotonic_time() + 300_000
        _ = AdwaitaTestHost.runMainLoop(until: { g_get_monotonic_time() >= deadline })
        XCTAssertNotEqual(try pixels(of: bar), first, "the bar pulses")
        _ = ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: 1, key: "progress", value: 0.4)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_progress_bar_get_fraction(OpaquePointer(indicator(node))), 0.4, "a progress stops the pulse and shows")
    }

    /// Whether `widget` or a widget inside it has the CSS class `name`.
    private func hasClass(_ widget: WidgetPointer, _ name: String) -> Bool {
        if gtk_widget_has_css_class(widget, name) != 0 { return true }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if hasClass(current, name) { return true }
            child = gtk_widget_get_next_sibling(current)
        }
        return false
    }

    func testAProgressOfTheFractionTheBarHadStopsThePulse() throws {
        // The bar pulses at fraction 0; a progress of 0 must still leave the activity mode, which
        // only gtk_progress_bar_set_fraction does.
        let node = try render(#""progressViewStyle": "linear""#)
        let bar = indicator(node)
        let window = gtk_window_new()!
        defer { gtk_window_destroy(typed(window)) }
        gtk_window_set_child(typed(window), node.outerWidget)
        defer { gtk_window_set_child(typed(window), nil) }
        gtk_window_present(typed(window))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { hasClass(bar, "pulse") }), "the bar pulses")
        _ = ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: 1, key: "progress", value: 0.0)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertFalse(hasClass(indicator(node), "pulse"), "a progress of 0 stops the pulse")
    }

    func testCircularWithAProgressIsARing() throws {
        let node = try render(#""value": 0.5, "progressViewStyle": "circular", "title": "Half""#)
        let ring = indicator(node)
        XCTAssertEqual(typeName(ring), "ActionUIProgressRing")
        XCTAssertEqual(gtk_accessible_get_accessible_role(OpaquePointer(ring)), GTK_ACCESSIBLE_ROLE_PROGRESS_BAR)
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(ring), GTK_ACCESSIBLE_PROPERTY_VALUE_NOW), 0)
        let drawing = try XCTUnwrap(AdwaitaTestHost.drawing(of: ring, shownIn: node.outerWidget), "the ring drew nothing")
        defer { gsk_render_node_unref(drawing.node) }
        let pixels = try XCTUnwrap(AdwaitaTestHost.pixels(of: drawing.node, width: drawing.width, height: drawing.height))
        let width = Int(drawing.width)
        func alpha(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }
        // Half: the right side of the ring is drawn strong, the left only as the faint track.
        XCTAssertGreaterThan(alpha(width - 2, Int(drawing.height) / 2), 200)
        XCTAssertLessThan(alpha(1, Int(drawing.height) / 2), 100)
    }

    func testARingAtZeroHasAValueForAssistiveTechnologies() throws {
        let node = try render(#""value": 0, "progressViewStyle": "circular""#)
        let ring = indicator(node)
        XCTAssertEqual(typeName(ring), "ActionUIProgressRing")
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(ring), GTK_ACCESSIBLE_PROPERTY_VALUE_NOW), 0)
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(ring), GTK_ACCESSIBLE_PROPERTY_VALUE_MAX), 0)
    }

    func testTheIndicatorIsNamedAfterTheTitleAndAClickFires() throws {
        let node = try render(#""value": 0.5, "title": "Copying", "actionID": "test.tapped""#)
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(indicator(node)), GTK_ACCESSIBLE_PROPERTY_LABEL), 0)
        let title = try XCTUnwrap(gtk_widget_get_first_child(node.widget))
        XCTAssertEqual(gtk_accessible_get_accessible_role(OpaquePointer(title)), GTK_ACCESSIBLE_ROLE_PRESENTATION)

        // The click gesture's "released" with its arguments (press count, x, y).
        let controllers = gtk_widget_observe_controllers(node.widget)!
        defer { g_object_unref(UnsafeMutableRawPointer(controllers)) }
        let gesture = try XCTUnwrap(g_list_model_get_item(controllers, 0))
        defer { g_object_unref(gesture) }
        let type = gesture.assumingMemoryBound(to: GTypeInstance.self).pointee.g_class.pointee.g_type
        var values = [GValue(), GValue(), GValue(), GValue()]
        g_value_init(&values[0], type)
        g_value_set_object(&values[0], gesture)
        g_value_init(&values[1], g_type_from_name("gint"))
        g_value_set_int(&values[1], 1)
        g_value_init(&values[2], g_type_from_name("gdouble"))
        g_value_init(&values[3], g_type_from_name("gdouble"))
        g_signal_emitv(&values, g_signal_lookup("released", type), 0, nil)
        for index in values.indices { g_value_unset(&values[index]) }
        XCTAssertEqual(fired, ["test.tapped"])
    }

    func testAnEmptyTitleStillTakesItsLine() throws {
        // Measured on macOS 27: a bar with "title": "" is 34 points tall, 20 without a title.
        let titled = try render(#""value": 0.5, "title": """#)
        let label = try XCTUnwrap(gtk_widget_get_first_child(titled.widget))
        XCTAssertNotEqual(gtk_widget_get_visible(label), 0)
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(label, GTK_ORIENTATION_VERTICAL, -1, &minimum, &natural, nil, nil)
        XCTAssertGreaterThan(natural, 10, "an empty label is a line tall")
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let untitled = try render(#""value": 0.5"#)
        XCTAssertEqual(gtk_widget_get_visible(try XCTUnwrap(gtk_widget_get_first_child(untitled.widget))), 0)
    }
}
