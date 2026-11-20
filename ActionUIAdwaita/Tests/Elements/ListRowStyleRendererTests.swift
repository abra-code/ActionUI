// Tests/Elements/ListRowStyleRendererTests.swift
/*
 Tests for a List's row styling on GTK, against what SwiftUI draws on macOS: plain rows with the
 text 4 points from the row's top and 16 from the list's side, 24 points tall at least;
 listRowInsets replacing the 4 points above and below and adding its leading to the 16, in every
 form; a listRowBackground filling unselected rows across the list's width; listRowSeparator hidden
 and visible; listRowSeparatorTint coloring the lines; the other styles keeping libadwaita's rows
 without insets.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ListRowStyleRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var gtkWindows: [UnsafeMutablePointer<GtkWindow>] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "list-row-style-\(name)"
    }

    override func tearDown() async throws {
        for window in gtkWindows {
            gtk_window_destroy(window)
        }
        gtkWindows = []
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

    private func box(_ node: RenderNode) throws -> WidgetPointer {
        try XCTUnwrap(attached(on: node.widget, key: listStateKey)).box
    }

    /// Whether the List's list view or list box draws lines between its rows.
    private func showsSeparators(_ node: RenderNode) throws -> Bool {
        let box = try box(node)
        if Gtk.Widget(box).isA(gtk_list_view_get_type()) {
            return gtk_list_view_get_show_separators(OpaquePointer(box)) != 0
        }
        return gtk_list_box_get_show_separators(OpaquePointer(box)) != 0
    }

    /// A rows list with these properties, showing two rows, laid out 300 wide in a window on screen
    /// (its list view binds its rows there).
    private func rowsList(_ properties: String) throws -> RenderNode {
        let node = try render(#"{"type": "List", "id": 1, "properties": {\#(properties)}}"#)
        let gtkWindow: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        gtkWindows.append(gtkWindow)
        gtk_window_set_default_size(gtkWindow, 300, 300)
        adw_window_set_content(typed(gtkWindow), try XCTUnwrap(windows.last).contentWidget)
        gtk_window_present(gtkWindow)
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["Apple"], ["Cherry"]])
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: 300)
        AdwaitaTestHost.drainMainLoop()
        return node
    }

    /// Row `position` and its content: a list view's cell and the row holding it, or a list box's.
    private func row(_ node: RenderNode, _ position: Int) throws -> (row: WidgetPointer, content: WidgetPointer) {
        if let lazy = try XCTUnwrap(attached(on: node.widget, key: listStateKey)).lazy {
            let cell = try XCTUnwrap(lazy.cells[position]?.cell)
            return (try XCTUnwrap(gtk_widget_get_parent(cell)), cell)
        }
        let row: WidgetPointer = typed(try XCTUnwrap(gtk_list_box_get_row_at_index(OpaquePointer(try box(node)), Int32(position))))
        return (row, try XCTUnwrap(gtk_list_box_row_get_child(typed(row))))
    }

    /// The first row's bounds and its content's, in the scrolled window's coordinates (the list's own
    /// start inside its padding).
    private func firstRow(_ node: RenderNode) throws -> (row: graphene_rect_t, content: graphene_rect_t) {
        let (row, content) = try self.row(node, 0)
        var rowBounds = graphene_rect_t()
        var contentBounds = graphene_rect_t()
        XCTAssertNotEqual(gtk_widget_compute_bounds(row, node.outerWidget, &rowBounds), 0)
        XCTAssertNotEqual(gtk_widget_compute_bounds(content, node.outerWidget, &contentBounds), 0)
        return (rowBounds, contentBounds)
    }

    func testPlainRowsHaveMacOSMetrics() throws {
        let (row, content) = try firstRow(try rowsList(""))
        XCTAssertEqual(content.origin.x, 16, "8 of the list and 8 of the row")
        XCTAssertEqual(content.origin.y - row.origin.y, 4)
        XCTAssertGreaterThanOrEqual(row.size.height, 24)
        XCTAssertEqual(row.origin.x, 8)
    }

    func testInsetsReplaceTheSpaceAboveAndBelowAndAddToTheSides() throws {
        let node = try rowsList(#""listRowInsets": {"top": 12, "leading": 30, "bottom": 12, "trailing": 0}"#)
        let (row, content) = try firstRow(node)
        XCTAssertEqual(content.origin.x, 46, "16 and the leading inset")
        XCTAssertEqual(content.origin.y - row.origin.y, 12)
        XCTAssertEqual(row.size.height, content.size.height + 24 + 1, "and the line below")
    }

    func testTheLastRowHasNoLineBelow() throws {
        let node = try rowsList("")
        let (last, content) = try self.row(node, 1)
        var row = graphene_rect_t()
        var text = graphene_rect_t()
        XCTAssertNotEqual(gtk_widget_compute_bounds(last, node.outerWidget, &row), 0)
        XCTAssertNotEqual(gtk_widget_compute_bounds(content, node.outerWidget, &text), 0)
        XCTAssertEqual(row.size.height, max(24, text.size.height + 8), "no line below")
    }

    func testZeroInsetsKeepTheMinimumHeight() throws {
        let (row, content) = try firstRow(try rowsList(#""listRowInsets": 0"#))
        XCTAssertEqual(content.origin.x, 16)
        XCTAssertEqual(row.size.height, max(24, content.size.height) + 1, "and the line below")
    }

    func testABackgroundFillsUnselectedRowsAcrossTheList() throws {
        let node = try rowsList(##""listRowBackground": "#FFE0B0""##)
        let (row, content) = try firstRow(node)
        XCTAssertEqual(row.origin.x, 0, "the row spans the list's width")
        XCTAssertEqual(Double(row.size.width), Double(gtk_widget_get_width(try box(node))))
        XCTAssertEqual(content.origin.x, 16, "the text stays where it was")
        XCTAssertTrue(StyleSheet.shared.css.contains("> row:not(:selected) { background-color: rgba("), StyleSheet.shared.css)
    }

    func testHiddenSeparatorsTakeTheLinesAway() throws {
        let node = try rowsList(#""listRowSeparator": "hidden", "listStyle": "insetGrouped""#)
        XCTAssertFalse(try showsSeparators(node))
        XCTAssertTrue(StyleSheet.shared.css.contains("> row { border-bottom-width: 0; }"), "the cards' lines too")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "listStyle", value: "plain")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertFalse(try showsSeparators(node))
    }

    func testVisibleSeparatorsShowInTheSidebar() throws {
        let node = try rowsList(#""listStyle": "sidebar""#)
        XCTAssertFalse(try showsSeparators(node))
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "listRowSeparator", value: "visible")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertTrue(try showsSeparators(node))
    }

    func testATintColorsTheLines() throws {
        _ = try rowsList(##""listRowSeparatorTint": "#FF0000""##)
        XCTAssertTrue(StyleSheet.shared.css.contains("> row { border-bottom-color: rgba(255, 0, 0, 1); }"), StyleSheet.shared.css)
    }

    func testOtherStylesKeepLibadwaitasRowsWithoutInsets() {
        XCTAssertTrue(List.rowMetrics(plain: false, background: false, insets: nil) == ([], []))
        let inset = List.rowMetrics(plain: false, background: true, insets: .uniform(4))
        XCTAssertEqual(inset.list, [])
        XCTAssertEqual(inset.row, ["padding: 4px 12px 4px 12px;"])
    }

    func testOutOfRangeInsetsStayValidCSS() {
        XCTAssertEqual(List.rowMetrics(plain: false, background: false, insets: .uniform(1e20)).row,
                       ["padding: 100000px 100000px 100000px 100000px;"])
        XCTAssertEqual(List.rowMetrics(plain: false, background: false, insets: .uniform(.nan)).row,
                       ["padding: 0px 0px 0px 0px;"])
        XCTAssertEqual(List.rowMetrics(plain: false, background: false, insets: .edges(top: 1e-7, leading: 0.25, bottom: -3, trailing: 0)).row,
                       ["padding: 0px 8px 0px 8.3px;"])
    }

    func testInsetsReachChildRows() throws {
        let node = try render(#"{"type": "List", "id": 1, "properties": {"listRowInsets": {"leading": 30}}, "children": [{"type": "Text", "id": 2, "properties": {"text": "Only"}}]}"#)
        gtk_widget_allocate(node.outerWidget, 300, 300, -1, nil)
        let text = try XCTUnwrap(node.childNodes[2])
        var bounds = graphene_rect_t()
        XCTAssertNotEqual(gtk_widget_compute_bounds(text.outerWidget, node.outerWidget, &bounds), 0)
        XCTAssertEqual(bounds.origin.x, 46)
    }
}
