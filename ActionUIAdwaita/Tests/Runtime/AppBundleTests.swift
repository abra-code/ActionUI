// Tests/Runtime/AppBundleTests.swift
/*
 Tests for resource lookup on Linux (AppBundle): the running program's folder as the bundle,
 whatever its name; a LoadableView name found beside the window's document, beside the file an
 enclosing LoadableView loaded, and in the bundle; Image resourceName and assetName found in the
 bundle.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class AppBundleTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var folders: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "app-bundle-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        AppBundle.setDocumentFolder(nil, window: windowUUID)
        AppBundle.folder = AppBundle.defaultFolder()
        for folder in folders {
            try? FileManager.default.removeItem(atPath: folder)
        }
        folders = []
        ActionUIRegistry.shared.loadBuiltIns()
    }

    /// A new empty folder in the temporary folder.
    private func folder() throws -> String {
        let path = NSTemporaryDirectory() + "actionui-bundle-\(ProcessInfo.processInfo.processIdentifier)-\(folders.count)-\(name.count)"
        try? FileManager.default.removeItem(atPath: path)
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        folders.append(path)
        return path
    }

    private func write(_ text: String, _ name: String, in folder: String) throws {
        try Data(text.utf8).write(to: URL(fileURLWithPath: folder).appendingPathComponent(name))
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private func typeName(_ widget: WidgetPointer?) -> String? {
        widget.flatMap { swiftString(G_OBJECT_TYPE_NAME_of($0)) }
    }

    func testTheBundleIsTheRunningProgramsFolder() {
        let program = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent().path
        XCTAssertEqual(AppBundle.defaultFolder(), program, "whatever the folder is named")
    }

    func testALoadableViewNameIsFoundBesideTheWindowsDocument() throws {
        let documents = try folder()
        try write(#"{"type": "Text", "id": 10, "properties": {"text": "Beside"}}"#, "Inner.json", in: documents)
        AppBundle.setDocumentFolder(documents, window: windowUUID)
        let node = try render(#"{"type": "LoadableView", "id": 1, "properties": {"name": "Inner.json"}}"#)
        XCTAssertEqual(node.childNodes[10].map { Gtk.Label($0.widget).text }, "Beside")
    }

    func testANestedLoadableViewLooksBesideTheFileThatHoldsIt() throws {
        let documents = try folder()
        let other = try folder()
        try write(#"{"type": "LoadableView", "id": 20, "properties": {"name": "Leaf"}}"#, "Middle.json", in: other)
        try write(#"{"type": "Text", "id": 30, "properties": {"text": "Leaf"}}"#, "Leaf.json", in: other)
        AppBundle.setDocumentFolder(documents, window: windowUUID)
        let node = try render(#"{"type": "LoadableView", "id": 1, "properties": {"filePath": "\#(other)/Middle.json"}}"#)
        AdwaitaTestHost.drainMainLoop()
        let middle = try XCTUnwrap(node.childNodes[20])
        XCTAssertEqual(middle.childNodes[30].map { Gtk.Label($0.widget).text }, "Leaf", "found beside Middle.json, with .json added")
    }

    func testALoadableViewNameFallsBackToTheBundle() throws {
        let bundle = try folder()
        try write(#"{"type": "Text", "id": 10, "properties": {"text": "Bundled"}}"#, "Shared.json", in: bundle)
        AppBundle.folder = bundle
        AppBundle.setDocumentFolder(try folder(), window: windowUUID)
        let node = try render(#"{"type": "LoadableView", "id": 1, "properties": {"name": "Shared.json"}}"#)
        XCTAssertEqual(node.childNodes[10].map { Gtk.Label($0.widget).text }, "Bundled")
    }

    func testImageResourceAndAssetNamesAreFoundInTheBundle() throws {
        let bundle = try folder()
        let png = TestImages.png(width: 12, height: 8)
        try Data(png).write(to: URL(fileURLWithPath: bundle).appendingPathComponent("photo.png"))
        try Data(png).write(to: URL(fileURLWithPath: bundle).appendingPathComponent("BundleOrb.png"))
        AppBundle.folder = bundle
        let node = try render(#"{"type": "HStack", "id": 1, "children": [{"type": "Image", "id": 2, "properties": {"resourceName": "photo.png"}}, {"type": "Image", "id": 3, "properties": {"assetName": "BundleOrb"}}]}"#)
        let resource = try XCTUnwrap(node.childNodes[2])
        XCTAssertEqual(typeName(resource.widget), "GtkPicture")
        let asset = try XCTUnwrap(node.childNodes[3])
        XCTAssertEqual(swiftString(gtk_image_get_icon_name(opaque(asset.widget))), "BundleOrb", "the bundle's image, not the missing-image icon")
    }
}
