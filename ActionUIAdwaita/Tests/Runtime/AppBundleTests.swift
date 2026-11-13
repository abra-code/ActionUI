// Tests/Runtime/AppBundleTests.swift
/*
 Tests for resource lookup on Linux (AppBundle): the running program's folder as the bundle,
 whatever its name; a LoadableView name found beside the window's document, beside the file an
 enclosing LoadableView loaded, and in the bundle; Image resourceName and assetName found in the
 bundle; the bundle's Info.plist read (flat, or in the macOS Contents layout), with its icon found in the resources.
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
        ActionUIResourceFolder.path = nil
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
        ActionUIResourceFolder.path = bundle
        AppBundle.setDocumentFolder(try folder(), window: windowUUID)
        let node = try render(#"{"type": "LoadableView", "id": 1, "properties": {"name": "Shared.json"}}"#)
        XCTAssertEqual(node.childNodes[10].map { Gtk.Label($0.widget).text }, "Bundled")
    }

    func testImageResourceAndAssetNamesAreFoundInTheBundle() throws {
        let bundle = try folder()
        let png = TestImages.png(width: 12, height: 8)
        try Data(png).write(to: URL(fileURLWithPath: bundle).appendingPathComponent("photo.png"))
        try Data(png).write(to: URL(fileURLWithPath: bundle).appendingPathComponent("BundleOrb.png"))
        ActionUIResourceFolder.path = bundle
        let node = try render(#"{"type": "HStack", "id": 1, "children": [{"type": "Image", "id": 2, "properties": {"resourceName": "photo.png"}}, {"type": "Image", "id": 3, "properties": {"assetName": "BundleOrb"}}]}"#)
        let resource = try XCTUnwrap(node.childNodes[2])
        XCTAssertEqual(typeName(resource.widget), "GtkPicture")
        let asset = try XCTUnwrap(node.childNodes[3])
        XCTAssertEqual(swiftString(gtk_image_get_icon_name(opaque(asset.widget))), "BundleOrb", "the bundle's image, not the missing-image icon")
    }

    /// An Info.plist of these keys (string values), with the DOCTYPE line Xcode and plutil write.
    private func plist(_ keys: [(String, String)]) -> String {
        let entries = keys.map { "<key>\($0.0)</key><string>\($0.1)</string>" }.joined()
        return #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
            + #"<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">"# + "\n"
            + #"<plist version="1.0"><dict>"# + entries + "</dict></plist>"
    }

    func testInfoPlistIsReadFromTheFolder() throws {
        let bundle = try folder()
        try write(plist([("CFBundleIdentifier", "org.example.Info"), ("CFBundleName", "Info"), ("CFBundleDisplayName", "Info App"),
                         ("CFBundleIconFile", "Info"), ("LinuxDesktopComment", "for installers")]), "Info.plist", in: bundle)
        let info = try XCTUnwrap(AppBundle.info(in: bundle))
        XCTAssertEqual(info, AppInfo(applicationID: "org.example.Info", name: "Info App", iconFile: "Info", resources: bundle),
                       "the display name before the name; other keys are ignored")
    }

    func testTheNameIsCFBundleNameWithoutADisplayName() throws {
        let bundle = try folder()
        try write(plist([("CFBundleName", "Only a Name")]), "Info.plist", in: bundle)
        XCTAssertEqual(AppBundle.info(in: bundle), AppInfo(applicationID: nil, name: "Only a Name", iconFile: nil, resources: bundle))
    }

    func testInfoPlistInTheMacOSLayoutIsFoundFromTheProgramOrResourcesFolder() throws {
        let bundle = try folder()
        let contents = bundle + "/Contents"
        for sub in ["Linux", "Resources"] {
            try FileManager.default.createDirectory(atPath: contents + "/" + sub, withIntermediateDirectories: true)
        }
        try write(plist([("CFBundleIdentifier", "org.example.Contents")]), "Info.plist", in: contents)
        for sub in ["Linux", "Resources"] {
            XCTAssertEqual(AppBundle.info(in: contents + "/" + sub),
                           AppInfo(applicationID: "org.example.Contents", name: nil, iconFile: nil, resources: contents + "/Resources"), sub)
        }
    }

    func testAnEmptyInfoPlistValueCountsAsLeftOut() throws {
        let bundle = try folder()
        try write(plist([("CFBundleIdentifier", ""), ("CFBundleDisplayName", ""), ("CFBundleName", "Named"), ("CFBundleIconFile", "")]),
                  "Info.plist", in: bundle)
        XCTAssertEqual(AppBundle.info(in: bundle), AppInfo(applicationID: nil, name: "Named", iconFile: nil, resources: bundle))
    }

    func testAMissingOrMalformedInfoPlistGivesNothing() throws {
        let bundle = try folder()
        XCTAssertNil(AppBundle.info(in: bundle), "no file")
        try write("not a property list", "Info.plist", in: bundle)
        XCTAssertNil(AppBundle.info(in: bundle), "not a property list")
        try write(#"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleName</key><integer>5</integer></dict></plist>"#,
                  "Info.plist", in: bundle)
        XCTAssertNil(AppBundle.info(in: bundle), "a key of the wrong type")
    }

    func testTheIconIsAnSVGOrPNGInTheResources() throws {
        let bundle = try folder()
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"/>"
        XCTAssertNil(AppInfo(iconFile: "App", resources: bundle).iconValue(), "no file")
        try write("icns", "App.icns", in: bundle)
        XCTAssertNil(AppInfo(iconFile: "App.icns", resources: bundle).iconValue(), "GTK reads no .icns")
        try write("png", "App.png", in: bundle)
        XCTAssertEqual(AppInfo(iconFile: "App.icns", resources: bundle).iconValue(), bundle + "/App.png", "the name with .png")
        try write(svg, "App.svg", in: bundle)
        XCTAssertEqual(AppInfo(iconFile: "App", resources: bundle).iconValue(), bundle + "/App.svg", "the SVG before the PNG")
        XCTAssertEqual(AppInfo(iconFile: "App.png", resources: bundle).iconValue(), bundle + "/App.png", "the file named, when it is one")
        XCTAssertNil(AppInfo(iconFile: "icons/App.svg", resources: bundle).iconValue(), "a file name, not a path")
        XCTAssertNil(AppInfo(iconFile: nil, resources: bundle).iconValue())
    }
}
