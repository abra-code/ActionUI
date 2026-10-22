// Tests/Elements/SliderRendererTests.swift
/*
 Tests for the Slider renderer on GTK: a horizontal scale over the range, without its value drawn,
 greedy in width only; the position follows the value, else the value property, and a host value
 fires nothing; moving it sets the value and fires valueChangeActionID; with a step, a dragged
 position snaps to the nearest step and the arrow keys move by the step; a new range applies.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class SliderRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var fired: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "slider-\(name)"
        fired = []
        ActionUIModel.shared.registerActionHandler(for: "test.moved") { [weak self] actionID, _, _, _, _ in
            MainActor.assumeIsolated { self?.fired.append(actionID) }
        }
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIModel.shared.unregisterActionHandler(for: "test.moved")
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func range(_ node: RenderNode) -> UnsafeMutablePointer<GtkRange> {
        typed(node.widget)
    }

    private func value(_ id: Int = 1) -> Double? {
        ActionUIModel.shared.windowModels[windowUUID]?.viewModels[id]?.value as? Double
    }

    func testAScaleOverTheRangeAtTheValue() throws {
        let node = try render(#"{"type": "Slider", "id": 1, "properties": {"value": 25, "range": {"min": 0, "max": 100}}}"#)
        let adjustment = try XCTUnwrap(gtk_range_get_adjustment(range(node)))
        XCTAssertEqual(gtk_adjustment_get_lower(adjustment), 0)
        XCTAssertEqual(gtk_adjustment_get_upper(adjustment), 100)
        XCTAssertEqual(gtk_range_get_value(range(node)), 25, "no value: the value property")
        XCTAssertEqual(gtk_scale_get_draw_value(typed(node.widget)), 0, "no value drawn, as in SwiftUI")
        XCTAssertNotEqual(gtk_widget_get_hexpand(node.widget), 0, "greedy in width")
        XCTAssertEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_VERTICAL), 0)

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: 60.0)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_range_get_value(range(node)), 60)
        XCTAssertTrue(fired.isEmpty, "host values fire nothing")
    }

    func testMovingSetsTheValueAndFires() throws {
        let node = try render(#"{"type": "Slider", "id": 1, "properties": {"valueChangeActionID": "test.moved"}}"#)
        gtk_range_set_value(range(node), 0.4)
        XCTAssertEqual(try XCTUnwrap(value()), 0.4, accuracy: 1e-9)
        XCTAssertEqual(fired, ["test.moved"])
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired.count, 1, "the sync after the move fires nothing")
    }

    func testWithAStepADraggedPositionSnaps() throws {
        let node = try render(#"{"type": "Slider", "id": 1, "properties": {"range": {"min": 0, "max": 10}, "step": 2, "valueChangeActionID": "test.moved"}}"#)
        gtk_range_set_value(range(node), 4.9)
        XCTAssertEqual(value(), 4, "the nearest step")
        XCTAssertEqual(gtk_range_get_value(range(node)), 4, "the scale shows the snapped position")
        XCTAssertEqual(fired, ["test.moved"], "one change, one action")
        let adjustment = try XCTUnwrap(gtk_range_get_adjustment(range(node)))
        XCTAssertEqual(gtk_adjustment_get_step_increment(adjustment), 2, "the arrow keys move by the step")
    }

    func testTheLastStepIsTheLastValidValue() throws {
        // 0...10 by 4: 0, 4, 8 are the valid values (min + n * step), not 10.
        let node = try render(#"{"type": "Slider", "id": 1, "properties": {"range": {"min": 0, "max": 10}, "step": 4}}"#)
        gtk_range_set_value(range(node), 9.9)
        XCTAssertEqual(value(), 8)
        XCTAssertEqual(Slider.snap(0.3, Slider.Props(["range": ["min": 0.0, "max": 0.3], "step": 0.1])), 0.30000000000000004, accuracy: 1e-12,
                       "a whole number of steps that divides to just under it keeps its top step")
    }

    func testSnappingKeepsAValueTheActionSet() throws {
        ActionUIModel.shared.registerActionHandler(for: "test.moved") { [weak self] actionID, windowUUID, _, _, _ in
            MainActor.assumeIsolated {
                self?.fired.append(actionID)
                ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: 8.0)
            }
        }
        let node = try render(#"{"type": "Slider", "id": 1, "properties": {"range": {"min": 0, "max": 10}, "step": 2, "valueChangeActionID": "test.moved"}}"#)
        gtk_range_set_value(range(node), 4.9)
        XCTAssertEqual(fired, ["test.moved"], "snapping the scale fires nothing more")
        XCTAssertEqual(value(), 8, "the value the action set")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_range_get_value(range(node)), 8)
    }

    func testANewRangeApplies() throws {
        let node = try render(#"{"type": "Slider", "id": 1, "properties": {"value": 5, "range": {"min": 0, "max": 10}}}"#)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "range", value: ["min": 0.0, "max": 100.0])
        AdwaitaTestHost.drainMainLoop()
        let adjustment = try XCTUnwrap(gtk_range_get_adjustment(range(node)))
        XCTAssertEqual(gtk_adjustment_get_upper(adjustment), 100)
        XCTAssertEqual(gtk_range_get_value(range(node)), 5)
        XCTAssertTrue(fired.isEmpty)
    }
}
