// Core/ActionAndLoadCapabilityTests.swift
/*
 Tests that the trust policy is asked before an action fires (ActionUICapability.action), with the
 origin of the element that fires it, and before a LoadableView loads a source
 (ActionUICapability.load), with the origin of the content the LoadableView is in: a host policy
 that refuses them has its way. The default policy allows both.
*/

import XCTest
@testable import ActionUI

/// Refuses actions from content that is not trusted, and loads of remote sources; records what it
/// was asked.
private final class StrictPolicy: ActionUITrustPolicy, @unchecked Sendable {
    var asked: [(ActionUICapability, JSONContentOrigin)] = []

    func allows(_ capability: ActionUICapability, for origin: JSONContentOrigin) -> Bool {
        asked.append((capability, origin))
        switch capability {
        case .action: return origin.trust == .trusted
        case .load(.remote): return false
        default: return DefaultTrustPolicy.allowsByDefault(capability, for: origin)
        }
    }
}

/// Refuses loads from one host.
private final class RefusesHost: ActionUITrustPolicy, @unchecked Sendable {
    let host: String
    init(host: String) { self.host = host }

    func allows(_ capability: ActionUICapability, for origin: JSONContentOrigin) -> Bool {
        if case .load(.remote(let url)) = capability, url.host == host { return false }
        return DefaultTrustPolicy.allowsByDefault(capability, for: origin)
    }
}

// Records messages without failing the test, for a refusal logged on purpose.
private final class RecordingLogger: ActionUILogger, @unchecked Sendable {
    private(set) var warnings: [String] = []
    func log(_ message: String, _ level: LoggerLevel) {
        if level == .warning { warnings.append(message) }
    }
}

@MainActor
final class ActionAndLoadCapabilityTests: XCTestCase {
    private var windowUUID: String!
    private var fired: [Int] = []
    private var recording: RecordingLogger!

    override func setUp() async throws {
        // No super.setUp(): see DocumentLoaderTests.
        recording = RecordingLogger()
        ActionUIModel.shared.logger = recording
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
        fired = []
        ActionUIModel.shared.registerActionHandler(for: "test.run") { [weak self] _, _, viewID, _, _ in
            self?.fired.append(viewID)
        }
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
    }

