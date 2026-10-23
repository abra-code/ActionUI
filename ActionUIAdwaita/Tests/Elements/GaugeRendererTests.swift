// Tests/Elements/GaugeRendererTests.swift
/*
 Tests for the Gauge renderer on GTK: no style is a level bar under a centered title, over the
 range, greedy in width, one color for any value; accessoryLinearCapacity the same with a leading
 title; accessoryLinear a drawn bar without a title; the circular styles 58 x 58 drawings with the
 title over them; a value outside the range shows at its end; a range below 0 shows in the level bar
 moved to start at 0; a host value moves the gauge; the drawings are meters with their value, named
 after the title, which is read once.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class GaugeRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "gauge-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ properties: String) throws -> RenderNode {
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let json = #"{"type": "Gauge", "id": 1, "properties": {"# + properties + "}}"
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func meter(_ node: RenderNode) -> WidgetPointer {
        Gauge.accessibleWidget(node.widget)
    }

    private func typeName(_ widget: WidgetPointer) -> String {
        String(cString: g_type_name(UnsafeMutablePointer<GTypeInstance>(OpaquePointer(widget)).pointee.g_class.pointee.g_type))
    }

    func testNoStyleIsALevelBarUnderACenteredTitle() throws {
        let node = try render(#""value": 30, "range": {"min": 0, "max": 100}, "title": "Disk""#)
        let bar = OpaquePointer(meter(node))
        XCTAssertEqual(typeName(meter(node)), "GtkLevelBar")
        XCTAssertEqual(gtk_level_bar_get_max_value(bar), 100)
        XCTAssertEqual(gtk_level_bar_get_value(bar), 30)
        var offset = 0.0
        XCTAssertEqual(gtk_level_bar_get_offset_value(bar, GTK_LEVEL_BAR_OFFSET_HIGH, &offset), 0, "one color for any value")
        let title = try XCTUnwrap(gtk_widget_get_first_child(node.widget))
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(title))), "Disk")
        XCTAssertEqual(gtk_label_get_xalign(opaque(title)), 0.5, "centered, as macOS puts it")
        XCTAssertEqual(gtk_accessible_get_accessible_role(OpaquePointer(title)), GTK_ACCESSIBLE_ROLE_PRESENTATION)
        XCTAssertNotEqual(gtk_test_accessible_has_property(bar, GTK_ACCESSIBLE_PROPERTY_LABEL), 0, "the bar is named after the title")
        XCTAssertNotEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_HORIZONTAL), 0, "greedy in width")

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: 150.0)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_level_bar_get_value(OpaquePointer(meter(node))), 100, "outside the range: at its end")
    }

    func testLinearCapacityHasALeadingTitle() throws {
        let node = try render(#""value": 0.5, "title": "Disk", "style": "accessoryLinearCapacity""#)
        XCTAssertEqual(typeName(meter(node)), "GtkLevelBar")
        XCTAssertEqual(gtk_label_get_xalign(opaque(try XCTUnwrap(gtk_widget_get_first_child(node.widget)))), 0)
    }

    func testLinearIsADrawnBarWithoutATitle() throws {
        let node = try render(#""value": 0.5, "title": "Disk", "style": "accessoryLinear""#)
        XCTAssertEqual(typeName(node.widget), "ActionUIGauge")
        XCTAssertEqual(gtk_accessible_get_accessible_role(OpaquePointer(node.widget)), GTK_ACCESSIBLE_ROLE_METER)
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(node.widget), GTK_ACCESSIBLE_PROPERTY_LABEL), 0,
                          "no title shown, but it names the meter")
        XCTAssertNotEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_HORIZONTAL), 0)
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(node.widget, GTK_ORIENTATION_VERTICAL, -1, &minimum, &natural, nil, nil)
        XCTAssertEqual(natural, 8, "8 points tall, as on macOS")
    }

    func testTheCircularStylesAreDrawingsWithTheTitleOverThem() throws {
        for (style, align) in [("accessoryCircular", GTK_ALIGN_END), ("accessoryCircularCapacity", GTK_ALIGN_CENTER)] {
            let node = try render(#""value": 0.25, "title": "Disk", "style": "\#(style)""#)
            let drawing = meter(node)
            XCTAssertEqual(typeName(drawing), "ActionUIGauge", style)
            var width: Int32 = 0
            var height: Int32 = 0
            gtk_widget_get_size_request(drawing, &width, &height)
            XCTAssertEqual([width, height], [58, 58], style)
            let title = try XCTUnwrap(gtk_widget_get_last_child(node.widget))
            XCTAssertEqual(swiftString(gtk_label_get_text(opaque(title))), "Disk", style)
            XCTAssertEqual(gtk_widget_get_valign(title), align, style)
            XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(drawing), GTK_ACCESSIBLE_PROPERTY_VALUE_NOW), 0, style)
            let painted = try XCTUnwrap(AdwaitaTestHost.drawing(of: drawing, shownIn: node.outerWidget), "\(style) drew nothing")
            gsk_render_node_unref(painted.node)
        }
    }

    func testARangeBelowZeroIsShownInTheLevelBar() throws {
        // GtkLevelBar refuses a negative minimum: the bar shows the range moved to start at 0.
        let node = try render(#""value": -5, "range": {"min": -20, "max": 40}"#)
        let bar = OpaquePointer(meter(node))
        XCTAssertEqual([gtk_level_bar_get_min_value(bar), gtk_level_bar_get_max_value(bar), gtk_level_bar_get_value(bar)], [0, 60, 15])
        XCTAssertNotEqual(gtk_test_accessible_has_property(bar, GTK_ACCESSIBLE_PROPERTY_VALUE_NOW), 0)

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: -30.0)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_level_bar_get_value(OpaquePointer(meter(node))), 0, "below the range: at its start")
    }

    func testAGaugeAtItsMinimumHasAValueForAssistiveTechnologies() throws {
        let node = try render(#""value": 0, "range": {"min": 0, "max": 100}, "style": "accessoryCircularCapacity""#)
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(meter(node)), GTK_ACCESSIBLE_PROPERTY_VALUE_NOW), 0)
        // The range written is the gauge's, not a default, also before the value first changes.
        XCTAssertEqual(attached(on: meter(node), key: gaugeStateKey)?.accessibleValue, [0, 100, 0])
    }
}
