// Tests/Views/WebViewTests.swift
/*
 WebViewTests.swift

 Tests for the WebView component in the ActionUI component library.
 Verifies JSON decoding, property validation, view construction, initialValue / initialStates,
 and programmatic value updates.

 Note: WebView requires iOS 26+ / macOS 26+. buildView returns a SwiftUI Label fallback on
 older OS versions. The internal WebViewContent struct (navigation commands, state sync) is
 exercised in integration; unit tests here focus on the static ActionUIViewConstruction surface.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class WebViewTests: XCTestCase {
    private var logger: XCTestLogger!
    private var consoleLogger: ConsoleLogger!
    private var windowUUID: String!

    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        consoleLogger = ConsoleLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }

    override func tearDown() {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        consoleLogger = nil
        windowUUID = nil
        super.tearDown()
    }

    // MARK: - validateProperties – valid input

    func testWebViewValidatePropertiesValid() {
        let properties: [String: Any] = [
            "url": "https://www.swift.org",
            "customUserAgent": "MyApp/1.0",
            "backForwardNavigationGestures": true,
            "magnificationGestures": false,
            "linkPreviews": true,
            "navigationActionID": "nav.event",
            "padding": 10.0
        ]

        let validated = WebView.validateProperties(properties, logger)

        XCTAssertEqual(validated["url"] as? String, "https://www.swift.org", "url should be preserved")
        XCTAssertEqual(validated["customUserAgent"] as? String, "MyApp/1.0", "customUserAgent should be preserved")
        XCTAssertEqual(validated["backForwardNavigationGestures"] as? Bool, true, "backForwardNavigationGestures should be preserved")
        XCTAssertEqual(validated["magnificationGestures"] as? Bool, false, "magnificationGestures should be preserved")
        XCTAssertEqual(validated["linkPreviews"] as? Bool, true, "linkPreviews should be preserved")
        XCTAssertEqual(validated["navigationActionID"] as? String, "nav.event", "navigationActionID should be preserved")
        XCTAssertEqual(validated.cgFloat(forKey: "padding"), 10.0, "base View padding should pass through")
    }

    func testWebViewValidatePropertiesValid_HTML() {
        let properties: [String: Any] = [
            "html": "<h1>Hello</h1>",
            "baseURL": "https://example.com"
        ]

        let validated = WebView.validateProperties(properties, logger)

        XCTAssertEqual(validated["html"] as? String, "<h1>Hello</h1>", "html should be preserved")
        XCTAssertEqual(validated["baseURL"] as? String, "https://example.com", "baseURL should be preserved")
        XCTAssertNil(validated["url"], "url should be absent when not provided")
    }

    // MARK: - validateProperties – invalid types

    func testWebViewValidatePropertiesInvalid_Types() {
        ActionUIRegistry.shared.setLogger(consoleLogger)
        ActionUIModel.shared.logger = consoleLogger

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

        let validated = WebView.validateProperties(properties, consoleLogger)

        XCTAssertNil(validated["url"], "Non-String url should be nil")
        XCTAssertNil(validated["html"], "Non-String html should be nil")
        XCTAssertNil(validated["baseURL"], "Non-String baseURL should be nil")
        XCTAssertNil(validated["customUserAgent"], "Non-String customUserAgent should be nil")
        XCTAssertNil(validated["backForwardNavigationGestures"], "Non-Bool backForwardNavigationGestures should be nil")
        XCTAssertNil(validated["magnificationGestures"], "Non-Bool magnificationGestures should be nil")
        XCTAssertNil(validated["linkPreviews"], "Non-Bool linkPreviews should be nil")
        XCTAssertNil(validated["navigationActionID"], "Non-String navigationActionID should be nil")

        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger
    }

    // MARK: - validateProperties – missing properties

    func testWebViewValidatePropertiesMissing() {
        let properties: [String: Any] = [:]

        let validated = WebView.validateProperties(properties, logger)

        XCTAssertNil(validated["url"], "Missing url should be nil")
        XCTAssertNil(validated["html"], "Missing html should be nil")
        XCTAssertNil(validated["baseURL"], "Missing baseURL should be nil")
        XCTAssertNil(validated["customUserAgent"], "Missing customUserAgent should be nil")
        XCTAssertNil(validated["backForwardNavigationGestures"], "Missing backForwardNavigationGestures should be nil")
        XCTAssertNil(validated["magnificationGestures"], "Missing magnificationGestures should be nil")
        XCTAssertNil(validated["linkPreviews"], "Missing linkPreviews should be nil")
        XCTAssertNil(validated["navigationActionID"], "Missing navigationActionID should be nil")
    }

    // MARK: - validateProperties – valueChangeActionID (base View property)

    func testWebViewValidatePropertiesValueChangeActionID() {
        let properties: [String: Any] = [
            "valueChangeActionID": "url.changed"
        ]

        let validated = WebView.validateProperties(properties, logger)

        XCTAssertEqual(validated["valueChangeActionID"] as? String, "url.changed",
                       "valueChangeActionID should pass through base View validation")
    }

    // MARK: - initialValue
    // Note: initialValue / initialStates closures access @MainActor-isolated ViewModel
    // properties (e.g. validatedProperties) and are exercised safely through loadDescription in
    // the JSON decoding tests below. The two tests here only verify branches that touch the
    // @Published var value (which has MainActor-aware bridging) so they are safe to call directly.

    func testWebViewInitialValue_FromExistingModelValue() {
        // When model.value is already a String it takes precedence over the url property.
        let viewModel = ViewModel()
        viewModel.value = "https://www.apple.com"
        viewModel.validatedProperties = ["url": "https://www.swift.org"]

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
        let validatedProperties = WebView.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

        XCTAssertEqual(validatedProperties["url"] as? String, "https://www.swift.org", "Validated url should be correct")
        XCTAssertEqual(validatedProperties["backForwardNavigationGestures"] as? Bool, true)
        XCTAssertEqual(validatedProperties["magnificationGestures"] as? Bool, true)
        XCTAssertEqual(validatedProperties["linkPreviews"] as? Bool, true)
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
        let validatedProperties = WebView.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

        XCTAssertEqual(validatedProperties["html"] as? String, "<p>Hello, world!</p>", "html should be preserved")
        XCTAssertEqual(validatedProperties["baseURL"] as? String, "https://example.com", "baseURL should be preserved")
        XCTAssertNil(validatedProperties["url"], "url should be absent")
    }

    func testWebViewConstruction_NoContent() throws {
        // WebView with no url or html should still construct without crashing
        ActionUIRegistry.shared.setLogger(consoleLogger)
        ActionUIModel.shared.logger = consoleLogger

        let elementDict: [String: Any] = [
            "id": 3,
            "type": "WebView",
            "properties": [:]
        ]

        let element = try ActionUIElement(from: elementDict, logger: consoleLogger)
        let validatedProperties = WebView.validateProperties(element.properties, consoleLogger)
        let viewModel = ViewModel()
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

        XCTAssertNil(validatedProperties["url"], "url should be nil when absent")
        XCTAssertNil(validatedProperties["html"], "html should be nil when absent")

        ActionUIRegistry.shared.setLogger(logger)
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
        let validatedProperties = WebView.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

        XCTAssertEqual(validatedProperties["customUserAgent"] as? String, "TestAgent/2.0", "customUserAgent should be validated correctly")
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
        let validatedProperties = WebView.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

        // Simulate setElementValue with a new URL
        viewModel.value = "https://www.apple.com"
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

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
        let validatedProperties = WebView.validateProperties(element.properties, logger)
        let viewModel = ViewModel()
        _ = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, validatedProperties: validatedProperties)

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

    // MARK: - validateProperties – new configuration properties

    func testWebViewValidateProperties_LimitsNavigationsToAppBoundDomains_Valid() {
        let validated = WebView.validateProperties(["limitsNavigationsToAppBoundDomains": true], logger)
        XCTAssertEqual(validated["limitsNavigationsToAppBoundDomains"] as? Bool, true)
    }

    func testWebViewValidateProperties_LimitsNavigationsToAppBoundDomains_Invalid() {
        ActionUIModel.shared.logger = consoleLogger
        let validated = WebView.validateProperties(["limitsNavigationsToAppBoundDomains": "yes"], consoleLogger)
        XCTAssertNil(validated["limitsNavigationsToAppBoundDomains"], "Non-Bool should be removed")
        ActionUIModel.shared.logger = logger
    }

    func testWebViewValidateProperties_UpgradeKnownHostsToHTTPS_Valid() {
        let validated = WebView.validateProperties(["upgradeKnownHostsToHTTPS": true], logger)
        XCTAssertEqual(validated["upgradeKnownHostsToHTTPS"] as? Bool, true)
    }

    func testWebViewValidateProperties_UpgradeKnownHostsToHTTPS_Invalid() {
        ActionUIModel.shared.logger = consoleLogger
        let validated = WebView.validateProperties(["upgradeKnownHostsToHTTPS": 1], consoleLogger)
        XCTAssertNil(validated["upgradeKnownHostsToHTTPS"], "Non-Bool should be removed")
        ActionUIModel.shared.logger = logger
    }

    // MARK: - validateProperties – userScripts

    func testWebViewValidateProperties_UserScripts_InlineSource() {
        let scripts: [[String: Any]] = [
            ["injectionTime": "documentStart", "source": "window.foo = 1;", "forMainFrameOnly": false]
        ]
        let validated = WebView.validateProperties(["userScripts": scripts], logger)
        let out = validated["userScripts"] as? [[String: Any]]
        XCTAssertEqual(out?.count, 1, "Valid script should be preserved")
        XCTAssertEqual(out?.first?["source"] as? String, "window.foo = 1;")
        XCTAssertEqual(out?.first?["injectionTime"] as? String, "documentStart")
    }

    func testWebViewValidateProperties_UserScripts_DocumentEnd() {
        let scripts: [[String: Any]] = [
            ["injectionTime": "documentEnd", "source": "console.log('ready');"]
        ]
        let validated = WebView.validateProperties(["userScripts": scripts], logger)
        let out = validated["userScripts"] as? [[String: Any]]
        XCTAssertEqual(out?.first?["injectionTime"] as? String, "documentEnd")
    }

    func testWebViewValidateProperties_UserScripts_FilePath() {
        let scripts: [[String: Any]] = [
            ["injectionTime": "documentEnd", "filePath": "/tmp/script.js"]
        ]
        let validated = WebView.validateProperties(["userScripts": scripts], logger)
        let out = validated["userScripts"] as? [[String: Any]]
        XCTAssertEqual(out?.count, 1, "Script with filePath should be accepted at validation time")
        XCTAssertEqual(out?.first?["filePath"] as? String, "/tmp/script.js")
    }

    func testWebViewValidateProperties_UserScripts_ResourceName() {
        let scripts: [[String: Any]] = [
            ["injectionTime": "documentStart", "resourceName": "MyScript.js"]
        ]
        let validated = WebView.validateProperties(["userScripts": scripts], logger)
        let out = validated["userScripts"] as? [[String: Any]]
        XCTAssertEqual(out?.count, 1, "Script with resourceName should be accepted at validation time")
        XCTAssertEqual(out?.first?["resourceName"] as? String, "MyScript.js")
    }

    func testWebViewValidateProperties_UserScripts_ResourceName_UppercaseExtension() {
        // .JS (uppercase) must be treated the same as .js when stripping the extension
        let scripts: [[String: Any]] = [
            ["injectionTime": "documentStart", "resourceName": "MyScript.JS"]
        ]
        let validated = WebView.validateProperties(["userScripts": scripts], logger)
        let out = validated["userScripts"] as? [[String: Any]]
        XCTAssertEqual(out?.count, 1, "Script with uppercase .JS extension should be accepted")
        XCTAssertEqual(out?.first?["resourceName"] as? String, "MyScript.JS")
    }

    func testWebViewValidateProperties_UserScripts_MissingSource_Skipped() {
        ActionUIModel.shared.logger = consoleLogger
        // No source, filePath, or resourceName — should be dropped
        let scripts: [[String: Any]] = [
            ["injectionTime": "documentStart"]
        ]
        let validated = WebView.validateProperties(["userScripts": scripts], consoleLogger)
        XCTAssertNil(validated["userScripts"], "Scripts without any source should be removed entirely")
        ActionUIModel.shared.logger = logger
    }

    func testWebViewValidateProperties_UserScripts_InvalidInjectionTime_NormalisedToDocumentEnd() {
        ActionUIModel.shared.logger = consoleLogger
        let scripts: [[String: Any]] = [
            ["injectionTime": "immediately", "source": "1+1;"]
        ]
        let validated = WebView.validateProperties(["userScripts": scripts], consoleLogger)
        let out = validated["userScripts"] as? [[String: Any]]
        XCTAssertEqual(out?.first?["injectionTime"] as? String, "documentEnd",
                       "Invalid injectionTime should be normalised to 'documentEnd'")
        ActionUIModel.shared.logger = logger
    }

    func testWebViewValidateProperties_UserScripts_NotAnArray_Removed() {
        ActionUIModel.shared.logger = consoleLogger
        let validated = WebView.validateProperties(["userScripts": "console.log('hi');"], consoleLogger)
        XCTAssertNil(validated["userScripts"], "Non-array userScripts should be removed")
        ActionUIModel.shared.logger = logger
    }

    func testWebViewValidateProperties_UserScripts_MultipleScripts() {
        let scripts: [[String: Any]] = [
            ["injectionTime": "documentStart", "source": "var a = 1;"],
            ["injectionTime": "documentEnd",   "source": "var b = 2;", "forMainFrameOnly": true],
            ["injectionTime": "documentStart"] // no source — should be dropped
        ]
        ActionUIModel.shared.logger = consoleLogger
        let validated = WebView.validateProperties(["userScripts": scripts], consoleLogger)
        ActionUIModel.shared.logger = logger
        let out = validated["userScripts"] as? [[String: Any]]
        XCTAssertEqual(out?.count, 2, "Only scripts with a source should be kept")
        XCTAssertEqual(out?[0]["injectionTime"] as? String, "documentStart")
        XCTAssertEqual(out?[1]["forMainFrameOnly"] as? Bool, true)
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

        let validated = element.properties
        XCTAssertEqual(validated["limitsNavigationsToAppBoundDomains"] as? Bool, true)
        XCTAssertEqual(validated["upgradeKnownHostsToHTTPS"] as? Bool, true)
        let scripts = validated["userScripts"] as? [[String: Any]]
        XCTAssertEqual(scripts?.count, 1)
        XCTAssertEqual(scripts?.first?["source"] as? String, "window.injected = true;")
        XCTAssertEqual(scripts?.first?["injectionTime"] as? String, "documentStart")
    }
}
