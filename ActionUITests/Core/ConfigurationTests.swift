// Core/ConfigurationTests.swift
/*
 Tests for ActionUIConfiguration: the defaults, the JSON keys (each optional, the rest kept), a
 change refused whole for an unknown key, a wrong type, a value out of range or a trusted origin
 that is not an https origin, the configuration fixed by the first window's load (the resource
 folder setter too), the limits read from it, and trusted origins: trusted only by the address the
 ActionUI JSON finally came from and only inside trusted content.
*/

import XCTest
import Dispatch
@testable import ActionUI

// Records error messages without failing the test, for a refusal logged on purpose.
private final class RecordingLogger: ActionUILogger, @unchecked Sendable {
    private(set) var errors: [String] = []
    func log(_ message: String, _ level: LoggerLevel) {
        if level == .error { errors.append(message) }
    }
}

@MainActor
final class ConfigurationTests: XCTestCase {
    private var windowUUID: String!

    override func setUp() async throws {
        // No super.setUp(): see DocumentLoaderTests.
        ActionUIModel.shared.logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        ActionUIConfiguration.replaceForTesting()
        ActionUIConfiguration.setFixedForTesting(false)
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        ActionUIConfiguration.replaceForTesting()
        ActionUIConfiguration.setFixedForTesting(true)
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
    }

