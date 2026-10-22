// Tests/Elements/PickerRendererTests.swift
/*
 Tests for the Picker renderer on GTK (menu style): the options are the dropdown's items and the
 value selects one (the first option without a value, none for a value that is no tag); the title
 is shown beside the dropdown, hidden by labelsHidden, and names the dropdown either way; choosing
 an item sets the value and fires actionID with the tag, and a host value fires nothing; sections
 give the popup headers; changed options rebuild the items.
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
}
