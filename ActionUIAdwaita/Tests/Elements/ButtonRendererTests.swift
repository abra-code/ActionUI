// Tests/Elements/ButtonRendererTests.swift
/*
 Tests for the Button renderer on GTK: the content is the title, the icon, or both in an
 AdwButtonContent, and changes between them; a click fires actionID and an update fires nothing;
 imageScale sizes the icon; role and the inherited buttonStyle become libadwaita's style classes,
 and plain loses the button's padding; no relation to its label outranks accessibilityLabel; the
 inherited controlSize sizes the button in macOS's proportions to GNOME's regular one.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ButtonRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "button-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIModel.shared.unregisterActionHandler(for: "test.click")
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func button(_ node: RenderNode) -> UnsafeMutablePointer<GtkButton> {
        typed(node.widget)
    }

    private func classes(_ node: RenderNode) -> Set<String> {
        Set(Button.styleClasses.filter { gtk_widget_has_css_class(node.widget, $0) != 0 })
    }

    private func width(_ widget: WidgetPointer) -> Int32 {
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(widget, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &natural, nil, nil)
        return natural
    }

    private func height(_ widget: WidgetPointer?) -> Int32 {
        guard let widget else { return 0 }
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(widget, GTK_ORIENTATION_VERTICAL, -1, &minimum, &natural, nil, nil)
        return natural
    }

    func testControlSizeSizesTheButtonAsMacOSDoesAgainstGNOMEsRegular() throws {
        let root = try render(#"""
            {"type": "HStack", "id": 1, "children": [
              {"type": "Button", "id": 2, "properties": {"title": "Mini", "controlSize": "mini"}},
              {"type": "Button", "id": 3, "properties": {"title": "Small", "controlSize": "small"}},
              {"type": "Button", "id": 4, "properties": {"title": "Regular", "controlSize": "regular"}},
              {"type": "Button", "id": 5, "properties": {"title": "Large", "controlSize": "large"}},
              {"type": "Button", "id": 6, "properties": {"title": "Extra", "controlSize": "extraLarge"}},
              {"type": "Button", "id": 7, "properties": {"title": "Default"}}]}
            """#)
        let heights = try (2...7).map { height(try XCTUnwrap(root.childNodes[$0]).widget) }
        XCTAssertEqual(heights[5], heights[2], "regular is GNOME's own size: \(heights)")
        // macOS's proportions to regular: 0.54, 0.83, 1.17 and 1.5 of it.
        let regular = Double(heights[2])
        for (index, ratio) in [(0, 0.54), (1, 0.83), (3, 1.17), (4, 1.5)] {
            XCTAssertEqual(Double(heights[index]) / regular, ratio, accuracy: 0.05, "\(heights)")
        }
        let mini = try XCTUnwrap(root.childNodes[2]?.widget)
        let regularWidget = try XCTUnwrap(root.childNodes[4]?.widget)
        XCTAssertLessThan(width(mini), width(regularWidget), "a smaller font too")
    }

    func testControlSizeReachesTheButtonsInsideAndTheNearestWins() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "properties": {"controlSize": "small"}, "children": [
              {"type": "Button", "id": 2, "properties": {"title": "Small"}},
              {"type": "HStack", "id": 3, "properties": {"controlSize": "large"}, "children": [
                {"type": "Button", "id": 4, "properties": {"title": "Large"}}]},
              {"type": "Button", "id": 5, "properties": {"title": "Plain", "buttonStyle": "plain"}}]}
            """#)
        let small = try XCTUnwrap(root.childNodes[2])
        let large = try XCTUnwrap(root.childNodes[3]?.childNodes[4])
        XCTAssertEqual(small.environment.controlSize, .small)
        XCTAssertEqual(large.environment.controlSize, .large)
        XCTAssertLessThan(height(small.widget), height(large.widget))
        let plain = try XCTUnwrap(root.childNodes[5]).widget
        XCTAssertLessThan(height(plain), height(small.widget), "a plain button is its label alone")
        let own = ControlSizeCSS.button(.mini, content: .title, plain: false, ownFont: true)
        XCTAssertFalse(own.contains { $0.hasPrefix("font-size") }, "a font of its own stays, as in SwiftUI")

        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "controlSize", value: "mini")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(small.environment.controlSize, .mini, "a change reaches the descendants")
        XCTAssertEqual(large.environment.controlSize, .large)
    }

    func testControlSizeScalesTheSidePaddingOfEachKindAndKeepsAnIconButtonSquare() throws {
        // libadwaita pads a title 17 px, an icon and a title 9 px, and makes an icon alone a square.
        let sizes = ["mini", "small", "regular", "large", "extraLarge"]
        let buttons = sizes.enumerated().map { index, size in
            #"{"type": "HStack", "id": \#(10 * (index + 1)), "children": ["#
                + #"{"type": "Button", "id": \#(10 * (index + 1) + 1), "properties": {"title": "Same", "controlSize": "\#(size)"}},"#
                + #"{"type": "Button", "id": \#(10 * (index + 1) + 2), "properties": {"title": "Same", "systemImage": "plus", "controlSize": "\#(size)"}},"#
                + #"{"type": "Button", "id": \#(10 * (index + 1) + 3), "properties": {"systemImage": "plus", "controlSize": "\#(size)"}}]}"#
        }
        let root = try render(#"{"type": "VStack", "id": 1, "children": ["# + buttons.joined(separator: ",") + "]}")
        func widget(_ row: Int, _ kind: Int) throws -> WidgetPointer {
            try XCTUnwrap(root.childNodes[10 * (row + 1)]?.childNodes[10 * (row + 1) + kind]?.widget)
        }
        for kind in 1...3 {
            let widths = try sizes.indices.map { width(try widget($0, kind)) }
            XCTAssertEqual(widths, widths.sorted(), "kind \(kind) grows with the size: \(widths)")
            XCTAssertEqual(Set(widths).count, widths.count, "kind \(kind): \(widths)")
        }
        for row in sizes.indices {
            let icon = try widget(row, 3)
            XCTAssertEqual(width(icon), height(icon), "\(sizes[row]) icon button is a square")
        }
    }

    func testTheContentIsTheTitleTheIconOrBoth() throws {
        let node = try render(#"{"type": "Button", "id": 1, "properties": {"title": "Save"}}"#)
        XCTAssertEqual(swiftString(gtk_button_get_label(button(node))), "Save")

        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "systemImage", value: "plus.circle")
        AdwaitaTestHost.drainMainLoop()
        let content = try XCTUnwrap(gtk_button_get_child(button(node)))
        XCTAssertEqual(swiftString(G_OBJECT_TYPE_NAME_of(content)), "AdwButtonContent")
        XCTAssertEqual(swiftString(adw_button_content_get_icon_name(OpaquePointer(content))), SymbolNames.iconName("plus.circle"))
        XCTAssertEqual(swiftString(adw_button_content_get_label(OpaquePointer(content))), "Save")

        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "title", value: "")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(swiftString(gtk_button_get_icon_name(button(node))), SymbolNames.iconName("plus.circle"), "an image alone is an icon")

        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "systemImage", value: "")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "title", value: "Done")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(swiftString(gtk_button_get_label(button(node))), "Done")
        XCTAssertNil(gtk_button_get_icon_name(button(node)))
    }

    func testAClickFiresTheActionAndAnUpdateFiresNothing() throws {
        let counter = CallCounter()
        var viewID = 0
        ActionUIModel.shared.registerActionHandler(for: "test.click") { _, _, id, _, _ in
            MainActor.assumeIsolated {
                counter.count += 1
                viewID = id
            }
        }
        let node = try render(#"{"type": "Button", "id": 4, "properties": {"title": "Go", "actionID": "test.click"}}"#)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 4, propertyName: "title", value: "Again")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(counter.count, 0, "rendering and updating fire nothing")

        AdwaitaTestHost.emit("clicked", on: node.widget)
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(viewID, 4)
    }

    func testTheButtonIsNotLabelledByItsLabelSoTheAccessibilityLabelNamesIt() throws {
        let node = try render(#"""
            {"type": "Button", "id": 1, "properties": {"title": "Save", "systemImage": "plus.circle", "accessibilityLabel": "Store"}}
            """#)
        let accessible = OpaquePointer(node.widget)
        XCTAssertEqual(gtk_test_accessible_has_relation(accessible, GTK_ACCESSIBLE_RELATION_LABELLED_BY), 0)
        XCTAssertNotEqual(gtk_test_accessible_has_property(accessible, GTK_ACCESSIBLE_PROPERTY_LABEL), 0)

        // AdwButtonContent names the button as its label's mnemonic widget when it is rooted.
        let window = gtk_window_new()!
        defer { gtk_window_destroy(typed(window)) }
        gtk_window_set_child(typed(window), node.outerWidget)
        gtk_window_present(typed(window))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(node.widget) != 0 }))
        XCTAssertEqual(gtk_test_accessible_has_relation(accessible, GTK_ACCESSIBLE_RELATION_LABELLED_BY), 0, "after rooting")

        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "systemImage", value: "")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(swiftString(gtk_button_get_label(button(node))), "Save")
        XCTAssertEqual(gtk_test_accessible_has_relation(accessible, GTK_ACCESSIBLE_RELATION_LABELLED_BY), 0, "a new label")
    }

    func testImageScaleSizesTheIcon() throws {
        let root = try render(#"""
            {"type": "HStack", "id": 1, "children": [
              {"type": "Button", "id": 2, "properties": {"systemImage": "trash", "imageScale": "small"}},
              {"type": "Button", "id": 3, "properties": {"systemImage": "trash", "imageScale": "large"}}]}
            """#)
        let small = try XCTUnwrap(gtk_button_get_child(button(try XCTUnwrap(root.childNodes[2]))))
        let large = try XCTUnwrap(gtk_button_get_child(button(try XCTUnwrap(root.childNodes[3]))))
        XCTAssertLessThan(width(small), width(large))
    }

    func testRoleAndTheInheritedStyleBecomeStyleClasses() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "properties": {"buttonStyle": "borderedProminent"}, "children": [
              {"type": "Button", "id": 2, "properties": {"title": "OK"}},
              {"type": "Button", "id": 3, "properties": {"title": "Delete", "role": "destructive"}},
              {"type": "Button", "id": 4, "properties": {"title": "Cancel", "role": "cancel", "buttonStyle": "borderless"}}]}
            """#)
        let ok = try XCTUnwrap(root.childNodes[2])
        XCTAssertEqual(classes(ok), ["suggested-action"])
        XCTAssertEqual(classes(try XCTUnwrap(root.childNodes[3])), ["destructive-action"])
        XCTAssertEqual(classes(try XCTUnwrap(root.childNodes[4])), ["flat"], "its own style wins; cancel adds nothing")

        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "buttonStyle", value: "bordered")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(classes(ok), [], "a changed style takes its classes away")
    }

    func testAPlainButtonIsAsLargeAsItsContent() throws {
        let root = try render(#"""
            {"type": "HStack", "id": 1, "children": [
              {"type": "Button", "id": 2, "properties": {"title": "Same"}},
              {"type": "Button", "id": 3, "properties": {"title": "Same", "buttonStyle": "plain"}}]}
            """#)
        let bordered = try XCTUnwrap(root.childNodes[2])
        let plain = try XCTUnwrap(root.childNodes[3])
        XCTAssertEqual(classes(plain), ["flat"])
        let label = try XCTUnwrap(gtk_button_get_child(button(plain)))
        XCTAssertEqual(width(plain.widget), width(label), "no padding around the label")
        XCTAssertGreaterThan(width(bordered.widget), width(label))
    }
}