    private let root = Data(#"{"id": 1, "type": "VStack", "children": [{"id": 100, "type": "LoadableView"}]}"#.utf8)
    private let panel = Data(#"{"id": 200, "type": "Text", "properties": {"text": "Panel"}}"#.utf8)

    // MARK: Defaults and JSON

    func testTheDefaults() {
        let configuration = ActionUIConfiguration.current
        XCTAssertEqual(configuration.limits.maximumJSONSize, 16 * 1024 * 1024)
        XCTAssertEqual(configuration.limits.loadBudget, ActionUILoadBudget(loads: 256, seconds: 60))
        XCTAssertEqual(configuration.limits.maximumNestingDepth, 16)
        XCTAssertEqual(configuration.limits.maximumDownloadTime, 120)
        XCTAssertEqual(configuration.trust.trustedOrigins, [])
        XCTAssertNil(configuration.resourceFolder)
        XCTAssertEqual(configuration, ActionUIConfiguration())
    }

    func testJSONChangesOnlyTheKeysItNames() throws {
        try ActionUIConfiguration.set(json: #"{"limits": {"maximumJSONSize": 67108864, "loadBudget": {"seconds": 30}}}"#)
        try ActionUIConfiguration.set(json: #"{"trust": {"trustedOrigins": ["https://ui.example.com", "https://cdn.example.com:8443/"]}, "resourceFolder": "/opt/app"}"#)
        let configuration = ActionUIConfiguration.current
        XCTAssertEqual(configuration.limits.maximumJSONSize, 64 * 1024 * 1024, "a host may raise a limit")
        XCTAssertEqual(configuration.limits.loadBudget, ActionUILoadBudget(loads: 256, seconds: 30), "loads kept")
        XCTAssertEqual(configuration.limits.maximumNestingDepth, 16)
        XCTAssertEqual(configuration.trust.trustedOrigins.map(\.absoluteString), ["https://ui.example.com", "https://cdn.example.com:8443/"])
        XCTAssertEqual(configuration.resourceFolder, "/opt/app")
        XCTAssertEqual(ActionUIResourceFolder.path, "/opt/app", "the resource folder is the configuration's")
        try ActionUIConfiguration.set(json: #"{"resourceFolder": null}"#)
        XCTAssertNil(ActionUIConfiguration.current.resourceFolder)
        try ActionUIConfiguration.set(json: #"{"limits": {"maximumDownloadTime": 600}}"#)
        XCTAssertEqual(ActionUIConfiguration.current.limits.maximumDownloadTime, 600)
        try ActionUIConfiguration.set(json: #"{"limits": {"maximumDownloadTime": 0.5}}"#)
        XCTAssertEqual(ActionUIConfiguration.current.limits.maximumDownloadTime, 0.5)
        try ActionUIConfiguration.set(json: #"{"limits": {"maximumDownloadTime": null}}"#)
        XCTAssertNil(ActionUIConfiguration.current.limits.maximumDownloadTime, "null removes the time limit")
        try ActionUIConfiguration.set(json: "{}")
        XCTAssertEqual(ActionUIConfiguration.current.limits.maximumJSONSize, 64 * 1024 * 1024, "an empty change keeps everything")
    }

    func testABadChangeIsRefusedWhole() throws {
        let refused: [(String, String)] = [
            (#"{"limits": {"maximumJSONSize": 1000}, "trustedOrigins": []}"#, "unknown configuration key trustedOrigins"),
            (#"{"limits": {"maximumJSONSize": 1000, "maxJSONSize": 5}}"#, "unknown configuration key limits.maxJSONSize"),
            (#"{"limits": {"loadBudget": {"loads": 3, "span": 1}}}"#, "unknown configuration key limits.loadBudget.span"),
            (#"{"limits": {"maximumJSONSize": "big"}}"#, "limits.maximumJSONSize must be a whole number"),
            (#"{"limits": {"maximumJSONSize": true}}"#, "limits.maximumJSONSize must be a whole number"),
            (#"{"limits": {"maximumJSONSize": 1.5}}"#, "limits.maximumJSONSize must be a whole number"),
            (#"{"limits": {"maximumJSONSize": 0}}"#, "limits.maximumJSONSize must be more than 0"),
            (#"{"limits": {"loadBudget": {"seconds": 0}}}"#, "limits.loadBudget.seconds must be a number more than 0"),
            (#"{"limits": {"maximumNestingDepth": -1}}"#, "limits.maximumNestingDepth must not be negative"),
            (#"{"limits": {"maximumDownloadTime": 0}}"#, "limits.maximumDownloadTime must be a number more than 0, or null for no limit"),
            (#"{"limits": {"maximumDownloadTime": -5}}"#, "limits.maximumDownloadTime must be a number more than 0, or null for no limit"),
            (#"{"limits": {"maximumDownloadTime": "slow"}}"#, "limits.maximumDownloadTime must be a number"),
            (#"{"limits": {"maximumDownloadTime": true}}"#, "limits.maximumDownloadTime must be a number"),
            (#"{"limits": []}"#, "limits must be an object"),
            (#"{"trust": {"trustedOrigins": "https://ui.example.com"}}"#, "trust.trustedOrigins must be an array of strings"),
            (#"{"trust": {"trustedOrigins": ["http://ui.example.com"]}}"#, "trust.trustedOrigins: http://ui.example.com is not an https address"),
            (#"{"trust": {"trustedOrigins": ["https://ui.example.com/app"]}}"#, "trust.trustedOrigins: https://ui.example.com/app has a path; an origin is the scheme, host and port only"),
            (#"{"trust": {"trustedOrigins": ["https://me@ui.example.com"]}}"#, "trust.trustedOrigins: https://me@ui.example.com has a user name or password"),
            (#"{"trust": {"trustedOrigins": ["https://ui.example.com/?a=1"]}}"#, "trust.trustedOrigins: https://ui.example.com/?a=1 has a query or fragment"),
            (#"{"trust": {"trustedOrigins": ["ui.example.com"]}}"#, "trust.trustedOrigins: ui.example.com is not an https address"),
            (#"{"resourceFolder": ""}"#, "resourceFolder must not be empty; null for none"),
            (#"{"resourceFolder": 3}"#, "resourceFolder must be a string or null"),
            (#"{"addOns": 3}"#, "addOns must be an object"),
            ("[]", "the configuration must be an object"),
        ]
        for (json, message) in refused {
            XCTAssertThrowsError(try ActionUIConfiguration.set(json: json), json) { error in
                XCTAssertEqual("\(error)", message, json)
            }
            XCTAssertEqual(ActionUIConfiguration.current, ActionUIConfiguration(), "nothing of \(json) applied")
        }
        XCTAssertThrowsError(try ActionUIConfiguration.set(json: "{limits")) { error in
            XCTAssertTrue("\(error)".hasPrefix("the configuration is not valid JSON"), "\(error)")
        }
        var bad = ActionUIConfiguration()
        bad.trust.trustedOrigins = [URL(string: "file:///etc")!]
        XCTAssertThrowsError(try ActionUIConfiguration.set(bad), "the Swift setter validates too")
        XCTAssertEqual(ActionUIConfiguration.current, ActionUIConfiguration())
    }

    func testTheJSONReadBackHasEveryKeyAndSetsTheSame() throws {
        let defaults = try XCTUnwrap(try ActionUIJSON.value(from: ActionUIConfiguration.current.json) as? [String: Any])
        XCTAssertEqual(Set(defaults.keys), ["limits", "trust", "resourceFolder", "addOns"])
        XCTAssertTrue(defaults["resourceFolder"] is ActionUIJSONNull)
        let limits = try XCTUnwrap(defaults["limits"] as? [String: Any])
        XCTAssertEqual(limits["maximumJSONSize"] as? Int, 16 * 1024 * 1024)
        XCTAssertEqual((limits["loadBudget"] as? [String: Any])?["loads"] as? Int, 256)
        XCTAssertEqual((limits["maximumDownloadTime"] as? NSNumber)?.doubleValue, 120)
        try ActionUIConfiguration.set(json: #"{"limits": {"loadBudget": {"seconds": 0.5}, "maximumDownloadTime": null}, "trust": {"trustedOrigins": ["https://ui.example.com"]}, "resourceFolder": "/opt/app", "addOns": {"Sample": {"on": true}}}"#)
        let changed = ActionUIConfiguration.current
        ActionUIConfiguration.replaceForTesting()
        try ActionUIConfiguration.set(json: changed.json)
        XCTAssertEqual(ActionUIConfiguration.current, changed, "its own JSON sets the same configuration")
    }

    func testAddOnSettingsRoundTrip() throws {
        try ActionUIConfiguration.set(json: #"{"addOns": {"Sample": {"mode": "fast", "level": 2}}}"#)
        let settings = try XCTUnwrap(ActionUIConfiguration.current.addOnSettings("Sample") as? [String: Any])
        XCTAssertEqual(settings["mode"] as? String, "fast")
        XCTAssertEqual(settings["level"] as? Int, 2)
        XCTAssertNil(ActionUIConfiguration.current.addOnSettings("Other"))
        try ActionUIConfiguration.update { try $0.setAddOnSettings("Other", ["on": true]) }
        XCTAssertEqual((ActionUIConfiguration.current.addOnSettings("Other") as? [String: Any])?["on"] as? Bool, true)
        try ActionUIConfiguration.set(json: #"{"addOns": {"Sample": null}}"#)
        XCTAssertNil(ActionUIConfiguration.current.addOnSettings("Sample"), "null removes a section")
        XCTAssertNotNil(ActionUIConfiguration.current.addOnSettings("Other"), "and keeps the others")
    }

    // MARK: Fixed after the first load

    func testTheFirstLoadFixesTheConfiguration() async throws {
        try ActionUIConfiguration.set(json: #"{"limits": {"maximumNestingDepth": 4}}"#)
        XCTAssertFalse(ActionUIConfiguration.isFixed)
        _ = try ActionUIDocumentLoader.load(data: root, format: "json", windowUUID: windowUUID, isContentView: true, parentID: 0, source: nil)
        XCTAssertTrue(ActionUIConfiguration.isFixed)
        for change in [{ try ActionUIConfiguration.set(json: #"{"limits": {"maximumNestingDepth": 8}}"#) },
                       { try ActionUIConfiguration.set(ActionUIConfiguration()) },
                       { try ActionUIConfiguration.update { $0.limits.maximumNestingDepth = 8 } }] {
            XCTAssertThrowsError(try change()) { error in
                XCTAssertEqual("\(error)", "the configuration is fixed once a window has loaded its ActionUI JSON; set it before")
            }
        }
        XCTAssertEqual(ActionUIConfiguration.current.limits.maximumNestingDepth, 4, "the setting from before the load stays")
        let recording = RecordingLogger()
        ActionUIModel.shared.logger = recording
        ActionUIResourceFolder.path = "/opt/late"
        XCTAssertNil(ActionUIResourceFolder.path, "the resource folder setter is refused too")
        // Logged from a main-actor task, since the setter may run on any thread.
        for _ in 0..<10 where recording.errors.isEmpty { await Task.yield() }
        XCTAssertEqual(recording.errors, ["The resource folder was not set to /opt/late: the configuration is fixed once a window has loaded its ActionUI JSON; set it before"])
    }

    func testUpdatesFromManyThreadsAtOnceAreAllKept() throws {
        // Each adds one to the depth; a change made from a value another thread replaced meanwhile
        // runs again, so none is lost.
        DispatchQueue.concurrentPerform(iterations: 200) { _ in
            try? ActionUIConfiguration.update { $0.limits.maximumNestingDepth += 1 }
        }
        XCTAssertEqual(ActionUIConfiguration.current.limits.maximumNestingDepth, 16 + 200)
    }

    // MARK: Limits read from it

    func testTheLimitsComeFromTheConfiguration() throws {
        try ActionUIConfiguration.set(json: #"{"limits": {"maximumJSONSize": 3000, "maximumNestingDepth": 2}}"#)
        XCTAssertEqual(WindowModel.maximumJSONSize, 3000)
        XCTAssertEqual(ActionUIDocumentLoader.maximumFileSize, 3000)
        XCTAssertNil(ActionUIDocumentLoader.nestingRefusal("c", inside: ["a"]))
        XCTAssertEqual(ActionUIDocumentLoader.nestingRefusal("c", inside: ["a", "b"]), "LoadableViews are nested more than 2 deep")
    }

    // MARK: Trusted origins

    func testATrustedOriginIsTrustedOnlyByItsExactOriginAndInsideTrustedContent() {
        let origins = [URL(string: "https://ui.example.com")!]
        func trust(_ address: String, inside parent: JSONContentOrigin? = nil) -> JSONContentOrigin.Trust {
            ActionUIDocumentLoader.origin(for: .remote(URL(string: address)!), inside: parent, parentID: nil,
                                          resourceFolders: [], trustedOrigins: origins).trust
        }
        XCTAssertEqual(trust("https://ui.example.com/app/main.json"), .trusted)
        XCTAssertEqual(trust("https://UI.Example.com:443/main.json"), .trusted, "case and the default port")
        XCTAssertEqual(trust("http://ui.example.com/main.json"), .lessTrusted, "plain http")
        XCTAssertEqual(trust("https://ui.example.com:8443/main.json"), .lessTrusted, "another port")
        XCTAssertEqual(trust("https://evil.ui.example.com/main.json"), .lessTrusted, "a subdomain")
        XCTAssertEqual(trust("https://ui.example.com.evil.net/main.json"), .lessTrusted)
        let remote = JSONContentOrigin(source: .remote(URL(string: "https://other.net/a.json")!), trust: .lessTrusted, parentID: nil)
        XCTAssertEqual(trust("https://ui.example.com/main.json", inside: remote), .lessTrusted, "named by less-trusted content")
        XCTAssertEqual(trust("https://ui.example.com/main.json", inside: .host), .trusted)
        XCTAssertEqual(ActionUIDocumentLoader.origin(for: .remote(URL(string: "https://ui.example.com/a.json")!), inside: nil, parentID: nil,
                                                     resourceFolders: []).trust, .lessTrusted, "no trusted origins by default")
    }

    func testARemoteLoadIsJudgedByWhereItFinallyCameFrom() async throws {
        try ActionUIConfiguration.set(json: #"{"trust": {"trustedOrigins": ["https://ui.example.com"]}}"#)
        let trusted = URL(string: "https://ui.example.com/root.json")!
        let elsewhere = URL(string: "https://cdn.other.net/root.json")!
        let data = root
        let logger = XCTestLogger(maxLevel: .verbose)

        // Redirected off the trusted server: less trusted, recorded with the address it came from.
        var element = try await ActionUIDocumentLoader.loadRemote(url: trusted, windowUUID: windowUUID, isContentView: true,
                                                                  parentID: 0, logger: logger) { _ in (data, elsewhere) }
        var origin = ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: element.id)
        XCTAssertEqual(origin?.trust, .lessTrusted)
        XCTAssertEqual(origin?.source, .remote(elsewhere))

        // Straight from it: trusted, with nothing refused.
        element = try await ActionUIDocumentLoader.loadRemote(url: trusted, windowUUID: windowUUID, isContentView: true,
                                                              parentID: 0, logger: logger) { url in (data, url) }
        origin = ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: element.id)
        XCTAssertEqual(origin?.trust, .trusted)
        XCTAssertEqual(origin?.source, .remote(trusted))
        XCTAssertTrue(ActionUIModel.shared.allows(.windowTitle, windowUUID: windowUUID, viewID: element.id))
        XCTAssertTrue(ActionUIModel.shared.allows(.presentModal, windowUUID: windowUUID, viewID: element.id))

        // A LoadableView in it that loads more from the server: trusted; from elsewhere: less trusted.
        let sub = try await ActionUIDocumentLoader.loadRemote(url: URL(string: "https://ui.example.com/panel.json")!, windowUUID: windowUUID,
                                                              isContentView: false, parentID: 100, logger: logger) { url in (self.panel, url) }
        XCTAssertEqual(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: sub.id)?.trust, .trusted)
        let other = try await ActionUIDocumentLoader.loadRemote(url: elsewhere, windowUUID: windowUUID,
                                                                isContentView: false, parentID: 100, logger: logger) { url in (self.panel, url) }
        XCTAssertEqual(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: other.id)?.trust, .lessTrusted)
    }

    func testATrustPolicySeesTheTrustedOriginAsItsDefault() async throws {
        final class Recorder: ActionUITrustPolicy, @unchecked Sendable {
            var defaults: [JSONContentOrigin.Trust] = []
            func trust(for source: JSONContentOrigin.Source, inside parent: JSONContentOrigin?, byDefault: JSONContentOrigin.Trust) -> JSONContentOrigin.Trust {
                defaults.append(byDefault)
                return .lessTrusted
            }
        }
        try ActionUIConfiguration.set(json: #"{"trust": {"trustedOrigins": ["https://ui.example.com"]}}"#)
        let recorder = Recorder()
        ActionUIModel.shared.trustPolicy = recorder
        let data = root
        let element = try await ActionUIDocumentLoader.loadRemote(url: URL(string: "https://ui.example.com/root.json")!, windowUUID: windowUUID,
                                                                  isContentView: true, parentID: 0, logger: XCTestLogger(maxLevel: .verbose)) { url in (data, url) }
        XCTAssertEqual(recorder.defaults, [.trusted])
        XCTAssertEqual(ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: element.id)?.trust, .lessTrusted, "the policy has the last word")
    }
}
