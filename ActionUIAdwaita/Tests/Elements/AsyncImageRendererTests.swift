// Tests/Elements/AsyncImageRendererTests.swift
/*
 Tests for the AsyncImage renderer on GTK: the placeholder symbol until the image has loaded, then
 a picture of it; resizable (the default) scaling to the frame, fit or fill, and not resizable at
 its own size; a URL that fails keeping the placeholder without loading again; a new value loading
 its URL; an image kept from before shown at once; no URL showing the placeholder.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class AsyncImageRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var files: [String] = []
    private var server: TestImageServer?

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        RemoteImages.shared.removeAll()
        windowUUID = "async-image-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        server?.stop()
        server = nil
        for path in files {
            try? FileManager.default.removeItem(atPath: path)
        }
        files = []
        RemoteImages.shared.removeAll()
        RemoteImages.shared.budget = 64 << 20
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func pngURL(_ name: String, width: Int32 = 40, height: Int32 = 20) throws -> String {
        let path = try TestImages.file(TestImages.png(width: width, height: height), name: name)
        files.append(path)
        return TestImages.fileURL(path)
    }

    private func typeName(_ widget: WidgetPointer) -> String? {
        swiftString(G_OBJECT_TYPE_NAME_of(widget))
    }

    /// Waits until the node shows a picture.
    private func waitForPicture(_ node: RenderNode) -> Bool {
        AdwaitaTestHost.runMainLoop { typeName(node.widget) == "GtkPicture" }
    }

    func testThePlaceholderShowsUntilTheImageHasLoaded() throws {
        let url = try pngURL("loads.png")
        let node = try render(#"{"type": "AsyncImage", "id": 1, "properties": {"url": "\#(url)", "placeholder": "star"}}"#)
        XCTAssertEqual(typeName(node.widget), "GtkImage")
        XCTAssertEqual(swiftString(gtk_image_get_icon_name(opaque(node.widget))), SymbolNames.iconName("star"))
        XCTAssertTrue(waitForPicture(node))
        let paintable = try XCTUnwrap(gtk_picture_get_paintable(opaque(node.widget)))
        XCTAssertEqual(gdk_paintable_get_intrinsic_width(paintable), 40)
    }

    func testAResizableImageScalesToItsFrame() throws {
        let url = try pngURL("fill.png")
        let node = try render(#"{"type": "AsyncImage", "id": 1, "properties": {"url": "\#(url)", "contentMode": "fill"}}"#)
        XCTAssertTrue(waitForPicture(node))
        let picture = opaque(node.widget)
        XCTAssertNotEqual(gtk_picture_get_can_shrink(picture), 0)
        XCTAssertEqual(gtk_picture_get_content_fit(picture), GTK_CONTENT_FIT_COVER)
        XCTAssertNotEqual(gtk_widget_get_hexpand(node.widget), 0)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "contentMode", value: "fit")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_picture_get_content_fit(opaque(node.widget)), GTK_CONTENT_FIT_CONTAIN)
    }

    func testANotResizableImageShowsAtItsOwnSize() throws {
        let url = try pngURL("own.png")
        let node = try render(#"{"type": "AsyncImage", "id": 1, "properties": {"url": "\#(url)", "resizable": false}}"#)
        XCTAssertTrue(waitForPicture(node))
        XCTAssertEqual(gtk_picture_get_can_shrink(opaque(node.widget)), 0)
        XCTAssertEqual(gtk_widget_get_hexpand(node.widget), 0)
        XCTAssertEqual(gtk_picture_get_content_fit(opaque(node.widget)), GTK_CONTENT_FIT_SCALE_DOWN, "never scaled up")
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(node.widget, GTK_ORIENTATION_HORIZONTAL, -1, &minimum, &natural, nil, nil)
        XCTAssertEqual(natural, 40)
    }

    func testAURLThatFailsKeepsThePlaceholderWithoutLoadingAgain() throws {
        let server = try TestImageServer(png: [])
        self.server = server
        let node = try render(#"{"type": "AsyncImage", "id": 1, "properties": {"url": "\#(server.base)/missing.png"}}"#)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop { server.requests == 1 })
        // Another update of the node (a property change) asks for nothing new.
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "placeholder", value: "trash")
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: 300)
        XCTAssertEqual(server.requests, 1)
        XCTAssertEqual(typeName(node.widget), "GtkImage")
        XCTAssertEqual(swiftString(gtk_image_get_icon_name(opaque(node.widget))), SymbolNames.iconName("trash"))
    }

    func testANewValueLoadsItsURL() throws {
        let server = try TestImageServer(png: TestImages.png(width: 30, height: 30))
        self.server = server
        let first = try pngURL("first.png")
        let node = try render(#"{"type": "AsyncImage", "id": 1, "properties": {"url": "\#(first)"}}"#)
        XCTAssertTrue(waitForPicture(node))
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: server.base + "/image.png")
        XCTAssertTrue(AdwaitaTestHost.runMainLoop {
            typeName(node.widget) == "GtkPicture"
                && gtk_picture_get_paintable(opaque(node.widget)).map { gdk_paintable_get_intrinsic_width($0) } == 30
        })
    }

    func testAnImageKeptFromBeforeShowsAtOnce() throws {
        let url = try pngURL("kept.png")
        var loaded = false
        RemoteImages.shared.load(url) { _ in loaded = true }
        XCTAssertTrue(AdwaitaTestHost.runMainLoop { loaded })
        let node = try render(#"{"type": "AsyncImage", "id": 1, "properties": {"url": "\#(url)"}}"#)
        XCTAssertEqual(typeName(node.widget), "GtkPicture", "no placeholder first")
    }

    func testAnImageShownStaysWhenTheCacheDropsIt() throws {
        // Each 40 x 20 image costs 3200 bytes; the budget holds one.
        RemoteImages.shared.budget = 3200
        let shown = try pngURL("shown.png")
        let other = try pngURL("other.png")
        let node = try render(#"{"type": "AsyncImage", "id": 1, "properties": {"url": "\#(shown)"}}"#)
        XCTAssertTrue(waitForPicture(node))
        var loaded = false
        RemoteImages.shared.load(other) { _ in loaded = true }
        XCTAssertTrue(AdwaitaTestHost.runMainLoop { loaded })
        XCTAssertNil(RemoteImages.shared.texture(shown))
        // Another update of the node keeps the picture, without the placeholder or a new load.
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "contentMode", value: "fill")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(typeName(node.widget), "GtkPicture")
        XCTAssertEqual(gtk_picture_get_content_fit(opaque(node.widget)), GTK_CONTENT_FIT_COVER)
    }

    func testNoURLShowsThePlaceholder() throws {
        let node = try render(#"{"type": "AsyncImage", "id": 1, "properties": {}}"#)
        XCTAssertEqual(typeName(node.widget), "GtkImage")
        XCTAssertEqual(swiftString(gtk_image_get_icon_name(opaque(node.widget))), SymbolNames.iconName("photo"))
    }
}
