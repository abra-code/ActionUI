// ActionUIAdwaita/Apps/Tests/ActionUIAdwaitaAppsTests/DemoTests.swift
/*
 Tests for ActionUIDemo (the ActionUIAdwaitaDemo program), run as the program it is, with the test
 app's documents: the launcher and a document opened at launch are saved as screenshots; an action
 fired at launch runs the test app's handler; a document that cannot be loaded fails the run; an unknown
 document, no documents, and bad arguments stop it with an error; the add-ons are there.
*/

import XCTest
import CAdwaita
import Foundation

@MainActor
final class DemoTests: XCTestCase {
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

    /// The demo program (outside its bundle, so it needs --resources).
    private var demo: URL { ProgramTestSupport.program("ActionUIAdwaitaDemo") }

    /// The test app's documents.
    private var resources: String {
        ProgramTestSupport.repository.appendingPathComponent("ActionUISwiftTestApp/Resources").path
    }

    private func runDemo(_ arguments: [String]) throws -> Int32? {
        try ProgramTestSupport.run(demo, arguments)
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

    /// Without the add-on, both documents show the same placeholder.
    func testRichTextIsThere() throws {
        let empty = screenshotPath("richtext-empty")
        let text = screenshotPath("richtext-text")
        // One file name in two folders: the name is the window's title, so only the document differs.
        for (markdown, screenshot) in [("", empty), ("# A heading", text)] {
            let folder = NSTemporaryDirectory() + "actionui-demo-addon-\(ProcessInfo.processInfo.processIdentifier)-\(markdown.count)"
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            files.append(folder)
            let document = #"{"type": "RichText", "id": 1, "properties": {"markdown": ""# + markdown + #"", "frame": {"width": 320, "height": 200}}}"#
            try Data(document.utf8).write(to: URL(fileURLWithPath: folder).appendingPathComponent("Document.json"))
            XCTAssertEqual(try runDemo(["--resources", folder, "--open", "Document", "--screenshot", screenshot]), 0)
        }
        XCTAssertNotNil(FileManager.default.contents(atPath: text))
        XCTAssertNotEqual(FileManager.default.contents(atPath: text), FileManager.default.contents(atPath: empty), "the document made no difference: the add-on is not registered")
    }

    func testAnUnknownDocumentNoDocumentsAndBadArgumentsStopIt() throws {
        XCTAssertEqual(try runDemo(["--resources", resources, "--open", "NoSuchDocument"]), 66)
        XCTAssertEqual(try runDemo(["--resources", NSTemporaryDirectory() + "actionui-demo-empty-\(ProcessInfo.processInfo.processIdentifier)"]), 66)
        XCTAssertEqual(try runDemo(["--open"]), 64)
        XCTAssertEqual(try runDemo(["--frobnicate"]), 64)
        XCTAssertEqual(try runDemo(["--action", "list.demo.load"]), 64, "an action needs a document")
    }
}
