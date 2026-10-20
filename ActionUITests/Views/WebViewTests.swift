// Tests/Views/WebViewTests.swift
/*
 WebViewTests.swift

 Tests for the WebView component in the ActionUI component library.
 Verifies JSON decoding, Props reading, view construction, initialValue / initialStates,
 and programmatic value updates.

 Note: WebView requires iOS 26+ / macOS 26+. buildView returns a SwiftUI Label fallback on
 older OS versions. The internal WebViewContent struct (navigation commands, state sync) is
 exercised in integration; unit tests here focus on the static ActionUIViewConstruction surface.
*/

import XCTest
import SwiftUI
import WebKit
@testable import ActionUI

@MainActor
final class WebViewTests: XCTestCase {
    private var logger: XCTestLogger!
    private var consoleLogger: ConsoleLogger!
    private var windowUUID: String!

    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        consoleLogger = ConsoleLogger(maxLevel: .verbose)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIRegistry.shared.webViewImplementation = .native // restore default; it's global state
        ActionUIModel.resetForTesting()
        logger = nil
        consoleLogger = nil
        windowUUID = nil
        try await super.tearDown()
    }

    // MARK: - Props - valid input

    func testWebViewPropsValid() {
        let properties: [String: Any] = [
            "url": "https://www.swift.org",
            "customUserAgent": "MyApp/1.0",
            "backForwardNavigationGestures": true,
            "magnificationGestures": false,
            "linkPreviews": true,
            "navigationActionID": "nav.event",
            "padding": 10.0
        ]

        let props = WebView.Props(properties)

        XCTAssertEqual(props.url, "https://www.swift.org", "url should be preserved")
        XCTAssertEqual(props.customUserAgent, "MyApp/1.0", "customUserAgent should be preserved")
        XCTAssertEqual(props.backForwardNavigationGestures, true, "backForwardNavigationGestures should be preserved")
        XCTAssertEqual(props.magnificationGestures, false, "magnificationGestures should be preserved")
        XCTAssertEqual(props.linkPreviews, true, "linkPreviews should be preserved")
        XCTAssertEqual(props.navigationActionID, "nav.event", "navigationActionID should be preserved")
        XCTAssertEqual(BaseModifiers(properties).padding, .uniform(10.0), "base View padding should be read")
    }

    func testWebViewPropsValid_HTML() {
        let properties: [String: Any] = [
            "html": "<h1>Hello</h1>",
            "baseURL": "https://example.com"
        ]

        let props = WebView.Props(properties)

        XCTAssertEqual(props.html, "<h1>Hello</h1>", "html should be preserved")
        XCTAssertEqual(props.baseURL, "https://example.com", "baseURL should be preserved")
        XCTAssertNil(props.url, "url should be absent when not provided")
    }

    // MARK: - Props - invalid types

    func testWebViewPropsIgnoreInvalidTypes() {
        let properties: [String: Any] = [
            "url": 42,                              // should be String
            "html": true,                           // should be String
            "baseURL": 3.14,                        // should be String
            "customUserAgent": ["invalid"],         // should be String
            "backForwardNavigationGestures": "yes", // should be Bool
            "magnificationGestures": 1,             // should be Bool
            "linkPreviews": "true",                 // should be Bool
            "navigationActionID": false             // should be String
        ]

        let props = WebView.Props(properties)

        XCTAssertNil(props.url, "Non-String url should be ignored")
        XCTAssertNil(props.html, "Non-String html should be ignored")
        XCTAssertNil(props.baseURL, "Non-String baseURL should be ignored")
        XCTAssertNil(props.customUserAgent, "Non-String customUserAgent should be ignored")
        XCTAssertEqual(props.backForwardNavigationGestures, true, "Non-Bool backForwardNavigationGestures should be the default")
        XCTAssertEqual(props.magnificationGestures, true, "Non-Bool magnificationGestures should be the default")
        XCTAssertEqual(props.linkPreviews, true, "Non-Bool linkPreviews should be the default")
        XCTAssertNil(props.navigationActionID, "Non-String navigationActionID should be ignored")
    }

    // MARK: - Props - missing properties

    func testWebViewPropsMissing() {
        let properties: [String: Any] = [:]

        let props = WebView.Props(properties)

        XCTAssertNil(props.url, "Missing url should be nil")
        XCTAssertNil(props.html, "Missing html should be nil")
        XCTAssertNil(props.baseURL, "Missing baseURL should be nil")
        XCTAssertNil(props.customUserAgent, "Missing customUserAgent should be nil")
        XCTAssertEqual(props.backForwardNavigationGestures, true, "Missing backForwardNavigationGestures should be the default")
        XCTAssertEqual(props.magnificationGestures, true, "Missing magnificationGestures should be the default")
        XCTAssertEqual(props.linkPreviews, true, "Missing linkPreviews should be the default")
        XCTAssertNil(props.navigationActionID, "Missing navigationActionID should be nil")
    }

    // MARK: - Props - valueChangeActionID (base View property)

    func testWebViewPropsValueChangeActionID() {
        let properties: [String: Any] = [
            "valueChangeActionID": "url.changed"
        ]

        let props = WebView.Props(properties)

        XCTAssertEqual(props.valueChangeActionID, "url.changed",
                       "valueChangeActionID should be read")
    }

    // MARK: - initialValue
    // Note: initialValue / initialStates closures access @MainActor-isolated ViewModel
    // properties (e.g. viewModel.properties) and are exercised safely through loadDescription in
    // the JSON decoding tests below. The two tests here only verify branches that touch the
    // @Published var value (which has MainActor-aware bridging) so they are safe to call directly.

    func testWebViewInitialValue_FromExistingModelValue() {
        // When model.value is already a String it takes precedence over the url property.
        let viewModel = ViewModel()
        viewModel.value = "https://www.apple.com"
        viewModel.properties = ["url": "https://www.swift.org"]

        let value = WebView.initialValue(viewModel)

        XCTAssertEqual(value as? String, "https://www.apple.com",
                       "initialValue should prefer existing model.value over properties url")
    }

    // MARK: - initialStates

    func testWebViewInitialStates_Preserved() {
        // When states are already populated they must be returned unchanged.
        let viewModel = ViewModel()
        viewModel.states = [
            "isLoading": true,
            "estimatedProgress": 0.75,
            "canGoBack": true,
            "canGoForward": false,
            "title": "Swift.org"
        ]

        let states = WebView.initialStates(viewModel)

        XCTAssertEqual(states["isLoading"] as? Bool, true, "Existing isLoading should be preserved")
        XCTAssertEqual(states["estimatedProgress"] as? Double, 0.75, "Existing estimatedProgress should be preserved")
        XCTAssertEqual(states["canGoBack"] as? Bool, true, "Existing canGoBack should be preserved")
        XCTAssertEqual(states["canGoForward"] as? Bool, false, "Existing canGoForward should be preserved")
        XCTAssertEqual(states["title"] as? String, "Swift.org", "Existing title should be preserved")
    }

    // MARK: - buildView

    func testWebViewConstruction_WithURL() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "WebView",
            "properties": [
                "url": "https://www.swift.org",
                "backForwardNavigationGestures": true,
                "magnificationGestures": true,
                "linkPreviews": true,
                "padding": 8.0
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)

        let props = WebView.Props(properties)
        XCTAssertEqual(props.url, "https://www.swift.org", "url should be read correctly")
        XCTAssertEqual(props.backForwardNavigationGestures, true)
        XCTAssertEqual(props.magnificationGestures, true)
        XCTAssertEqual(props.linkPreviews, true)
    }

    func testWebViewConstruction_WithHTML() throws {
        let elementDict: [String: Any] = [
            "id": 2,
            "type": "WebView",
            "properties": [
                "html": "<p>Hello, world!</p>",
                "baseURL": "https://example.com"
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)

        let props = WebView.Props(properties)
        XCTAssertEqual(props.html, "<p>Hello, world!</p>", "html should be preserved")
        XCTAssertEqual(props.baseURL, "https://example.com", "baseURL should be preserved")
        XCTAssertNil(props.url, "url should be absent")
    }

    func testWebViewConstruction_NoContent() throws {
        // WebView with no url or html should still construct without crashing
        ActionUIModel.shared.logger = consoleLogger

        let elementDict: [String: Any] = [
            "id": 3,
            "type": "WebView",
            "properties": [:]
        ]

        let element = try ActionUIElement(from: elementDict, logger: consoleLogger)
        let properties = element.properties
        let viewModel = ViewModel()
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)

        let props = WebView.Props(properties)
        XCTAssertNil(props.url, "url should be nil when absent")
        XCTAssertNil(props.html, "html should be nil when absent")

        ActionUIModel.shared.logger = logger
    }

    func testWebViewConstruction_WithCustomUserAgent() throws {
        let elementDict: [String: Any] = [
            "id": 4,
            "type": "WebView",
            "properties": [
                "url": "https://www.swift.org",
                "customUserAgent": "TestAgent/2.0"
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)

        let props = WebView.Props(properties)
        XCTAssertEqual(props.customUserAgent, "TestAgent/2.0", "customUserAgent should be read correctly")
    }

    // MARK: - JSON decoding

    func testWebViewJSONDecoding_Full() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "WebView",
            "properties": {
                "url": "https://www.swift.org",
                "customUserAgent": "MyApp/1.0",
                "backForwardNavigationGestures": false,
                "magnificationGestures": true,
                "linkPreviews": false,
                "valueChangeActionID": "url.changed",
                "navigationActionID": "nav.event",
                "padding": 12.0
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "WebView", "Element type should be WebView")
        XCTAssertEqual(element.properties["url"] as? String, "https://www.swift.org")
        XCTAssertEqual(element.properties["customUserAgent"] as? String, "MyApp/1.0")
        XCTAssertEqual(element.properties["backForwardNavigationGestures"] as? Bool, false)
        XCTAssertEqual(element.properties["magnificationGestures"] as? Bool, true)
        XCTAssertEqual(element.properties["linkPreviews"] as? Bool, false)
        XCTAssertEqual(element.properties["valueChangeActionID"] as? String, "url.changed")
        XCTAssertEqual(element.properties["navigationActionID"] as? String, "nav.event")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 12.0)
        XCTAssertNil(element.subviews?["children"], "WebView should have no children")

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        XCTAssertEqual(viewModel.value as? String, "https://www.swift.org",
                       "Initial viewModel value should be the url string")
    }

    func testWebViewJSONDecoding_Minimal_URL() throws {
        let jsonString = """
        {
            "id": 5,
            "type": "WebView",
            "properties": {
                "url": "https://example.com"
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        XCTAssertEqual(element.type, "WebView")
        XCTAssertEqual(element.properties["url"] as? String, "https://example.com")

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        XCTAssertEqual(viewModel.value as? String, "https://example.com",
                       "Initial viewModel value should be the url string")
        XCTAssertEqual(viewModel.states["isLoading"] as? Bool, false,
                       "isLoading should be initialised to false")
        XCTAssertEqual(viewModel.states["estimatedProgress"] as? Double, 0.0,
                       "estimatedProgress should be initialised to 0.0")
        XCTAssertEqual(viewModel.states["canGoBack"] as? Bool, false,
                       "canGoBack should be initialised to false")
        XCTAssertEqual(viewModel.states["canGoForward"] as? Bool, false,
                       "canGoForward should be initialised to false")
    }

    func testWebViewJSONDecoding_HTML() throws {
        let jsonString = """
        {
            "id": 6,
            "type": "WebView",
            "properties": {
                "html": "<h1>Hello</h1>",
                "baseURL": "https://example.com"
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }

        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        XCTAssertEqual(element.properties["html"] as? String, "<h1>Hello</h1>")
        XCTAssertEqual(element.properties["baseURL"] as? String, "https://example.com")
        XCTAssertNil(element.properties["url"], "url should not be present")

        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        // With no url, initialValue falls back to ""
        XCTAssertEqual(viewModel.value as? String, "",
                       "Initial viewModel value should be empty string when url is absent")
    }

    // MARK: - Programmatic value updates

    func testWebViewDynamicURLUpdate() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "WebView",
            "properties": [
                "url": "https://www.swift.org",
                "valueChangeActionID": "url.changed"
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)

        // Simulate setElementValue with a new URL
        viewModel.value = "https://www.apple.com"
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)

        XCTAssertEqual(viewModel.value as? String, "https://www.apple.com",
                       "model.value should reflect the updated URL")
    }

    func testWebViewNavigationCommands_StoredInModelValue() throws {
        // Verify that navigation command strings can be written to model.value.
        // Actual command dispatch (goBack, goForward, reload, stop) is handled by
        // WebViewContent in a live SwiftUI environment; here we confirm the value
        // round-trips correctly through the ViewModel.
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "WebView",
            "properties": ["url": "https://www.swift.org"]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)

        for command in ["#goBack", "#goForward", "#reload", "#stop"] {
            viewModel.value = command
            XCTAssertEqual(viewModel.value as? String, command,
                           "Command '\(command)' should be stored in model.value")
        }
    }

    // MARK: - valueType

    func testWebViewValueType() {
        XCTAssertTrue(WebView.valueType == String.self, "WebView valueType should be String")
    }

    // MARK: - Props - new configuration properties

    func testWebViewProps_LimitsNavigationsToAppBoundDomains_Valid() {
        let props = WebView.Props(["limitsNavigationsToAppBoundDomains": true])
        XCTAssertEqual(props.limitsNavigationsToAppBoundDomains, true)
    }

    func testWebViewProps_LimitsNavigationsToAppBoundDomains_Invalid() {
        let props = WebView.Props(["limitsNavigationsToAppBoundDomains": "yes"])
        XCTAssertNil(props.limitsNavigationsToAppBoundDomains, "Non-Bool should be ignored")
    }

    func testWebViewProps_UpgradeKnownHostsToHTTPS_Valid() {
        let props = WebView.Props(["upgradeKnownHostsToHTTPS": true])
        XCTAssertEqual(props.upgradeKnownHostsToHTTPS, true)
    }

    func testWebViewProps_UpgradeKnownHostsToHTTPS_Invalid() {
        let props = WebView.Props(["upgradeKnownHostsToHTTPS": 1])
        XCTAssertNil(props.upgradeKnownHostsToHTTPS, "Non-Bool should be ignored")
    }

    // MARK: - Props - userScripts

    func testWebViewProps_UserScripts_InlineSource() {
        let scripts: [[String: Any]] = [
            ["injectionTime": "documentStart", "source": "window.foo = 1;", "forMainFrameOnly": false]
        ]
        let props = WebView.Props(["userScripts": scripts])
        XCTAssertEqual(props.userScripts.count, 1, "Valid script should be preserved")
        XCTAssertEqual(props.userScripts.first?.source, "window.foo = 1;")
        XCTAssertEqual(props.userScripts.first?.injectionTime, .documentStart)
    }

    func testWebViewProps_UserScripts_DocumentEnd() {
        let scripts: [[String: Any]] = [
            ["injectionTime": "documentEnd", "source": "console.log('ready');"]
        ]
        let props = WebView.Props(["userScripts": scripts])
        XCTAssertEqual(props.userScripts.first?.injectionTime, .documentEnd)
    }

    func testWebViewProps_UserScripts_FilePath() {
        let scripts: [[String: Any]] = [
            ["injectionTime": "documentEnd", "filePath": "/tmp/script.js"]
        ]
        let props = WebView.Props(["userScripts": scripts])
        XCTAssertEqual(props.userScripts.count, 1, "Script with filePath should be accepted at parse time")
        XCTAssertEqual(props.userScripts.first?.filePath, "/tmp/script.js")
    }

    func testWebViewProps_UserScripts_ResourceName() {
        let scripts: [[String: Any]] = [
            ["injectionTime": "documentStart", "resourceName": "MyScript.js"]
        ]
        let props = WebView.Props(["userScripts": scripts])
        XCTAssertEqual(props.userScripts.count, 1, "Script with resourceName should be accepted at parse time")
        XCTAssertEqual(props.userScripts.first?.resourceName, "MyScript.js")
    }

    func testWebViewProps_UserScripts_ResourceName_UppercaseExtension() {
        // .JS (uppercase) must be treated the same as .js when stripping the extension
        let scripts: [[String: Any]] = [
            ["injectionTime": "documentStart", "resourceName": "MyScript.JS"]
        ]
        let props = WebView.Props(["userScripts": scripts])
        XCTAssertEqual(props.userScripts.count, 1, "Script with uppercase .JS extension should be accepted")
        XCTAssertEqual(props.userScripts.first?.resourceName, "MyScript.JS")
    }

    func testWebViewProps_UserScripts_MissingSource_Skipped() {
        // No source, filePath, or resourceName — should be dropped
        let scripts: [[String: Any]] = [
            ["injectionTime": "documentStart"]
        ]
        let props = WebView.Props(["userScripts": scripts])
        XCTAssertTrue(props.userScripts.isEmpty, "Scripts without any source should be skipped entirely")
    }

    func testWebViewProps_UserScripts_InvalidInjectionTime_NormalisedToDocumentEnd() {
        let scripts: [[String: Any]] = [
            ["injectionTime": "immediately", "source": "1+1;"]
        ]
        let props = WebView.Props(["userScripts": scripts])
        XCTAssertEqual(props.userScripts.first?.injectionTime, .documentEnd,
                       "Invalid injectionTime should be normalised to 'documentEnd'")
    }

    func testWebViewProps_UserScripts_NotAnArray_Ignored() {
        let props = WebView.Props(["userScripts": "console.log('hi');"])
        XCTAssertTrue(props.userScripts.isEmpty, "Non-array userScripts should be ignored")
    }

    func testWebViewProps_UserScripts_MultipleScripts() {
        let scripts: [[String: Any]] = [
            ["injectionTime": "documentStart", "source": "var a = 1;"],
            ["injectionTime": "documentEnd",   "source": "var b = 2;", "forMainFrameOnly": true],
            ["injectionTime": "documentStart"] // no source — should be dropped
        ]
        let props = WebView.Props(["userScripts": scripts])
        XCTAssertEqual(props.userScripts.count, 2, "Only scripts with a source should be kept")
        XCTAssertEqual(props.userScripts[0].injectionTime, .documentStart)
        XCTAssertEqual(props.userScripts[1].forMainFrameOnly, true)
    }

    // MARK: - Implementation selection (global flag)

    func testWebViewImplementation_DefaultIsNative() {
        // resetForTesting + tearDown restore the default; verify it out of the box.
        XCTAssertEqual(ActionUIRegistry.shared.webViewImplementation, .native,
                       "WebView should default to the native WKWebView backing")
    }

    func testWebViewImplementation_Selectable() {
        ActionUIRegistry.shared.webViewImplementation = .swiftUI
        XCTAssertEqual(ActionUIRegistry.shared.webViewImplementation, .swiftUI,
                       "Host app should be able to select the SwiftUI backing")
        ActionUIRegistry.shared.webViewImplementation = .native
        XCTAssertEqual(ActionUIRegistry.shared.webViewImplementation, .native)
    }

    func testWebViewImplementation_RawValues() {
        XCTAssertEqual(WebViewImplementation.native.rawValue, "native")
        XCTAssertEqual(WebViewImplementation.swiftUI.rawValue, "swiftUI")
    }

    func testWebViewConstruction_NativeBacking() throws {
        // buildView must succeed (not crash) under the native backing on all OS versions.
        ActionUIRegistry.shared.webViewImplementation = .native
        let element = try ActionUIElement(from: [
            "id": 1, "type": "WebView", "properties": ["url": "https://www.swift.org"]
        ], logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        XCTAssertNotNil(view, "Native backing should build a view")
    }

    func testWebViewConstruction_SwiftUIBacking() throws {
        // Under the .swiftUI flag, buildView must also succeed (falls back to native pre-OS-26).
        ActionUIRegistry.shared.webViewImplementation = .swiftUI
        let element = try ActionUIElement(from: [
            "id": 1, "type": "WebView", "properties": ["url": "https://www.swift.org"]
        ], logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        XCTAssertNotNil(view, "SwiftUI backing should build a view (or native fallback)")
    }

    // MARK: - WebViewSupport (shared by both backings)

    func testWebViewSupport_ResolveJSSource_Inline() {
        let source = WebViewSupport.resolveJSSource(from: ["source": "var x = 1;"], logger: logger)
        XCTAssertEqual(source, "var x = 1;")
    }

    func testWebViewSupport_ResolveJSSource_FilePath() throws {
        let tmp = NSTemporaryDirectory() + "actionui-webview-test-\(UUID().uuidString).js"
        try "console.log('from file');".write(toFile: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        let source = WebViewSupport.resolveJSSource(from: ["filePath": tmp], logger: logger)
        XCTAssertEqual(source, "console.log('from file');")
    }

    func testWebViewSupport_ResolveJSSource_MissingFile_ReturnsNil() {
        ActionUIModel.shared.logger = consoleLogger
        let source = WebViewSupport.resolveJSSource(from: ["filePath": "/no/such/file.js"], logger: consoleLogger)
        XCTAssertNil(source, "Missing file should yield nil source")
        ActionUIModel.shared.logger = logger
    }

    func testWebViewSupport_BuildUserScripts() {
        let properties: [String: Any] = [
            "userScripts": [
                ["injectionTime": "documentStart", "source": "var a = 1;", "forMainFrameOnly": true],
                ["injectionTime": "documentEnd", "source": "var b = 2;"]
            ]
        ]
        let scripts = WebViewSupport.buildUserScripts(from: properties, logger: logger)
        XCTAssertEqual(scripts.count, 2)
        XCTAssertEqual(scripts[0].injectionTime, .atDocumentStart)
        XCTAssertTrue(scripts[0].isForMainFrameOnly)
        XCTAssertEqual(scripts[1].injectionTime, .atDocumentEnd)
        XCTAssertFalse(scripts[1].isForMainFrameOnly, "forMainFrameOnly defaults to false")
    }

    func testWebViewSupport_BuildUserScripts_Empty() {
        XCTAssertTrue(WebViewSupport.buildUserScripts(from: [:], logger: logger).isEmpty)
    }

    func testWebViewSupport_MakeWKConfiguration_AppliesFlags() {
        let properties: [String: Any] = [
            "limitsNavigationsToAppBoundDomains": true,
            "upgradeKnownHostsToHTTPS": true,
            "userScripts": [["injectionTime": "documentStart", "source": "1;"]]
        ]
        let config = WebViewSupport.makeWKConfiguration(properties: properties, logger: logger)
        XCTAssertTrue(config.limitsNavigationsToAppBoundDomains)
        XCTAssertTrue(config.upgradeKnownHostsToHTTPS)
        XCTAssertEqual(config.userContentController.userScripts.count, 1,
                       "User scripts should be installed on the configuration")
    }

    // MARK: - JSON round-trip with new properties

    func testWebViewJSONDecoding_WithConfigurationProperties() throws {
        let jsonString = """
        {
            "id": 10,
            "type": "WebView",
            "properties": {
                "url": "https://example.com",
                "limitsNavigationsToAppBoundDomains": true,
                "upgradeKnownHostsToHTTPS": true,
                "userScripts": [
                    { "injectionTime": "documentStart", "source": "window.injected = true;" }
                ]
            }
        }
        """
        let jsonData = try XCTUnwrap(jsonString.data(using: .utf8))
        let element = try ActionUIModel.shared.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)

        let properties = element.properties
        XCTAssertEqual(properties["limitsNavigationsToAppBoundDomains"] as? Bool, true)
        XCTAssertEqual(properties["upgradeKnownHostsToHTTPS"] as? Bool, true)
        let scripts = properties["userScripts"] as? [[String: Any]]
        XCTAssertEqual(scripts?.count, 1)
        XCTAssertEqual(scripts?.first?["source"] as? String, "window.injected = true;")
        XCTAssertEqual(scripts?.first?["injectionTime"] as? String, "documentStart")
    }
}
