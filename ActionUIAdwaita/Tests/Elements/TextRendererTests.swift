// Tests/Elements/TextRendererTests.swift
/*
 Tests for the Text renderer on GTK: what the label shows (the text property, markdown's source, a
 runtime String or AttributedString value, one line's height for an empty Text), wrapping (natural
 width one line, also inside a word that does not fit, as SwiftUI does; taller when narrower), the
 alignment and selection from the environment, and the accessible name a removed
 accessibilityLabel gives back.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class TextRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "text-\(name)"
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

    private func text(_ node: RenderNode) -> String? {
        swiftString(gtk_label_get_text(opaque(node.widget)))
    }

    private func measure(_ widget: WidgetPointer, _ orientation: GtkOrientation, forSize: Int32 = -1) -> (Int32, Int32) {
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(widget, orientation, forSize, &minimum, &natural, nil, nil)
        return (minimum, natural)
    }

    func testTheLabelShowsTheTextAndARuntimeValue() throws {
        let node = try render(#"{"type": "Text", "id": 1, "properties": {"text": "Hello"}}"#)
        XCTAssertEqual(text(node), "Hello")
        XCTAssertEqual(swiftString(G_OBJECT_TYPE_NAME_of(node.widget)), "GtkLabel")
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "Changed")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(text(node), "Changed")
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: AttributedString("Attributed"))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(text(node), "Attributed")
    }

    func testMarkdownShowsItsSourceUntilTheParserArrives() throws {
        let node = try render(#"{"type": "Text", "id": 1, "properties": {"markdown": "**Bold**", "text": "plain"}}"#)
        XCTAssertEqual(text(node), "**Bold**", "markdown takes precedence over text")
    }

    func testAnEmptyTextKeepsOneLinesHeight() throws {
        // No zero-width space as on Apple: an empty GtkLabel keeps the height, and the space would
        // be its accessible name.
        let root = try render(#"{"type": "VStack", "id": 1, "children": [{"type": "Text", "id": 2}, {"type": "Text", "id": 3, "properties": {"text": "x"}}]}"#)
        let empty = try XCTUnwrap(root.childNodes[2])
        XCTAssertEqual(text(empty), "")
        XCTAssertEqual(measure(empty.widget, GTK_ORIENTATION_VERTICAL).1,
                       measure(try XCTUnwrap(root.childNodes[3]).widget, GTK_ORIENTATION_VERTICAL).1)
        XCTAssertEqual(gtk_test_accessible_has_property(OpaquePointer(empty.widget), GTK_ACCESSIBLE_PROPERTY_LABEL), 0)
    }

    func testTextWrapsAtWordsAndInsideALongOne() throws {
        let words = "one two three four five six seven eight nine ten eleven twelve"
        let node = try render(#"{"type": "Text", "id": 1, "properties": {"text": "\#(words)"}}"#)
        let (minimum, natural) = measure(node.widget, GTK_ORIENTATION_HORIZONTAL)
        XCTAssertLessThan(minimum, natural, "it can shrink by wrapping")
        // SwiftUI breaks a word that does not fit (Text("eleven") offered 20 points takes three
        // lines), so the minimum is below the longest word, and that word alone wraps.
        let longest = try render(#"{"type": "Text", "id": 2, "properties": {"text": "eleven"}}"#)
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let (wordMinimum, wordNatural) = measure(longest.widget, GTK_ORIENTATION_HORIZONTAL)
        XCTAssertLessThan(minimum, wordNatural)
        XCTAssertGreaterThan(measure(longest.widget, GTK_ORIENTATION_VERTICAL, forSize: wordMinimum).1,
                             measure(longest.widget, GTK_ORIENTATION_VERTICAL, forSize: wordNatural).1)
        XCTAssertGreaterThan(measure(node.widget, GTK_ORIENTATION_VERTICAL, forSize: minimum).1,
                             measure(node.widget, GTK_ORIENTATION_VERTICAL, forSize: natural).1, "taller when narrower")
    }

    func testAlignmentAndSelectionComeFromTheEnvironment() throws {
        let root = try render(#"{"type": "VStack", "id": 1, "properties": {"multilineTextAlignment": "trailing", "textSelection": "enabled"}, "children": [{"type": "Text", "id": 2, "properties": {"text": "x"}}]}"#)
        let node = try XCTUnwrap(root.childNodes[2])
        XCTAssertEqual(gtk_label_get_justify(opaque(node.widget)), GTK_JUSTIFY_RIGHT)
        XCTAssertEqual(gtk_label_get_xalign(opaque(node.widget)), 0.5, "the parent VStack is centered")
        XCTAssertNotEqual(gtk_label_get_selectable(opaque(node.widget)), 0)
        XCTAssertEqual(gtk_widget_get_focusable(node.widget), 0, "selectable, not focusable, as SwiftUI's Text")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "multilineTextAlignment", value: "center")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_label_get_justify(opaque(node.widget)), GTK_JUSTIFY_CENTER)
    }

    func testWrappedTextSitsWhereTheParentVStackPlacesIt() throws {
        let root = try render(#"{"type": "VStack", "id": 1, "properties": {"alignment": "leading"}, "children": [{"type": "Text", "id": 2, "properties": {"text": "x"}}]}"#)
        let node = try XCTUnwrap(root.childNodes[2])
        XCTAssertEqual(gtk_label_get_xalign(opaque(node.widget)), 0)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "alignment", value: "trailing")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_label_get_xalign(opaque(node.widget)), 1)
    }

    func testARemovedAccessibilityLabelGivesTheTextBack() throws {
        let node = try render(#"{"type": "Text", "id": 1, "properties": {"text": "Visible words", "accessibilityLabel": "Spoken"}}"#)
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(node.widget), GTK_ACCESSIBLE_PROPERTY_LABEL), 0)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "accessibilityLabel", value: "")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(node.widget), GTK_ACCESSIBLE_PROPERTY_LABEL), 0,
                          "named from its text again, not left nameless")
    }
}

/// G_OBJECT_TYPE_NAME, a macro Swift does not import.
func G_OBJECT_TYPE_NAME_of(_ widget: WidgetPointer) -> UnsafePointer<CChar>? {
    g_type_name(UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GTypeInstance.self).pointee.g_class.pointee.g_type)
}
