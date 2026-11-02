// Apps/ActionUIViewer/Tests/ActionUIViewerTests/ViewerTests.swift
/*
 Tests for ActionUIViewer on Linux, run as the program it is: it opens the TemperatureConverter
 sample and saves a screenshot, in the light and the dark style; the PNG is as large as the
 window and the dark one is darker. The same sample from an http URL opens once it has loaded; one
 that cannot be loaded fails the run, its error window saved. The add-ons are there: what they show
 depends on their documents.
*/

import XCTest
import CAdwaita
import Foundation

@MainActor
final class ViewerTests: XCTestCase {
    private var files: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try ProgramTestSupport.requireDisplay()
    }

    override func tearDown() async throws {
        for file in files {
            try? FileManager.default.removeItem(atPath: file)
        }
    }

    private var viewer: URL { ProgramTestSupport.program("ActionUIViewer") }

    /// The TemperatureConverter sample.
    private var sample: String {
        ProgramTestSupport.repository.appendingPathComponent("Examples/TemperatureConverter/shared/TemperatureConverter.json").path
    }

    private func runViewer(_ arguments: [String]) throws -> Int32? {
        try ProgramTestSupport.run(viewer, arguments)
    }

    /// A new path in the temporary folder, removed after the test.
    private func temporaryPath(_ name: String) -> String {
        let path = NSTemporaryDirectory() + "actionui-viewer-\(name)-\(ProcessInfo.processInfo.processIdentifier)"
        files.append(path)
        return path
    }

    /// The screenshot of a document, as bytes. Every document has the same file name, which is the window's title:
    /// two screenshots differ only by what the documents show.
    private func screenshot(of document: String, _ name: String) throws -> Data? {
        let path = temporaryPath("document.json")
        let image = temporaryPath(name + ".png")
        try Data(document.utf8).write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(try runViewer([path, "--screenshot", image]), 0)
        return FileManager.default.contents(atPath: image)
    }

    /// The average brightness (0 to 255) of a PNG's pixels, and its size.
    private func brightness(_ path: String) throws -> (average: Double, width: Int32, height: Int32) {
        let texture = try XCTUnwrap(gdk_texture_new_from_filename(path, nil), "no PNG at \(path)")
        defer { g_object_unref(UnsafeMutableRawPointer(texture)) }
        let width = gdk_texture_get_width(texture)
        let height = gdk_texture_get_height(texture)
        let rowBytes = Int(width) * 4
        var bytes = [UInt8](repeating: 0, count: rowBytes * Int(height))
        let downloader = gdk_texture_downloader_new(texture)!
        defer { gdk_texture_downloader_free(downloader) }
        gdk_texture_downloader_set_format(downloader, GDK_MEMORY_R8G8B8A8)
        gdk_texture_downloader_download_into(downloader, &bytes, gsize(rowBytes))
        var total = 0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            total += Int(bytes[index]) + Int(bytes[index + 1]) + Int(bytes[index + 2])
        }
        return (Double(total) / Double(bytes.count / 4 * 3), width, height)
    }

    func testTheViewerSavesTheSampleInTheLightAndDarkStyles() throws {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: viewer.path), "no viewer at \(viewer.path)")
        let light = NSTemporaryDirectory() + "actionui-viewer-light-\(ProcessInfo.processInfo.processIdentifier).png"
        let dark = NSTemporaryDirectory() + "actionui-viewer-dark-\(ProcessInfo.processInfo.processIdentifier).png"
        files += [light, dark]
        XCTAssertEqual(try runViewer([sample, "--screenshot", light]), 0)
        XCTAssertEqual(try runViewer([sample, "--dark", "--screenshot", dark]), 0)
        let lightImage = try brightness(light)
        let darkImage = try brightness(dark)
        XCTAssertGreaterThanOrEqual(lightImage.width, 360, "the sample's ideal width")
        XCTAssertGreaterThan(lightImage.height, 320, "its ideal height and the header bar")
        XCTAssertGreaterThan(lightImage.average, darkImage.average + 50, "the dark style is darker")
    }

    func testADocumentThatCannotBeLoadedFailsTheRun() throws {
        let path = NSTemporaryDirectory() + "actionui-viewer-missing-\(ProcessInfo.processInfo.processIdentifier).png"
        files.append(path)
        XCTAssertEqual(try runViewer(["/no/such/document.json", "--screenshot", path]), 65)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "the window with the error is saved too")
    }

    func testAnHTTPDocumentOpensOnceItHasLoaded() throws {
        let document = try String(contentsOfFile: sample, encoding: .utf8)
        let server = try TestDocumentServer(document: document)
        defer { server.stop() }
        let path = NSTemporaryDirectory() + "actionui-viewer-http-\(ProcessInfo.processInfo.processIdentifier).png"
        files.append(path)
        XCTAssertEqual(try runViewer([server.base + "/view.json", "--screenshot", path]), 0)
        XCTAssertGreaterThanOrEqual(try brightness(path).width, 360, "the sample's window")
    }

    func testAnHTTPDocumentThatCannotBeLoadedFailsTheRun() throws {
        let server = try TestDocumentServer(document: "")
        defer { server.stop() }
        let path = NSTemporaryDirectory() + "actionui-viewer-http-missing-\(ProcessInfo.processInfo.processIdentifier).png"
        files.append(path)
        XCTAssertEqual(try runViewer([server.base + "/missing.json", "--screenshot", path]), 65)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "the window with the error is saved too")
    }

    /// Without the add-on, both documents show the same placeholder.
    func testRichTextIsThere() throws {
        let empty = try screenshot(of: richText(""), "richtext-empty")
        let text = try screenshot(of: richText("# A heading\n\nSome **bold** text."), "richtext-text")
        XCTAssertNotNil(text)
        XCTAssertNotEqual(text, empty, "the document made no difference: the add-on is not registered")
    }

    /// Without the add-on, both documents show the same placeholder.
    func testCachedImageIsThere() throws {
        let red = temporaryPath("red.png")
        let blue = temporaryPath("blue.png")
        try ProgramTestSupport.writeSolidPNG(red: 255, green: 0, blue: 0, to: red)
        try ProgramTestSupport.writeSolidPNG(red: 0, green: 0, blue: 255, to: blue)
        let redWindow = try screenshot(of: cachedImage(red), "cached-red")
        let blueWindow = try screenshot(of: cachedImage(blue), "cached-blue")
        XCTAssertNotNil(blueWindow)
        XCTAssertNotEqual(blueWindow, redWindow, "the image made no difference: the add-on is not registered")
    }

    private func richText(_ markdown: String) -> String {
        let json = String(decoding: try! JSONEncoder().encode(markdown), as: UTF8.self)
        return #"{"type": "RichText", "id": 1, "properties": {"markdown": "# + json + #", "frame": {"width": 320, "height": 200}}}"#
    }

    private func cachedImage(_ path: String) -> String {
        let url = URL(fileURLWithPath: path).absoluteString
        return #"{"type": "CachedImage", "id": 1, "properties": {"url": ""# + url + #"", "frame": {"width": 200, "height": 200}}}"#
    }

    func testTheViewerRefusesBadArguments() throws {
        XCTAssertEqual(try runViewer([]), 64)
        XCTAssertEqual(try runViewer(["a.json", "--screenshot"]), 64)
    }
}
