// Tests/Elements/ListCellRendererTests.swift
/*
 Tests for the cells of a List's data rows on GTK (itemType.viewType): a Button cell at its natural
 width at the leading edge, whose click fires itemType.actionID with the row's text or its index in
 the content, taking the inherited buttonStyle; an Image cell showing a symbol or a file as
 dataInterpretation reads the text; a changed text is shown in a new cell, an unchanged row keeping
 its cell (the rows are made as they come into view, in a GtkListView); a new viewType makes the
 rows again; an AsyncImage cell showing a spinner
 until its image has loaded, and when it cannot be, then the image across the row.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ListCellRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var gtkWindows: [UnsafeMutablePointer<GtkWindow>] = []
    private var files: [String] = []
    private var fired: [(actionID: String, viewID: Int, context: Any?)] = []
    private let actionIDs = ["test.cell", "test.pick"]

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        RemoteImages.shared.removeAll()
        windowUUID = "list-cell-\(name)"
        fired = []
        for id in actionIDs {
            ActionUIModel.shared.registerActionHandler(for: id) { [weak self] actionID, _, viewID, _, context in
                MainActor.assumeIsolated { self?.fired.append((actionID, viewID, context)) }
            }
        }
    }

    override func tearDown() async throws {
        for window in gtkWindows {
            gtk_window_destroy(window)
        }
        gtkWindows = []
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        for id in actionIDs {
            ActionUIModel.shared.unregisterActionHandler(for: id)
        }
        for path in files {
            try? FileManager.default.removeItem(atPath: path)
        }
        files = []
        RemoteImages.shared.removeAll()
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        // On screen: the list view of the content-rows and template forms makes its rows only when
        // it lays them out there.
        let gtkWindow: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        gtkWindows.append(gtkWindow)
        gtk_window_set_default_size(gtkWindow, 300, 400)
        adw_window_set_content(typed(gtkWindow), window.contentWidget)
        gtk_window_present(gtkWindow)
        settle()
        return try XCTUnwrap(window.root)
    }

    /// Runs the main loop long enough for the window to lay the List out, which binds its rows.
    private func settle() {
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: 300)
        AdwaitaTestHost.drainMainLoop()
    }

    private func setRows(_ rows: [[String]]) {
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 1, rows: rows)
        settle()
    }

    private func lazy(_ node: RenderNode) throws -> LazyListRows {
        try XCTUnwrap(try XCTUnwrap(attached(on: node.widget, key: listStateKey)).lazy, "the lazy content-rows form")
    }

    /// The cell widget of each row (all of them are in view).
    private func cells(_ node: RenderNode) throws -> [WidgetPointer] {
        try lazy(node).cells.sorted { $0.key < $1.key }.map(\.value.cell)
    }

    private func typeName(_ widget: WidgetPointer) -> String? {
        swiftString(G_OBJECT_TYPE_NAME_of(widget))
    }

    /// Emits "clicked" on a button, as a click does.
    private func click(_ button: WidgetPointer) {
        var value = GValue()
        g_value_init(&value, gtk_button_get_type())
        g_value_set_object(&value, UnsafeMutableRawPointer(button))
        g_signal_emitv(&value, g_signal_lookup("clicked", gtk_button_get_type()), 0, nil)
        g_value_unset(&value)
        AdwaitaTestHost.drainMainLoop()
    }

    /// A red PNG file, removed after the test.
    private func pngFile() throws -> String {
        var data = [UInt8](repeating: 0, count: 20 * 10 * 4)
        for index in stride(from: 0, to: data.count, by: 4) {
            data[index] = 255
            data[index + 3] = 255
        }
        let bytes = g_bytes_new(data, gsize(data.count))!
        defer { g_bytes_unref(bytes) }
        let texture = gdk_memory_texture_new(20, 10, GDK_MEMORY_R8G8B8A8, bytes, 20 * 4)!
        defer { g_object_unref(UnsafeMutableRawPointer(texture)) }
        let path = NSTemporaryDirectory() + "actionui-list-cell-\(ProcessInfo.processInfo.processIdentifier)-\(files.count).png"
        XCTAssertNotEqual(gdk_texture_save_to_png(texture, path), 0, "could not write \(path)")
        files.append(path)
        return path
    }

    func testButtonCellsSitAtTheLeadingEdgeAndFireWithTheirText() throws {
        let node = try render(#"{"type": "List", "id": 1, "properties": {"actionID": "test.pick", "itemType": {"viewType": "Button", "actionID": "test.cell"}}}"#)
        setRows([["Open"], ["Save"]])
        let cells = try cells(node)
        XCTAssertEqual(cells.map { swiftString(gtk_button_get_label(typed($0))) }, ["Open", "Save"])
        XCTAssertEqual(gtk_widget_get_halign(cells[0]), GTK_ALIGN_START)
        click(cells[1])
        XCTAssertEqual(fired.map(\.actionID), ["test.cell"], "the cell's action, not the list's")
        XCTAssertEqual(fired.first?.viewID, 1)
        XCTAssertEqual(fired.first?.context as? String, "Save")
    }

    func testAButtonCellWithRowIndexFiresWithTheContentIndex() throws {
        let node = try render(#"{"type": "List", "id": 1, "properties": {"itemType": {"viewType": "Button", "actionID": "test.cell", "actionContext": "rowIndex"}}}"#)
        setRows([["Open"], [""], ["Close"]])
        let cells = try cells(node)
        XCTAssertEqual(cells.count, 2, "a row without a first column is not shown")
        click(cells[1])
        XCTAssertEqual(fired.first?.context as? Int, 2, "the index in the content, past the row not shown")
    }

    func testAChangedTextIsShownAndAnUnchangedCellIsKept() throws {
        let node = try render(#"{"type": "List", "id": 1, "properties": {"itemType": {"viewType": "Button", "actionID": "test.cell"}}}"#)
        setRows([["Open"], ["Save"]])
        let before = try cells(node)
        setRows([["Open"], ["Save As"], ["Close"]])
        let after = try cells(node)
        XCTAssertEqual(UInt(bitPattern: after[0]), UInt(bitPattern: before[0]), "an unchanged row keeps its cell")
        XCTAssertEqual(after.map { swiftString(gtk_button_get_label(typed($0))) }, ["Open", "Save As", "Close"])
        click(after[2])
        XCTAssertEqual(fired.first?.context as? String, "Close")
    }

    func testButtonCellsTakeTheInheritedButtonStyle() throws {
        let node = try render(#"{"type": "List", "id": 1, "properties": {"buttonStyle": "borderless", "itemType": {"viewType": "Button"}}}"#)
        setRows([["Open"]])
        XCTAssertTrue(Gtk.Widget(try XCTUnwrap(try cells(node).first)).hasCSSClass("flat"))
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "buttonStyle", value: "borderedProminent")
        AdwaitaTestHost.drainMainLoop()
        let cell = try XCTUnwrap(try cells(node).first)
        XCTAssertFalse(Gtk.Widget(cell).hasCSSClass("flat"))
        XCTAssertTrue(Gtk.Widget(cell).hasCSSClass("suggested-action"))
    }

    func testImageCellsShowSymbolsAndFiles() throws {
        let path = try pngFile()
        let node = try render(#"{"type": "List", "id": 1, "properties": {"itemType": {"viewType": "Image", "dataInterpretation": "mixed"}}}"#)
        setRows([["star"], [path]])
        var cells = try cells(node)
        XCTAssertEqual(typeName(cells[0]), "GtkImage")
        XCTAssertEqual(swiftString(gtk_image_get_icon_name(opaque(cells[0]))), SymbolNames.iconName("star"))
        XCTAssertTrue(Gtk.Widget(cells[0]).hasCSSClass("actionui-list-icon"))
        XCTAssertEqual(typeName(cells[1]), "GtkPicture")
        XCTAssertEqual(gtk_widget_get_halign(cells[1]), GTK_ALIGN_START)
        setRows([[path], ["star"]])
        cells = try self.cells(node)
        XCTAssertEqual(cells.map { typeName($0) }, ["GtkPicture", "GtkImage"], "a changed text makes the image again")
    }

    func testSystemNameImageCellsShowAPathAsASymbolName() throws {
        // A file that mixed would show as a picture: the default interpretation is systemName.
        let path = try pngFile()
        let node = try render(#"{"type": "List", "id": 1, "properties": {"itemType": {"viewType": "Image"}}}"#)
        setRows([[path]])
        let cell = try XCTUnwrap(try cells(node).first)
        XCTAssertEqual(typeName(cell), "GtkImage")
        XCTAssertEqual(swiftString(gtk_image_get_icon_name(opaque(cell))), SymbolNames.iconName(path))
    }

    func testANewViewTypeMakesTheRowsAgain() throws {
        let node = try render(#"{"type": "List", "id": 1, "properties": {"actionID": "test.pick"}}"#)
        setRows([["Open"], ["Save"]])
        XCTAssertEqual(try cells(node).map { typeName($0) }, ["GtkLabel", "GtkLabel"])
        node.model.value = ["Save"]
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "itemType", value: ["viewType": "Button"])
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(try cells(node).map { typeName($0) }, ["GtkButton", "GtkButton"])
        XCTAssertEqual(try lazy(node).selectedPosition, 1, "the selection is shown again")
        XCTAssertTrue(fired.isEmpty)
    }

    func testAnAsyncImageCellShowsASpinnerThenTheImageAcrossTheRow() throws {
        let url = TestImages.fileURL(try pngFile())
        let node = try render(#"{"type": "List", "id": 1, "properties": {"itemType": {"viewType": "AsyncImage"}}}"#)
        // A local file loads before the rows are first laid out: the spinner it shows meanwhile is
        // the next tests' (one that cannot load keeps it, a new text shows it again).
        setRows([[url], [url], [url]])
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { (try? self.cells(node).allSatisfy { self.typeName($0) == "GtkPicture" }) == true }))
        XCTAssertEqual(try cells(node).count, 3)
        settle()
        // The 20 x 10 image across the row's content (the List's width less 16 at each side), half
        // as tall: the row's natural height, not its minimum.
        let content = Float(gtk_widget_get_width(node.outerWidget) - 32)
        for picture in try cells(node) {
            var bounds = graphene_rect_t()
            XCTAssertNotEqual(gtk_widget_compute_bounds(picture, node.outerWidget, &bounds), 0)
            XCTAssertEqual(bounds.size.width, content)
            XCTAssertEqual(bounds.size.height, content / 2)
        }
    }

    func testAnAsyncImageCellThatCannotLoadKeepsTheSpinner() throws {
        let node = try render(#"{"type": "List", "id": 1, "properties": {"itemType": {"viewType": "AsyncImage"}}}"#)
        let missing = "file:///no/such/image.png"
        setRows([[missing]])
        // Waiters run in the order they asked, so the cell's has run when this one does.
        var failed = false
        RemoteImages.shared.load(missing) { loaded in failed = !loaded }
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { failed }))
        XCTAssertEqual(typeName(try XCTUnwrap(try cells(node).first)), "AdwSpinner")
    }

    func testAnAsyncImageCellShowsAKeptImageAtOnceAndANewTextAgain() throws {
        let kept = TestImages.fileURL(try pngFile())
        var loaded = false
        RemoteImages.shared.load(kept) { _ in loaded = true }
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { loaded }))
        let node = try render(#"{"type": "List", "id": 1, "properties": {"itemType": {"viewType": "AsyncImage"}}}"#)
        setRows([[kept]])
        XCTAssertEqual(typeName(try XCTUnwrap(try cells(node).first)), "GtkPicture", "no spinner first")
        setRows([["file:///no/such/image.png"]])
        XCTAssertEqual(typeName(try XCTUnwrap(try cells(node).first)), "AdwSpinner", "a new text loads again")
    }

    /// A label's or button's text.
    private func cellText(_ cell: WidgetPointer) -> String {
        if Gtk.Widget(cell).isA(gtk_button_get_type()) {
            return swiftString(gtk_button_get_label(typed(cell))) ?? ""
        }
        return Gtk.Widget(cell).isA(gtk_label_get_type()) ? Gtk.Label(cell).text : "?"
    }

    /// Each bound cell is its list item's child, at its item's position, showing that row's text,
    /// and every row shown holds a bound cell.
    private func checkBoundCells(_ node: RenderNode, _ texts: [String], _ step: String) throws {
        let lazy = try lazy(node)
        XCTAssertFalse(lazy.cells.isEmpty, step)
        XCTAssertLessThan(lazy.cells.count, 600, "\(step): only the rows near the view")
        for (position, bound) in lazy.cells {
            XCTAssertEqual(Int(gtk_list_item_get_position(bound.item)), position, "\(step): the item's position")
            XCTAssertEqual(gtk_list_item_get_child(bound.item).map { UInt(bitPattern: $0) }, UInt(bitPattern: bound.cell), "\(step): the item's child")
            XCTAssertEqual(LazyListRows.position(of: bound.cell), position, "\(step): the cell's position")
            XCTAssertEqual(cellText(bound.cell), texts[position], "\(step): the text at \(position)")
        }
        let known = Set(lazy.cells.values.map { UInt(bitPattern: $0.cell) })
        var child = gtk_widget_get_first_child(lazy.view)
        var shown = 0
        while let row = child {
            if let cell = gtk_widget_get_first_child(row), gtk_widget_get_mapped(row) != 0 {
                shown += 1
                XCTAssertTrue(known.contains(UInt(bitPattern: cell)), "\(step): a row shows a cell not bound")
            }
            child = gtk_widget_get_next_sibling(row)
        }
        XCTAssertGreaterThan(shown, 0, step)
    }

    /// Scrolls the List to `fraction` of its scrollable height.
    private func scroll(_ node: RenderNode, to fraction: Double) {
        let adjustment = gtk_scrolled_window_get_vadjustment(OpaquePointer(node.widget))
        let range = gtk_adjustment_get_upper(adjustment) - gtk_adjustment_get_page_size(adjustment)
        gtk_adjustment_set_value(adjustment, range * fraction)
        settle()
    }

    func testBoundCellsFollowScrollingChangesAndANewViewType() throws {
        let node = try render(#"{"type": "List", "id": 1, "properties": {"itemType": {"viewType": "Text", "actionID": "test.cell"}}}"#)
        var texts = (0..<3000).map { "Row \($0)" }
        setRows(texts.map { [$0] })
        try checkBoundCells(node, texts, "first")
        scroll(node, to: 0.5)
        try checkBoundCells(node, texts, "scrolled")
        let lazy = try lazy(node)
        let middle = try XCTUnwrap(lazy.cells.keys.sorted().dropFirst(lazy.cells.count / 2).first)
        for index in (middle - 5)..<(middle + 5) {
            texts[index] = "Changed \(index)"
        }
        // A hidden row above changes nothing shown.
        var withHidden = texts.map { [$0] }
        withHidden.insert([""], at: 10)
        setRows(withHidden)
        try checkBoundCells(node, texts, "changed")
        // A row taken out: those below move up one, their cells made again.
        texts.remove(at: middle + 20)
        setRows(texts.map { [$0] })
        try checkBoundCells(node, texts, "removed")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "itemType",
                                                value: ["viewType": "Button", "actionID": "test.cell"])
        settle()
        try checkBoundCells(node, texts, "buttons")
        scroll(node, to: 0.9)
        try checkBoundCells(node, texts, "near the end")
        let first = try XCTUnwrap(lazy.cells.min { $0.key < $1.key })
        click(first.value.cell)
        XCTAssertEqual(fired.first?.context as? String, texts[first.key], "the clicked row's text")
        scroll(node, to: 0)
        try checkBoundCells(node, texts, "back at the top")
    }
}
