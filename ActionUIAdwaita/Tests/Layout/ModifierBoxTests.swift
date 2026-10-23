// Tests/Layout/ModifierBoxTests.swift
/*
 Tests for ModifierBox, the box around every element, and for ZStack: padding and frames as their
 stack sees them (sizes, expansion, caps) and as their content sits in them (alignment), hidden
 keeping its space, disabled, opacity and help, a runtime property change, and ZStack's sizing and
 alignment. Leaves are StackLayoutTests' test Rectangle.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ModifierBoxTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        ActionUIRegistry.shared.renderers["Rectangle"] = TestBlockRenderer.self
        windowUUID = "modifier-box-\(name)"
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

    /// A test Rectangle `width` x `height` with extra base modifier properties (JSON members).
    private func block(_ id: Int, _ width: Int, _ height: Int, _ modifiers: String = "", fill: String? = nil) -> String {
        let fillText = fill.map { #", "fill": "\#($0)""# } ?? ""
        let extra = modifiers.isEmpty ? "" : ", " + modifiers
        return #"{"type": "Rectangle", "id": \#(id), "properties": {"w": \#(width), "h": \#(height)\#(fillText)\#(extra)}}"#
    }

    private func measure(_ widget: WidgetPointer, _ orientation: GtkOrientation, forSize: Int32 = -1) -> [Int32] {
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(widget, orientation, forSize, &minimum, &natural, nil, nil)
        return [minimum, natural]
    }

    /// [x, y, width, height] of `widget` in `ancestor`.
    private func frame(_ widget: WidgetPointer, in ancestor: WidgetPointer) -> [Int] {
        var bounds = graphene_rect_t()
        _ = gtk_widget_compute_bounds(widget, ancestor, &bounds)
        return [Int(bounds.origin.x), Int(bounds.origin.y), Int(bounds.size.width), Int(bounds.size.height)]
    }

    /// Each child box's frame in `stack` after allocating it `width` x `height`.
    private func frames(_ stack: WidgetPointer, _ width: Int32, _ height: Int32) -> [[Int]] {
        gtk_widget_allocate(stack, width, height, -1, nil)
        var result: [[Int]] = []
        var child = gtk_widget_get_first_child(stack)
        while let current = child {
            result.append(frame(current, in: stack))
            child = gtk_widget_get_next_sibling(current)
        }
        return result
    }

    func testNegativePaddingShrinksTheBoxAndTheContentOverflows() throws {
        // SwiftUI on macOS: a 40 x 20 view with padding(-5) is 30 x 10.
        let node = try render(block(1, 40, 20, #""padding": -5"#))
        XCTAssertEqual(measure(node.outerWidget, GTK_ORIENTATION_HORIZONTAL), [30, 30])
        XCTAssertEqual(measure(node.outerWidget, GTK_ORIENTATION_VERTICAL), [10, 10])
        gtk_widget_allocate(node.outerWidget, 30, 10, -1, nil)
        XCTAssertEqual(frame(node.widget, in: node.outerWidget), [-5, -5, 40, 20])
    }

    func testPaddingAddsToTheSizeAndInsetsTheContent() throws {
        let node = try render(block(1, 40, 20, #""padding": {"top": 1, "leading": 2, "bottom": 3, "trailing": 4}"#))
        XCTAssertEqual(measure(node.outerWidget, GTK_ORIENTATION_HORIZONTAL), [46, 46])
        XCTAssertEqual(measure(node.outerWidget, GTK_ORIENTATION_VERTICAL), [24, 24])
        gtk_widget_allocate(node.outerWidget, 46, 24, -1, nil)
        XCTAssertEqual(frame(node.widget, in: node.outerWidget), [2, 1, 40, 20])
    }

    func testDefaultPaddingIsSixteen() throws {
        let node = try render(block(1, 10, 10, #""padding": "default""#))
        XCTAssertEqual(measure(node.outerWidget, GTK_ORIENTATION_HORIZONTAL), [42, 42])
    }

    func testAFixedFrameIsItsSizeAndCentersItsContent() throws {
        let node = try render(block(1, 20, 10, #""frame": {"width": 100, "height": 50}"#))
        XCTAssertEqual(measure(node.outerWidget, GTK_ORIENTATION_HORIZONTAL), [100, 100])
        XCTAssertEqual(measure(node.outerWidget, GTK_ORIENTATION_VERTICAL), [50, 50])
        gtk_widget_allocate(node.outerWidget, 100, 50, -1, nil)
        XCTAssertEqual(frame(node.widget, in: node.outerWidget), [40, 20, 20, 10])
        XCTAssertEqual(gtk_widget_compute_expand(node.outerWidget, GTK_ORIENTATION_HORIZONTAL), 0)
    }

    func testTheFrameAlignmentPlacesTheContent() throws {
        let node = try render(block(1, 20, 10, #""frame": {"width": 100, "height": 50, "alignment": "bottomTrailing"}"#))
        gtk_widget_allocate(node.outerWidget, 100, 50, -1, nil)
        XCTAssertEqual(frame(node.widget, in: node.outerWidget), [80, 40, 20, 10])
    }

    func testPaddingSitsInsideTheFrame() throws {
        // View.applyModifiers pads first, then frames: the frame holds the padded content.
        let node = try render(block(1, 20, 10, #""padding": 5, "frame": {"width": 100, "height": 50, "alignment": "topLeading"}"#))
        gtk_widget_allocate(node.outerWidget, 100, 50, -1, nil)
        XCTAssertEqual(frame(node.widget, in: node.outerWidget), [5, 5, 20, 10])
    }

    func testAnInfiniteMaxWidthSharesAStackEquallyWithAnotherFiller() throws {
        let root = try render(#"{"type": "HStack", "id": 1, "properties": {"spacing": 0}, "children": [\#(block(2, 10, 10, #""frame": {"maxWidth": "infinity"}"#)), \#(block(3, 60, 10, #""frame": {"maxWidth": "infinity"}"#))]}"#)
        XCTAssertNotEqual(gtk_widget_compute_expand(root.outerWidget, GTK_ORIENTATION_HORIZONTAL), 0, "the frame's expansion propagates")
        XCTAssertEqual(frames(root.widget, 300, 10).map { $0[2] }, [150, 150])
    }

    func testAFiniteMaxWidthExpandsUpToItEvenWithSmallerContent() throws {
        let root = try render(#"{"type": "HStack", "id": 1, "properties": {"spacing": 0}, "children": [\#(block(2, 10, 10, #""frame": {"maxWidth": 50}"#)), \#(block(3, 0, 10, fill: "h"))]}"#)
        XCTAssertEqual(frames(root.widget, 300, 10).map { $0[2] }, [50, 250])
    }

    func testAnIdealWidthIsTheNaturalWidth() throws {
        let node = try render(block(1, 10, 10, #""frame": {"minWidth": 20, "idealWidth": 120, "maxWidth": "infinity"}"#))
        XCTAssertEqual(measure(node.outerWidget, GTK_ORIENTATION_HORIZONTAL), [20, 120])
    }

    func testHiddenKeepsItsSpaceButIsTransparentAndTakesNoInput() throws {
        let root = try render(#"{"type": "VStack", "id": 1, "children": [\#(block(2, 10, 30, #""hidden": true"#)), \#(block(3, 10, 30))]}"#)
        XCTAssertEqual(measure(root.widget, GTK_ORIENTATION_VERTICAL), [60, 60])
        let hidden = try XCTUnwrap(root.childNodes[2])
        XCTAssertEqual(gtk_widget_get_opacity(hidden.outerWidget), 0)
        XCTAssertEqual(gtk_widget_get_can_target(hidden.outerWidget), 0)
        XCTAssertEqual(gtk_widget_get_can_focus(hidden.outerWidget), 0, "keyboard focus cannot reach a hidden element")
        let shown = try XCTUnwrap(root.childNodes[3])
        XCTAssertNotEqual(gtk_widget_get_can_focus(shown.outerWidget), 0)
    }

    func testABoxGivenMoreThanItsFrameTakesCentersTheFrame() throws {
        // SwiftUI on macOS, in a 300 x 100 parent: a fixed 100 x 50 frame of filling content is
        // centered and the content stays 100 x 50 (the window's root is allocated the window).
        let fixed = try render(block(1, 10, 10, #""frame": {"width": 100, "height": 50}"#, fill: "both"))
        gtk_widget_allocate(fixed.outerWidget, 300, 100, -1, nil)
        XCTAssertEqual(frame(fixed.widget, in: fixed.outerWidget), [100, 25, 100, 50])
        // frame(minWidth: 50, alignment: .leading) around a 10-wide content in 300: the frame is
        // 50, centered at 125, and the content sits at its leading edge.
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let minimum = try render(block(1, 10, 10, #""frame": {"minWidth": 50, "alignment": "leading"}"#))
        gtk_widget_allocate(minimum.outerWidget, 300, 10, -1, nil)
        XCTAssertEqual(frame(minimum.widget, in: minimum.outerWidget), [125, 0, 10, 10])
        // frame(maxWidth: 100, alignment: .leading) in 300: the frame is 100, centered at 100.
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let maximum = try render(block(1, 10, 10, #""frame": {"maxWidth": 100, "alignment": "leading"}"#))
        gtk_widget_allocate(maximum.outerWidget, 300, 10, -1, nil)
        XCTAssertEqual(frame(maximum.widget, in: maximum.outerWidget), [100, 0, 10, 10])
    }

    func testDecorationStopsAtTheCapOfWhatABoxHolds() throws {
        // SwiftUI: a VStack holding a child framed to maxWidth 200 is 200 wide however much its
        // parent offers, so its background is too; the window's root gives its box 1000 here.
        let child = block(2, 10, 10, #""frame": {"maxWidth": 200}"#, fill: "h")
        let node = try render(#"{"type": "VStack", "id": 1, "properties": {"background": "red"}, "children": [\#(child)]}"#)
        gtk_widget_allocate(node.outerWidget, 1000, 100, -1, nil)
        let content = try XCTUnwrap(ModifierBox.content(of: node.outerWidget))
        XCTAssertEqual(frame(content, in: node.outerWidget), [400, 45, 200, 10], "the painted group, centered")
        XCTAssertEqual(frame(node.widget, in: node.outerWidget), [400, 45, 200, 10])
    }

    func testAFrameWiderThanACappedElementCentersIt() throws {
        // SwiftUI: frame(maxWidth: .infinity) around that VStack takes the width (its background
        // too), and the VStack in it stays 200, centered; leading alignment inside the VStack
        // does not move it.
        let child = block(2, 10, 10, #""frame": {"maxWidth": 200}"#, fill: "h")
        let node = try render(#"{"type": "VStack", "id": 1, "properties": {"alignment": "leading", "background": "red", "frame": {"maxWidth": "infinity"}}, "children": [\#(child)]}"#)
        gtk_widget_allocate(node.outerWidget, 1000, 100, -1, nil)
        let content = try XCTUnwrap(ModifierBox.content(of: node.outerWidget))
        XCTAssertEqual(frame(content, in: node.outerWidget), [0, 45, 1000, 10])
        XCTAssertEqual(frame(node.widget, in: node.outerWidget), [400, 45, 200, 10])
    }

    func testWrappedTextKeepsACappedSiblingAtItsCap() throws {
        // The VStack's height cap is measured at its width, so the text wrapping at 150 counts with
        // all its lines: the stack stops at the text plus 50 and is centered in the frame, as in
        // SwiftUI, and the Color keeps its 50.
        let words = Array(repeating: "wrap", count: 80).joined(separator: " ")
        let node = try render(##"{"type": "VStack", "id": 1, "properties": {"spacing": 0, "frame": {"width": 150, "height": 800}}, "children": [{"type": "Text", "id": 2, "properties": {"text": "\##(words)"}}, {"type": "Color", "id": 3, "properties": {"color": "#FF0000", "frame": {"maxHeight": 50}}}]}"##)
        gtk_widget_allocate(node.outerWidget, 150, 800, -1, nil)
        let text = try XCTUnwrap(node.childNodes.values.first { $0.element.id == 2 })
        let color = try XCTUnwrap(node.childNodes.values.first { $0.element.id == 3 })
        let textHeight = frame(text.widget, in: node.outerWidget)[3]
        XCTAssertGreaterThan(textHeight, 100, "the text wraps to many lines")
        XCTAssertEqual(frame(color.widget, in: node.outerWidget)[3], 50, "the Color keeps its cap under the text")
        XCTAssertEqual(frame(node.widget, in: node.outerWidget), [0, (800 - textHeight - 50) / 2, 150, textHeight + 50],
                       "the stack stops at its height for its width, centered")
    }

    func testAnHStackGivesAWrappedTextColumnItsHeightForItsWidth() throws {
        // The HStack measures the VStack's height cap at the width it gives it, 150: the text with
        // all its lines plus 50, so the Color under the text keeps its 50.
        let words = Array(repeating: "wrap", count: 80).joined(separator: " ")
        let column = ##"{"type": "VStack", "id": 2, "properties": {"spacing": 0}, "children": [{"type": "Text", "id": 3, "properties": {"text": "\##(words)"}}, {"type": "Color", "id": 4, "properties": {"color": "#FF0000", "frame": {"maxHeight": 50}}}]}"##
        let node = try render(#"{"type": "HStack", "id": 1, "properties": {"spacing": 0, "frame": {"width": 150, "height": 800}}, "children": [\#(column)]}"#)
        gtk_widget_allocate(node.outerWidget, 150, 800, -1, nil)
        let stack = try XCTUnwrap(node.childNodes[2])
        let text = try XCTUnwrap(stack.childNodes[3])
        let color = try XCTUnwrap(stack.childNodes[4])
        let textHeight = frame(text.widget, in: node.outerWidget)[3]
        XCTAssertGreaterThan(textHeight, 100, "the text wraps to many lines")
        XCTAssertEqual(frame(color.widget, in: node.outerWidget)[3], 50, "the Color keeps its cap under the text")
        XCTAssertEqual(frame(stack.outerWidget, in: node.outerWidget)[3], textHeight + 50)
    }

    func testAZStackGivesAWrappedTextColumnItsHeightForItsWidth() throws {
        let words = Array(repeating: "wrap", count: 80).joined(separator: " ")
        let column = ##"{"type": "VStack", "id": 2, "properties": {"spacing": 0}, "children": [{"type": "Text", "id": 3, "properties": {"text": "\##(words)"}}, {"type": "Color", "id": 4, "properties": {"color": "#FF0000", "frame": {"maxHeight": 50}}}]}"##
        let node = try render(#"{"type": "ZStack", "id": 1, "properties": {"frame": {"width": 150, "height": 800}}, "children": [\#(column)]}"#)
        gtk_widget_allocate(node.outerWidget, 150, 800, -1, nil)
        let stack = try XCTUnwrap(node.childNodes[2])
        let textHeight = frame(try XCTUnwrap(stack.childNodes[3]).widget, in: node.outerWidget)[3]
        XCTAssertGreaterThan(textHeight, 100, "the text wraps to many lines")
        XCTAssertEqual(frame(try XCTUnwrap(stack.childNodes[4]).widget, in: node.outerWidget)[3], 50)
        XCTAssertEqual(frame(stack.outerWidget, in: node.outerWidget)[3], textHeight + 50)
    }

    func testAPaddedBoxMeasuresItsCapAtItsContentWidth() throws {
        // The box is 150 wide with padding 10, so the text wraps at 130 and the cap counts all its
        // lines: the Color keeps its 50, and the box stops at the text plus 50 plus the padding.
        let words = Array(repeating: "wrap", count: 80).joined(separator: " ")
        let column = ##"{"type": "VStack", "id": 2, "properties": {"spacing": 0, "padding": 10, "frame": {"maxWidth": 150}}, "children": [{"type": "Text", "id": 3, "properties": {"text": "\##(words)"}}, {"type": "Color", "id": 4, "properties": {"color": "#FF0000", "frame": {"maxHeight": 50}}}]}"##
        let node = try render(#"{"type": "VStack", "id": 1, "properties": {"spacing": 0, "frame": {"width": 200, "height": 800}}, "children": [\#(column)]}"#)
        gtk_widget_allocate(node.outerWidget, 200, 800, -1, nil)
        let stack = try XCTUnwrap(node.childNodes[2])
        let text = frame(try XCTUnwrap(stack.childNodes[3]).widget, in: node.outerWidget)
        XCTAssertEqual(text[2], 130, "the text wraps inside the padding")
        XCTAssertGreaterThan(text[3], 100, "the text wraps to many lines")
        XCTAssertEqual(frame(try XCTUnwrap(stack.childNodes[4]).widget, in: node.outerWidget)[3], 50)
        XCTAssertEqual(frame(stack.outerWidget, in: node.outerWidget), [25, (800 - text[3] - 70) / 2, 150, text[3] + 70])
    }

    func testAGroupBoxMeasuresItsCapAtItsCardWidth() throws {
        // The card insets its content 5 on each side, so the text wraps at 140; the GroupBox stops
        // at the text, the default spacing of 8, the Color's 50 and the padding.
        let words = Array(repeating: "wrap", count: 80).joined(separator: " ")
        let box = ##"{"type": "GroupBox", "id": 2, "children": [{"type": "Text", "id": 3, "properties": {"text": "\##(words)"}}, {"type": "Color", "id": 4, "properties": {"color": "#FF0000", "frame": {"maxHeight": 50}}}]}"##
        let node = try render(#"{"type": "VStack", "id": 1, "properties": {"spacing": 0, "frame": {"width": 150, "height": 800}}, "children": [\#(box)]}"#)
        gtk_widget_allocate(node.outerWidget, 150, 800, -1, nil)
        let groupBox = try XCTUnwrap(node.childNodes[2])
        let text = frame(try XCTUnwrap(groupBox.childNodes[3]).widget, in: node.outerWidget)
        XCTAssertEqual(text[2], 140, "the text wraps inside the card")
        XCTAssertGreaterThan(text[3], 100, "the text wraps to many lines")
        XCTAssertEqual(frame(try XCTUnwrap(groupBox.childNodes[4]).widget, in: node.outerWidget)[3], 50)
        XCTAssertEqual(frame(groupBox.outerWidget, in: node.outerWidget)[3], text[3] + 8 + 50 + 10)
    }

    func testDisabledOpacityAndHelp() throws {
        let node = try render(block(1, 10, 10, #""disabled": true, "opacity": 0.5, "help": "A tip""#))
        XCTAssertEqual(gtk_widget_get_sensitive(node.widget), 0)
        XCTAssertEqual(gtk_widget_get_opacity(node.outerWidget), 0.5, accuracy: 1.0 / 255, "GTK keeps 8 bits")
        XCTAssertEqual(swiftString(gtk_widget_get_tooltip_text(node.widget)), "A tip")
    }

    func testARuntimePropertyChangeUpdatesTheBox() throws {
        let node = try render(block(1, 10, 10))
        XCTAssertEqual(measure(node.outerWidget, GTK_ORIENTATION_HORIZONTAL), [10, 10])
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "padding", value: 7)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "disabled", value: true)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(measure(node.outerWidget, GTK_ORIENTATION_HORIZONTAL), [24, 24])
        XCTAssertEqual(gtk_widget_get_sensitive(node.widget), 0)
    }

    func testAZStackIsItsBiggestChildAndAlignsTheOthers() throws {
        let root = try render(#"{"type": "ZStack", "id": 1, "properties": {"alignment": "topTrailing"}, "children": [\#(block(2, 100, 60)), \#(block(3, 20, 10))]}"#)
        XCTAssertEqual(measure(root.widget, GTK_ORIENTATION_HORIZONTAL), [100, 100])
        XCTAssertEqual(measure(root.widget, GTK_ORIENTATION_VERTICAL), [60, 60])
        // Allocated more than it needs: the 100 x 60 block is centered, the small child at its
        // top trailing corner.
        XCTAssertEqual(frames(root.widget, 200, 100), [[50, 20, 100, 60], [130, 20, 20, 10]])
    }

    func testAnExpandingZStackChildFillsItAndMakesItExpand() throws {
        let root = try render(#"{"type": "ZStack", "id": 1, "children": [\#(block(2, 10, 10, fill: "both")), \#(block(3, 20, 10))]}"#)
        XCTAssertNotEqual(gtk_widget_compute_expand(root.widget, GTK_ORIENTATION_VERTICAL), 0)
        XCTAssertEqual(frames(root.widget, 200, 100), [[0, 0, 200, 100], [90, 45, 20, 10]])
    }
}
