// Tests/Elements/ScrollViewReaderRendererTests.swift
/*
 Tests for the ScrollViewReader renderer on GTK: once laid out, the reader scrolls its ScrollView
 so the scrollTo element is at the top, the center or the bottom (within the scroll range), and
 again after a write to the reader, also of the same id once the user scrolled away; in a
 horizontal ScrollView the element is centered; shown again, the reader scrolls back; an id the
 reader does not hold scrolls nothing.
 The tests are not on screen, so a scroll after a write jumps instead of animating.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ScrollViewReaderRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "scrollviewreader-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIRegistry.shared.loadBuiltIns()
    }

    /// A reader 300 x 300 around a ScrollView of twelve rows 100 long (ids 2...13), laid out.
    private func render(scrollTo: Int, anchor: String, axis: String = "vertical", laidOut: Bool = true) throws -> RenderNode {
        let frame = axis == "vertical" ? #""width": 200, "height": 100"# : #""width": 100, "height": 200"#
        let rows = (2...13).map { ##"{"type": "Color", "id": \##($0), "properties": {"color": "#FF0000", "frame": {\##(frame)}}}"## }
        let stack = axis == "vertical" ? "VStack" : "HStack"
        let json = #"{"type": "ScrollViewReader", "id": 1, "properties": {"scrollTo": \#(scrollTo), "anchor": "\#(anchor)", "frame": {"width": 300, "height": 300}}, "content": {"type": "ScrollView", "id": 20, "properties": {"axis": "\#(axis)"}, "content": {"type": "\#(stack)", "id": 21, "properties": {"spacing": 0}, "children": [\#(rows.joined(separator: ","))]}}}"#
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        let root = try XCTUnwrap(window.root)
        if laidOut { layOut(root) }
        return root
    }

    /// Lays the reader out at 300 x 300 and runs what that scheduled (the scroll), twice: a scroll
    /// moves the content at the next layout.
    private func layOut(_ root: RenderNode) {
        for _ in 0..<2 {
            gtk_widget_allocate(root.outerWidget, 300, 300, -1, nil)
            AdwaitaTestHost.drainMainLoop()
        }
    }

    private func adjustment(_ root: RenderNode, horizontal: Bool = false) throws -> UnsafeMutablePointer<GtkAdjustment> {
        let scroller = try XCTUnwrap(root.childNodes[20]).widget
        let window = OpaquePointer(scroller)
        return try XCTUnwrap(horizontal ? gtk_scrolled_window_get_hadjustment(window) : gtk_scrolled_window_get_vadjustment(window))
    }

    func testTheTargetIsAtTheTopOnceLaidOut() throws {
        let root = try render(scrollTo: 5, anchor: "top")
        // Id 5 is the fourth row: its top is 300 down the content.
        XCTAssertEqual(gtk_adjustment_get_value(try adjustment(root)), 300, accuracy: 0.5)
        let row = try XCTUnwrap(root.childNodes[20]?.childNodes[21]?.childNodes[5])
        var bounds = graphene_rect_t()
        XCTAssertNotEqual(gtk_widget_compute_bounds(row.widget, root.outerWidget, &bounds), 0)
        XCTAssertEqual(Double(bounds.origin.y), 0, accuracy: 0.5, "the row is drawn at the top")
    }

    func testARequestMadeBeforeTheFirstLayoutWaitsForIt() throws {
        let root = try render(scrollTo: 5, anchor: "top", laidOut: false)
        // What the first sync scheduled runs before any layout: the request waits.
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_adjustment_get_value(try adjustment(root)), 0)
        // The ScrollView's first layout scrolls.
        layOut(root)
        XCTAssertEqual(gtk_adjustment_get_value(try adjustment(root)), 300, accuracy: 0.5)
    }

    func testAWriteThatAlsoMovesTheTargetScrollsToItsNewPlace() throws {
        let root = try render(scrollTo: 5, anchor: "top")
        // In one flush, the row above grows by 200 and the reader is written again.
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 3, propertyName: "frame", value: ["width": 200, "height": 300])
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "scrollTo", value: 5)
        AdwaitaTestHost.drainMainLoop()
        layOut(root)
        XCTAssertEqual(gtk_adjustment_get_value(try adjustment(root)), 500, accuracy: 0.5, "the row's top after the change")
    }

    func testNestedScrollViewsBothBringTheTargetIntoView() throws {
        // An outer ScrollView (id 20) of 400 + a ScrollView 200 high (id 40) + 400; the inner one
        // holds twelve rows 100 long (ids 2...13).
        let rows = (2...13).map { ##"{"type": "Color", "id": \##($0), "properties": {"color": "#FF0000", "frame": {"width": 200, "height": 100}}}"## }
        let spacer = { (id: Int) in ##"{"type": "Color", "id": \##(id), "properties": {"color": "#0000FF", "frame": {"width": 200, "height": 400}}}"## }
        let inner = #"{"type": "ScrollView", "id": 40, "properties": {"frame": {"width": 200, "height": 200}}, "content": {"type": "VStack", "id": 41, "properties": {"spacing": 0}, "children": [\#(rows.joined(separator: ","))]}}"#
        let json = #"{"type": "ScrollViewReader", "id": 1, "properties": {"scrollTo": 9, "anchor": "top", "frame": {"width": 300, "height": 300}}, "content": {"type": "ScrollView", "id": 20, "content": {"type": "VStack", "id": 21, "properties": {"spacing": 0}, "children": [\#(spacer(30)), \#(inner), \#(spacer(31))]}}}"#
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        let root = try XCTUnwrap(window.root)
        layOut(root)
        let innerNode = try XCTUnwrap(root.childNodes[20]?.childNodes[21]?.childNodes[40])
        let innerAdjustment = try XCTUnwrap(gtk_scrolled_window_get_vadjustment(OpaquePointer(innerNode.widget)))
        // Id 9 is 700 down the inner content; the inner ScrollView then shows it at its top, which
        // is 400 down the outer content.
        XCTAssertEqual(gtk_adjustment_get_value(innerAdjustment), 700, accuracy: 0.5)
        XCTAssertEqual(gtk_adjustment_get_value(try adjustment(root)), 400, accuracy: 0.5)
        let row = try XCTUnwrap(innerNode.childNodes[41]?.childNodes[9])
        var bounds = graphene_rect_t()
        XCTAssertNotEqual(gtk_widget_compute_bounds(row.widget, root.outerWidget, &bounds), 0)
        XCTAssertEqual(Double(bounds.origin.y), 0, accuracy: 0.5, "the row is drawn at the top of the reader")
    }

    func testTheCenterAndBottomAnchors() throws {
        let root = try render(scrollTo: 7, anchor: "center")
        // Id 7 spans 500...600: its middle at the middle of 300.
        XCTAssertEqual(gtk_adjustment_get_value(try adjustment(root)), 400, accuracy: 0.5)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "anchor", value: "bottom")
        AdwaitaTestHost.drainMainLoop()
        layOut(root)
        // Its bottom, 600, at the bottom of 300.
        XCTAssertEqual(gtk_adjustment_get_value(try adjustment(root)), 300, accuracy: 0.5)
    }

    func testATargetPastTheEndStopsAtTheEnd() throws {
        let root = try render(scrollTo: 13, anchor: "top")
        // 1200 of content in 300: the last row cannot reach the top.
        XCTAssertEqual(gtk_adjustment_get_value(try adjustment(root)), 900, accuracy: 0.5)
    }

    func testWritingTheSameTargetAgainBringsItBack() throws {
        let root = try render(scrollTo: 5, anchor: "top")
        let adjustment = try adjustment(root)
        // The user scrolls back to the top.
        gtk_adjustment_set_value(adjustment, 0)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "scrollTo", value: 5)
        AdwaitaTestHost.drainMainLoop()
        layOut(root)
        XCTAssertEqual(gtk_adjustment_get_value(adjustment), 300, accuracy: 0.5)
    }

    func testANewTargetScrollsToIt() throws {
        let root = try render(scrollTo: 5, anchor: "top")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "scrollTo", value: 3)
        AdwaitaTestHost.drainMainLoop()
        layOut(root)
        XCTAssertEqual(gtk_adjustment_get_value(try adjustment(root)), 100, accuracy: 0.5)
    }

    func testAHorizontalScrollViewCentersTheTarget() throws {
        let root = try render(scrollTo: 7, anchor: "top", axis: "horizontal")
        // Id 7 spans 500...600 across: SwiftUI's top anchor centers it horizontally.
        XCTAssertEqual(gtk_adjustment_get_value(try adjustment(root, horizontal: true)), 400, accuracy: 0.5)
    }

    func testShownAgainItScrollsBack() throws {
        let root = try render(scrollTo: 5, anchor: "top")
        let adjustment = try adjustment(root)
        // The user scrolls to the top; then the reader is mapped again (a tab returning).
        gtk_adjustment_set_value(adjustment, 0)
        ScrollViewReader.shownAgain(try XCTUnwrap(attached(on: root.widget, key: scrollReaderStateKey)))
        layOut(root)
        XCTAssertEqual(gtk_adjustment_get_value(adjustment), 300, accuracy: 0.5)
    }

    func testAnIdTheReaderDoesNotHoldScrollsNothing() throws {
        let root = try render(scrollTo: 99, anchor: "top")
        XCTAssertEqual(gtk_adjustment_get_value(try adjustment(root)), 0)
    }
}
