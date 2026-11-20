// Tests/Elements/LazyRowsRendererTests.swift
/*
 Tests for the template form of LazyVStack and LazyHStack (LazyRows): in a ScrollView a row is made
 only when it comes in or near view and let go when far from it; outside one every row is made;
 rows are kept by index (a changed row is made again, rows are added and removed at the end); and
 the row at the top of the visible part stays in place when rows made above it turn out longer than
 estimated. The document and numbers follow the Windows preview's LazyRows.json (2000 rows scrolled
 to 20000, 500 columns scrolled to 4000), so the two platforms can be compared.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class LazyRowsRendererTests: XCTestCase {
    private var windowUUID = ""
    private var tree: AdwaitaWindow?
    private var gtkWindow: UnsafeMutablePointer<GtkWindow>?

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "lazy-rows-\(name)"
    }

    override func tearDown() async throws {
        if let gtkWindow {
            gtk_window_destroy(gtkWindow)
        }
        gtkWindow = nil
        tree = nil
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
    }

    /// The document of the Windows preview's LazyRows.json: a ScrollView 260 high holding a
    /// LazyVStack of two texts per row, and a horizontal ScrollView 44 high holding a LazyHStack of
    /// padded yellow texts.
    private let document = #"""
        {"type": "VStack", "id": 1, "properties": {"spacing": 8, "alignment": "leading", "padding": 16}, "children": [
          {"type": "Text", "id": 2, "properties": {"text": "2000 rows, made as they come into view", "font": "headline"}},
          {"type": "ScrollView", "id": 3, "properties": {"frame": {"height": 260}}, "content":
            {"type": "LazyVStack", "id": 4, "properties": {"spacing": 4, "alignment": "leading"}, "template":
              {"type": "HStack", "id": 5, "children": [
                {"type": "Text", "id": 6, "properties": {"text": "$1"}},
                {"type": "Text", "id": 7, "properties": {"text": "$2", "foregroundStyle": "secondary"}}]}}},
          {"type": "Text", "id": 8, "properties": {"text": "500 columns", "font": "headline"}},
          {"type": "ScrollView", "id": 9, "properties": {"axis": "horizontal", "frame": {"height": 44}}, "content":
            {"type": "LazyHStack", "id": 10, "properties": {"spacing": 6}, "template":
              {"type": "Text", "id": 11, "properties": {"text": "$1", "padding": 6, "background": "yellow"}}}}]}
        """#

    /// `json` in a window on screen, 480 x 520.
    private func present(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let tree = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        self.tree = tree
        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        gtkWindow = window
        gtk_window_set_default_size(window, 480, 520)
        adw_window_set_content(typed(window), tree.contentWidget)
        gtk_window_present(window)
        settle()
        return try XCTUnwrap(tree.root)
    }

    /// `json` in a window that is not shown.
    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let tree = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        self.tree = tree
        AdwaitaTestHost.drainMainLoop()
        return try XCTUnwrap(tree.root)
    }

    /// Runs the main loop long enough for the rows to be made, laid out and drawn.
    private func settle() {
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: 400)
        AdwaitaTestHost.drainMainLoop()
    }

    private func setRows(_ viewID: Int, _ rows: [[String]]) {
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: viewID, rows: rows)
        settle()
    }

    private func node(_ id: Int, in root: RenderNode) -> RenderNode? {
        if root.element.id == id { return root }
        for child in root.childNodes.values {
            if let found = node(id, in: child) { return found }
        }
        return nil
    }

    private func lazyRows(_ id: Int, in root: RenderNode) throws -> LazyRows {
        let stack = try XCTUnwrap(node(id, in: root))
        return try XCTUnwrap(attached(on: stack.widget, key: lazyRowsKey))
    }

    private func adjustment(_ scrollViewID: Int, in root: RenderNode, vertical: Bool) throws -> UnsafeMutablePointer<GtkAdjustment> {
        let scroller = OpaquePointer(try XCTUnwrap(node(scrollViewID, in: root)).widget)
        return try XCTUnwrap(vertical ? gtk_scrolled_window_get_vadjustment(scroller) : gtk_scrolled_window_get_hadjustment(scroller))
    }

    /// The texts of `widget`'s labels, depth first.
    private func texts(_ widget: WidgetPointer) -> [String] {
        Gtk.Widget(widget).children.flatMap { child -> [String] in
            child.isA(gtk_label_get_type()) ? [Gtk.Label(child.pointer).text] : texts(child.pointer)
        }
    }

    /// The made row shown at `position` along the axis in the stack (the one before the gap when
    /// `position` is between two rows), and where its box starts; nil when no made row covers it.
    private func madeRow(at position: Double, in rows: LazyRows, vertical: Bool) -> (index: Int, start: Double)? {
        var found: (index: Int, start: Double, end: Double)?
        for (index, row) in rows.made {
            let box = row.outerWidget!
            var bounds = graphene_rect_t()
            guard let stack = gtk_widget_get_parent(box), gtk_widget_compute_bounds(box, stack, &bounds) != 0 else { continue }
            let start = Double(vertical ? bounds.origin.y : bounds.origin.x)
            let end = start + Double(vertical ? bounds.size.height : bounds.size.width)
            if start <= position && start > (found?.start ?? -Double.infinity) {
                found = (index, start, end)
            }
        }
        // Past the row found by more than a gap: no made row there.
        guard let found, position < found.end + Double(rows.spacing) else { return nil }
        return (found.index, found.start)
    }

    private func numbered(_ count: Int) -> [[String]] {
        (0..<count).map { ["Row \($0)", "detail \($0)"] }
    }

    func testALazyVStackInAScrollViewMakesOnlyTheRowsNearView() throws {
        let root = try present(document)
        setRows(4, numbered(2000))
        let rows = try lazyRows(4, in: root)
        XCTAssertGreaterThan(rows.made.count, 0)
        XCTAssertLessThan(rows.made.count, 200, "made: \(rows.made.count) of 2000")
        XCTAssertNotNil(rows.made[0])
        XCTAssertEqual(texts(try XCTUnwrap(rows.made[0]).outerWidget), ["Row 0", "detail 0"])

        let vertical = try adjustment(3, in: root, vertical: true)
        gtk_adjustment_set_value(vertical, 20000)
        settle()
        let value = gtk_adjustment_get_value(vertical)
        XCTAssertLessThan(rows.made.count, 200, "made: \(rows.made.count) of 2000")
        XCTAssertNil(rows.made[0], "the first row is let go far from view")
        let top = try XCTUnwrap(madeRow(at: value, in: rows, vertical: true), "a made row at the top of the visible part")
        let bottom = try XCTUnwrap(madeRow(at: value + 259, in: rows, vertical: true), "a made row at the bottom of the visible part")
        XCTAssertEqual(texts(try XCTUnwrap(rows.made[top.index]).outerWidget), ["Row \(top.index)", "detail \(top.index)"])
        XCTAssertGreaterThan(top.index, 500)
        print("[lazy rows] LazyVStack: \(rows.made.count) of 2000 made, rows \(top.index) to \(bottom.index) shown at \(value)")
    }

    func testALazyHStackInAHorizontalScrollViewMakesOnlyTheColumnsNearView() throws {
        let root = try present(document)
        setRows(10, (0..<500).map { ["\($0)"] })
        let columns = try lazyRows(10, in: root)
        XCTAssertGreaterThan(columns.made.count, 0)
        XCTAssertLessThan(columns.made.count, 200, "made: \(columns.made.count) of 500")
        let horizontal = try adjustment(9, in: root, vertical: false)
        gtk_adjustment_set_value(horizontal, 4000)
        settle()
        let value = gtk_adjustment_get_value(horizontal)
        XCTAssertLessThan(columns.made.count, 200, "made: \(columns.made.count) of 500")
        XCTAssertNil(columns.made[0])
        let first = try XCTUnwrap(madeRow(at: value, in: columns, vertical: false))
        XCTAssertEqual(texts(try XCTUnwrap(columns.made[first.index]).outerWidget), ["\(first.index)"])
        XCTAssertGreaterThan(first.index, 50)
        let page = gtk_adjustment_get_page_size(horizontal)
        let last = try XCTUnwrap(madeRow(at: value + page - 1, in: columns, vertical: false))
        print("[lazy rows] LazyHStack: \(columns.made.count) of 500 made, columns \(first.index) to \(last.index) shown at \(value)")
    }

    func testOutsideAScrollViewEveryRowIsMade() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "LazyVStack", "id": 2, "template": {"type": "Text", "properties": {"text": "$1"}}}]}
            """#)
        setRows(2, numbered(300))
        let rows = try lazyRows(2, in: root)
        XCTAssertEqual(rows.made.count, 300)
        XCTAssertEqual(texts(try XCTUnwrap(node(2, in: root)).widget).prefix(3), ["Row 0", "Row 1", "Row 2"])
    }

    func testAChangedRowIsMadeAgainAndTheOthersAreKept() throws {
        let root = try present(document)
        var data = numbered(2000)
        setRows(4, data)
        let rows = try lazyRows(4, in: root)
        let first = try XCTUnwrap(rows.made[1])
        let second = try XCTUnwrap(rows.made[2])
        data[2] = ["Changed", "row"]
        setRows(4, data)
        XCTAssertTrue(rows.made[1] === first, "an unchanged row keeps its instance")
        let remade = try XCTUnwrap(rows.made[2])
        XCTAssertFalse(remade === second, "a changed row is made again")
        XCTAssertFalse(second.isAttached)
        XCTAssertEqual(texts(remade.outerWidget), ["Changed", "row"])
    }

    func testRowsAreAddedAndRemovedAtTheEnd() throws {
        let root = try present(document)
        setRows(4, numbered(2000))
        let rows = try lazyRows(4, in: root)
        let stack = try XCTUnwrap(node(4, in: root)).widget!
        let tall = gtk_widget_get_height(stack)
        setRows(4, numbered(5))
        XCTAssertEqual(rows.made.keys.sorted(), [0, 1, 2, 3, 4])
        XCTAssertLessThan(gtk_widget_get_height(stack), tall / 100, "the stack is as long as its five rows")
        setRows(4, numbered(8))
        XCTAssertEqual(rows.made.keys.sorted(), Array(0..<8))
        XCTAssertEqual(texts(stack).suffix(2), ["Row 7", "detail 7"])
    }

    func testNewDataOfTheSameLengthsKeepsTheRowsInView() throws {
        let root = try present(document)
        setRows(4, numbered(2000))
        let rows = try lazyRows(4, in: root)
        let vertical = try adjustment(3, in: root, vertical: true)
        gtk_adjustment_set_value(vertical, 20000)
        settle()
        let valueBefore = gtk_adjustment_get_value(vertical)
        let before = try XCTUnwrap(madeRow(at: valueBefore, in: rows, vertical: true))
        // Every row's data changes, none of their lengths.
        setRows(4, (0..<2000).map { ["Item \($0)", "note \($0)"] })
        let value = gtk_adjustment_get_value(vertical)
        let after = try XCTUnwrap(madeRow(at: value, in: rows, vertical: true))
        XCTAssertEqual(after.index, before.index, "the same row at the top")
        XCTAssertEqual(value - after.start, valueBefore - before.start, accuracy: 1, "at the same place")
        XCTAssertEqual(texts(try XCTUnwrap(rows.made[after.index]).outerWidget), ["Item \(after.index)", "note \(after.index)"])
    }

    func testTheTopVisibleRowStaysInPlaceWhenRowsMadeAboveItAreLonger() throws {
        // A header above the stack in the scrolled content; the first rows one line, the rest three:
        // the estimate from the first rows is too short for the rows made later.
        let root = try present(#"""
            {"type": "ScrollView", "id": 1, "properties": {"frame": {"height": 300}}, "content":
              {"type": "VStack", "id": 2, "properties": {"spacing": 0}, "children": [
                {"type": "Text", "id": 3, "properties": {"text": "Header", "padding": 20}},
                {"type": "LazyVStack", "id": 4, "properties": {"alignment": "leading"}, "template":
                  {"type": "Text", "properties": {"text": "$1"}}}]}}
            """#)
        setRows(4, (0..<2000).map { $0 < 30 ? ["Row \($0)"] : ["Row \($0)\nsecond line\nthird line"] })
        let rows = try lazyRows(4, in: root)
        let vertical = try adjustment(1, in: root, vertical: true)
        let header = try XCTUnwrap(rows.contentOffset)
        XCTAssertGreaterThan(header, 0)
        // Where the visible part will start, by the current estimate: inside row `anchor`, `inside` into it.
        let target = 3000.0
        let cross = rows.allocatedCross
        let anchor = try XCTUnwrap(rows.row(at: Int(target - header), cross: cross))
        let inside = target - header - Double(rows.offset(of: anchor, cross: cross))
        gtk_adjustment_set_value(vertical, target)
        settle()
        let value = gtk_adjustment_get_value(vertical)
        XCTAssertGreaterThan(value, target + 100, "the rows above turned out longer: the position moved down")
        let shown = try XCTUnwrap(madeRow(at: value - header, in: rows, vertical: true))
        XCTAssertEqual(shown.index, anchor, "the same row at the top")
        XCTAssertEqual(value - header - shown.start, inside, accuracy: 1, "at the same place")
    }

    func testTheTopVisibleRowStaysInPlaceWhenTheWidthChanges() throws {
        // Every third row wraps more lines in a narrower stack: the lengths above change unevenly.
        let long = "a row long enough to wrap onto more lines when the scroll view becomes narrower than before"
        let root = try present(#"""
            {"type": "ScrollView", "id": 1, "properties": {"frame": {"width": 440, "height": 300}}, "content":
              {"type": "LazyVStack", "id": 2, "properties": {"alignment": "leading", "spacing": 2}, "template":
                {"type": "Text", "properties": {"text": "$1"}}}}
            """#)
        setRows(2, (0..<2000).map { $0 % 3 == 0 ? ["\($0) \(long)"] : ["\($0)"] })
        let rows = try lazyRows(2, in: root)
        let vertical = try adjustment(1, in: root, vertical: true)
        gtk_adjustment_set_value(vertical, 6000)
        settle()
        let valueBefore = gtk_adjustment_get_value(vertical)
        let before = try XCTUnwrap(madeRow(at: valueBefore, in: rows, vertical: true))
        let stack = try XCTUnwrap(node(2, in: root)).widget!
        let heightBefore = gtk_widget_get_height(stack)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "frame",
                                                value: ["width": 240, "height": 300])
        settle()
        XCTAssertGreaterThan(gtk_widget_get_height(stack), heightBefore, "the rows wrap onto more lines")
        let value = gtk_adjustment_get_value(vertical)
        let after = try XCTUnwrap(madeRow(at: value, in: rows, vertical: true))
        XCTAssertEqual(after.index, before.index, "the same row at the top")
        XCTAssertEqual(value - after.start, valueBefore - before.start, accuracy: 1, "at the same place in it")
    }

    func testTheTopVisibleRowStaysInPlaceWhenAWiderStackIsShorterThanTheScrollPosition() throws {
        // The rows but the last 100 wrap; the short last rows are shown. In a wider stack the rows
        // above are estimated at the short rows' length, so the stack becomes shorter than the scroll
        // position and the viewport moves it back before the stack is laid out at its new width.
        let long = "a row long enough to wrap onto more lines when the scroll view becomes narrower than before"
        let root = try present(#"""
            {"type": "ScrollView", "id": 1, "properties": {"frame": {"width": 240, "height": 300}}, "content":
              {"type": "LazyVStack", "id": 2, "properties": {"alignment": "leading", "spacing": 2}, "template":
                {"type": "Text", "properties": {"text": "$1"}}}}
            """#)
        setRows(2, (0..<2000).map { $0 < 1900 ? ["\($0) \(long)"] : ["\($0)"] })
        let rows = try lazyRows(2, in: root)
        let vertical = try adjustment(1, in: root, vertical: true)
        gtk_adjustment_set_value(vertical, gtk_adjustment_get_upper(vertical))
        settle()
        gtk_adjustment_set_value(vertical, gtk_adjustment_get_value(vertical) - 1000)
        settle()
        let valueBefore = gtk_adjustment_get_value(vertical)
        let before = try XCTUnwrap(madeRow(at: valueBefore, in: rows, vertical: true))
        XCTAssertGreaterThanOrEqual(before.index, 1900, "a short row at the top")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "frame",
                                                value: ["width": 440, "height": 300])
        settle()
        let value = gtk_adjustment_get_value(vertical)
        XCTAssertLessThan(value, valueBefore, "the stack became shorter")
        let after = try XCTUnwrap(madeRow(at: value, in: rows, vertical: true))
        XCTAssertEqual(after.index, before.index, "the same row at the top")
        XCTAssertEqual(value - after.start, valueBefore - before.start, accuracy: 1, "at the same place in it")
    }
}
