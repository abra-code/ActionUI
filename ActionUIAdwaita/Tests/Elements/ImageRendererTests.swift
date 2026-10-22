// Tests/Elements/ImageRendererTests.swift
/*
 Tests for the Image renderer on GTK: a symbol is an Adwaita icon sized from the font and the image
 scale; a resizable symbol scales to its frame in the text color; a file is a picture at its own
 size, or scaled keeping its aspect ratio; a missing file shows the photo symbol; the first source
 that can be shown wins; an assetName is an icon of the theme; a runtime value that needs another
 kind of widget replaces the widget in the same box, keeping the base modifiers.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class ImageRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var files: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "image-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIRegistry.shared.loadBuiltIns()
        for file in files {
            try? FileManager.default.removeItem(atPath: file)
        }
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    /// A red PNG file of this size, removed after the test.
    private func pngFile(width: Int32, height: Int32) throws -> String {
        var data = [UInt8](repeating: 0, count: Int(width * height * 4))
        for index in stride(from: 0, to: data.count, by: 4) {
            data[index] = 255
            data[index + 3] = 255
        }
        let bytes = g_bytes_new(data, gsize(data.count))!
        defer { g_bytes_unref(bytes) }
        let texture = gdk_memory_texture_new(width, height, GDK_MEMORY_R8G8B8A8, bytes, gsize(width * 4))!
        defer { g_object_unref(UnsafeMutableRawPointer(texture)) }
        let path = NSTemporaryDirectory() + "actionui-image-\(ProcessInfo.processInfo.processIdentifier)-\(files.count).png"
        XCTAssertNotEqual(gdk_texture_save_to_png(texture, path), 0, "could not write \(path)")
        files.append(path)
        return path
    }

    private func typeName(_ widget: WidgetPointer) -> String? {
        swiftString(G_OBJECT_TYPE_NAME_of(widget))
    }

    private func iconName(_ node: RenderNode) -> String? {
        swiftString(gtk_image_get_icon_name(opaque(node.widget)))
    }

    private func measure(_ widget: WidgetPointer, _ orientation: GtkOrientation, forSize: Int32 = -1) -> (Int32, Int32) {
        var minimum: Int32 = 0
        var natural: Int32 = 0
        gtk_widget_measure(widget, orientation, forSize, &minimum, &natural, nil, nil)
        return (minimum, natural)
    }

    func testASymbolIsAnAdwaitaIconSizedFromTheFontAndScale() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "Image", "id": 2, "properties": {"systemName": "star.fill"}},
              {"type": "Image", "id": 3, "properties": {"systemName": "star.fill", "imageScale": "small"}},
              {"type": "Image", "id": 4, "properties": {"systemName": "star.fill", "imageScale": "large"}},
              {"type": "Image", "id": 5, "properties": {"systemName": "star.fill", "font": "largeTitle"}}]}
            """#)
        let medium = try XCTUnwrap(root.childNodes[2])
        XCTAssertEqual(typeName(medium.widget), "GtkImage")
        XCTAssertEqual(iconName(medium), "starred-symbolic")
        let mediumWidth = measure(medium.widget, GTK_ORIENTATION_HORIZONTAL).1
        XCTAssertEqual(Double(mediumWidth), 16, accuracy: 1, "GNOME's icon size at the default font")
        let small = measure(try XCTUnwrap(root.childNodes[3]).widget, GTK_ORIENTATION_HORIZONTAL).1
        let large = measure(try XCTUnwrap(root.childNodes[4]).widget, GTK_ORIENTATION_HORIZONTAL).1
        let titled = measure(try XCTUnwrap(root.childNodes[5]).widget, GTK_ORIENTATION_HORIZONTAL).1
        XCTAssertLessThan(small, mediumWidth)
        XCTAssertGreaterThan(large, mediumWidth)
        XCTAssertGreaterThan(titled, mediumWidth, "a larger font makes a larger symbol, as in SwiftUI")
        XCTAssertEqual(gtk_widget_get_hexpand(medium.widget), 0)
    }

    func testAResizableSymbolScalesToItsFrameInTheTextColor() throws {
        let node = try render(##"{"type": "Image", "id": 1, "properties": {"systemName": "star.fill", "resizable": true, "contentMode": "fit", "foregroundStyle": "#FF0000", "frame": {"width": 60, "height": 40}}}"##)
        XCTAssertEqual(typeName(node.widget), "ActionUIScalableIcon")
        XCTAssertEqual(measure(node.widget, GTK_ORIENTATION_HORIZONTAL).0, 0, "it can shrink")
        XCTAssertNotEqual(gtk_widget_get_hexpand(node.widget), 0)
        let drawing = try XCTUnwrap(AdwaitaTestHost.drawing(of: node.widget, shownIn: node.outerWidget), "the image drew nothing")
        defer { gsk_render_node_unref(drawing.node) }
        XCTAssertEqual([drawing.width, drawing.height], [60, 40])
        let pixels = try XCTUnwrap(AdwaitaTestHost.pixels(of: drawing.node, width: 60, height: 40))
        var painted = 0
        var outside = 0
        for y in 0..<40 {
            for x in 0..<60 {
                let pixel = (y * 60 + x) * 4
                guard pixels[pixel + 3] > 128 else { continue }
                painted += 1
                XCTAssertGreaterThan(pixels[pixel], 200, "not drawn in the text color at \(x), \(y)")
                XCTAssertLessThan(pixels[pixel + 1], 80, "not drawn in the text color at \(x), \(y)")
                if x < 10 || x >= 50 { outside += 1 }
            }
        }
        // A 40 px star paints about 370 pixels; a 16 px one, about 60.
        XCTAssertGreaterThan(painted, 250, "drawn at the size of its frame, not at the icon size")
        XCTAssertEqual(outside, 0, "fitted: a 40 x 40 square in the middle of the 60 x 40 frame")
        XCTAssertEqual(measure(node.widget, GTK_ORIENTATION_VERTICAL, forSize: 100).1, 100,
                       "given a width, as tall: SwiftUI's fitted symbol")

        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "contentMode", value: "fill")
        AdwaitaTestHost.drainMainLoop()
        let filled = try XCTUnwrap(AdwaitaTestHost.drawing(of: node.widget, shownIn: node.outerWidget))
        defer { gsk_render_node_unref(filled.node) }
        let filledPixels = try XCTUnwrap(AdwaitaTestHost.pixels(of: filled.node, width: 60, height: 40))
        let beyondFit = (0..<40).contains { y in
            (0..<60).contains { x in (x < 10 || x >= 50) && filledPixels[(y * 60 + x) * 4 + 3] > 128 }
        }
        XCTAssertTrue(beyondFit, "filled: a 60 x 60 icon, wider than the fitted square")
    }

    func testAResizableSymbolsNaturalSizeFollowsTheFont() throws {
        let root = try render(#"""
            {"type": "VStack", "id": 1, "children": [
              {"type": "Image", "id": 2, "properties": {"systemName": "star", "resizable": true, "contentMode": "fit"}},
              {"type": "Image", "id": 3, "properties": {"systemName": "star", "resizable": true, "contentMode": "fit", "font": "largeTitle"}}]}
            """#)
        let body = measure(try XCTUnwrap(root.childNodes[2]).widget, GTK_ORIENTATION_HORIZONTAL).1
        XCTAssertEqual(Double(body), 16, accuracy: 1)
        XCTAssertGreaterThan(measure(try XCTUnwrap(root.childNodes[3]).widget, GTK_ORIENTATION_HORIZONTAL).1, body)
    }

    func testAFileIsAPictureAtItsOwnSize() throws {
        let path = try pngFile(width: 40, height: 20)
        let node = try render(#"{"type": "Image", "id": 1, "properties": {"filePath": "\#(path)"}}"#)
        XCTAssertEqual(typeName(node.widget), "GtkPicture")
        XCTAssertEqual(measure(node.widget, GTK_ORIENTATION_HORIZONTAL).0, 40, "not resizable: no smaller than the image")
        XCTAssertEqual(measure(node.widget, GTK_ORIENTATION_HORIZONTAL).1, 40)
        XCTAssertEqual(measure(node.widget, GTK_ORIENTATION_VERTICAL).1, 20)
        XCTAssertEqual(gtk_widget_get_hexpand(node.widget), 0)
    }

    func testAResizableFileScalesKeepingItsAspectRatio() throws {
        let path = try pngFile(width: 40, height: 20)
        let node = try render(#"{"type": "Image", "id": 1, "properties": {"filePath": "\#(path)", "resizable": true, "contentMode": "fit"}}"#)
        XCTAssertEqual(measure(node.widget, GTK_ORIENTATION_HORIZONTAL).0, 0)
        XCTAssertEqual(measure(node.widget, GTK_ORIENTATION_VERTICAL, forSize: 80).1, 40, "twice as wide, twice as tall")
        XCTAssertNotEqual(gtk_widget_get_hexpand(node.widget), 0)
        XCTAssertNotEqual(gtk_widget_get_vexpand(node.widget), 0)
        XCTAssertEqual(gtk_picture_get_content_fit(opaque(node.widget)), GTK_CONTENT_FIT_CONTAIN)

        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "contentMode", value: "fill")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(gtk_picture_get_content_fit(opaque(node.widget)), GTK_CONTENT_FIT_COVER)
    }

    func testAMissingFileShowsThePhotoSymbol() throws {
        let node = try render(#"{"type": "Image", "id": 1, "properties": {"filePath": "/no/such/picture.png"}}"#)
        XCTAssertEqual(typeName(node.widget), "GtkImage")
        XCTAssertEqual(iconName(node), "image-x-generic-symbolic")
    }

    func testTheFirstSourceThatCanBeShownWins() throws {
        // A PDF is not an image on Linux, so the symbol after it is shown.
        let node = try render(#"{"type": "Image", "id": 1, "properties": {"filePath": "/tmp/document.pdf", "systemName": "trash"}}"#)
        XCTAssertEqual(iconName(node), "user-trash-symbolic")

        // A path without an extension is kept, and shows the photo symbol, as on Apple.
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "filePath", value: "/tmp/picture")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(iconName(node), "image-x-generic-symbolic")
    }

    func testAValueThatIsASymbolNameStaysASymbol() throws {
        // The theme has a full-color "folder" too; a value naming a known symbol is the symbol.
        let node = try render(#"{"type": "Image", "id": 1, "properties": {"systemName": "star"}}"#)
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "folder")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(iconName(node), "folder-symbolic")
    }

    func testAnAssetNameIsAnIconOfTheTheme() throws {
        let root = try render(#"{"type": "VStack", "id": 1, "children": [{"type": "Image", "id": 2, "properties": {"assetName": "folder"}}, {"type": "Image", "id": 3, "properties": {"assetName": "no-such-asset"}}]}"#)
        XCTAssertEqual(iconName(try XCTUnwrap(root.childNodes[2])), "folder")
        XCTAssertEqual(iconName(try XCTUnwrap(root.childNodes[3])), SymbolNames.missing)
    }

    func testAValueNeedingAnotherWidgetReplacesItInTheSameBox() throws {
        let path = try pngFile(width: 40, height: 20)
        let root = try render(#"{"type": "VStack", "id": 1, "children": [{"type": "Image", "id": 2, "properties": {"systemName": "star", "accessibilityLabel": "Picture", "padding": 4}}]}"#)
        let node = try XCTUnwrap(root.childNodes[2])
        let box: WidgetPointer = node.outerWidget
        XCTAssertEqual(typeName(node.widget), "GtkImage")
        XCTAssertEqual(iconName(node), "non-starred-symbolic")

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 2, value: path)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(typeName(node.widget), "GtkPicture")
        XCTAssertTrue(node.outerWidget == box, "the same box, still in its stack")
        XCTAssertTrue(gtk_widget_get_parent(box) == root.widget)
        let content = try XCTUnwrap(ModifierBox.content(of: box))
        XCTAssertTrue(gtk_widget_get_first_child(content) == node.widget, "the new widget is in the box")
        XCTAssertNil(gtk_widget_get_next_sibling(node.widget), "and the old one is gone")
        XCTAssertNotEqual(gtk_test_accessible_has_property(OpaquePointer(node.widget), GTK_ACCESSIBLE_PROPERTY_LABEL), 0,
                          "the base modifiers apply to the new widget")

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 2, value: "")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(typeName(node.widget), "GtkImage", "an empty value: the properties again")
        XCTAssertEqual(iconName(node), "non-starred-symbolic")
    }
}
