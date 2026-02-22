// Sources/Views/WebView.swift
/*
 Sample JSON for WebView:
 {
   "type": "WebView",
   "id": 1,              // Required: Non-zero positive integer for runtime programmatic interaction
   "properties": {
     "url": "https://www.swift.org",          // Optional: Initial URL to load; takes precedence over html
     "html": "<h1>Hello</h1>",               // Optional: Inline HTML to render (used when url is absent)
     "baseURL": "https://example.com",        // Optional: Base URL for resolving relative links in html content
     "customUserAgent": "MyApp/1.0",          // Optional: Overrides the default WebKit user agent
     "backForwardNavigationGestures": true,   // Optional: Bool, enable swipe back/forward gestures; default true
     "magnificationGestures": true,           // Optional: Bool, enable pinch-to-zoom; default true
     "linkPreviews": true,                    // Optional: Bool, enable long-press link previews; default true
     "limitsNavigationsToAppBoundDomains": false, // Optional: Bool; restrict navigation to app-bound domains; default false
     "upgradeKnownHostsToHTTPS": false,           // Optional: Bool; auto-upgrade known HTTP hosts to HTTPS; default false
     "userScripts": [     // Optional: Array of JS descriptors injected before/after page load
       {
         "injectionTime": "documentStart", // Required: "documentStart" or "documentEnd"
         "source": "window.myFlag = true;", // One required source — inline JS string
         // OR "filePath": "/absolute/path/to/script.js"  — absolute path to a .js file on disk
         // OR "resourceName": "MyScript.js"              — .js file in the app's main bundle
         "forMainFrameOnly": false          // Optional Bool; inject into all frames when false; default false
       }
     ],
     "valueChangeActionID": "onURLChange",    // Optional: Fired when URL changes after a navigation completes
     "navigationActionID": "onNavigation"     // Optional: Fired when isLoading changes (navigation started / finished)
   }
 }

 Note: WebView requires iOS 26.0+ / macOS 26.0+. On older OS versions a fallback Label is shown instead.

 Note: userScripts are injected via WKUserScript on each page load via WebPage.Configuration.
 The "resourceName" lookup strips a trailing .js extension then calls Bundle.main.path(forResource:ofType:),
 mirroring Image.swift's resourceName pattern.

 Observable state (via getElementValue / getElementState):
   value (String)                     Current page URL.
                                      Write a URL string to navigate, or one of these commands:
                                        "goBack"    – navigate back  (no-op if canGoBack is false)
                                        "goForward" – navigate forward (no-op if canGoForward is false)
                                        "reload"    – reload the current page
                                        "stop"      – cancel an in-flight load
   states["title"]     String?        Page <title> text; absent until first load completes
   states["isLoading"] Bool           true while a navigation is in flight
   states["estimatedProgress"] Double 0.0–1.0 load progress
   states["canGoBack"] Bool           Back list has items
   states["canGoForward"] Bool        Forward list has items

 Baseline View properties (padding, hidden, foregroundStyle, font, background, frame, opacity,
 cornerRadius, actionID, disabled, onAppearActionID, onDisappearActionID, etc.) are inherited from base View.
 */

import SwiftUI
import WebKit

struct WebView: ActionUIViewConstruction {
    static var valueType: Any.Type { String.self }

