// Tests/Elements/ControlTitleGapTests.swift
/*
 The title of a control with a title beside it (Picker, ColorPicker, a switch Toggle, Stepper,
 DatePicker), on GTK as measured on macOS 27: an empty title stays, 0 wide, so the control starts 8
 points in, as SwiftUI keeps the gap; labelsHidden takes the title and the gap away.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ControlTitleGapTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "title-gap-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIRegistry.shared.loadBuiltIns()
    }

    /// Where the control (the box's last part) starts in the box, laid out at its natural size.
    private func controlStart(_ json: String) throws -> Int {
        ActionUIModel.shared.windowModels[windowUUID] = nil
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        let box = try XCTUnwrap(window.root?.widget)
        var minimum: Int32 = 0
        var width: Int32 = 0
        var height: Int32 = 0
        gtk_widget_measure(box, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &width, nil, nil)
        gtk_widget_measure(box, GTK_ORIENTATION_VERTICAL, width, &minimum, &height, nil, nil)
        gtk_widget_allocate(box, width, height, -1, nil)
        var bounds = graphene_rect_t()
        _ = gtk_widget_compute_bounds(try XCTUnwrap(gtk_widget_get_last_child(box)), box, &bounds)
        return Int(bounds.origin.x)
    }

    private let controls = [
        #"{"type": "Picker", "id": 1, "properties": {"title": "", "options": ["One"]"#,
        #"{"type": "ColorPicker", "id": 1, "properties": {"title": """#,
        #"{"type": "Toggle", "id": 1, "properties": {"title": "", "style": "switch""#,
        #"{"type": "Stepper", "id": 1, "properties": {"label": """#,
        #"{"type": "DatePicker", "id": 1, "properties": {"title": "", "selectedDate": "2024-07-16""#,
    ]

    func testAnEmptyTitleKeepsItsGap() throws {
        for control in controls {
            XCTAssertEqual(try controlStart(control + "}}"), 8, control)
        }
    }

    func testHiddenLabelsTakeTheGapAway() throws {
        for control in controls {
            XCTAssertEqual(try controlStart(control + #", "labelsHidden": true}}"#), 0, control)
        }
    }
}
