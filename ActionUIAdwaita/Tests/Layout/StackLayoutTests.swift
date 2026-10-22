// Tests/Layout/StackLayoutTests.swift
/*
 Tests for StackLayout and the stack and Spacer renderers on GTK: measured sizes, where children
 are placed (alignment, centering, spacing), Spacers, equal shares for expanding children, frame
 caps, height for width, and expand flags propagating to the stack. Leaves are a test renderer
 for Rectangle: a box of a given size that expands where told.
*/

import XCTest
import CAdwaita
@testable import ActionUI

/// Rectangle as an empty box: "w" and "h" its size, "fill" one of "h", "v", "both".
@MainActor
enum TestBlockRenderer: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        let properties = node.properties
        gtk_widget_set_size_request(widget, Int32(properties.int(forKey: "w") ?? 0), Int32(properties.int(forKey: "h") ?? 0))
        let fill = properties["fill"] as? String
        gtk_widget_set_hexpand(widget, fill == "h" || fill == "both" ? 1 : 0)
        gtk_widget_set_vexpand(widget, fill == "v" || fill == "both" ? 1 : 0)
    }
}

/// Text as a wrapping label of the model's value, for height-for-width.
@MainActor
enum TestWrappingTextRenderer: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        let label = gtk_label_new(nil)!
        gtk_label_set_wrap(opaque(label), 1)
        return label
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        gtk_label_set_text(opaque(widget), node.model.value as? String ?? "")
    }
}

