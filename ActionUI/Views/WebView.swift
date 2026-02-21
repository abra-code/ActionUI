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
     "valueChangeActionID": "onURLChange",    // Optional: Fired when URL changes after a navigation completes
     "navigationActionID": "onNavigation"     // Optional: Fired when isLoading changes (navigation started / finished)
   }
 }

 Note: WebView requires iOS 26.0+ / macOS 26.0+. On older OS versions a fallback Label is shown instead.

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

        if let navActionID = validated["navigationActionID"], !(navActionID is String) {
            logger.log("WebView navigationActionID must be a String; ignoring", .warning)
            validated["navigationActionID"] = nil
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
    @State private var page = WebPage()
    /// Tracks the last URL we pushed into model.value ourselves, so we can distinguish
    /// programmatic URL updates from host-app navigation commands in onChange(of: commandValue).
    @State private var lastTrackedURL: String = ""
    @ObservedObject var model: ViewModel
    let properties: [String: Any]
    let element: any ActionUIElementBase
    let windowUUID: String
    let logger: any ActionUILogger

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
