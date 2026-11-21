// Core/DocumentLoaderTests.swift
/*
 Tests for ActionUIDocumentLoader: where a LoadableView's text points (with a stub bundle), the
 format of a file or URL, loading a description as content or as a sub-view (from data, and from a
 stub fetch), viewDidLoad once per source, and the origin each loaded element is given (trusted
 for the host and the app's resources, less trusted for remote documents, files elsewhere and all
 they load).
*/

import XCTest
@testable import ActionUI

/// A policy that trusts every local file, lowers the app's resources, and refuses links to less-
/// trusted content, recording what it was asked.
private final class TestPolicy: ActionUITrustPolicy, @unchecked Sendable {
    var asked: [(source: JSONContentOrigin.Source, parent: JSONContentOrigin?, byDefault: JSONContentOrigin.Trust)] = []
    var capabilities: [(ActionUICapability, JSONContentOrigin)] = []

    func trust(for source: JSONContentOrigin.Source, inside parent: JSONContentOrigin?, byDefault: JSONContentOrigin.Trust) -> JSONContentOrigin.Trust {
        asked.append((source, parent, byDefault))
        switch source {
        case .file: return .trusted
        case .resource: return .lessTrusted
        default: return byDefault
        }
    }

    func allows(_ capability: ActionUICapability, for origin: JSONContentOrigin) -> Bool {
        capabilities.append((capability, origin))
        if case .openLink = capability { return origin.trust == .trusted }
        return true
    }
}