@MainActor
final class StackLayoutTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        ActionUIRegistry.shared.renderers["Rectangle"] = TestBlockRenderer.self
        ActionUIRegistry.shared.renderers["Text"] = TestWrappingTextRenderer.self
        windowUUID = "stack-layout-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIRegistry.shared.loadBuiltIns()
    }

    /// The root element's widget (the stack itself, inside its box) of `json`, rendered (kept
    /// alive until the test ends). The stack's children are their nodes' boxes.
    private func render(_ json: String) throws -> WidgetPointer {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root?.widget)
    }

    private func block(_ id: Int, _ width: Int, _ height: Int, fill: String? = nil) -> String {
        let fillText = fill.map { #", "fill": "\#($0)""# } ?? ""
        return #"{"type": "Rectangle", "id": \#(id), "properties": {"w": \#(width), "h": \#(height)\#(fillText)}}"#
    }

    private func measure(_ widget: WidgetPointer, _ orientation: GtkOrientation, forSize: Int32 = -1) -> (Int32, Int32) {
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(widget, orientation, forSize, &minimum, &natural, nil, nil)
        return (minimum, natural)
    }

    /// Each child's frame in the stack after allocating the stack `width` x `height`.
    private func frames(_ stack: WidgetPointer, _ width: Int32, _ height: Int32) -> [[Int]] {
        gtk_widget_allocate(stack, width, height, -1, nil)
        var result: [[Int]] = []
        var child = gtk_widget_get_first_child(stack)
        while let current = child {
            var bounds = graphene_rect_t()
            _ = gtk_widget_compute_bounds(current, stack, &bounds)
            result.append([Int(bounds.origin.x), Int(bounds.origin.y), Int(bounds.size.width), Int(bounds.size.height)])
            child = gtk_widget_get_next_sibling(current)
        }
        return result
    }

    private func vstack(alignment: String, _ children: [String], spacing: Int = 10) -> String {
        #"{"type": "VStack", "id": 1, "properties": {"spacing": \#(spacing), "alignment": "\#(alignment)"}, "children": [\#(children.joined(separator: ","))]}"#
    }

    func testAVStackMeasuresItsChildrenPlusSpacing() throws {
        let stack = try render(vstack(alignment: "center", [block(2, 50, 20), block(3, 80, 30)]))
        XCTAssertEqual(measure(stack, GTK_ORIENTATION_VERTICAL).0, 60)
        XCTAssertEqual(measure(stack, GTK_ORIENTATION_VERTICAL).1, 60)
        XCTAssertEqual(measure(stack, GTK_ORIENTATION_HORIZONTAL).1, 80)
    }

    func testAVStackCentersItsGroupAndAlignsChildrenInTheBlock() throws {
        // The block is the widest child (80), centered in 200: it starts at 60. The group (60
        // high) is centered in 100: it starts at 20.
        let center = try render(vstack(alignment: "center", [block(2, 50, 20), block(3, 80, 30)]))
        XCTAssertEqual(frames(center, 200, 100), [[75, 20, 50, 20], [60, 50, 80, 30]])
    }

    func testLeadingAndTrailingAlignToTheStacksEdgesNotTheWindows() throws {
        let leading = try render(vstack(alignment: "leading", [block(2, 50, 20), block(3, 80, 30)]))
        XCTAssertEqual(frames(leading, 200, 100).map { $0[0] }, [60, 60])
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let trailing = try render(vstack(alignment: "trailing", [block(2, 50, 20), block(3, 80, 30)]))
        XCTAssertEqual(frames(trailing, 200, 100).map { $0[0] }, [90, 60])
    }

    func testASpacerTakesTheRestOfAVStackAndMakesItExpand() throws {
        let stack = try render(vstack(alignment: "center", [block(2, 40, 20), #"{"type": "Spacer", "id": 3}"#, block(4, 40, 20)], spacing: 0))
        XCTAssertEqual(frames(stack, 100, 200), [[30, 0, 40, 20], [50, 20, 0, 160], [30, 180, 40, 20]])
        XCTAssertNotEqual(gtk_widget_compute_expand(stack, GTK_ORIENTATION_VERTICAL), 0, "the spacer's expansion propagates")
        XCTAssertEqual(gtk_widget_compute_expand(stack, GTK_ORIENTATION_HORIZONTAL), 0)
        XCTAssertEqual(measure(stack, GTK_ORIENTATION_VERTICAL).0, 48, "the spacer's minimum length is 8")
    }

    func testASpacersMinLengthIsAlongItsStacksAxis() throws {
        let stack = try render(#"{"type": "HStack", "id": 1, "properties": {"spacing": 0}, "children": [{"type": "Spacer", "id": 2, "properties": {"minLength": 30}}]}"#)
        XCTAssertEqual(measure(stack, GTK_ORIENTATION_HORIZONTAL).0, 30)
        XCTAssertEqual(measure(stack, GTK_ORIENTATION_VERTICAL).0, 0)
    }

    func testExpandingChildrenOfAnHStackGetEqualWidths() throws {
        let stack = try render(#"{"type": "HStack", "id": 1, "properties": {"spacing": 0}, "children": [\#(block(2, 10, 20, fill: "h")), \#(block(3, 50, 20, fill: "h"))]}"#)
        XCTAssertEqual(frames(stack, 300, 20).map { $0[2] }, [150, 150])
    }

    func testAnHStackWithoutSpacingUsesEight() throws {
        let stack = try render(#"{"type": "HStack", "id": 1, "children": [\#(block(2, 10, 10)), \#(block(3, 10, 10))]}"#)
        XCTAssertEqual(measure(stack, GTK_ORIENTATION_HORIZONTAL).1, 28)
    }

    func testAnHStackWithoutSpacingPutsNoneNextToASpacer() throws {
        // SwiftUI on macOS: 20 at 0, the spacer 20...180, 20 at 180.
        let stack = try render(#"{"type": "HStack", "id": 1, "children": [\#(block(2, 20, 20)), {"type": "Spacer", "id": 3}, \#(block(4, 20, 20))]}"#)
        XCTAssertEqual(measure(stack, GTK_ORIENTATION_HORIZONTAL).0, 48, "20 + 8 + 20, no gaps")
        XCTAssertEqual(frames(stack, 200, 20).map { [$0[0], $0[2]] }, [[0, 20], [20, 160], [180, 20]])
        // Explicit spacing applies next to the spacer too (SwiftUI: 20, 30...170, 180).
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let spaced = try render(#"{"type": "HStack", "id": 1, "properties": {"spacing": 10}, "children": [\#(block(2, 20, 20)), {"type": "Spacer", "id": 3}, \#(block(4, 20, 20))]}"#)
        XCTAssertEqual(frames(spaced, 200, 20).map { [$0[0], $0[2]] }, [[0, 20], [30, 140], [180, 20]])
    }

    func testASpacerYieldsToAnExpandingSibling() throws {
        // SwiftUI on macOS: the fixed child 50, the spacer its minimum 8, the expanding child 242.
        let stack = try render(#"{"type": "HStack", "id": 1, "properties": {"spacing": 0}, "children": [\#(block(2, 50, 20)), {"type": "Spacer", "id": 3}, \#(block(4, 0, 20, fill: "h"))]}"#)
        XCTAssertEqual(frames(stack, 300, 20).map { $0[2] }, [50, 8, 242])
    }

    func testHugeDocumentLengthsDoNotCrash() throws {
        let stack = try render(#"{"type": "HStack", "id": 1, "properties": {"spacing": 1e300}, "children": [{"type": "Spacer", "id": 2, "properties": {"minLength": 1e300}}, \#(block(3, 10, 10))]}"#)
        let (minimum, natural) = measure(stack, GTK_ORIENTATION_HORIZONTAL)
        XCTAssertGreaterThanOrEqual(minimum, Int32(StackSolver.maximumLength))
        XCTAssertGreaterThanOrEqual(natural, minimum)
    }

    func testAFrameCapLimitsAnExpandingChild() throws {
        let capped = #"{"type": "Rectangle", "id": 3, "properties": {"w": 0, "h": 20, "fill": "h", "frame": {"maxWidth": 50}}}"#
        let stack = try render(#"{"type": "HStack", "id": 1, "properties": {"spacing": 0}, "children": [\#(block(2, 0, 20, fill: "h")), \#(capped)]}"#)
        XCTAssertEqual(frames(stack, 300, 20).map { $0[2] }, [250, 50])
    }

    func testAnHStacksChildrenAlignOnTheCrossAxisAndAVerticalFillerTakesTheHeight() throws {
        let stack = try render(#"{"type": "HStack", "id": 1, "properties": {"spacing": 0, "alignment": "bottom"}, "children": [\#(block(2, 10, 20)), \#(block(3, 10, 40)), \#(block(4, 10, 5, fill: "v"))]}"#)
        // The filler takes the whole height, so the block is 100 high and the others sit at its bottom.
        XCTAssertEqual(frames(stack, 30, 100).map { [$0[1], $0[3]] }, [[80, 20], [60, 40], [0, 100]])
    }

    func testWrappingTextMakesAVStackTallerWhenNarrower() throws {
        let words = Array(repeating: "word", count: 40).joined(separator: " ")
        let stack = try render(vstack(alignment: "center", [#"{"type": "Text", "id": 2, "properties": {"text": "\#(words)"}}"#]))
        let narrow = measure(stack, GTK_ORIENTATION_VERTICAL, forSize: 100).1
        let wide = measure(stack, GTK_ORIENTATION_VERTICAL, forSize: 1000).1
        XCTAssertGreaterThan(narrow, wide)
        // An HStack's height for a width wraps its children at the widths it gives them.
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let row = try render(#"{"type": "HStack", "id": 1, "children": [{"type": "Text", "id": 2, "properties": {"text": "\#(words)"}}]}"#)
        XCTAssertGreaterThan(measure(row, GTK_ORIENTATION_VERTICAL, forSize: 100).1,
                             measure(row, GTK_ORIENTATION_VERTICAL, forSize: 1000).1)
    }

    func testAnInsertedChildTakesItsPlaceInTheStack() throws {
        let stack = try render(vstack(alignment: "center", [block(2, 10, 10), block(3, 10, 10)], spacing: 0))
        _ = try ActionUIModel.shared.insertElement(windowUUID: windowUUID, parentID: 1, json: block(4, 10, 30), position: .at(1))
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(frames(stack, 10, 50).map { $0[3] }, [10, 30, 10])
    }
}
