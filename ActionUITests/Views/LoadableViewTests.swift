// Tests/Views/LoadableViewTests.swift
/*
 LoadableViewTests.swift

 Tests for the LoadableView component in the ActionUI component library.
 Verifies JSON decoding, Props reading, and view construction.
*/

import XCTest
import SwiftUI
@testable import ActionUI

/// Serves fixed bodies for RemoteJSONFetch: /big (1001 bytes), /exact (1000), /told (says
/// 5000 bytes in Content-Length), /stall (headers, then nothing), /moved (a redirect to
/// https://elsewhere.invalid/exact).
private final class StubJSONProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        if url.path == "/moved" {
            let target = URL(string: "https://elsewhere.invalid/exact")!
            let redirect = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: redirect)
            return
        }
        var headers = ["Content-Type": "application/json"]
        let body: Data?
        switch url.path {
        case "/big": body = Data(repeating: 0x20, count: 1001)
        case "/exact": body = Data(repeating: 0x20, count: 1000)
        case "/told":
            headers["Content-Length"] = "5000"
            body = Data(repeating: 0x20, count: 10)
        default: body = nil
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        guard let body else { return }
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
final class LoadableViewTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!
    
    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }
    
    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        try await super.tearDown()
    }
    
    func testLoadableViewPropsValid() {
        let properties: [String: Any] = [
            "url": "https://example.com/view.json"
        ]
        
        let props = LoadableView.Props(properties)
        
        XCTAssertEqual(props.url, "https://example.com/view.json", "url should be valid")
    }
    
    func testLoadableViewPropsIgnoreInvalidValues() {
        let properties: [String: Any] = [
            "url": 123
        ]
        
        let props = LoadableView.Props(properties)
        
        XCTAssertNil(props.url, "Invalid url should be ignored")
    }
    
    func testLoadableViewJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "LoadableView",
            "properties": {
                "url": "https://example.com/view.json",
                "padding": 10.0
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        
        // Parse JSON into ActionUIElement
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
        
        // Verify element properties
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "LoadableView", "Element type should be LoadableView")
        XCTAssertEqual(element.properties["url"] as? String, "https://example.com/view.json", "url should be https://example.com/view.json")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        
        // Verify ViewModel setup
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }
        XCTAssertEqual(viewModel.value as? String, "https://example.com/view.json", "Initial viewModel value should be the URL string")
        
