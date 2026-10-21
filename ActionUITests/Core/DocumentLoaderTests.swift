// Core/DocumentLoaderTests.swift
/*
 Tests for ActionUIDocumentLoader: where a LoadableView's text points (with a stub bundle), the
 format of a file or URL, loading a description as content or as a sub-view (from data, and from a
 stub fetch), and viewDidLoad once per source.
*/

import XCTest
@testable import ActionUI

@MainActor
final class DocumentLoaderTests: XCTestCase {
    private var windowUUID: String!
    private var logger: XCTestLogger!

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = nil
        logger = nil
    }

    /// A bundle holding "panel.json", "settings.plist" and "both.json" and "both.plist".
    private func bundleURL(_ name: String, _ ext: String) -> URL? {
        let files = ["panel.json", "settings.plist", "both.json", "both.plist"]
        let file = "\(name).\(ext)"
        return files.contains(file) ? URL(fileURLWithPath: "/bundle/" + file) : nil
    }

    private func source(_ value: String) -> Result<ActionUIDocumentLoader.Source, ActionUIDocumentLoader.SourceError> {
        ActionUIDocumentLoader.source(for: value, bundleURL: bundleURL, logger: logger)
    }

    func testRemoteURLs() {
        XCTAssertEqual(source("https://example.com/a.json"), .success(.remote(URL(string: "https://example.com/a.json")!)))
        XCTAssertEqual(source("HTTP://example.com/a"), .success(.remote(URL(string: "HTTP://example.com/a")!)))
        XCTAssertEqual(source("http://exa mple.com"), .failure(.init(message: "Invalid URL: http://exa mple.com")))
    }

    func testFileURLsAndPaths() {
        XCTAssertEqual(source("file:///tmp/a.json"), .success(.file(URL(string: "file:///tmp/a.json")!)))
        XCTAssertEqual(source("file://"), .failure(.init(message: "Invalid file URL: file://")))
        XCTAssertEqual(source("/tmp/a.json"), .success(.file(URL(fileURLWithPath: "/tmp/a.json"))))
        XCTAssertEqual(source("dir/a.plist"), .success(.file(URL(fileURLWithPath: "dir/a.plist"))))
    }

    func testBundledResources() {
        XCTAssertEqual(source("panel"), .success(.file(URL(fileURLWithPath: "/bundle/panel.json"))))
        XCTAssertEqual(source("panel.json"), .success(.file(URL(fileURLWithPath: "/bundle/panel.json"))))
        XCTAssertEqual(source("settings"), .success(.file(URL(fileURLWithPath: "/bundle/settings.plist"))), "json, then plist")
        XCTAssertEqual(source("settings.json"), .success(.file(URL(fileURLWithPath: "/bundle/settings.plist"))))
        XCTAssertEqual(source("panel.plist"), .success(.file(URL(fileURLWithPath: "/bundle/panel.json"))), "plist, then json")
        XCTAssertEqual(source("both"), .success(.file(URL(fileURLWithPath: "/bundle/both.json"))))
        XCTAssertEqual(source("both.plist"), .success(.file(URL(fileURLWithPath: "/bundle/both.plist"))))
        XCTAssertEqual(source("panel.JSON"), .failure(.init(message: "Bundle resource 'panel.JSON' not found")),
                       "an extension not in lower case stays in the name (panel.JSON.json), as before")
        XCTAssertEqual(source("missing"), .failure(.init(message: "Bundle resource 'missing' not found")))
    }

    func testFormat() {
        XCTAssertEqual(ActionUIDocumentLoader.format(of: URL(fileURLWithPath: "/a/b.plist")), "plist")
        XCTAssertEqual(ActionUIDocumentLoader.format(of: URL(string: "https://x/b.PLIST")!), "plist")
        XCTAssertEqual(ActionUIDocumentLoader.format(of: URL(fileURLWithPath: "/a/b.json")), "json")
        XCTAssertEqual(ActionUIDocumentLoader.format(of: URL(fileURLWithPath: "/a/b")), "json")
    }

    private let root = Data(#"{ "id": 1, "type": "VStack", "children": [ { "id": 100, "type": "LoadableView", "properties": {} } ] }"#.utf8)
    private let panel = Data(#"{ "id": 200, "type": "Text", "properties": { "text": "Panel" } }"#.utf8)

    func testLoadAsContentAndAsSubView() throws {
        let content = try ActionUIDocumentLoader.load(data: root, format: "json", windowUUID: windowUUID, isContentView: true, parentID: 0)
        XCTAssertEqual(content.id, 1)
        let sub = try ActionUIDocumentLoader.load(data: panel, format: "json", windowUUID: windowUUID, isContentView: false, parentID: 100)
        XCTAssertEqual(sub.id, 200)
        XCTAssertNotNil(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[200])
        XCTAssertNotNil(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1], "a sub-view keeps the content")
    }

    func testLoadRemoteFetchesAndLoads() async throws {
        let url = URL(string: "https://example.com/root.json")!
        var fetched: [URL] = []
        let data = root
        let element = try await ActionUIDocumentLoader.loadRemote(
            url: url, windowUUID: windowUUID, isContentView: true, parentID: 0, logger: logger
        ) { url in
            fetched.append(url)
            return data
        }
        XCTAssertEqual(fetched, [url])
        XCTAssertEqual(element.id, 1)
    }

    func testLoadRemotePassesTheFetchErrorOn() async {
        struct Offline: Error {}
        do {
            _ = try await ActionUIDocumentLoader.loadRemote(
                url: URL(string: "https://example.com/a.json")!, windowUUID: windowUUID, isContentView: true, parentID: 0, logger: logger
            ) { _ in throw Offline() }
            XCTFail("expected the fetch error")
        } catch {
            XCTAssertTrue(error is Offline)
        }
    }

    func testViewDidLoadFiresOncePerSource() throws {
        _ = try ActionUIDocumentLoader.load(data: root, format: "json", windowUUID: windowUUID, isContentView: true, parentID: 0)
        var fired: [Int] = []
        ActionUIModel.shared.setDefaultActionHandler { actionID, _, viewID, viewPartID, _ in
            XCTAssertEqual(actionID, "loaded")
            XCTAssertEqual(viewPartID, 0)
            fired.append(viewID)
        }
        let viewDidLoad = ActionUIDocumentLoader.ViewDidLoad()
        viewDidLoad.fire(source: "a", windowUUID: windowUUID, parentID: 100, actionID: "loaded")
        viewDidLoad.fire(source: "a", windowUUID: windowUUID, parentID: 100, actionID: "loaded")
        XCTAssertEqual(fired, [100], "the same source again does not fire")
        viewDidLoad.fire(source: "b", windowUUID: windowUUID, parentID: 100, actionID: "loaded")
        viewDidLoad.fire(source: "a", windowUUID: windowUUID, parentID: 100, actionID: "loaded")
        XCTAssertEqual(fired, [100, 100, 100], "a different source fires, and so does the first one again")
        viewDidLoad.fire(source: "c", windowUUID: windowUUID, parentID: 100, actionID: nil)
        viewDidLoad.fire(source: "c", windowUUID: windowUUID, parentID: 999, actionID: "loaded")
        viewDidLoad.fire(source: "c", windowUUID: "no-such-window", parentID: 100, actionID: "loaded")
        XCTAssertEqual(fired.count, 3, "no action, no such element, no such window")
        viewDidLoad.fire(source: "c", windowUUID: windowUUID, parentID: 100, actionID: "loaded")
        XCTAssertEqual(fired.count, 4, "a call that did not fire records nothing")
    }
}