// Records messages without failing the test, for a load that logs an id conflict on purpose.
private final class RecordingLogger: ActionUILogger, @unchecked Sendable {
    private(set) var errors: [String] = []
    func log(_ message: String, _ level: LoggerLevel) {
        if level == .error { errors.append(message) }
    }
}

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
        for path in ["/dev/zero", "/dev/null", folder.path, deviceLink.path] {
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
        let content = try ActionUIDocumentLoader.load(data: root, format: "json", windowUUID: windowUUID, isContentView: true, parentID: 0, source: nil)
        XCTAssertEqual(content.id, 1)
        let sub = try ActionUIDocumentLoader.load(data: panel, format: "json", windowUUID: windowUUID, isContentView: false, parentID: 100, source: nil)
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

    // MARK: Origin

    /// A new folder with a "resources" folder (holding "inside.json"), an "outside.json" beside it,
    /// a link in the resources to the outside file, and a sibling folder named "resources2".
    private func originFolders() throws -> (root: URL, resources: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("actionui-origin-\(UUID().uuidString)")
        let resources = root.appendingPathComponent("resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("resources2"), withIntermediateDirectories: true)
        try panel.write(to: resources.appendingPathComponent("inside.json"))
        try panel.write(to: root.appendingPathComponent("outside.json"))
        try panel.write(to: root.appendingPathComponent("resources2/sibling.json"))
        try FileManager.default.createSymbolicLink(at: resources.appendingPathComponent("link.json"),
                                                   withDestinationURL: root.appendingPathComponent("outside.json"))
        return (root, resources)
    }

    func testAFileIsInsideAFolderOnlyBelowIt() throws {
        let (root, resources) = try originFolders()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(ActionUIResourceFolder.isFile(resources.appendingPathComponent("inside.json"), inside: resources.path))
        XCTAssertTrue(ActionUIResourceFolder.isFile(resources.appendingPathComponent("inside.json"), inside: resources.path + "/"))
        XCTAssertFalse(ActionUIResourceFolder.isFile(root.appendingPathComponent("outside.json"), inside: resources.path))
        XCTAssertFalse(ActionUIResourceFolder.isFile(root.appendingPathComponent("resources2/sibling.json"), inside: resources.path),
                       "a sibling whose name starts with the folder's")
        XCTAssertFalse(ActionUIResourceFolder.isFile(resources.appendingPathComponent("link.json"), inside: resources.path),
                       "a link in the folder to a file outside it")
        XCTAssertFalse(ActionUIResourceFolder.isFile(resources.appendingPathComponent("../outside.json"), inside: resources.path))
        XCTAssertFalse(ActionUIResourceFolder.isFile(resources.appendingPathComponent("inside.json"), inside: "/"), "the root holds nothing")
        XCTAssertFalse(ActionUIResourceFolder.isFile(resources.appendingPathComponent("inside.json"), inside: ""))
    }

    func testTheOriginOfASource() throws {
        let (root, resources) = try originFolders()
        defer { try? FileManager.default.removeItem(at: root) }
        let folders = [resources.path]
        func origin(_ source: ActionUIDocumentLoader.Source, inside parent: JSONContentOrigin? = nil) -> JSONContentOrigin {
            ActionUIDocumentLoader.origin(for: source, inside: parent, parentID: 7, resourceFolders: folders)
        }
        let remoteURL = URL(string: "https://example.com/a.json")!
        let remote = origin(.remote(remoteURL))
        XCTAssertEqual(remote, JSONContentOrigin(source: .remote(remoteURL), trust: .lessTrusted, parentID: 7))
        let inside = origin(.file(resources.appendingPathComponent("inside.json")))
        XCTAssertEqual(inside.trust, .trusted)
        guard case .resource(let path) = inside.source else { return XCTFail("\(inside)") }
        XCTAssertTrue(path.hasSuffix("/resources/inside.json"), path)
        let outside = origin(.file(root.appendingPathComponent("outside.json")))
        XCTAssertEqual(outside.trust, .lessTrusted)
        guard case .file = outside.source else { return XCTFail("\(outside)") }
        XCTAssertEqual(origin(.file(resources.appendingPathComponent("link.json"))).trust, .lessTrusted, "a link out of the resources")
        XCTAssertEqual(origin(.file(resources.appendingPathComponent("inside.json")), inside: remote).trust, .lessTrusted,
                       "a bundled file a remote document names stays less trusted")
        XCTAssertEqual(origin(.file(resources.appendingPathComponent("inside.json")), inside: .host).trust, .trusted)
        XCTAssertEqual(ActionUIDocumentLoader.origin(for: .file(resources.appendingPathComponent("inside.json")), inside: nil,
                                                     parentID: 7, resourceFolders: []).trust,
                       .lessTrusted, "no resource folders: no file is the app's")
    }

    func testEachLoadedElementKeepsItsOrigin() throws {
        let (root, resources) = try originFolders()
        defer { try? FileManager.default.removeItem(at: root) }
        let savedFolders = ActionUIRendererHooks.resourceFolders
        defer { ActionUIRendererHooks.resourceFolders = savedFolders }
        ActionUIRendererHooks.resourceFolders = { [resources.path] }
        // The window takes the logger it is made with: the conflicts below are logged as errors.
        let recording = RecordingLogger()
        ActionUIModel.shared.logger = recording

        // The window's root, from a file in the resources: trusted, no parent.
        _ = try ActionUIDocumentLoader.load(data: self.root, format: "json", windowUUID: windowUUID, isContentView: true, parentID: 0,
                                            source: .file(resources.appendingPathComponent("inside.json")))
        let rootOrigin = try XCTUnwrap(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 1))
        XCTAssertEqual(rootOrigin.trust, .trusted)
        XCTAssertNil(rootOrigin.parentID)
        XCTAssertTrue(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 100) === rootOrigin, "one object for the whole load")

        // A remote document in the LoadableView 100, with a LoadableView 300 of its own.
        let remote = Data(#"{ "id": 200, "type": "VStack", "children": [ { "id": 300, "type": "LoadableView", "properties": {} } ] }"#.utf8)
        let remoteURL = URL(string: "https://example.com/panel.json")!
        _ = try ActionUIDocumentLoader.load(data: remote, format: "json", windowUUID: windowUUID, isContentView: false, parentID: 100,
                                            source: .remote(remoteURL))
        XCTAssertEqual(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 200),
                       JSONContentOrigin(source: .remote(remoteURL), trust: .lessTrusted, parentID: 100))
        XCTAssertEqual(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 300)?.trust, .lessTrusted)
        XCTAssertTrue(recording.errors.isEmpty, "\(recording.errors)")

        // A less-trusted document that reuses a trusted element's id (1, the root's) is refused
        // whole: its element would be drawn with the root's view model and read as trusted.
        let colliding = Data(#"{ "id": 350, "type": "VStack", "children": [ { "id": 1, "type": "LoadableView", "properties": {} } ] }"#.utf8)
        XCTAssertThrowsError(try ActionUIDocumentLoader.load(data: colliding, format: "json", windowUUID: windowUUID, isContentView: false,
                                                             parentID: 300, source: .remote(remoteURL))) { error in
            XCTAssertEqual("\(error)", "id conflict: 1 already in the window")
        }
        XCTAssertTrue(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 1) === rootOrigin, "the root's element is untouched")
        XCTAssertNil(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 350), "nothing of it is loaded")
        XCTAssertEqual(recording.errors, ["Not loading a less-trusted sub-view for parent 300: id 1 is already in the window"])

        // A bundled file the remote document names: less trusted, as the content around it.
        let inner = Data(#"{ "id": 400, "type": "Text", "properties": { "text": "Inner" } }"#.utf8)
        _ = try ActionUIDocumentLoader.load(data: inner, format: "json", windowUUID: windowUUID, isContentView: false, parentID: 300,
                                            source: .file(resources.appendingPathComponent("inside.json")))
        let nested = try XCTUnwrap(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 400))
        XCTAssertEqual(nested.trust, .lessTrusted)
        XCTAssertEqual(nested.parentID, 300)
        guard case .resource = nested.source else { return XCTFail("\(nested)") }

        // Data the host holds, loaded in place of the remote document: the host's, and the remote
        // document's elements (and what they loaded) are gone with their origins.
        let hostPanel = Data(#"{ "id": 500, "type": "Text", "properties": {} }"#.utf8)
        _ = try ActionUIDocumentLoader.load(data: hostPanel, format: "json", windowUUID: windowUUID, isContentView: false, parentID: 100, source: nil)
        XCTAssertTrue(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 500) === JSONContentOrigin.host)
        XCTAssertNil(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 200))
        XCTAssertNil(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 400))
        XCTAssertTrue(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 1) === rootOrigin)
        XCTAssertNil(ActionUIModel.shared.origin(windowUUID: "no-such-window", viewID: 1))

        // A trusted document's conflict is skipped, as before: the rest loads, the id keeps its own.
        let trustedColliding = Data(#"{ "id": 600, "type": "VStack", "children": [ { "id": 1, "type": "Text", "properties": {} } ] }"#.utf8)
        _ = try ActionUIDocumentLoader.load(data: trustedColliding, format: "json", windowUUID: windowUUID, isContentView: false, parentID: 100,
                                            source: .file(resources.appendingPathComponent("inside.json")))
        XCTAssertEqual(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 600)?.trust, .trusted)
        XCTAssertTrue(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 1) === rootOrigin, "a conflicting id keeps its own origin")
        XCTAssertEqual(recording.errors.last, "ID conflict for sub-view 1; skipping merge")
    }

    func testALoadableViewWithNoViewModelLoadsLessTrustedContent() throws {
        let (root, resources) = try originFolders()
        defer { try? FileManager.default.removeItem(at: root) }
        let savedFolders = ActionUIRendererHooks.resourceFolders
        defer { ActionUIRendererHooks.resourceFolders = savedFolders }
        ActionUIRendererHooks.resourceFolders = { [resources.path] }
        // A remote window root whose LoadableView 600 is in a template: a blueprint, with no view
        // model, as a template row's LoadableView loads into.
        let remote = Data(#"{ "id": 1, "type": "VStack", "template": { "id": 600, "type": "LoadableView", "properties": {} } }"#.utf8)
        _ = try ActionUIDocumentLoader.load(data: remote, format: "json", windowUUID: windowUUID, isContentView: true, parentID: 0,
                                            source: .remote(URL(string: "https://example.com/list.json")!))
        XCTAssertNil(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[600])
        _ = try ActionUIDocumentLoader.load(data: panel, format: "json", windowUUID: windowUUID, isContentView: false, parentID: 600,
                                            source: .file(resources.appendingPathComponent("inside.json")))
        let origin = try XCTUnwrap(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 200))
        XCTAssertEqual(origin.trust, .lessTrusted, "a parent with no known trust is not the host's")
        XCTAssertEqual(origin.parentID, 600)
        guard case .resource = origin.source else { return XCTFail("\(origin)") }
    }

    func testTheHostsTrustPolicyHasTheLastWord() throws {
        let (root, resources) = try originFolders()
        defer { try? FileManager.default.removeItem(at: root) }
        let savedFolders = ActionUIRendererHooks.resourceFolders
        defer { ActionUIRendererHooks.resourceFolders = savedFolders }
        ActionUIRendererHooks.resourceFolders = { [resources.path] }
        let policy = TestPolicy()
        ActionUIModel.shared.trustPolicy = policy

        // A file outside the resources, as the window's root: the policy raises it.
        _ = try ActionUIDocumentLoader.load(data: self.root, format: "json", windowUUID: windowUUID, isContentView: true, parentID: 0,
                                            source: .file(root.appendingPathComponent("outside.json")))
        XCTAssertEqual(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 1)?.trust, .trusted)
        XCTAssertEqual(policy.asked.count, 1)
        XCTAssertNil(policy.asked[0].parent, "a window's root has no parent")
        XCTAssertEqual(policy.asked[0].byDefault, .lessTrusted, "what ActionUI would decide")

        // A resource file in the LoadableView 100: the policy lowers it, and is told the parent.
        _ = try ActionUIDocumentLoader.load(data: panel, format: "json", windowUUID: windowUUID, isContentView: false, parentID: 100,
                                            source: .file(resources.appendingPathComponent("inside.json")))
        XCTAssertEqual(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 200)?.trust, .lessTrusted)
        XCTAssertEqual(policy.asked.last?.parent?.trust, .trusted)
        XCTAssertEqual(policy.asked.last?.byDefault, .trusted)

        // allows: the element's origin goes to the policy; an element with no view model (a
        // template row's, or none) is less trusted.
        XCTAssertFalse(ActionUIModel.shared.allows(.openLink(URL(string: "https://example.com")!), windowUUID: windowUUID, viewID: 200))
        XCTAssertTrue(ActionUIModel.shared.allows(.openLink(URL(string: "https://example.com")!), windowUUID: windowUUID, viewID: 1))
        XCTAssertFalse(ActionUIModel.shared.allows(.openLink(URL(string: "https://example.com")!), windowUUID: windowUUID, viewID: 999))
        XCTAssertEqual(policy.capabilities.last?.1.trust, .lessTrusted)

        // A LoadableView with no view model (a template row's, id 999): no parent, and less trusted
        // by default, so a policy that keeps the default stays safe.
        _ = try ActionUIDocumentLoader.load(data: Data(#"{ "id": 700, "type": "Text", "properties": {} }"#.utf8), format: "json",
                                            windowUUID: windowUUID, isContentView: false, parentID: 999,
                                            source: .remote(URL(string: "https://example.com/row.json")!))
        XCTAssertNil(policy.asked.last?.parent)
        XCTAssertEqual(policy.asked.last?.byDefault, .lessTrusted)
    }

    func testTheDefaultPolicyLetsLessTrustedLinksOpenOnlyWebAndMail() {
        let lessTrusted = JSONContentOrigin(source: .remote(URL(string: "https://example.com/a.json")!), trust: .lessTrusted, parentID: 1)
        let capabilities: [ActionUICapability] = [
            .load(.remote(URL(string: "https://example.com/b.json")!)), .openLink(URL(string: "https://example.com")!),
            .webView(nil), .webViewScriptFile("/tmp/a.js"), .windowTitle, .presentModal,
            .menuCommands, .action("a"),
        ]
        for capability in capabilities {
            XCTAssertTrue(DefaultTrustPolicy().allows(capability, for: lessTrusted), "\(capability)")
            XCTAssertTrue(DefaultTrustPolicy().allows(capability, for: .host), "\(capability)")
        }
        for address in ["file:///etc/hosts", "smb://server/share", "someapp://run", "javascript:alert(1)", "example.com"] {
            let url = try! XCTUnwrap(URL(string: address))
            XCTAssertFalse(DefaultTrustPolicy().allows(.openLink(url), for: lessTrusted), address)
            XCTAssertTrue(DefaultTrustPolicy().allows(.openLink(url), for: .host), "\(address): the host's content opens anything")
        }
        XCTAssertFalse(DefaultTrustPolicy().allows(.readLocalFile("/tmp/a.png"), for: lessTrusted), "a file outside the app's resources")
        XCTAssertTrue(DefaultTrustPolicy().allows(.readLocalFile("/tmp/a.png"), for: .host))
        for address in ["HTTPS://example.com", "mailto:someone@example.com"] {
            XCTAssertTrue(DefaultTrustPolicy().allows(.openLink(URL(string: address)!), for: lessTrusted), address)
        }
        XCTAssertEqual(DefaultTrustPolicy().trust(for: .file("/tmp/a.json"), inside: nil, byDefault: .lessTrusted), .lessTrusted)
    }

    func testAWindowsLoadsAreCappedPerSpanOfTime() throws {
        let recording = RecordingLogger()
        ActionUIModel.shared.logger = recording
        // A long span while counting, so a slow machine cannot let a load expire in the middle.
        ActionUIModel.shared.loadBudget = ActionUILoadBudget(loads: 3, seconds: 60)
        _ = try ActionUIDocumentLoader.load(data: root, format: "json", windowUUID: windowUUID, isContentView: true, parentID: 0, source: nil)
        for _ in 0..<3 {
            _ = try ActionUIDocumentLoader.load(data: panel, format: "json", windowUUID: windowUUID, isContentView: false, parentID: 100, source: nil)
        }
        XCTAssertThrowsError(try ActionUIDocumentLoader.load(data: panel, format: "json", windowUUID: windowUUID, isContentView: false,
                                                             parentID: 100, source: nil)) { error in
            XCTAssertEqual("\(error)", "too many loads in this window")
        }
        XCTAssertNotNil(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[200], "the content loaded before stays")
        XCTAssertEqual(recording.errors.count, 1)
        // The window's own reload does not reset the count; another window has its own.
        _ = try ActionUIDocumentLoader.load(data: root, format: "json", windowUUID: windowUUID, isContentView: true, parentID: 0, source: nil)
        XCTAssertThrowsError(try ActionUIDocumentLoader.load(data: panel, format: "json", windowUUID: windowUUID, isContentView: false,
                                                             parentID: 100, source: nil))
        let other = UUID().uuidString
        _ = try ActionUIDocumentLoader.load(data: root, format: "json", windowUUID: other, isContentView: true, parentID: 0, source: nil)
        XCTAssertNoThrow(try ActionUIDocumentLoader.load(data: panel, format: "json", windowUUID: other, isContentView: false, parentID: 100, source: nil))
        // Once the span has passed, loads go on (the span read at each load, shortened here).
        ActionUIModel.shared.loadBudget = ActionUILoadBudget(loads: 3, seconds: 0.2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertNoThrow(try ActionUIDocumentLoader.load(data: panel, format: "json", windowUUID: windowUUID, isContentView: false, parentID: 100, source: nil))
    }

    func testJSONLargerThanTheCapIsRefused() throws {
        let recording = RecordingLogger()
        ActionUIModel.shared.logger = recording
        let saved = WindowModel.maximumJSONSize
        defer { WindowModel.maximumJSONSize = saved }
        WindowModel.maximumJSONSize = root.count
        _ = try ActionUIDocumentLoader.load(data: root, format: "json", windowUUID: windowUUID, isContentView: true, parentID: 0, source: nil)
        WindowModel.maximumJSONSize = root.count - 1
        XCTAssertThrowsError(try ActionUIDocumentLoader.load(data: root, format: "json", windowUUID: windowUUID, isContentView: true,
                                                             parentID: 0, source: nil)) { error in
            XCTAssertEqual("\(error)", "the ActionUI JSON is larger than 0 MB")
        }
        WindowModel.maximumJSONSize = panel.count - 1
        XCTAssertThrowsError(try ActionUIDocumentLoader.load(data: panel, format: "json", windowUUID: windowUUID, isContentView: false,
                                                             parentID: 100, source: nil))
        XCTAssertThrowsError(try ActionUIModel.shared.windowModels[windowUUID]?.loadModalDescription(from: panel, format: "json"))
        XCTAssertEqual(recording.errors.count, 3)
        XCTAssertEqual(saved, 16 * 1024 * 1024, "16 MB")
    }

    func testAFileLargerThanTheCapIsNotRead() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("actionui-big-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let exact = folder.appendingPathComponent("exact.json")
        let over = folder.appendingPathComponent("over.json")
        try Data(count: ActionUIDocumentLoader.maximumFileSize).write(to: exact)
        try Data(count: ActionUIDocumentLoader.maximumFileSize + 1).write(to: over)
        XCTAssertEqual(try ActionUIDocumentLoader.readRegularFile(exact).count, ActionUIDocumentLoader.maximumFileSize)
        XCTAssertThrowsError(try ActionUIDocumentLoader.readRegularFile(over)) { error in
            XCTAssertEqual("\(error)", "over.json is larger than 16 MB")
        }
    }

    func testALessTrustedWebViewShowsOnlyWebAddressesAndItsOwnOriginAsABase() throws {
        let document = try XCTUnwrap(URL(string: "https://example.com/app/view.json"))
        let remote = JSONContentOrigin(source: .remote(document), trust: .lessTrusted, parentID: 1)
        let file = JSONContentOrigin(source: .file("/tmp/view.json"), trust: .lessTrusted, parentID: 1)
        let policy = DefaultTrustPolicy()
        func url(_ text: String) -> URL { URL(string: text)! }
        XCTAssertTrue(policy.allows(.webView(url("https://example.com/page")), for: remote))
        XCTAssertTrue(policy.allows(.webView(url("http://other.example/page")), for: remote))
        XCTAssertFalse(policy.allows(.webView(url("file:///etc/hosts")), for: remote))
        XCTAssertFalse(policy.allows(.webView(url("someapp://run")), for: remote))
        XCTAssertTrue(policy.allows(.webView(nil), for: remote), "inline html")
        XCTAssertTrue(policy.allows(.webView(url("file:///etc/hosts")), for: .host), "the host's content shows anything")
        // A base of the document's own origin only.
        XCTAssertTrue(policy.allows(.webViewBaseURL(url("https://example.com/assets/")), for: remote))
        XCTAssertTrue(policy.allows(.webViewBaseURL(url("HTTPS://Example.com:443/")), for: remote), "the default port, any case")
        XCTAssertFalse(policy.allows(.webViewBaseURL(url("https://example.com:8443/")), for: remote), "another port")
        XCTAssertFalse(policy.allows(.webViewBaseURL(url("http://example.com/")), for: remote), "another scheme")
        XCTAssertFalse(policy.allows(.webViewBaseURL(url("https://bank.example/")), for: remote), "another site")
        XCTAssertFalse(policy.allows(.webViewBaseURL(url("file:///Users/")), for: remote))
        XCTAssertFalse(policy.allows(.webViewBaseURL(url("https://example.com/")), for: file), "a local file has no origin to keep")
        XCTAssertTrue(policy.allows(.webViewBaseURL(url("file:///Users/")), for: .host))

        let recording = RecordingLogger()
        let refuseAll: (ActionUICapability) -> Bool = { _ in false }
        let allowAll: (ActionUICapability) -> Bool = { _ in true }
        XCTAssertEqual(WebViewTrust.base(url("https://bank.example/"), allows: refuseAll, logger: recording), WebViewTrust.blankBase)
        XCTAssertEqual(WebViewTrust.base(url("https://example.com/"), allows: allowAll, logger: recording), url("https://example.com/"))
        XCTAssertEqual(WebViewTrust.base(nil, allows: refuseAll, logger: recording), WebViewTrust.blankBase, "no base: nothing to ask")
        XCTAssertFalse(WebViewTrust.showsAddress(url("file:///etc/hosts"), allows: refuseAll, logger: recording))
        XCTAssertTrue(WebViewTrust.showsAddress(url("https://example.com/"), allows: allowAll, logger: recording))
        XCTAssertEqual(recording.errors, [], "refusals are warnings")
        let page = WebViewTrust.blockedPage(url("https://example.com/?a=<b>&c=\"d\""))
        XCTAssertTrue(page.contains("Blocked: https://example.com/?a=%3Cb%3E&amp;c=%22d%22") || page.contains("&lt;b&gt;"), page)
        XCTAssertFalse(page.contains("<b>"), "the address is escaped")
    }

    func testALessTrustedWebViewsPageGoesOnlyToWebAddressesOrAllowedLinks() {
        let lessTrusted = JSONContentOrigin(source: .remote(URL(string: "https://example.com/v.json")!), trust: .lessTrusted, parentID: 1)
        let allows: (ActionUICapability) -> Bool = { DefaultTrustPolicy().allows($0, for: lessTrusted) }
        let recording = RecordingLogger()
        func decide(_ text: String, mainFrame: Bool = true) -> WebViewTrust.Navigation {
            WebViewTrust.navigation(URL(string: text)!, isMainFrame: mainFrame, allows: allows, logger: recording)
        }
        XCTAssertEqual(decide("https://example.com/next"), .load)
        XCTAssertEqual(decide("http://other.example/"), .load)
        XCTAssertEqual(decide("about:blank"), .load)
        XCTAssertEqual(decide("data:text/html,hi"), .load)
        XCTAssertEqual(decide("blob:https://example.com/1234"), .load)
        XCTAssertEqual(decide("mailto:a@example.com"), .open, "an allowed link goes to the system")
        XCTAssertEqual(decide("mailto:a@example.com", mainFrame: false), .refuse, "a frame opens no other app")
        XCTAssertEqual(decide("someapp://run"), .refuse, "an app's own scheme")
        XCTAssertEqual(decide("file:///etc/hosts"), .refuse)
        XCTAssertEqual(decide("smb://server/share"), .refuse)
        // A host policy that keeps a page on its own site: other web addresses are refused for the
        // page itself, while a frame in it still loads.
        let ownSiteOnly: (ActionUICapability) -> Bool = { capability in
            if case .webView(let url?) = capability { return url.host == "example.com" }
            return allows(capability)
        }
        XCTAssertEqual(WebViewTrust.navigation(URL(string: "https://other.example/")!, isMainFrame: true, allows: ownSiteOnly, logger: recording), .refuse)
        XCTAssertEqual(WebViewTrust.navigation(URL(string: "https://other.example/")!, isMainFrame: false, allows: ownSiteOnly, logger: recording), .load)
        // A host policy that lets the WebView show a local file: its own load is not refused.
        let fileAllowed: (ActionUICapability) -> Bool = { capability in
            if case .webView(let url?) = capability, url.isFileURL { return true }
            return allows(capability)
        }
        XCTAssertEqual(WebViewTrust.navigation(URL(fileURLWithPath: "/tmp/page.html"), isMainFrame: true, allows: fileAllowed, logger: recording), .load)
        XCTAssertEqual(recording.errors, [], "refusals are warnings")
    }

    func testViewDidLoadFiresOncePerSource() throws {
        _ = try ActionUIDocumentLoader.load(data: root, format: "json", windowUUID: windowUUID, isContentView: true, parentID: 0, source: nil)
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