//        // Verify view construction
//        let properties = element.properties
//        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
//        XCTAssertTrue(view is SwiftUI.AnyView, "Built view should be wrapped in AnyView")
    }

    // MARK: - Sub-view replacement (dynamic content swapping) tests

    /// Helper: loads a root window with a LoadableView placeholder, then loads a sub-view JSON as its content.
    private func loadRootWithLoadableView() throws -> WindowModel {
        let rootJSON = """
        {
            "id": 1,
            "type": "VStack",
            "properties": {},
            "children": [
                { "id": 100, "type": "LoadableView", "properties": { "filePath": "/tmp/panel.json" } }
            ]
        }
        """
        let data = rootJSON.data(using: .utf8)!
        _ = try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
        return ActionUIModel.shared.windowModels[windowUUID]!
    }

    /// Helper: creates sub-view JSON data with a given root id and child ids.
    private func subViewJSON(rootID: Int, childIDs: [Int]) -> Data {
        let children = childIDs.map { """
            { "id": \($0), "type": "Text", "properties": { "text": "child \($0)" } }
        """ }.joined(separator: ",\n")
        let json = """
        {
            "id": \(rootID),
            "type": "VStack",
            "properties": {},
            "children": [ \(children) ]
        }
        """
        return json.data(using: .utf8)!
    }

    func testFirstLoadWithParentIDRecordsOwnership() throws {
        let windowModel = try loadRootWithLoadableView()
        let parentID = 100

        let subData = subViewJSON(rootID: 200, childIDs: [201, 202])
        _ = try windowModel.loadSubViewDescription(from: subData, format: "json", parentID: parentID)

        // Ownership should be recorded
        XCTAssertNotNil(windowModel.loadedSubViewIDs[parentID], "Should record child IDs under parentID")
        XCTAssertTrue(windowModel.loadedSubViewIDs[parentID]!.contains(200))
        XCTAssertTrue(windowModel.loadedSubViewIDs[parentID]!.contains(201))
        XCTAssertTrue(windowModel.loadedSubViewIDs[parentID]!.contains(202))

        // ViewModels should be populated
        XCTAssertNotNil(windowModel.viewModels[200])
        XCTAssertNotNil(windowModel.viewModels[201])
        XCTAssertNotNil(windowModel.viewModels[202])
    }

    func testReplaceRemovesOldChildModels() throws {
        let windowModel = try loadRootWithLoadableView()
        let parentID = 100

        // First load
        let subData1 = subViewJSON(rootID: 200, childIDs: [201, 202])
        _ = try windowModel.loadSubViewDescription(from: subData1, format: "json", parentID: parentID)
        XCTAssertNotNil(windowModel.viewModels[200])
        XCTAssertNotNil(windowModel.viewModels[201])

        // Replace with new content
        let subData2 = subViewJSON(rootID: 300, childIDs: [301])
        _ = try windowModel.loadSubViewDescription(from: subData2, format: "json", parentID: parentID)

        // Old models should be gone
        XCTAssertNil(windowModel.viewModels[200], "Old root sub-view model should be removed")
        XCTAssertNil(windowModel.viewModels[201], "Old child model should be removed")
        XCTAssertNil(windowModel.viewModels[202], "Old child model should be removed")

        // New models should be present
        XCTAssertNotNil(windowModel.viewModels[300], "New root sub-view model should be present")
        XCTAssertNotNil(windowModel.viewModels[301], "New child model should be present")

        // Ownership tracking updated
        XCTAssertEqual(windowModel.loadedSubViewIDs[parentID], Set([300, 301]))
    }

    func testIDReuseAcrossSwaps() throws {
        let windowModel = try loadRootWithLoadableView()
        let parentID = 100

        // First load with IDs 1001, 1002
        let subData1 = subViewJSON(rootID: 1001, childIDs: [1002])
        _ = try windowModel.loadSubViewDescription(from: subData1, format: "json", parentID: parentID)
        let oldViewModel = windowModel.viewModels[1001]
        XCTAssertNotNil(oldViewModel)

        // Replace reusing the same IDs — should not conflict
        let subData2 = subViewJSON(rootID: 1001, childIDs: [1002])
        _ = try windowModel.loadSubViewDescription(from: subData2, format: "json", parentID: parentID)

        // New ViewModels should be different instances
        let newViewModel = windowModel.viewModels[1001]
        XCTAssertNotNil(newViewModel)
        XCTAssertFalse(oldViewModel === newViewModel, "Reused IDs should get fresh ViewModel instances after swap")
    }

    func testNestedLoadableViewRecursiveCleanup() throws {
        let windowModel = try loadRootWithLoadableView()
        let parentA = 100

        // Parent A loads child B (which is itself a LoadableView parent)
        let subDataA = subViewJSON(rootID: 500, childIDs: [501])
        _ = try windowModel.loadSubViewDescription(from: subDataA, format: "json", parentID: parentA)

        // Simulate child B (id=500) acting as a nested LoadableView that loaded its own children
        let parentB = 500
        let subDataB = subViewJSON(rootID: 600, childIDs: [601, 602])
        _ = try windowModel.loadSubViewDescription(from: subDataB, format: "json", parentID: parentB)

        // Verify nested state
        XCTAssertNotNil(windowModel.viewModels[600])
        XCTAssertNotNil(windowModel.viewModels[601])
        XCTAssertNotNil(windowModel.loadedSubViewIDs[parentB])

        // Now replace parent A — should recursively remove B's children too
        let subDataA2 = subViewJSON(rootID: 700, childIDs: [701])
        _ = try windowModel.loadSubViewDescription(from: subDataA2, format: "json", parentID: parentA)

        // All of A's old direct children and B's nested children should be gone
        XCTAssertNil(windowModel.viewModels[500], "Direct child of A should be removed")
        XCTAssertNil(windowModel.viewModels[501], "Direct child of A should be removed")
        XCTAssertNil(windowModel.viewModels[600], "Nested child of B should be removed")
        XCTAssertNil(windowModel.viewModels[601], "Nested child of B should be removed")
        XCTAssertNil(windowModel.viewModels[602], "Nested child of B should be removed")

        // B's ownership entry should also be cleaned up
        XCTAssertNil(windowModel.loadedSubViewIDs[parentB], "Nested parent's tracking should be removed")

        // New content should be present
        XCTAssertNotNil(windowModel.viewModels[700])
        XCTAssertNotNil(windowModel.viewModels[701])
    }

    func testRemovingTheLoadableViewRemovesTheContentItLoaded() throws {
        let windowModel = try loadRootWithLoadableView()
        _ = try windowModel.loadSubViewDescription(from: subViewJSON(rootID: 200, childIDs: [201]), format: "json", parentID: 100)

        try ActionUIModel.shared.removeElement(windowUUID: windowUUID, viewID: 100)

        XCTAssertNil(windowModel.viewModels[200], "Loaded content goes with its LoadableView")
        XCTAssertNil(windowModel.viewModels[201], "Loaded content goes with its LoadableView")
        XCTAssertNil(windowModel.loadedSubViewIDs[100])
        XCTAssertEqual(ActionUIModel.shared.getElementInfo(windowUUID: windowUUID), [1: "VStack"])
    }

    func testFullWindowReloadClearsTracking() throws {
        let windowModel = try loadRootWithLoadableView()
        let parentID = 100

        // Load a sub-view with parentID tracking
        let subData = subViewJSON(rootID: 200, childIDs: [201])
        _ = try windowModel.loadSubViewDescription(from: subData, format: "json", parentID: parentID)
        XCTAssertFalse(windowModel.loadedSubViewIDs.isEmpty, "Should have tracking entries")

        // Full window reload
        let rootJSON = """
        { "id": 1, "type": "Text", "properties": { "text": "fresh" } }
        """
        _ = try windowModel.loadDescription(from: rootJSON.data(using: .utf8)!, format: "json")

        XCTAssertTrue(windowModel.loadedSubViewIDs.isEmpty, "Full reload should clear all sub-view tracking")
    }

    func testParentIDZeroDoesNotTrack() throws {
        let windowModel = try loadRootWithLoadableView()

        // Load sub-view with default parentID=0 (backward-compatible path)
        let subData = subViewJSON(rootID: 200, childIDs: [201])
        _ = try windowModel.loadSubViewDescription(from: subData, format: "json")

        // No ownership tracking for parentID 0
        XCTAssertNil(windowModel.loadedSubViewIDs[0], "parentID 0 should not create tracking entries")

        // ViewModels should still be populated
        XCTAssertNotNil(windowModel.viewModels[200])
        XCTAssertNotNil(windowModel.viewModels[201])
    }

    func testRootViewModelsPreservedDuringSubViewReplace() throws {
        let windowModel = try loadRootWithLoadableView()
        let parentID = 100

        // Root viewModels (id 1 and 100) should exist
        XCTAssertNotNil(windowModel.viewModels[1], "Root VStack model should exist")
        XCTAssertNotNil(windowModel.viewModels[100], "LoadableView model should exist")

        // Load and replace sub-views
        let subData1 = subViewJSON(rootID: 200, childIDs: [201])
        _ = try windowModel.loadSubViewDescription(from: subData1, format: "json", parentID: parentID)
        let subData2 = subViewJSON(rootID: 300, childIDs: [301])
        _ = try windowModel.loadSubViewDescription(from: subData2, format: "json", parentID: parentID)

        // Root viewModels should be untouched
        XCTAssertNotNil(windowModel.viewModels[1], "Root VStack model should be preserved after sub-view swap")
        XCTAssertNotNil(windowModel.viewModels[100], "LoadableView model should be preserved after sub-view swap")
    }

    // MARK: - viewDidLoadActionID tests

    /// Helper: loads a root window with a LoadableView that has viewDidLoadActionID set.
    private func loadRootWithViewDidLoadAction() throws -> WindowModel {
        let rootJSON = """
        {
            "id": 1,
            "type": "VStack",
            "properties": {},
            "children": [
                { "id": 100, "type": "LoadableView", "properties": { "filePath": "/tmp/panel.json", "viewDidLoadActionID": "params.loaded" } }
            ]
        }
        """
        let data = rootJSON.data(using: .utf8)!
        _ = try ActionUIModel.shared.loadDescription(from: data, format: "json", windowUUID: windowUUID)
        return ActionUIModel.shared.windowModels[windowUUID]!
    }

    /// The viewDidLoad tracking FileLoadableView and RemoteLoadableView use, one per test.
    private let viewDidLoad = ActionUIDocumentLoader.ViewDidLoad()

    /// Fires viewDidLoad as FileLoadableView/RemoteLoadableView do after a load, without
    /// instantiating SwiftUI views. An empty actionID stands for a LoadableView without one.
    private func simulateFireViewDidLoad(parentID: Int, source: String, actionID: String) {
        viewDidLoad.fire(source: source, windowUUID: windowUUID, parentID: parentID,
                         actionID: actionID.isEmpty ? nil : actionID)
    }

    func testViewDidLoadActionIDPropertyIsStored() throws {
        let windowModel = try loadRootWithViewDidLoadAction()
        let viewModel = windowModel.viewModels[100]!
        XCTAssertEqual(viewModel.properties["viewDidLoadActionID"] as? String, "params.loaded",
                       "viewDidLoadActionID should be preserved in the properties")
    }

    func testViewDidLoadFiresOnFirstLoad() throws {
        let windowModel = try loadRootWithViewDidLoadAction()
        let parentID = 100

        // Load sub-view content
        let subData = subViewJSON(rootID: 200, childIDs: [201])
        _ = try windowModel.loadSubViewDescription(from: subData, format: "json", parentID: parentID)

        // Track action handler calls
        var firedActions: [(String, Int)] = []
        ActionUIModel.shared.setDefaultActionHandler { actionID, _, viewID, _, _ in
            firedActions.append((actionID, viewID))
        }

        // Simulate fireViewDidLoad
        simulateFireViewDidLoad(parentID: parentID, source: "file:///tmp/panel.json", actionID: "params.loaded")

        XCTAssertEqual(firedActions.count, 1, "Action should fire once")
        XCTAssertEqual(firedActions[0].0, "params.loaded", "Action ID should match")
        XCTAssertEqual(firedActions[0].1, parentID, "View ID should be the LoadableView's ID")
    }

    func testViewDidLoadDoesNotReFireForSameSource() throws {
        let windowModel = try loadRootWithViewDidLoadAction()
        let parentID = 100

        let subData = subViewJSON(rootID: 200, childIDs: [201])
        _ = try windowModel.loadSubViewDescription(from: subData, format: "json", parentID: parentID)

        var fireCount = 0
        ActionUIModel.shared.setDefaultActionHandler { _, _, _, _, _ in
            fireCount += 1
        }

        // First call should fire
        simulateFireViewDidLoad(parentID: parentID, source: "file:///tmp/panel.json", actionID: "params.loaded")
        XCTAssertEqual(fireCount, 1, "Should fire on first call")

        // Second call with same source should not fire (simulates SwiftUI body rebuild)
        simulateFireViewDidLoad(parentID: parentID, source: "file:///tmp/panel.json", actionID: "params.loaded")
        XCTAssertEqual(fireCount, 1, "Should not re-fire for the same source")
    }

    func testViewDidLoadFiresAgainForNewSource() throws {
        let windowModel = try loadRootWithViewDidLoadAction()
        let parentID = 100

        var firedSources: [String] = []
        ActionUIModel.shared.setDefaultActionHandler { actionID, _, _, _, _ in
            firedSources.append(actionID)
        }

        // First source
        let subData1 = subViewJSON(rootID: 200, childIDs: [201])
        _ = try windowModel.loadSubViewDescription(from: subData1, format: "json", parentID: parentID)
        simulateFireViewDidLoad(parentID: parentID, source: "file:///tmp/brightness.json", actionID: "params.loaded")

        // Replace with new source
        let subData2 = subViewJSON(rootID: 300, childIDs: [301])
        _ = try windowModel.loadSubViewDescription(from: subData2, format: "json", parentID: parentID)
        simulateFireViewDidLoad(parentID: parentID, source: "file:///tmp/contrast.json", actionID: "params.loaded")

        XCTAssertEqual(firedSources.count, 2, "Should fire for each new source")
    }

    func testViewDidLoadNotFiredWithoutActionID() throws {
        // Use the helper without viewDidLoadActionID
        let windowModel = try loadRootWithLoadableView()
        let parentID = 100

        let subData = subViewJSON(rootID: 200, childIDs: [201])
        _ = try windowModel.loadSubViewDescription(from: subData, format: "json", parentID: parentID)

        var fireCount = 0
        ActionUIModel.shared.setDefaultActionHandler { _, _, _, _, _ in
            fireCount += 1
        }

        // Empty actionID should not fire (mirrors nil viewDidLoadActionID in real code)
        simulateFireViewDidLoad(parentID: parentID, source: "file:///tmp/panel.json", actionID: "")
        XCTAssertEqual(fireCount, 0, "Should not fire when actionID is empty")
    }

    func testFullReloadClearsViewModels() throws {
        let windowModel = try loadRootWithViewDidLoadAction()
        let parentID = 100

        let subData = subViewJSON(rootID: 200, childIDs: [201])
        _ = try windowModel.loadSubViewDescription(from: subData, format: "json", parentID: parentID)

        var fireCount = 0
        ActionUIModel.shared.setDefaultActionHandler { _, _, _, _, _ in
            fireCount += 1
        }

        simulateFireViewDidLoad(parentID: parentID, source: "file:///tmp/panel.json", actionID: "params.loaded")
        XCTAssertEqual(fireCount, 1)

        // Full window reload should clear all ViewModels
        let rootJSON = """
        { "id": 1, "type": "Text", "properties": { "text": "fresh" } }
        """
        _ = try windowModel.loadDescription(from: rootJSON.data(using: .utf8)!, format: "json")

        XCTAssertNil(windowModel.viewModels[parentID], "Old LoadableView ViewModel should be gone after full reload")
    }

    func testALessTrustedLinkOpensOnlyWebAndMailAddresses() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("loadable-links-\(UUID().uuidString)")
        let resources = folder.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer {
            ActionUIConfiguration.updateForTesting { $0.resourceFolder = nil }
            try? FileManager.default.removeItem(at: folder)
        }
        ActionUIConfiguration.updateForTesting { $0.resourceFolder = resources.path }
        let inside = resources.appendingPathComponent("Root.json")
        let outside = folder.appendingPathComponent("Other.json")
        try Data(#"{"id": 5, "type": "Link", "properties": {"title": "In", "url": "file:///etc/hosts"}}"#.utf8).write(to: inside)
        try Data(#"{"id": 6, "type": "Link", "properties": {"title": "Out", "url": "file:///etc/hosts"}}"#.utf8).write(to: outside)
        let other = UUID().uuidString
        _ = FileLoadableView(fileURL: inside, windowUUID: windowUUID, isContentView: true, logger: logger)
        _ = FileLoadableView(fileURL: outside, windowUUID: other, isContentView: true, logger: ConsoleLogger(maxLevel: .error))
        let file = URL(string: "file:///etc/hosts")!
        XCTAssertTrue(ActionUIRegistry.opensLink(file, windowUUID: windowUUID, viewID: 5), "trusted content opens any link")
        XCTAssertFalse(ActionUIRegistry.opensLink(file, windowUUID: other, viewID: 6), "less trusted: not a local file")
        XCTAssertTrue(ActionUIRegistry.opensLink(URL(string: "https://example.com")!, windowUUID: other, viewID: 6))
        XCTAssertTrue(ActionUIRegistry.opensLink(URL(string: "mailto:a@example.com")!, windowUUID: other, viewID: 6))
    }

    func testANameIsFoundInTheHostsResourceFolderBeforeTheBundle() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("loadable-view-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            ActionUIConfiguration.updateForTesting { $0.resourceFolder = nil }
            try? FileManager.default.removeItem(at: folder)
        }
        let file = folder.appendingPathComponent("Panel.json")
        try Data("{}".utf8).write(to: file)
        XCTAssertNil(LoadableView.resourceURL("Panel", "json"))
        ActionUIConfiguration.updateForTesting { $0.resourceFolder = folder.path }
        XCTAssertEqual(LoadableView.resourceURL("Panel", "json")?.path, file.path)
        XCTAssertNil(LoadableView.resourceURL("Panel", "plist"))
        let source = ActionUIDocumentLoader.source(for: "Panel", bundleURL: LoadableView.resourceURL, logger: logger)
        XCTAssertEqual(try source.get(), .file(URL(fileURLWithPath: file.path)), "a name without an extension finds Panel.json")
    }

    func testAFileInTheHostsResourceFolderIsTrustedAndOneElsewhereIsNot() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("loadable-origin-\(UUID().uuidString)")
        let resources = folder.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer {
            ActionUIConfiguration.updateForTesting { $0.resourceFolder = nil }
            try? FileManager.default.removeItem(at: folder)
        }
        ActionUIConfiguration.updateForTesting { $0.resourceFolder = resources.path }
        let inside = resources.appendingPathComponent("Root.json")
        let outside = folder.appendingPathComponent("Other.json")
        try Data(#"{"id": 5, "type": "Text", "properties": {"text": "In"}}"#.utf8).write(to: inside)
        try Data(#"{"id": 6, "type": "Text", "properties": {"text": "Out"}}"#.utf8).write(to: outside)
        // The SwiftUI renderer's resource folders: the host's, then the bundle's.
        _ = FileLoadableView(fileURL: inside, windowUUID: windowUUID, isContentView: true, logger: logger)
        let trusted = try XCTUnwrap(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 5))
        XCTAssertEqual(trusted.trust, .trusted)
        XCTAssertNil(trusted.parentID, "a window's root")
        guard case .resource = trusted.source else { return XCTFail("\(trusted)") }
        _ = FileLoadableView(fileURL: outside, windowUUID: windowUUID, isContentView: true, logger: logger)
        XCTAssertEqual(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 6)?.trust, .lessTrusted)
        _ = FileLoadableView(data: Data(#"{"id": 7, "type": "Text", "properties": {}}"#.utf8), sourceName: "memory",
                             windowUUID: windowUUID, isContentView: true, logger: logger)
        XCTAssertTrue(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: 7) === JSONContentOrigin.host, "data the host holds")
    }

    func testRemoteJSONIsCappedInSizeAndTime() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubJSONProtocol.self]
        let session = URLSession(configuration: configuration)
        func fetch(_ path: String, timeout: Double = 10) async throws -> Data {
            try await RemoteJSONFetch.data(for: URLRequest(url: URL(string: "https://stub.invalid" + path)!), limit: 1000,
                                               timeout: timeout, session: session).data
        }
        let exact = try await fetch("/exact")
        XCTAssertEqual(exact.count, 1000, "exactly the cap loads")
        do {
            _ = try await fetch("/big")
            XCTFail("one byte over the cap")
        } catch {
            XCTAssertEqual("\(error)", "the ActionUI JSON is larger than 0 MB")
        }
        do {
            _ = try await fetch("/told")
            XCTFail("a Content-Length over the cap is refused before the body")
        } catch {
            XCTAssertTrue("\(error)".hasPrefix("the ActionUI JSON is larger"), "\(error)")
        }
        let start = Date()
        do {
            _ = try await fetch("/stall", timeout: 0.3)
            XCTFail("a server that never sends the body")
        } catch {
            XCTAssertEqual("\(error)", "loading it took longer than 0 seconds")
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
        XCTAssertEqual(WindowModel.maximumJSONSize, 16 * 1024 * 1024, "RemoteLoadableView fetches up to the document cap")
    }

    func testRemoteJSONGivesTheAddressItFinallyCameFrom() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubJSONProtocol.self]
        let session = URLSession(configuration: configuration)
        let direct = try await RemoteJSONFetch.data(for: URLRequest(url: URL(string: "https://stub.invalid/exact")!), limit: 1000,
                                                    session: session)
        XCTAssertEqual(direct.finalURL, URL(string: "https://stub.invalid/exact"))
        let moved = try await RemoteJSONFetch.data(for: URLRequest(url: URL(string: "https://stub.invalid/moved")!), limit: 1000,
                                                   session: session)
        XCTAssertEqual(moved.finalURL, URL(string: "https://elsewhere.invalid/exact"), "the redirect's target, not the address asked for")
        XCTAssertEqual(moved.data.count, 1000)
    }
}
