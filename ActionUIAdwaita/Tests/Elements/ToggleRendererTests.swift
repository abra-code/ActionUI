// Tests/Elements/ToggleRendererTests.swift
/*
 Tests for the Toggle renderer on GTK: no style is a check button, switch a title beside a
 GtkSwitch, button a toggle button, and a style change replaces the widget; on follows the value,
 else isOn, and a host value fires nothing; the user turning it on or off sets the value and fires
 actionID with the state; labelsHidden hides the title of a checkbox or switch, which still names
 the control; no relation to its label outranks accessibilityLabel; no style grows.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ToggleRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var fired: [(actionID: String, context: Bool?)] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "toggle-\(name)"
        fired = []
        ActionUIModel.shared.registerActionHandler(for: "test.toggled") { [weak self] actionID, _, _, _, context in
            let on = context as? Bool
            MainActor.assumeIsolated { self?.fired.append((actionID, on)) }
        }
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIModel.shared.unregisterActionHandler(for: "test.toggled")
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func value(_ id: Int) -> Bool? {
        ActionUIModel.shared.windowModels[windowUUID]?.viewModels[id]?.value as? Bool
    }

    private func isA(_ widget: WidgetPointer, _ type: GType) -> Bool {
        g_type_check_instance_is_a(UnsafeMutablePointer<GTypeInstance>(OpaquePointer(widget)), type) != 0
    }

    private func switchTitle(_ node: RenderNode) throws -> WidgetPointer {
        try XCTUnwrap(gtk_widget_get_first_child(node.widget))
    }

    private func switchWidget(_ node: RenderNode) -> OpaquePointer {
        OpaquePointer(Toggle.accessibleWidget(node.widget))
    }

    func testNoStyleIsACheckButtonThatFollowsTheValue() throws {
        let node = try render(#"{"type": "Toggle", "id": 1, "properties": {"title": "Wi-Fi", "isOn": true}}"#)
        XCTAssertTrue(isA(node.widget, gtk_check_button_get_type()))
        let check: UnsafeMutablePointer<GtkCheckButton> = typed(node.widget)
        XCTAssertEqual(swiftString(gtk_check_button_get_label(check)), "Wi-Fi")
        XCTAssertNotEqual(gtk_check_button_get_active(check), 0, "no value: isOn")

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: false)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_check_button_get_active(check), 0)
        XCTAssertTrue(fired.isEmpty, "host values fire nothing")
    }

    func testCheckingSetsTheValueAndFiresWithTheState() throws {
        let node = try render(#"{"type": "Toggle", "id": 1, "properties": {"style": "checkbox", "actionID": "test.toggled"}}"#)
        let check: UnsafeMutablePointer<GtkCheckButton> = typed(node.widget)
        gtk_check_button_set_active(check, 1)
        XCTAssertEqual(value(1), true)
        XCTAssertEqual(fired.map(\.actionID), ["test.toggled"])
        XCTAssertEqual(fired.first?.context, true)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNotEqual(gtk_check_button_get_active(check), 0)
        XCTAssertEqual(fired.count, 1, "the sync after the change fires nothing")
    }

    func testSwitchShowsTheTitleBesideASwitch() throws {
        let node = try render(#"{"type": "Toggle", "id": 1, "properties": {"style": "switch", "title": "Wi-Fi", "actionID": "test.toggled"}}"#)
        XCTAssertTrue(isA(node.widget, gtk_box_get_type()))
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(try switchTitle(node)))), "Wi-Fi")
        let toggle = switchWidget(node)
        XCTAssertTrue(isA(typed(toggle), gtk_switch_get_type()))
        XCTAssertEqual(gtk_switch_get_active(toggle), 0, "no value, no isOn: off")

        gtk_switch_set_active(toggle, 1)
        XCTAssertEqual(value(1), true)
        XCTAssertEqual(fired.map(\.context), [true])
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: false)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_switch_get_active(toggle), 0)
        XCTAssertEqual(fired.count, 1, "host values fire nothing")
    }

    func testButtonIsAToggleButton() throws {
        let node = try render(#"{"type": "Toggle", "id": 1, "properties": {"style": "button", "title": "Bold", "actionID": "test.toggled"}}"#)
        XCTAssertTrue(isA(node.widget, gtk_toggle_button_get_type()))
        XCTAssertFalse(isA(node.widget, gtk_check_button_get_type()))
        XCTAssertEqual(swiftString(gtk_button_get_label(typed(node.widget))), "Bold")
        gtk_toggle_button_set_active(typed(node.widget), 1)
        XCTAssertEqual(value(1), true)
        XCTAssertEqual(fired.map(\.context), [true])
    }

    func testAStyleChangeReplacesTheWidgetAndKeepsTheState() throws {
        let node = try render(#"{"type": "Toggle", "id": 1, "properties": {"title": "Wi-Fi", "isOn": true}}"#)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "style", value: "switch")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertTrue(isA(node.widget, gtk_box_get_type()))
        XCTAssertNotEqual(gtk_switch_get_active(switchWidget(node)), 0)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "style", value: "button")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertTrue(isA(node.widget, gtk_toggle_button_get_type()))
        XCTAssertNotEqual(gtk_toggle_button_get_active(typed(node.widget)), 0)
        XCTAssertTrue(fired.isEmpty)
    }

    func testLabelsHiddenHidesTheTitleWhichStillNamesTheControl() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "properties": {"labelsHidden": true}, "children": [
              {"type": "Toggle", "id": 2, "properties": {"title": "Wi-Fi"}},
              {"type": "Toggle", "id": 3, "properties": {"title": "Wi-Fi", "style": "switch"}},
              {"type": "Toggle", "id": 4, "properties": {"title": "Bold", "style": "button"}}]}
            """#)
        let check = try XCTUnwrap(root.childNodes[2])
        let row = try XCTUnwrap(root.childNodes[3])
        let button = try XCTUnwrap(root.childNodes[4])
        XCTAssertNil(swiftString(gtk_check_button_get_label(typed(check.widget))))
        XCTAssertEqual(gtk_widget_get_visible(try switchTitle(row)), 0)
        XCTAssertEqual(swiftString(gtk_button_get_label(typed(button.widget))), "Bold", "a button shows its title anyway")
        for accessible in [OpaquePointer(check.widget!), switchWidget(row), OpaquePointer(button.widget!)] {
            XCTAssertNotEqual(gtk_test_accessible_has_property(accessible, GTK_ACCESSIBLE_PROPERTY_LABEL), 0,
                              "the title names the control, shown or not")
        }
    }

    func testAccessibilityLabelIsNotOutrankedByTheTitle() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "Toggle", "id": 2, "properties": {"title": "Wi-Fi", "accessibilityLabel": "Wireless"}},
              {"type": "Toggle", "id": 3, "properties": {"title": "Bold", "style": "button", "accessibilityLabel": "Bold text"}}]}
            """#)
        for id in [2, 3] {
            let node = try XCTUnwrap(root.childNodes[id])
            XCTAssertEqual(gtk_test_accessible_has_relation(OpaquePointer(node.widget), GTK_ACCESSIBLE_RELATION_LABELLED_BY), 0,
                           "Toggle \(id): no relation to its label, which would outrank accessibilityLabel")
            XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(node.widget), GTK_ACCESSIBLE_PROPERTY_LABEL), 0)
        }
    }

    func testNoStyleGrowsWhenOfferedMore() throws {
        for style in ["checkbox", "switch", "button"] {
            let node = try render(#"{"type": "Toggle", "id": 1, "properties": {"title": "Wi-Fi", "style": "\#(style)"}}"#)
            XCTAssertEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_HORIZONTAL), 0, style)
            XCTAssertEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_VERTICAL), 0, style)
        }
    }
}
