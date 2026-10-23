// Tests/Elements/PickerRendererTests.swift
/*
 Tests for the Picker renderer on GTK. The menu style: the options are the dropdown's items and the
 value selects one (the first option without a value, none for a value that is no tag); the title
 is shown beside the dropdown, hidden by labelsHidden, and names the dropdown either way; choosing
 an item sets the value and fires actionID with the tag, and a host value fires nothing; sections
 give the popup headers; changed options rebuild the items. The other styles: wheel is the menu;
 segments and radio buttons (under headings) show the items and follow the value the same way; a
 radio group's title is beside its first row.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class PickerRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var fired: [(actionID: String, context: String?)] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "picker-\(name)"
        fired = []
        ActionUIModel.shared.registerActionHandler(for: "test.chosen") { [weak self] actionID, _, _, _, context in
            let tag = context as? String
            MainActor.assumeIsolated { self?.fired.append((actionID, tag)) }
        }
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIModel.shared.unregisterActionHandler(for: "test.chosen")
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func dropdown(_ node: RenderNode) -> OpaquePointer {
        OpaquePointer(Picker.accessibleWidget(node.widget))
    }

    private func title(_ node: RenderNode) -> WidgetPointer? {
        gtk_widget_get_first_child(node.widget)
    }

    private func items(_ node: RenderNode) -> [String] {
        guard let model = gtk_drop_down_get_model(dropdown(node)) else { return [] }
        return (0..<g_list_model_get_n_items(model)).compactMap { index in
            guard let item = g_list_model_get_item(model, index) else { return nil }
            defer { g_object_unref(item) }
            return swiftString(gtk_string_object_get_string(OpaquePointer(item)))
        }
    }

    private func selected(_ node: RenderNode) -> UInt32 {
        gtk_drop_down_get_selected(dropdown(node))
    }

    func testTheOptionsAndTheSelection() throws {
        let node = try render(#"{"type": "Picker", "id": 1, "properties": {"title": "Size", "options": ["Small", "Large"]}}"#)
        XCTAssertEqual(items(node), ["Small", "Large"])
        XCTAssertEqual(selected(node), 0, "no value: the first option")

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "2")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(selected(node), 1)
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "9")
        AdwaitaTestHost.drainMainLoop()
        // GtkDropDown always keeps an item selected (macOS shows an empty pop-up instead).
        XCTAssertEqual(selected(node), 1, "a value that is no tag leaves the dropdown on the item it showed")
        XCTAssertTrue(fired.isEmpty, "host values fire nothing")
    }

    func testTheTitleIsShownUnlessHiddenAndNamesTheDropdown() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "Picker", "id": 2, "properties": {"title": "Size", "options": ["S"]}},
              {"type": "Picker", "id": 3, "properties": {"title": "Size", "options": ["S"], "labelsHidden": true}}]}
            """#)
        let shown = try XCTUnwrap(root.childNodes[2])
        let hidden = try XCTUnwrap(root.childNodes[3])
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(try XCTUnwrap(title(shown))))), "Size")
        XCTAssertNotEqual(gtk_widget_get_visible(try XCTUnwrap(title(shown))), 0)
        XCTAssertEqual(gtk_widget_get_visible(try XCTUnwrap(title(hidden))), 0)
        for node in [shown, hidden] {
            XCTAssertNotEqual(gtk_test_accessible_has_property(dropdown(node), GTK_ACCESSIBLE_PROPERTY_LABEL), 0,
                              "the title names the dropdown, shown or not")
            XCTAssertEqual(gtk_test_accessible_has_relation(dropdown(node), GTK_ACCESSIBLE_RELATION_LABELLED_BY), 0,
                           "no relation to the item shown, which would outrank the label")
        }
    }

    func testChoosingAnItemSetsTheValueAndFiresWithTheTag() throws {
        let node = try render(#"{"type": "Picker", "id": 1, "properties": {"options": [{"title": "Yes", "tag": "y"}, {"title": "No", "tag": "n"}], "actionID": "test.chosen"}}"#)
        gtk_drop_down_set_selected(dropdown(node), 1)
        XCTAssertEqual(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1]?.value as? String, "n")
        XCTAssertEqual(fired.map(\.actionID), ["test.chosen"])
        XCTAssertEqual(fired.first?.context, "n")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(selected(node), 1)
        XCTAssertEqual(fired.count, 1, "the sync after the choice fires nothing")
    }

    func testSectionsGiveThePopupHeadersAndNewOptionsRebuildTheItems() throws {
        let node = try render(#"""
            {"type": "Picker", "id": 1, "properties": {"options": [
              {"section": "Popular"}, {"title": "HTML", "tag": "html"}, {"divider": true}, {"title": "XML", "tag": "xml"}]}}
            """#)
        XCTAssertEqual(items(node), ["HTML", "XML"])
        XCTAssertNotNil(gtk_drop_down_get_header_factory(dropdown(node)), "sections: the popup has headers")

        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "options", value: ["A", "B", "C"])
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(items(node), ["A", "B", "C"])
        XCTAssertNil(gtk_drop_down_get_header_factory(dropdown(node)), "a plain list: no headers")
    }

    // MARK: Styles

    private var value: String? {
        ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1]?.value as? String
    }

    private func isA(_ widget: WidgetPointer, _ type: GType) -> Bool {
        g_type_check_instance_is_a(UnsafeMutablePointer<GTypeInstance>(OpaquePointer(widget)), type) != 0
    }

    private func children(_ widget: WidgetPointer) -> [WidgetPointer] {
        var result: [WidgetPointer] = []
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            result.append(current)
            child = gtk_widget_get_next_sibling(current)
        }
        return result
    }

    private let sized = #"[{"title": "Small", "tag": "s"}, {"title": "Medium", "tag": "m"}, {"title": "Large", "tag": "l"}]"#

    func testTheWheelStyleIsTheMenu() throws {
        // macOS has no wheel style and shows the menu (measured on macOS 27).
        let node = try render(#"{"type": "Picker", "id": 1, "properties": {"title": "Size", "options": ["S"], "pickerStyle": "wheel"}}"#)
        XCTAssertTrue(isA(Picker.accessibleWidget(node.widget), gtk_drop_down_get_type()))
    }

    func testSegmentsShowTheOptionsAndFollowTheValue() throws {
        let node = try render(#"{"type": "Picker", "id": 1, "properties": {"title": "Size", "options": \#(sized), "pickerStyle": "segmented", "actionID": "test.chosen"}}"#)
        let group = OpaquePointer(Picker.accessibleWidget(node.widget))
        XCTAssertEqual(adw_toggle_group_get_n_toggles(group), 3)
        XCTAssertEqual(adw_toggle_group_get_homogeneous(group), 1, "equal segments, as macOS's")
        XCTAssertEqual(swiftString(adw_toggle_group_get_active_name(group)), "s", "the first option by default")

        adw_toggle_group_set_active_name(group, "l")
        XCTAssertEqual(value, "l")
        XCTAssertEqual(fired.map(\.context), ["l"], "the user's pick fires once, with the tag")

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "m")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(swiftString(adw_toggle_group_get_active_name(group)), "m")
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "nothing")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(adw_toggle_group_get_active(group), Picker.noSelection, "no segment for a value that is no tag")
        XCTAssertEqual(fired.count, 1, "host values fire nothing")
    }

    func testRadioButtonsShowTheOptionsUnderHeadings() throws {
        // Owner decision: section titles are headings, not the radio rows SwiftUI draws.
        let node = try render(#"{"type": "Picker", "id": 1, "properties": {"title": "Size", "options": [{"section": "First"}, {"title": "A", "tag": "a"}, {"title": "B", "tag": "b"}, {"section": "Second"}, {"title": "C", "tag": "c"}], "pickerStyle": "radioGroup", "actionID": "test.chosen"}}"#)
        let column = Picker.accessibleWidget(node.widget)
        let rows = children(column)
        XCTAssertEqual(rows.map { isA($0, gtk_check_button_get_type()) }, [false, true, true, false, true])
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(rows[0]))), "First")
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(rows[3]))), "Second")
        let radios = [rows[1], rows[2], rows[4]]
        XCTAssertEqual(radios.map { gtk_check_button_get_active(typed($0)) }, [1, 0, 0])

        gtk_check_button_set_active(typed(radios[1]), 1)
        XCTAssertEqual(value, "b")
        XCTAssertEqual(fired.map(\.context), ["b"], "one pick, one action (the button turned off fires nothing)")
        XCTAssertEqual(radios.map { gtk_check_button_get_active(typed($0)) }, [0, 1, 0])

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "c")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(radios.map { gtk_check_button_get_active(typed($0)) }, [0, 0, 1])
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "nothing")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(radios.map { gtk_check_button_get_active(typed($0)) }, [0, 0, 0], "no button for a value that is no tag")
        XCTAssertEqual(fired.count, 1, "host values fire nothing")
    }

    func testARadioGroupsTitleIsBesideItsFirstRow() throws {
        // Measured on macOS 27: the title on the first radio button's line, not the column's middle.
        let node = try render(#"{"type": "Picker", "id": 1, "properties": {"title": "Size", "options": \#(sized), "pickerStyle": "radioGroup"}}"#)
        var minimum: Int32 = 0
        var width: Int32 = 0
        var height: Int32 = 0
        gtk_widget_measure(node.widget, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &width, nil, nil)
        gtk_widget_measure(node.widget, GTK_ORIENTATION_VERTICAL, width, &minimum, &height, nil, nil)
        gtk_widget_allocate(node.widget, width, height, -1, nil)
        func center(_ widget: WidgetPointer) -> Float {
            var bounds = graphene_rect_t()
            _ = gtk_widget_compute_bounds(widget, node.widget, &bounds)
            return bounds.origin.y + bounds.size.height / 2
        }
        let first = try XCTUnwrap(gtk_widget_get_first_child(Picker.accessibleWidget(node.widget)))
        XCTAssertLessThanOrEqual(abs(center(try XCTUnwrap(title(node))) - center(first)), 3)
    }

    func testAHorizontalRadioGroupIsARow() throws {
        // Measured on macOS 27: horizontalRadioGroupLayout puts the buttons in a row, 8 apart.
        let node = try render(#"{"type": "Picker", "id": 1, "properties": {"title": "Size", "options": \#(sized), "pickerStyle": "radioGroup", "horizontalRadioGroupLayout": true}}"#)
        var minimum: Int32 = 0
        var width: Int32 = 0
        var height: Int32 = 0
        gtk_widget_measure(node.widget, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &width, nil, nil)
        gtk_widget_measure(node.widget, GTK_ORIENTATION_VERTICAL, width, &minimum, &height, nil, nil)
        gtk_widget_allocate(node.widget, width, height, -1, nil)
        let frames: [graphene_rect_t] = children(Picker.accessibleWidget(node.widget)).map { radio in
            var bounds = graphene_rect_t()
            _ = gtk_widget_compute_bounds(radio, node.widget, &bounds)
            return bounds
        }
        XCTAssertEqual(frames.count, 3)
        for (left, right) in zip(frames, frames.dropFirst()) {
            XCTAssertEqual(right.origin.y, left.origin.y, "one row")
            XCTAssertEqual(right.origin.x, left.origin.x + left.size.width + 8, "8 apart")
        }
    }

    func testEachStyleIsNamedAfterTheTitle() throws {
        for style in ["segmented", "radioGroup"] {
            ActionUIModel.shared.windowModels[windowUUID] = nil
            let node = try render(#"{"type": "Picker", "id": 1, "properties": {"title": "Size", "options": ["S"], "pickerStyle": "\#(style)"}}"#)
            XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(Picker.accessibleWidget(node.widget)), GTK_ACCESSIBLE_PROPERTY_LABEL), 0, style)
        }
    }
}
