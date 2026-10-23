// Tests/Elements/ColorPickerRendererTests.swift
/*
 Tests for the ColorPicker renderer on GTK: the title beside a GtkColorDialogButton showing the
 value, else selectedColor, and a host value fires nothing; picking a color sets the value and fires
 actionID once; labelsHidden or an empty title hides the title, which still names the button; it
 does not grow.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ColorPickerRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var fired: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "colorpicker-\(name)"
        fired = []
        ActionUIModel.shared.registerActionHandler(for: "test.picked") { [weak self] actionID, _, _, _, _ in
            MainActor.assumeIsolated { self?.fired.append(actionID) }
        }
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIModel.shared.unregisterActionHandler(for: "test.picked")
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func title(_ node: RenderNode) throws -> WidgetPointer {
        try XCTUnwrap(gtk_widget_get_first_child(node.widget))
    }

    private func button(_ node: RenderNode) -> OpaquePointer {
        OpaquePointer(ColorPicker.accessibleWidget(node.widget))
    }

    /// The color the button shows, as [red, green, blue, alpha] in whole 255ths.
    private func shown(_ node: RenderNode) throws -> [Int] {
        let rgba = try XCTUnwrap(gtk_color_dialog_button_get_rgba(button(node))).pointee
        return [rgba.red, rgba.green, rgba.blue, rgba.alpha].map { Int(($0 * 255).rounded()) }
    }

    func testShowsTheTitleAndTheColorAndFollowsTheValue() throws {
        let node = try render(##"{"type": "ColorPicker", "id": 1, "properties": {"title": "Tint", "selectedColor": "#FF8000", "actionID": "test.picked"}}"##)
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(try title(node)))), "Tint")
        XCTAssertNotEqual(gtk_widget_get_visible(try title(node)), 0)
        XCTAssertEqual(try shown(node), [255, 128, 0, 255])
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1,
                                             value: ColorSpec.rgba(red: 0, green: 0, blue: 1, alpha: 0.5))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try shown(node), [0, 0, 255, 128])
        XCTAssertTrue(fired.isEmpty, "a host value fires nothing")
    }

    func testPickingSetsTheValueAndFiresOnce() throws {
        let node = try render(#"{"type": "ColorPicker", "id": 1, "properties": {"selectedColor": "red", "actionID": "test.picked"}}"#)
        var green = GdkRGBA(red: 0, green: 1, blue: 0, alpha: 1)
        gtk_color_dialog_button_set_rgba(button(node), &green)
        let value = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1]?.value as? ColorSpec
        XCTAssertEqual(value, .rgba(red: 0, green: 1, blue: 0, alpha: 1))
        XCTAssertEqual(fired, ["test.picked"])
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try shown(node), [0, 255, 0, 255])
        XCTAssertEqual(fired.count, 1, "the sync after the change fires nothing")
    }

    func testAPickedFractionRoundTripsWithoutASecondSet() throws {
        // GdkRGBA is Float and ColorSpec Double: the picked value is the Float exactly, so the update
        // after the pick sees the same color and neither sets it again nor fires again.
        let node = try render(#"{"type": "ColorPicker", "id": 1, "properties": {"actionID": "test.picked"}}"#)
        var picked = GdkRGBA(red: 0.3, green: 0.6, blue: 0.9, alpha: 0.7)
        gtk_color_dialog_button_set_rgba(button(node), &picked)
        let value = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1]?.value as? ColorSpec
        XCTAssertEqual(value, .rgba(red: Double(Float(0.3)), green: Double(Float(0.6)), blue: Double(Float(0.9)),
                                    alpha: Double(Float(0.7))))
        AdwaitaTestHost.drainMainLoop()
        let notifications = CallCounter()
        connectSignal(UnsafeMutableRawPointer(button(node)), "notify::rgba", .instanceAndArgument) { notifications.count += 1 }
        ColorPicker.update(node.widget, node)
        XCTAssertEqual(notifications.count, 0, "the update sets nothing")
        XCTAssertEqual(fired, ["test.picked"])
    }

    func testAHiddenOrEmptyTitleStillNamesTheButton() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "ColorPicker", "id": 2, "properties": {"title": "Tint", "labelsHidden": true}},
              {"type": "ColorPicker", "id": 3, "properties": {}},
              {"type": "ColorPicker", "id": 4, "properties": {"title": "Fill"}}]}
            """#)
        let hidden = try XCTUnwrap(root.childNodes[2])
        let untitled = try XCTUnwrap(root.childNodes[3])
        let titled = try XCTUnwrap(root.childNodes[4])
        XCTAssertEqual(gtk_widget_get_visible(try title(hidden)), 0, "labelsHidden")
        XCTAssertEqual(gtk_widget_get_visible(try title(untitled)), 0, "no title")
        XCTAssertEqual(try shown(untitled)[3], 0, "no color: clear")
        for node in [hidden, titled] {
            XCTAssertNotEqual(gtk_test_accessible_has_property(button(node), GTK_ACCESSIBLE_PROPERTY_LABEL), 0,
                              "the title names the button, shown or not")
        }
        XCTAssertEqual(gtk_accessible_get_accessible_role(OpaquePointer(try title(titled))), GTK_ACCESSIBLE_ROLE_PRESENTATION,
                       "the title is not read a second time")
    }

    func testDoesNotGrowWhenOfferedMore() throws {
        let node = try render(#"{"type": "ColorPicker", "id": 1, "properties": {"title": "Tint"}}"#)
        XCTAssertEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_HORIZONTAL), 0)
        XCTAssertEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_VERTICAL), 0)
    }
}
