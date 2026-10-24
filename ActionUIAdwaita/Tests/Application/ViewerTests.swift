// Tests/Application/ViewerTests.swift
/*
 Tests for ActionUIAdwaitaViewer, run as the program it is: it opens the TemperatureConverter
 sample and saves a screenshot, in the light and the dark style; the PNG is as large as the
 window and the dark one is darker. The same sample from an http URL opens once it has loaded; one
 that cannot be loaded fails the run, its error window saved.
*/

import XCTest
import CAdwaita
import Foundation
@testable import ActionUI

@MainActor
final class ViewerTests: XCTestCase {
    private var files: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
    }

    override func tearDown() async throws {
        for file in files {
            try? FileManager.default.removeItem(atPath: file)
        }
    }

    /// The viewer, built next to the test program.
    private var viewer: URL {
        URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("ActionUIAdwaitaViewer")
    }

    /// The TemperatureConverter sample, found from this file.
    private var sample: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Examples/TemperatureConverter/shared/TemperatureConverter.json").path
    }

    /// Runs the viewer with `arguments` for at most 30 s; its exit status, or nil when it had to be
    /// stopped. The main loop keeps running meanwhile, so a test's http server can answer it.
    private func runViewer(_ arguments: [String]) throws -> Int32? {
        let process = Process()
        process.executableURL = viewer
        process.arguments = arguments
        try process.run()
        let deadline = Date().addingTimeInterval(30)
        while process.isRunning && Date() < deadline {
            AdwaitaTestHost.drainMainLoop()
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard !process.isRunning else {
            process.terminate()
            return nil
        }
        return process.terminationStatus
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
        let server = try TestImageServer(png: [], document: document)
        defer { server.stop() }
        let path = NSTemporaryDirectory() + "actionui-viewer-http-\(ProcessInfo.processInfo.processIdentifier).png"
        files.append(path)
        XCTAssertEqual(try runViewer([server.base + "/view.json", "--screenshot", path]), 0)
        XCTAssertGreaterThanOrEqual(try brightness(path).width, 360, "the sample's window")
    }

    func testAnHTTPDocumentThatCannotBeLoadedFailsTheRun() throws {
        let server = try TestImageServer(png: [])
        defer { server.stop() }
        let path = NSTemporaryDirectory() + "actionui-viewer-http-missing-\(ProcessInfo.processInfo.processIdentifier).png"
        files.append(path)
        XCTAssertEqual(try runViewer([server.base + "/missing.json", "--screenshot", path]), 65)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "the window with the error is saved too")
    }

    func testTheViewerRefusesBadArguments() throws {
        XCTAssertEqual(try runViewer([]), 64)
        XCTAssertEqual(try runViewer(["a.json", "--screenshot"]), 64)
    }
}
