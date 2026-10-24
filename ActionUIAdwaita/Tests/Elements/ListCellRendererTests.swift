// Tests/Elements/ListCellRendererTests.swift
/*
 Tests for the cells of a List's data rows on GTK (itemType.viewType): a Button cell at its natural
 width at the leading edge, whose click fires itemType.actionID with the row's text or its index in
 the content, taking the inherited buttonStyle; an Image cell showing a symbol or a file as
 dataInterpretation reads the text; a changed text updates the row's cell in place (an image's
 widget is made again); a new viewType makes the rows again; an AsyncImage cell showing a spinner
 until its image has loaded, and when it cannot be, then the image across the row.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ListCellRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
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
        return try XCTUnwrap(window.root)
    }

    private func setRows(_ rows: [[String]]) {
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 1, rows: rows)
        AdwaitaTestHost.drainMainLoop()
    }

    /// The cell widget of each row.
    private func cells(_ node: RenderNode) throws -> [WidgetPointer] {
        let box = OpaquePointer(try XCTUnwrap(attached(on: node.widget, key: listStateKey)).box)
        var cells: [WidgetPointer] = []
        var index: Int32 = 0
        while let row = gtk_list_box_get_row_at_index(box, index) {
            cells.append(try XCTUnwrap(gtk_list_box_row_get_child(row)))
            index += 1
        }
        return cells
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

    func testAChangedTextUpdatesTheButtonInPlace() throws {
        let node = try render(#"{"type": "List", "id": 1, "properties": {"itemType": {"viewType": "Button", "actionID": "test.cell"}}}"#)
        setRows([["Open"], ["Save"]])
        let before = try cells(node)
        setRows([["Open"], ["Save As"], ["Close"]])
        let after = try cells(node)
        XCTAssertEqual(after.prefix(2).map { UInt(bitPattern: $0) }, before.map { UInt(bitPattern: $0) })
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
        let box = OpaquePointer(try XCTUnwrap(attached(on: node.widget, key: listStateKey)).box)
        XCTAssertEqual(gtk_list_box_get_selected_row(box).map { gtk_list_box_row_get_index($0) }, 1, "the selection is shown again")
        XCTAssertTrue(fired.isEmpty)
    }

    func testAnAsyncImageCellShowsASpinnerThenTheImageAcrossTheRow() throws {
        let url = TestImages.fileURL(try pngFile())
        let node = try render(#"{"type": "List", "id": 1, "properties": {"itemType": {"viewType": "AsyncImage"}}}"#)
        setRows([[url], [url], [url]])
        XCTAssertEqual(try cells(node).map { typeName($0) }, Array(repeating: "AdwSpinner", count: 3))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { (try? self.cells(node).allSatisfy { self.typeName($0) == "GtkPicture" }) == true }))
        // Shorter than the rows: they keep their heights and the list scrolls.
        gtk_widget_allocate(node.outerWidget, 300, 100, -1, nil)
        for picture in try cells(node) {
            var bounds = graphene_rect_t()
            XCTAssertNotEqual(gtk_widget_compute_bounds(picture, node.outerWidget, &bounds), 0)
            // The 20 x 10 image across the row's content (300 less 16 at each side), half as tall.
            XCTAssertEqual(bounds.size.width, 268)
            XCTAssertEqual(bounds.size.height, 134)
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
}
