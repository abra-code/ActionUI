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

    func testOnlyARegularFileIsRead() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("regular-file-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a.json")
        try Data("{}".utf8).write(to: file)
        let link = folder.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let deviceLink = folder.appendingPathComponent("zero.json")
        try FileManager.default.createSymbolicLink(at: deviceLink, withDestinationURL: URL(fileURLWithPath: "/dev/zero"))

        XCTAssertEqual(try ActionUIDocumentLoader.readRegularFile(file), Data("{}".utf8))
        XCTAssertEqual(try ActionUIDocumentLoader.readRegularFile(link), Data("{}".utf8), "a link to a regular file is read")
        // Devices are /dev's on Unix; Windows has no /dev (there the paths do not exist, and reading them
        // fails as a missing file), so it checks the folder and the link.
#if os(Windows)
        let refused = [folder.path, deviceLink.path]
#else
        let refused = ["/dev/zero", "/dev/null", folder.path, deviceLink.path]
#endif
        for path in refused {
            XCTAssertThrowsError(try ActionUIDocumentLoader.readRegularFile(URL(fileURLWithPath: path)), path) { error in
                XCTAssertTrue(error is ActionUIDocumentLoader.NotARegularFile, "\(path): \(error)")
            }
        }
        // A missing file keeps the system's own error (LoadableView shows "no such file").
        XCTAssertThrowsError(try ActionUIDocumentLoader.readRegularFile(folder.appendingPathComponent("missing.json"))) { error in
            XCTAssertFalse(error is ActionUIDocumentLoader.NotARegularFile, "\(error)")
            XCTAssertEqual((error as? CocoaError)?.code, .fileReadNoSuchFile, "\(error)")
        }
    }

    func testRegularFilePathFollowsLinksAndRefusesEverythingElse() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("regular-path-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a.png")
        try Data([0]).write(to: file)
        let link = folder.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        XCTAssertEqual(ActionUIDocumentLoader.regularFilePath(file), file.resolvingSymlinksInPath().path)
        XCTAssertEqual(ActionUIDocumentLoader.regularFilePath(link), file.resolvingSymlinksInPath().path,
                       "a link gives the path of the file it names")
        for path in ["/dev/zero", "/dev/null", folder.path, folder.appendingPathComponent("missing.png").path] {
            XCTAssertNil(ActionUIDocumentLoader.regularFilePath(URL(fileURLWithPath: path)), path)
        }
    }

    func testTheNestingRuleRefusesARepeatAndADeepChain() {
        XCTAssertNil(ActionUIDocumentLoader.nestingRefusal("b", inside: ["a"]))
        XCTAssertEqual(ActionUIDocumentLoader.nestingRefusal("a", inside: ["a", "b"]), "it includes itself")
        let deep = (0..<16).map { "doc\($0)" }
        XCTAssertEqual(ActionUIDocumentLoader.nestingRefusal("next", inside: deep), "LoadableViews are nested more than 16 deep")
        XCTAssertNil(ActionUIDocumentLoader.nestingRefusal("next", inside: Array(deep.dropLast())))
    }

    func testANestingKeyNamesAFileByItsResolvedPath() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nesting-key-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a.json")
        try Data("{}".utf8).write(to: file)
        let link = folder.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
        let dotted = URL(fileURLWithPath: folder.path + "/./sub/../a.json")
        let key = ActionUIDocumentLoader.nestingKey(for: .file(file))
        XCTAssertEqual(ActionUIDocumentLoader.nestingKey(for: .file(link)), key)
        XCTAssertEqual(ActionUIDocumentLoader.nestingKey(for: .file(dotted)), key)
        let remote = URL(string: "https://example.com/a.json?x=1")!
        XCTAssertEqual(ActionUIDocumentLoader.nestingKey(for: .remote(remote)), remote.absoluteString)
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