    private let root = Data(#"{"id": 1, "type": "VStack", "children": [{"id": 100, "type": "LoadableView"}]}"#.utf8)
    private let panel = Data(#"{"id": 200, "type": "Button", "properties": {"title": "Run", "actionID": "test.run"}}"#.utf8)

    /// The window's root from the host, and less-trusted remote content in LoadableView 100.
    private func loadWindow() async throws {
        _ = try ActionUIDocumentLoader.load(data: root, format: "json", windowUUID: windowUUID, isContentView: true, parentID: 0, source: nil)
        let data = panel
        _ = try await ActionUIDocumentLoader.loadRemote(url: URL(string: "https://example.com/panel.json")!, windowUUID: windowUUID,
                                                        isContentView: false, parentID: 100, logger: recording) { url in (data, url) }
    }

    func testARefusalForContentOfUnknownOriginIsLoggedOncePerWindow() {
        let model = ActionUIModel.shared
        let file = ActionUICapability.openLink(URL(string: "file:///etc/hosts")!)
        XCTAssertFalse(model.allowsLoggingOnceForUnknownOrigin(file, what: "opening the link", windowUUID: windowUUID))
        XCTAssertFalse(model.allowsLoggingOnceForUnknownOrigin(file, what: "opening the link", windowUUID: windowUUID))
        XCTAssertEqual(recording.warnings.filter { $0.contains("origin cannot be told") }.count, 1, "\(recording.warnings)")
        XCTAssertTrue(model.allowsLoggingOnceForUnknownOrigin(.openLink(URL(string: "https://example.com")!), what: "opening the link",
                                                              windowUUID: windowUUID), "a web link is allowed for less-trusted content")
        model.removeWindow(windowUUID)
        XCTAssertFalse(model.allowsLoggingOnceForUnknownOrigin(file, what: "opening the link", windowUUID: windowUUID))
        XCTAssertEqual(recording.warnings.filter { $0.contains("origin cannot be told") }.count, 2, "logged again once the window is gone")
    }

    func testTheDefaultPolicyLetsEveryActionFire() async throws {
        try await loadWindow()
        for viewID in [1, 200, 0, 999] {
            ActionUIModel.shared.actionHandler("test.run", windowUUID: windowUUID, viewID: viewID, viewPartID: 0)
        }
        XCTAssertEqual(fired, [1, 200, 0, 999])
    }

    func testAPolicyThatRefusesAnActionHasItsWay() async throws {
        try await loadWindow()
        let policy = StrictPolicy()
        ActionUIModel.shared.trustPolicy = policy
        ActionUIModel.shared.actionHandler("test.run", windowUUID: windowUUID, viewID: 200, viewPartID: 0)
        ActionUIModel.shared.actionHandler("test.run", windowUUID: windowUUID, viewID: 1, viewPartID: 0)
        ActionUIModel.shared.actionHandler("test.run", windowUUID: windowUUID, viewID: 0, viewPartID: 0)
        ActionUIModel.shared.actionHandler("test.run", windowUUID: windowUUID, viewID: 999, viewPartID: 0)
        ActionUIModel.shared.actionHandler("test.run", windowUUID: windowUUID, viewID: 999, viewPartID: 0, origin: .host)
        XCTAssertEqual(fired, [1, 0, 999], "the host's element, no element (0), and an item the host names as its own")
        XCTAssertEqual(recording.warnings.filter { $0.contains("the trust policy refuses it") }.count, 2,
                       "the remote element and the element with no view model, each logged")
        let actions = policy.asked.filter { if case .action("test.run") = $0.0 { return true }; return false }
        XCTAssertEqual(actions.map(\.1.trust), [.lessTrusted, .trusted, .trusted, .lessTrusted, .trusted])
        XCTAssertEqual(actions.first?.1.source, .remote(URL(string: "https://example.com/panel.json")!), "asked with the element's origin")
    }

    func testContentWithElementIDZeroIsNotTakenForTheHost() async throws {
        _ = try ActionUIDocumentLoader.load(data: root, format: "json", windowUUID: windowUUID, isContentView: true, parentID: 0, source: nil)
        let data = Data(#"{"id": 0, "type": "Button", "properties": {"title": "Run", "actionID": "test.run"}}"#.utf8)
        _ = try await ActionUIDocumentLoader.loadRemote(url: URL(string: "https://example.com/zero.json")!, windowUUID: windowUUID,
                                                        isContentView: false, parentID: 100, logger: recording) { url in (data, url) }
        ActionUIModel.shared.trustPolicy = StrictPolicy()
        // What a tap on the remote Button fires (Button.userTapped passes its own id, 0).
        ActionUIModel.shared.actionHandler("test.run", windowUUID: windowUUID, viewID: 0, viewPartID: 0)
        XCTAssertEqual(fired, [], "the remote element 0 is less trusted, not the host's")
        // The host's own toast and dialog buttons still fire.
        ActionUIModel.shared.actionHandler("test.run", windowUUID: windowUUID, viewID: 0, viewPartID: 0, origin: .host)
        XCTAssertEqual(fired, [0])
    }

    func testAPolicyIsAskedAgainAboutTheAddressARedirectReaches() async throws {
        _ = try ActionUIDocumentLoader.load(data: root, format: "json", windowUUID: windowUUID, isContentView: true, parentID: 0, source: nil)
        ActionUIModel.shared.trustPolicy = RefusesHost(host: "elsewhere.example.com")
        let data = panel
        let asked = URL(string: "https://example.com/panel.json")!
        XCTAssertNil(ActionUIDocumentLoader.loadRefusal(.remote(asked), windowUUID: windowUUID, parentID: 100, logger: recording))
        do {
            _ = try await ActionUIDocumentLoader.loadRemote(url: asked, windowUUID: windowUUID, isContentView: false, parentID: 100,
                                                            logger: recording) { _ in (data, URL(string: "https://elsewhere.example.com/panel.json")!) }
            XCTFail("the redirect's address is refused")
        } catch {
            XCTAssertTrue("\(error)".contains("the trust policy refuses it"), "\(error)")
        }
        XCTAssertNil(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[200], "nothing of it is loaded")
    }

    func testATemplateRowsActionIsJudgedByItsContainerNotTheIDItCarries() async throws {
        try await loadWindow()
        let policy = StrictPolicy()
        ActionUIModel.shared.trustPolicy = policy
        // A template element in the remote content's row (container 200) that copied the host's id 1,
        // and one in a row of the host's own content (container 1) with an id nothing has.
        let borrowed = ViewModel()
        borrowed.templateContext = TemplateContext(parentID: 200, rowIndex: 0, row: [])
        let own = ViewModel()
        own.templateContext = TemplateContext(parentID: 1, rowIndex: 0, row: [])
        ActionUIModel.shared.actionHandler("test.run", windowUUID: windowUUID, viewID: 1, viewPartID: 0, model: borrowed)
        ActionUIModel.shared.actionHandler("test.run", windowUUID: windowUUID, viewID: 77, viewPartID: 0, model: own)
        XCTAssertEqual(fired, [77], "the borrowed id does not make remote content's action the host's; the host's row fires")
        // Outside a template row, the element's own origin, as before.
        ActionUIModel.shared.actionHandler("test.run", windowUUID: windowUUID, viewID: 1, viewPartID: 0, model: ViewModel())
        XCTAssertEqual(fired, [77, 1])
    }

    // readsLocalFile(_:windowUUID:viewID:model:), the add-ons' question: judged as the action above.
    func testATemplateRowsFileReadIsJudgedByItsContainerNotTheIDItCarries() async throws {
        try await loadWindow()
        let path = "/nonexistent-\(UUID().uuidString)/notes.txt"
        let borrowed = ViewModel()
        borrowed.templateContext = TemplateContext(parentID: 200, rowIndex: 0, row: [])
        let own = ViewModel()
        own.templateContext = TemplateContext(parentID: 1, rowIndex: 0, row: [])
        XCTAssertFalse(ActionUIModel.shared.readsLocalFile(path, windowUUID: windowUUID, viewID: 1, model: borrowed),
                       "the borrowed id does not make remote content's read the host's")
        XCTAssertTrue(ActionUIModel.shared.readsLocalFile(path, windowUUID: windowUUID, viewID: 77, model: own), "the host's row reads")
        XCTAssertTrue(ActionUIModel.shared.readsLocalFile(path, windowUUID: windowUUID, viewID: 1, model: ViewModel()))
        XCTAssertFalse(ActionUIModel.shared.readsLocalFile(path, windowUUID: windowUUID, viewID: 200, model: ViewModel()))
        XCTAssertEqual(recording.warnings.filter { $0.hasPrefix("Not reading \(path)") }.count, 2, "each refusal is logged")
    }

    func testAPolicyThatRefusesALoadHasItsWay() throws {
        _ = try ActionUIDocumentLoader.load(data: root, format: "json", windowUUID: windowUUID, isContentView: true, parentID: 0, source: nil)
        XCTAssertNil(ActionUIDocumentLoader.loadRefusal(.remote(URL(string: "https://example.com/a.json")!), windowUUID: windowUUID,
                                                        parentID: 100, logger: recording), "the default policy allows it")
        let policy = StrictPolicy()
        ActionUIModel.shared.trustPolicy = policy
        XCTAssertEqual(ActionUIDocumentLoader.loadRefusal(.remote(URL(string: "https://example.com/a.json")!), windowUUID: windowUUID,
                                                          parentID: 100, logger: recording), "the trust policy refuses it")
        XCTAssertNil(ActionUIDocumentLoader.loadRefusal(.file(URL(fileURLWithPath: "/tmp/a.json")), windowUUID: windowUUID,
                                                        parentID: 100, logger: recording), "a file is not refused by this policy")
        let loads = policy.asked.filter { if case .load = $0.0 { return true }; return false }
        XCTAssertEqual(loads.count, 2)
        XCTAssertEqual(loads.first?.1.trust, .trusted, "asked with the origin of the content the LoadableView is in: the host's")
        if case .load(let source) = loads.last?.0 {
            XCTAssertEqual(source, .file("/tmp/a.json".resolvingSymlinksForTest), "the source as its content would be classified")
        } else {
            XCTFail("a load capability")
        }
        XCTAssertTrue(recording.warnings.contains { $0.hasPrefix("LoadableView 100: not loading https://example.com/a.json") })
    }
}

private extension String {
    /// The path as the loader classifies it: symbolic links resolved (/tmp is /private/tmp on macOS).
    var resolvingSymlinksForTest: String {
        URL(fileURLWithPath: self).resolvingSymlinksInPath().standardizedFileURL.path
    }
}