    static var validateProperties: ([String: Any], any ActionUILogger) -> [String: Any] = { properties, logger in
        var validated = properties

        if let url = validated["url"], !(url is String) {
            logger.log("WebView url must be a String; ignoring", .warning)
            validated["url"] = nil
        }

        if let html = validated["html"], !(html is String) {
            logger.log("WebView html must be a String; ignoring", .warning)
            validated["html"] = nil
        }

        if let baseURL = validated["baseURL"], !(baseURL is String) {
            logger.log("WebView baseURL must be a String; ignoring", .warning)
            validated["baseURL"] = nil
        }

        if let userAgent = validated["customUserAgent"], !(userAgent is String) {
            logger.log("WebView customUserAgent must be a String; ignoring", .warning)
            validated["customUserAgent"] = nil
        }

        if let gestures = validated["backForwardNavigationGestures"], !(gestures is Bool) {
            logger.log("WebView backForwardNavigationGestures must be a Bool; ignoring", .warning)
            validated["backForwardNavigationGestures"] = nil
        }

        if let mag = validated["magnificationGestures"], !(mag is Bool) {
            logger.log("WebView magnificationGestures must be a Bool; ignoring", .warning)
            validated["magnificationGestures"] = nil
        }

        if let previews = validated["linkPreviews"], !(previews is Bool) {
            logger.log("WebView linkPreviews must be a Bool; ignoring", .warning)
            validated["linkPreviews"] = nil
        }

        if let limits = validated["limitsNavigationsToAppBoundDomains"], !(limits is Bool) {
            logger.log("WebView limitsNavigationsToAppBoundDomains must be a Bool; ignoring", .warning)
            validated["limitsNavigationsToAppBoundDomains"] = nil
        }

        if let upgrade = validated["upgradeKnownHostsToHTTPS"], !(upgrade is Bool) {
            logger.log("WebView upgradeKnownHostsToHTTPS must be a Bool; ignoring", .warning)
            validated["upgradeKnownHostsToHTTPS"] = nil
        }

        if let navActionID = validated["navigationActionID"], !(navActionID is String) {
            logger.log("WebView navigationActionID must be a String; ignoring", .warning)
            validated["navigationActionID"] = nil
        }

        // Validate userScripts array
        if let raw = validated["userScripts"] {
            if let scripts = raw as? [[String: Any]] {
                var validScripts: [[String: Any]] = []
                for (i, script) in scripts.enumerated() {
                    let hasSource = script["source"] is String
                    let hasFilePath = script["filePath"] is String
                    let hasResourceName = script["resourceName"] is String
                    guard hasSource || hasFilePath || hasResourceName else {
                        logger.log("WebView userScripts[\(i)] missing 'source', 'filePath', or 'resourceName'; skipping", .warning)
                        continue
                    }
                    var entry = script
                    if let time = script["injectionTime"] as? String,
                       !["documentStart", "documentEnd"].contains(time) {
                        logger.log("WebView userScripts[\(i)] injectionTime '\(time)' invalid; defaulting to 'documentEnd'", .warning)
                        entry["injectionTime"] = "documentEnd"
                    }
                    validScripts.append(entry)
                }
                validated["userScripts"] = validScripts.isEmpty ? nil : validScripts
            } else {
                logger.log("WebView userScripts must be an array of dictionaries; ignoring", .warning)
                validated["userScripts"] = nil
            }
        }

        return validated
    }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        if #available(iOS 26.0, macOS 26.0, *) {
            return WebViewContent(
                model: model,
                properties: properties,
                element: element,
                windowUUID: windowUUID,
                logger: logger
            )
        } else {
            logger.log("WebView requires iOS 26 / macOS 26 or later; displaying fallback Label", .error)
            return SwiftUI.Label("WebView requires iOS 26 or macOS 26 or later", systemImage: "exclamationmark.triangle")
        }
    }

    static var initialValue: (ViewModel) -> Any? = { model in
        if let existing = model.value as? String { return existing }
        return model.validatedProperties["url"] as? String ?? ""
    }

    static var initialStates: (ViewModel) -> [String: Any] = { model in
        var states = model.states
        if states.isEmpty {
            states["isLoading"] = false
            states["estimatedProgress"] = 0.0
            states["canGoBack"] = false
            states["canGoForward"] = false
        }
        return states
    }
}

// MARK: - WebViewContent

@available(iOS 26.0, macOS 26.0, *)
private struct WebViewContent: SwiftUI.View {
    @State private var page: WebPage
    /// Tracks the last URL we pushed into model.value ourselves, so we can distinguish
    /// programmatic URL updates from host-app navigation commands in onChange(of: commandValue).
    @State private var lastTrackedURL: String
    @ObservedObject var model: ViewModel
    let properties: [String: Any]
    let element: any ActionUIElementBase
    let windowUUID: String
    let logger: any ActionUILogger

    init(model: ViewModel, properties: [String: Any], element: any ActionUIElementBase, windowUUID: String, logger: any ActionUILogger) {
        self.model = model
        self.properties = properties
        self.element = element
        self.windowUUID = windowUUID
        self.logger = logger
        _page = State(initialValue: WebPage(configuration: WebViewContent.makeConfiguration(properties: properties, logger: logger)))
        _lastTrackedURL = State(initialValue: "")
    }

