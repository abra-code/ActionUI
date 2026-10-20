// Sources/Views/WebViewNative.swift
//
// Native WKWebView backing for ActionUI.WebView.
//
// The SwiftUI WebKit.WebView used by WebViewContent (see WebView.swift) requires
// iOS 26.0+ / macOS 26.0+ and has a crash when the in-page find UI is open while the
// view is torn down (FB22343526).
// This file provides an alternative implementation built directly on WKWebView
// via NS/UIViewRepresentable, which works on the package's baseline OS versions
// (macOS 14.6+ / iOS 17.6+) and avoids that crash.
//
// Selection between the two backings is global: ActionUIRegistry.shared.webViewImplementation
// (defaults to .native). See WebView.swift for the dispatch in buildView.
//
// Both backings share the same observable surface (model.value = current URL / navigation
// command, states["title"|"isLoading"|"estimatedProgress"|"canGoBack"|"canGoForward"]) and
// honour the same properties, so they are interchangeable from the host app's perspective.

import SwiftUI
import WebKit

// MARK: - Shared support

/// Configuration helpers shared by the native (WKWebView) and SwiftUI (WebPage) backings.
/// Keeping these here avoids duplicating user-script resolution between the two code paths.
/// Main-actor isolated: it constructs main-actor WebKit objects (WKWebViewConfiguration,
/// WKUserScript, WKUserContentController); both call sites are already on the main actor.
@MainActor
enum WebViewSupport {
    /// Builds WKUserScript objects from the raw properties' `userScripts` array.
    /// Returns an empty array when no (valid) scripts are present.
    static func buildUserScripts(from properties: [String: Any], logger: any ActionUILogger) -> [WKUserScript] {
        buildUserScripts(WebView.Props(properties).userScripts, logger: logger)
    }

    /// Builds WKUserScript objects from the parsed scripts.
    static func buildUserScripts(_ scripts: [WebView.Props.UserScript], logger: any ActionUILogger) -> [WKUserScript] {
        var result: [WKUserScript] = []
        for script in scripts {
            guard let source = resolveJSSource(from: script, logger: logger) else { continue }
            let injectionTime: WKUserScriptInjectionTime
            switch script.injectionTime {
            case .documentStart: injectionTime = .atDocumentStart
            case .documentEnd: injectionTime = .atDocumentEnd
            }
            result.append(WKUserScript(source: source, injectionTime: injectionTime, forMainFrameOnly: script.forMainFrameOnly))
        }
        return result
    }

    /// Resolves the JavaScript source string from a script descriptor dictionary.
    static func resolveJSSource(from descriptor: [String: Any], logger: any ActionUILogger) -> String? {
        resolveJSSource(from: WebView.Props.UserScript(descriptor), logger: logger)
    }

