// Tests/Application/DemoTests.swift
/*
 Tests for ActionUIDemo (the ActionUIAdwaitaDemo program), run as the program it is, with the test
 app's documents: the launcher and a document opened at launch are saved as screenshots; an action
 fired at launch runs the test app's handler; a document that cannot be loaded fails the run; an unknown document, no documents, and bad arguments stop it
 with an error.
*/

import XCTest
import CAdwaita
import Foundation
@testable import ActionUI

@MainActor
final class DemoTests: XCTestCase {
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

    /// The demo program, built next to the test program (outside its bundle, so it needs
    /// --resources).
    private var demo: URL {
        URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("ActionUIAdwaitaDemo")
    }

    /// The test app's documents, found from this file.
    private var resources: String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("ActionUISwiftTestApp/Resources").path
    }

    /// Runs the demo with `arguments` for at most 30 s; its exit status, or nil when it had to be
    /// stopped.
    private func runDemo(_ arguments: [String]) throws -> Int32? {
        let process = Process()
        process.executableURL = demo
        process.arguments = arguments
        try process.run()
        let deadline = Date().addingTimeInterval(30)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard !process.isRunning else {
            process.terminate()
            return nil
        }
        return process.terminationStatus
    }

    private func screenshotPath(_ name: String) -> String {
        let path = NSTemporaryDirectory() + "actionui-demo-\(name)-\(ProcessInfo.processInfo.processIdentifier).png"
        files.append(path)
        return path
    }

    func testTheLauncherAndAnOpenedDocumentAreShown() throws {
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: demo.path), "no demo at \(demo.path)")
        let launcher = screenshotPath("launcher")
        XCTAssertEqual(try runDemo(["--resources", resources, "--screenshot", launcher]), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: launcher))
        let button = screenshotPath("button")
        XCTAssertEqual(try runDemo(["--resources", resources, "--open", "Button", "--screenshot", button]), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: button))
        // The test app's handler fills the list: the window differs from the one without the action
        // (the screenshots of one window are the same file from run to run).
        let emptyList = screenshotPath("list-empty")
        XCTAssertEqual(try runDemo(["--resources", resources, "--open", "List", "--screenshot", emptyList]), 0)
        let list = screenshotPath("list")
        XCTAssertEqual(try runDemo(["--resources", resources, "--open", "List", "--action", "list.demo.load", "--screenshot", list]), 0)
        XCTAssertNotEqual(FileManager.default.contents(atPath: list), FileManager.default.contents(atPath: emptyList), "list.demo.load changed nothing")
    }

    func testADocumentThatCannotBeLoadedFailsTheRun() throws {
        let folder = NSTemporaryDirectory() + "actionui-demo-bad-\(ProcessInfo.processInfo.processIdentifier)"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        files.append(folder)
        try Data("not json".utf8).write(to: URL(fileURLWithPath: folder).appendingPathComponent("Bad.json"))
        XCTAssertEqual(try runDemo(["--resources", folder, "--open", "Bad", "--screenshot", screenshotPath("bad")]), 65)
    }

    func testAnUnknownDocumentNoDocumentsAndBadArgumentsStopIt() throws {
        XCTAssertEqual(try runDemo(["--resources", resources, "--open", "NoSuchDocument"]), 66)
        XCTAssertEqual(try runDemo(["--resources", NSTemporaryDirectory() + "actionui-demo-empty-\(ProcessInfo.processInfo.processIdentifier)"]), 66)
        XCTAssertEqual(try runDemo(["--open"]), 64)
        XCTAssertEqual(try runDemo(["--frobnicate"]), 64)
        XCTAssertEqual(try runDemo(["--action", "list.demo.load"]), 64, "an action needs a document")
    }
}