    /// A convenience accessor for the current model value cast to String.
    private var commandValue: String? { model.value as? String }

    var body: some SwiftUI.View {
        makeWebView()
            // URL changed – update state and fire valueChangeActionID
            .onChange(of: page.url, initial: false) { _, newURL in
                handleURLChange(newURL)
            }
            // Loading state changed – sync progress/navigation state and fire navigationActionID
            .onChange(of: page.isLoading) { _, _ in
                syncNavigationState()
                if let navActionID = properties["navigationActionID"] as? String {
                    ActionUIModel.shared.actionHandler(navActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
                }
            }
            // Progress changed – keep states in sync
            .onChange(of: page.estimatedProgress) { _, newProgress in
                DispatchQueue.main.async { model.states["estimatedProgress"] = newProgress }
            }
            // Title changed – expose to host app
            .onChange(of: page.title) { _, newTitle in
                DispatchQueue.main.async { model.states["title"] = newTitle }
            }
            // model.value changed externally – handle as navigation command
            .onChange(of: commandValue, initial: false) { _, cmd in
                handleCommand(cmd)
            }
            .onAppear {
                setupPage()
                loadInitialContent()
            }
    }

    // MARK: WebView construction with platform-conditional modifiers

    @ViewBuilder
    private func makeWebView() -> some SwiftUI.View {
        let backForward = properties["backForwardNavigationGestures"] as? Bool ?? true
        let magnification = properties["magnificationGestures"] as? Bool ?? true
        let linkPreviews = properties["linkPreviews"] as? Bool ?? true
        // WebKit.WebView refers to the SDK's SwiftUI WebView type (from _WebKit_SwiftUI overlay).
        // The explicit module prefix disambiguates from our own ActionUI.WebView struct.
        WebKit.WebView(page)
            .webViewBackForwardNavigationGestures(backForward ? .enabled : .disabled)
            .webViewMagnificationGestures(magnification ? .enabled : .disabled)
            .webViewLinkPreviews(linkPreviews ? .enabled : .disabled)
    }

    // MARK: Configuration

    /// Builds a WebPage.Configuration from validated properties.
    /// Called once at init time so user scripts survive page reloads within the same view lifetime.
    private static func makeConfiguration(properties: [String: Any], logger: any ActionUILogger) -> WebPage.Configuration {
        var config = WebPage.Configuration()

        if let limits = properties["limitsNavigationsToAppBoundDomains"] as? Bool {
            config.limitsNavigationsToAppBoundDomains = limits
        }

        if let upgrade = properties["upgradeKnownHostsToHTTPS"] as? Bool {
            config.upgradeKnownHostsToHTTPS = upgrade
        }

        if let scripts = properties["userScripts"] as? [[String: Any]], !scripts.isEmpty {
            let userContentController = WKUserContentController()
            for scriptDict in scripts {
                guard let source = resolveJSSource(from: scriptDict, logger: logger) else { continue }
                let injectionTimeStr = scriptDict["injectionTime"] as? String ?? "documentEnd"
                let injectionTime: WKUserScriptInjectionTime = (injectionTimeStr == "documentStart") ? .atDocumentStart : .atDocumentEnd
                let forMainFrameOnly = scriptDict["forMainFrameOnly"] as? Bool ?? false
                let script = WKUserScript(source: source, injectionTime: injectionTime, forMainFrameOnly: forMainFrameOnly)
                userContentController.addUserScript(script)
            }
            config.userContentController = userContentController
        }

        return config
    }

    /// Resolves the JavaScript source string from a script descriptor.
    /// Mirrors the Image.swift resourceName / filePath / source pattern.
    private static func resolveJSSource(from descriptor: [String: Any], logger: any ActionUILogger) -> String? {
        if let source = descriptor["source"] as? String {
            return source
        }

        if let filePath = descriptor["filePath"] as? String {
            do {
                return try String(contentsOfFile: filePath, encoding: .utf8)
            } catch {
                logger.log("WebView userScript: failed to read file at '\(filePath)': \(error.localizedDescription)", .warning)
                return nil
            }
        }

        if let resourceName = descriptor["resourceName"] as? String {
            // Strip .js extension to use Bundle path(forResource:ofType:)
            let nameWithoutExt = resourceName.lowercased().hasSuffix(".js") ? String(resourceName.dropLast(3)) : resourceName
            if let path = Bundle.main.path(forResource: nameWithoutExt, ofType: "js") {
                do {
                    return try String(contentsOfFile: path, encoding: .utf8)
                } catch {
                    logger.log("WebView userScript: failed to read bundle resource '\(resourceName)': \(error.localizedDescription)", .warning)
                    return nil
                }
            }
            // Fallback: try the name as-is (e.g. "MyScript" without extension, or unusual extension)
            if let path = Bundle.main.path(forResource: resourceName, ofType: nil) {
                do {
                    return try String(contentsOfFile: path, encoding: .utf8)
                } catch {
                    logger.log("WebView userScript: failed to read bundle resource '\(resourceName)': \(error.localizedDescription)", .warning)
                    return nil
                }
            }
            logger.log("WebView userScript: bundle resource '\(resourceName)' not found", .warning)
            return nil
        }

        return nil
    }

    // MARK: Setup

    private func setupPage() {
        if let userAgent = properties["customUserAgent"] as? String {
            page.customUserAgent = userAgent
        }
    }

    private func loadInitialContent() {
        // model.value holds the result of initialValue(model): the properties["url"] string or
        // a previously persisted URL. Prefer it over re-reading properties directly.
        if let urlString = model.value as? String, !urlString.isEmpty, let url = URL(string: urlString) {
            page.load(URLRequest(url: url))
        } else if let html = properties["html"] as? String {
            // baseURL has a default of "about:blank" in the SDK, but we honour the property when set.
            let baseURL = (properties["baseURL"] as? String).flatMap { URL(string: $0) }
                ?? URL(string: "about:blank")!
            page.load(html: html, baseURL: baseURL)
        }
        // If neither url nor html is provided the page stays blank.
    }

    // MARK: State synchronisation

    private func handleURLChange(_ newURL: URL?) {
        let urlString = newURL?.absoluteString ?? ""
        DispatchQueue.main.async {
            lastTrackedURL = urlString
            model.value = urlString
            model.states["canGoBack"] = !page.backForwardList.backList.isEmpty
            model.states["canGoForward"] = !page.backForwardList.forwardList.isEmpty
            if let actionID = properties["valueChangeActionID"] as? String, !urlString.isEmpty {
                ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
            }
        }
    }

    private func syncNavigationState() {
        DispatchQueue.main.async {
            model.states["isLoading"] = page.isLoading
            model.states["estimatedProgress"] = page.estimatedProgress
            model.states["canGoBack"] = !page.backForwardList.backList.isEmpty
            model.states["canGoForward"] = !page.backForwardList.forwardList.isEmpty
        }
    }

    // MARK: Command handling

    /// Executes navigation commands written to model.value by the host app.
    /// Skips the update if the value matches lastTrackedURL (i.e. it was set by our own
    /// handleURLChange, not by the host app) to prevent feedback loops.
    private func handleCommand(_ command: String?) {
        guard let command, !command.isEmpty, command != lastTrackedURL else { return }

        switch command {
        case "goBack":
            if let backItem = page.backForwardList.backList.last {
                page.load(backItem)
            } else {
                logger.log("WebView goBack: no back item available", .warning)
                resetModelValueToCurrentURL()
            }
        case "goForward":
            if let forwardItem = page.backForwardList.forwardList.first {
                page.load(forwardItem)
            } else {
                logger.log("WebView goForward: no forward item available", .warning)
                resetModelValueToCurrentURL()
            }
        case "reload":
            page.reload()
            resetModelValueToCurrentURL()
        case "stop":
            page.stopLoading()
            resetModelValueToCurrentURL()
        default:
            if let url = URL(string: command) {
                page.load(URLRequest(url: url))
                // model.value will be updated by handleURLChange when navigation completes
            } else {
                logger.log("WebView: unrecognized command or invalid URL '\(command)'; ignoring", .warning)
                resetModelValueToCurrentURL()
            }
        }
    }

    /// Resets model.value back to the current page URL so command strings like "reload" or "stop"
    /// don't linger as the observable value.
    private func resetModelValueToCurrentURL() {
        DispatchQueue.main.async {
            let urlString = page.url?.absoluteString ?? ""
            lastTrackedURL = urlString
            model.value = urlString
        }
    }
}