    /// Resolves the JavaScript source string from a parsed script.
    /// Mirrors the Image.swift resourceName / filePath / source pattern.
    static func resolveJSSource(from script: WebView.Props.UserScript, logger: any ActionUILogger) -> String? {
        if let source = script.source {
            return source
        }

        if let filePath = script.filePath {
            do {
                return try String(contentsOfFile: filePath, encoding: .utf8)
            } catch {
                logger.log("WebView userScript: failed to read file at '\(filePath)': \(error.localizedDescription)", .warning)
                return nil
            }
        }

        if let resourceName = script.resourceName {
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

    /// Builds a WKWebViewConfiguration for the native backing from raw properties.
    static func makeWKConfiguration(properties: [String: Any], logger: any ActionUILogger) -> WKWebViewConfiguration {
        makeWKConfiguration(props: WebView.Props(properties), logger: logger)
    }

    /// Builds a WKWebViewConfiguration for the native backing from parsed properties.
    static func makeWKConfiguration(props: WebView.Props, logger: any ActionUILogger) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()

        if let limits = props.limitsNavigationsToAppBoundDomains {
            config.limitsNavigationsToAppBoundDomains = limits
        }
        if let upgrade = props.upgradeKnownHostsToHTTPS {
            config.upgradeKnownHostsToHTTPS = upgrade
        }

        let scripts = buildUserScripts(props.userScripts, logger: logger)
        if !scripts.isEmpty {
            let userContentController = WKUserContentController()
            for script in scripts {
                userContentController.addUserScript(script)
            }
            config.userContentController = userContentController
        }

        return config
    }
}

// MARK: - Native representable

/// SwiftUI wrapper around a UIKit/AppKit WKWebView. Conforms to NSViewRepresentable on macOS
/// and UIViewRepresentable elsewhere; the Coordinator (shared between both) owns the WKWebView's
/// delegates, KVO observers, and the model synchronisation logic.
@MainActor
struct WKWebViewRepresentable {
    @ObservedObject var model: ViewModel
    let props: WebView.Props
    let element: any ActionUIElementBase
    let windowUUID: String
    let logger: any ActionUILogger

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, props: props, element: element, windowUUID: windowUUID, logger: logger)
    }

    /// Creates and configures the WKWebView, attaches the coordinator, and loads initial content.
    private func makeWebView(context: Context) -> WKWebView {
        let config = WebViewSupport.makeWKConfiguration(props: props, logger: logger)
        let webView = WKWebView(frame: .zero, configuration: config)

        if let userAgent = props.customUserAgent {
            webView.customUserAgent = userAgent
        }

        let backForward = props.backForwardNavigationGestures
        webView.allowsBackForwardNavigationGestures = backForward

        let linkPreviews = props.linkPreviews
        webView.allowsLinkPreview = linkPreviews

        #if os(macOS)
        let magnification = props.magnificationGestures
        webView.allowsMagnification = magnification
        #endif

        context.coordinator.attach(to: webView)
        context.coordinator.loadInitialContent()
        return webView
    }

    /// Forwards SwiftUI update passes (triggered by @Published model changes) to the coordinator,
    /// which interprets any new model.value as a navigation command.
    private func updateWebView(context: Context) {
        context.coordinator.handleCommand(model.value as? String)
    }
}

#if os(macOS)
import AppKit

extension WKWebViewRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateNSView(_ nsView: WKWebView, context: Context) { updateWebView(context: context) }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.invalidate()
    }
}
#else
import UIKit

extension WKWebViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { makeWebView(context: context) }
    func updateUIView(_ uiView: WKWebView, context: Context) { updateWebView(context: context) }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.invalidate()
    }
}
#endif

// MARK: - Coordinator

extension WKWebViewRepresentable {
    /// Owns the WKWebView's lifecycle observers and bridges WebKit state to the ViewModel.
    /// KVO is used for all observable values (url, title, loading, progress, back/forward) so the
    /// behaviour matches WebViewContent's onChange-driven SwiftUI backing.
    @MainActor
    final class Coordinator: NSObject, WKUIDelegate {
        let model: ViewModel
        let props: WebView.Props
        let element: any ActionUIElementBase
        let windowUUID: String
        let logger: any ActionUILogger

        /// The last URL we pushed into model.value ourselves, so handleCommand can distinguish our own
        /// programmatic updates from host-app navigation commands (mirrors WebViewContent.lastTrackedURL).
        private var lastTrackedURL: String = ""
        private weak var webView: WKWebView?
        private var observations: [NSKeyValueObservation] = []

        init(model: ViewModel, props: WebView.Props, element: any ActionUIElementBase, windowUUID: String, logger: any ActionUILogger) {
            self.model = model
            self.props = props
            self.element = element
            self.windowUUID = windowUUID
            self.logger = logger
        }

        deinit {
            // observations invalidate themselves on dealloc, but be explicit for clarity.
            observations.forEach { $0.invalidate() }
        }

        // MARK: Attachment

