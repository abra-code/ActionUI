// Tests/Elements/StepperRendererTests.swift
/*
 Tests for the Stepper renderer on GTK: the label, then minus and plus buttons; labelFormat puts the
 value in the label, a refused format shows the plain value; a button steps by step, kept in the
 range, and fires actionID with the value; a button is disabled at its end of the range; a host
 value fires nothing; labelsHidden hides the label, which still names the group; the buttons are
 named Decrement and Increment; it does not grow.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class StepperRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var fired: [(actionID: String, context: Double?)] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "stepper-\(name)"
        fired = []
        ActionUIModel.shared.registerActionHandler(for: "test.stepped") { [weak self] actionID, _, _, _, context in
            let value = context as? Double
            MainActor.assumeIsolated { self?.fired.append((actionID, value)) }
        }
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIModel.shared.unregisterActionHandler(for: "test.stepped")
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func parts(_ node: RenderNode) throws -> (label: WidgetPointer, minus: WidgetPointer, plus: WidgetPointer) {
        let label = try XCTUnwrap(gtk_widget_get_first_child(node.widget))
        let buttons = try XCTUnwrap(gtk_widget_get_last_child(node.widget))
        return (label, try XCTUnwrap(gtk_widget_get_first_child(buttons)), try XCTUnwrap(gtk_widget_get_last_child(buttons)))
    }

    private func labelText(_ node: RenderNode) throws -> String? {
        swiftString(gtk_label_get_text(opaque(try parts(node).label)))
    }

    private func value() -> Double? {
        ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1]?.value as? Double
    }

    func testTheButtonsStepInTheRangeAndFire() throws {
        let node = try render(#"{"type": "Stepper", "id": 1, "properties": {"value": 8, "range": {"min": 0, "max": 9}, "step": 2, "labelFormat": "Qty: %.0f", "actionID": "test.stepped"}}"#)
        let (_, minus, plus) = try parts(node)
        XCTAssertEqual(try labelText(node), "Qty: 8")
        AdwaitaTestHost.emit("clicked", on: plus)
        XCTAssertEqual(value(), 9, "kept in the range")
        XCTAssertEqual(fired.map(\.context), [9])
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try labelText(node), "Qty: 9")
        XCTAssertEqual(gtk_widget_get_sensitive(plus), 0, "disabled at the top of the range")
        XCTAssertNotEqual(gtk_widget_get_sensitive(minus), 0)
        AdwaitaTestHost.emit("clicked", on: minus)
        XCTAssertEqual(value(), 7)
        XCTAssertEqual(fired.map(\.context), [9, 7])

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: 0.0)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try labelText(node), "Qty: 0")
        XCTAssertEqual(gtk_widget_get_sensitive(minus), 0, "disabled at the bottom of the range")
        XCTAssertEqual(fired.count, 2, "host values fire nothing")
    }

    func testWithoutARangeNothingIsDisabledAndTheLabelIsPlain() throws {
        let node = try render(#"{"type": "Stepper", "id": 1, "properties": {"label": "Count"}}"#)
        let (_, minus, plus) = try parts(node)
        XCTAssertEqual(try labelText(node), "Count")
        AdwaitaTestHost.emit("clicked", on: minus)
        XCTAssertEqual(value(), -1, "unbounded")
        XCTAssertNotEqual(gtk_widget_get_sensitive(minus), 0)
        XCTAssertNotEqual(gtk_widget_get_sensitive(plus), 0)
        XCTAssertEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_HORIZONTAL), 0, "it does not grow")
    }

    func testARefusedFormatShowsThePlainValue() throws {
        let node = try render(#"{"type": "Stepper", "id": 1, "properties": {"value": 2.5, "labelFormat": "%@ items"}}"#)
        XCTAssertEqual(try labelText(node), "2.5")
    }

    func testTheGroupIsNamedAfterItsLabelAndTheButtonsAreNamed() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "properties": {"labelsHidden": true}, "children": [
              {"type": "Stepper", "id": 2, "properties": {"label": "Count"}}]}
            """#)
        let node = try XCTUnwrap(root.childNodes[2])
        let (label, minus, plus) = try parts(node)
        XCTAssertEqual(gtk_widget_get_visible(label), 0, "labelsHidden hides the label")
        XCTAssertEqual(gtk_accessible_get_accessible_role(OpaquePointer(node.widget)), GTK_ACCESSIBLE_ROLE_GROUP)
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(node.widget), GTK_ACCESSIBLE_PROPERTY_LABEL), 0,
                          "the label still names the group")
        XCTAssertEqual(gtk_accessible_get_accessible_role(OpaquePointer(label)), GTK_ACCESSIBLE_ROLE_PRESENTATION)
        for button in [minus, plus] {
            XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(button), GTK_ACCESSIBLE_PROPERTY_LABEL), 0)
        }
    }
}
