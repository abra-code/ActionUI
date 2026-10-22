// Tests/Elements/LabelRendererTests.swift
/*
 Tests for the Label renderer on GTK: the title is the value, else the title property; the icon is
 systemImage's or imageName's, hidden without either; it does not grow; assistive technologies
 read the title label, named by accessibilityLabel or the title, and not the icon.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class LabelRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "label-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func parts(_ node: RenderNode) throws -> (icon: WidgetPointer, title: WidgetPointer) {
        (try XCTUnwrap(gtk_widget_get_first_child(node.widget)), try XCTUnwrap(gtk_widget_get_last_child(node.widget)))
    }

    func testTheTitleIsTheValueElseTheProperty() throws {
        let node = try render(#"{"type": "Label", "id": 1, "properties": {"title": "Name"}}"#)
        let (icon, title) = try parts(node)
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(title))), "Name")
        XCTAssertEqual(gtk_widget_get_visible(icon), 0, "no image: the title alone")
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "Renamed")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(title))), "Renamed")
    }

    func testTheIconComesFromSystemImageElseImageName() throws {
        let node = try render(#"{"type": "Label", "id": 1, "properties": {"title": "Name", "systemImage": "star"}}"#)
        let (icon, _) = try parts(node)
        XCTAssertNotEqual(gtk_widget_get_visible(icon), 0)
        XCTAssertEqual(swiftString(gtk_image_get_icon_name(opaque(icon))), Image.iconName(.symbol("star")))
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "systemImage", value: "")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "imageName", value: "folder")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(swiftString(gtk_image_get_icon_name(opaque(icon))), Image.iconName(.themeIcon("folder")))
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "imageName", value: "")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_widget_get_visible(icon), 0)
        XCTAssertEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_HORIZONTAL), 0, "it does not grow")
    }

    func testTheTitleLabelIsNamedAndTheIconIsLeftOut() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "Label", "id": 2, "properties": {"title": "Name", "systemImage": "star"}},
              {"type": "Label", "id": 3, "properties": {"title": "Name", "accessibilityLabel": "Full name"}}]}
            """#)
        for id in [2, 3] {
            let (icon, title) = try parts(try XCTUnwrap(root.childNodes[id]))
            XCTAssertEqual(Label.accessibleWidget(try XCTUnwrap(root.childNodes[id]).widget), title)
            XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(title), GTK_ACCESSIBLE_PROPERTY_LABEL), 0, "Label \(id)")
            XCTAssertEqual(gtk_accessible_get_accessible_role(OpaquePointer(icon)), GTK_ACCESSIBLE_ROLE_PRESENTATION)
        }
    }
}
