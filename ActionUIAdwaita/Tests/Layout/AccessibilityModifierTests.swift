// Tests/Layout/AccessibilityModifierTests.swift
/*
 Tests for the accessibility modifiers on GTK: the label and hint become the element widget's
 accessible label and description, accessibilityHidden and hidden its hidden state, the
 identifier its widget name; they are removed again at run time; a label a widget overwrote is
 written again; the box and the content group have the generic role (a presentation role would
 take the element out of GTK's accessibility tree).
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class AccessibilityModifierTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        ActionUIRegistry.shared.renderers["Rectangle"] = TestBlockRenderer.self
        windowUUID = "accessibility-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ modifiers: String) throws -> RenderNode {
        let json = #"{"type": "Rectangle", "id": 1, "properties": {"w": 10, "h": 10"# + (modifiers.isEmpty ? "" : ", " + modifiers) + "}}"
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func has(_ widget: WidgetPointer, _ property: GtkAccessibleProperty) -> Bool {
        gtk_test_accessible_has_property(OpaquePointer(widget), property) != 0
    }

    /// The hidden state the box last gave the widget. GTK keeps a hidden state on every widget
    /// (from its visibility), so gtk_test_accessible_has_state is always true, and the call that
    /// compares its value, gtk_test_accessible_check_state, is variadic, which Swift cannot call.
    private func isHidden(_ widget: WidgetPointer) -> Bool {
        attached(AccessibilityState.self, on: widget, key: accessibilityStateKey)?.hidden ?? false
    }

    func testHelpIsTheDescriptionWithoutAHint() throws {
        let node = try render(#""help": "A tip""#)
        XCTAssertTrue(has(node.widget, GTK_ACCESSIBLE_PROPERTY_DESCRIPTION))
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "help", value: "")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertFalse(has(node.widget, GTK_ACCESSIBLE_PROPERTY_DESCRIPTION))
    }

    func testLabelHintAndIdentifierGoOnTheElement() throws {
        let node = try render(#""accessibilityLabel": "Save", "accessibilityHint": "Saves the file", "accessibilityIdentifier": "save-button""#)
        XCTAssertTrue(has(node.widget, GTK_ACCESSIBLE_PROPERTY_LABEL))
        XCTAssertTrue(has(node.widget, GTK_ACCESSIBLE_PROPERTY_DESCRIPTION))
        XCTAssertEqual(swiftString(gtk_widget_get_name(node.widget)), "save-button")

        // Removed at run time, they leave the element.
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "accessibilityLabel", value: "")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "accessibilityHint", value: "")
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "accessibilityIdentifier", value: "")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertFalse(has(node.widget, GTK_ACCESSIBLE_PROPERTY_LABEL))
        XCTAssertFalse(has(node.widget, GTK_ACCESSIBLE_PROPERTY_DESCRIPTION))
        XCTAssertEqual(swiftString(gtk_widget_get_name(node.widget)), swiftString(g_type_name_from_instance(typed(OpaquePointer(node.widget)))),
                       "the default name again, the widget's type name")
    }

    func testALabelTheWidgetOverwroteIsWrittenAgain() throws {
        let node = try render(#""accessibilityLabel": "Save""#)
        // As a widget's own write would (GtkLabel sets its label from its text).
        gtk_accessible_reset_property(OpaquePointer(node.widget), GTK_ACCESSIBLE_PROPERTY_LABEL)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "help", value: "Saves")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertTrue(has(node.widget, GTK_ACCESSIBLE_PROPERTY_LABEL))
    }

    func testAccessibilityHiddenAndHiddenHideTheElement() throws {
        let plain = try render("")
        XCTAssertFalse(isHidden(plain.widget))
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let hiddenFromAssistance = try render(#""accessibilityHidden": true"#)
        XCTAssertTrue(isHidden(hiddenFromAssistance.widget))
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let hidden = try render(#""hidden": true"#)
        XCTAssertTrue(isHidden(hidden.widget), "a hidden element is out of the tree too")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "hidden", value: false)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertFalse(isHidden(hidden.widget))
    }

    func testTheBoxAndTheContentGroupAreGeneric() throws {
        let node = try render("")
        let content = try XCTUnwrap(ModifierBox.content(of: node.outerWidget))
        XCTAssertNotEqual(gtk_test_accessible_has_role(OpaquePointer(node.outerWidget), GTK_ACCESSIBLE_ROLE_GENERIC), 0)
        XCTAssertNotEqual(gtk_test_accessible_has_role(OpaquePointer(content), GTK_ACCESSIBLE_ROLE_GENERIC), 0)
    }
}