        func attach(to webView: WKWebView) {
            self.webView = webView
            webView.uiDelegate = self

            // KVO closures are invoked on the main thread for WKWebView, but the change handler is
            // not statically MainActor-isolated, so we hop onto the MainActor before touching state.
            observations = [
                webView.observe(\.url) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.handleURLChange() }
                },
                webView.observe(\.isLoading) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.handleLoadingChange() }
                },
                webView.observe(\.estimatedProgress) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.handleProgressChange() }
                },
                webView.observe(\.title) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.handleTitleChange() }
                },
                webView.observe(\.canGoBack) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.syncBackForwardState() }
                },
                webView.observe(\.canGoForward) { [weak self] _, _ in
                    Task { @MainActor [weak self] in self?.syncBackForwardState() }
                },
            ]
        }

        func invalidate() {
            observations.forEach { $0.invalidate() }
            observations.removeAll()
            webView?.uiDelegate = nil
            webView = nil
        }

        // MARK: Initial content

        func loadInitialContent() {
            guard let webView else { return }
            // model.value holds initialValue(model): the properties["url"] string or a persisted URL.
            if let urlString = model.value as? String, !urlString.isEmpty, let url = URL(string: urlString) {
                // Seed lastTrackedURL so the first updateNSView/updateUIView pass (which sees this same
                // value in model.value) doesn't re-load the page as if it were a host command.
                lastTrackedURL = urlString
                load(url, into: webView)
            } else if let html = props.html {
                let baseURL = props.baseURL.flatMap { URL(string: $0) }
                    ?? URL(string: "about:blank")!
                webView.loadHTMLString(html, baseURL: baseURL)
            }
            // If neither url nor html is provided the page stays blank.
        }

        /// Loads a URL, using loadFileURL for file URLs so local resources are granted read access.
        private func load(_ url: URL, into webView: WKWebView) {
            if url.isFileURL {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                webView.load(URLRequest(url: url))
            }
        }

        // MARK: State synchronisation

        private func handleURLChange() {
            guard let webView else { return }
            let urlString = webView.url?.absoluteString ?? ""
            lastTrackedURL = urlString
            model.value = urlString
            model.states["canGoBack"] = webView.canGoBack
            model.states["canGoForward"] = webView.canGoForward
            if let actionID = props.valueChangeActionID, !urlString.isEmpty {
                ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
            }
        }

        private func handleLoadingChange() {
            guard let webView else { return }
            model.states["isLoading"] = webView.isLoading
            model.states["estimatedProgress"] = webView.estimatedProgress
            syncBackForwardState()
            if let navActionID = props.navigationActionID {
                ActionUIModel.shared.actionHandler(navActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0)
            }
        }

        private func handleProgressChange() {
            guard let webView else { return }
            model.states["estimatedProgress"] = webView.estimatedProgress
        }

        private func handleTitleChange() {
            model.states["title"] = webView?.title
        }

        private func syncBackForwardState() {
            guard let webView else { return }
            model.states["canGoBack"] = webView.canGoBack
            model.states["canGoForward"] = webView.canGoForward
        }

        // MARK: Command handling

        /// Executes navigation commands written to model.value by the host app.
        /// Skips the update when the value matches lastTrackedURL (i.e. it was set by our own
        /// handleURLChange, not by the host app) to prevent feedback loops.
        func handleCommand(_ command: String?) {
            guard let webView, let command, !command.isEmpty, command != lastTrackedURL else { return }

            switch command {
            case "#goBack":
                if webView.canGoBack {
                    webView.goBack()
                } else {
                    logger.log("WebView goBack: no back item available", .warning)
                    resetModelValueToCurrentURL()
                }
            case "#goForward":
                if webView.canGoForward {
                    webView.goForward()
                } else {
                    logger.log("WebView goForward: no forward item available", .warning)
                    resetModelValueToCurrentURL()
                }
            case "#reload":
                webView.reload()
                resetModelValueToCurrentURL()
            case "#stop":
                webView.stopLoading()
                resetModelValueToCurrentURL()
            default:
                if let url = URL(string: command) {
                    load(url, into: webView)
                    // model.value will be updated by handleURLChange when navigation completes
                } else {
                    logger.log("WebView: unrecognized command or invalid URL '\(command)'; ignoring", .warning)
                    resetModelValueToCurrentURL()
                }
            }
        }

        /// Resets model.value back to the current page URL so command strings like "#reload" or "#stop"
        /// don't linger as the observable value.
        private func resetModelValueToCurrentURL() {
            let urlString = webView?.url?.absoluteString ?? ""
            lastTrackedURL = urlString
            model.value = urlString
        }

        // MARK: WKUIDelegate

        #if os(macOS)
        func webView(_ webView: WKWebView,
                     runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping @MainActor ([URL]?) -> Void) {
            let openPanel = NSOpenPanel()
            openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
            openPanel.canChooseDirectories = parameters.allowsDirectories
            openPanel.canChooseFiles = true
            openPanel.begin { result in
                MainActor.assumeIsolated {
                    completionHandler(result == .OK ? openPanel.urls : nil)
                }
            }
        }
        #endif
    }
}
