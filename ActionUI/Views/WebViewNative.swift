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
    /// `readsFile`: whether a script file may be read (the element's trust); the host's own
    /// properties read any.
    static func buildUserScripts(from properties: [String: Any], logger: any ActionUILogger,
                                 readsFile: (String) -> Bool = { _ in true }) -> [WKUserScript] {
        buildUserScripts(WebView.Props(properties).userScripts, logger: logger, readsFile: readsFile)
    }

    /// Builds WKUserScript objects from the parsed scripts.
    static func buildUserScripts(_ scripts: [WebView.Props.UserScript], logger: any ActionUILogger,
                                 readsFile: (String) -> Bool) -> [WKUserScript] {
        var result: [WKUserScript] = []
        for script in scripts {
            guard let source = resolveJSSource(from: script, logger: logger, readsFile: readsFile) else { continue }
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
    static func resolveJSSource(from descriptor: [String: Any], logger: any ActionUILogger,
                                readsFile: (String) -> Bool = { _ in true }) -> String? {
        resolveJSSource(from: WebView.Props.UserScript(descriptor), logger: logger, readsFile: readsFile)
    }

    /// The UTF-8 text of the regular file at `path` (symbolic links followed), for a resourceName:
    /// a link in the bundle could still lead to a device or a pipe, which would never finish (or
    /// never begin) reading on the main thread.
    private static func regularFileText(_ path: String) throws -> String {
        let data = try ActionUIDocumentLoader.readRegularFile(URL(fileURLWithPath: path))
        guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        return text
    }

    /// Resolves the JavaScript source string from a parsed script.
    /// Mirrors the Image.swift resourceName / filePath / source pattern.
    /// A filePath script is read only when `readsFile` allows it (the element's trust; a refusal
    /// is logged by the check). A resourceName is the app's own and is not asked about.
    static func resolveJSSource(from script: WebView.Props.UserScript, logger: any ActionUILogger,
                                readsFile: (String) -> Bool) -> String? {
        if let source = script.source {
            return source
        }

        if let filePath = script.filePath {
            guard readsFile(filePath) else { return nil }
            do {
                // Only a regular file: a device or a pipe named by the document would block.
                let data = try ActionUIDocumentLoader.readRegularFile(URL(fileURLWithPath: filePath))
                guard let text = String(data: data, encoding: .utf8) else {
                    logger.log("WebView userScript: the file at '\(filePath)' is not UTF-8 text", .warning)
                    return nil
                }
                return text
            } catch {
                logger.log("WebView userScript: failed to read file at '\(filePath)': \(error.localizedDescription)", .warning)
                return nil
            }
        }

        if let resourceName = script.resourceName {
            // Strip .js extension to use Bundle path(forResource:ofType:)
            let nameWithoutExt = resourceName.lowercased().hasSuffix(".js") ? String(resourceName.dropLast(3)) : resourceName
            // The host's resource folder (ActionUIResourceFolder) first, then the main bundle.
            if let path = ActionUIResourceFolder.file(nameWithoutExt + ".js") ?? ActionUIResourceFolder.file(resourceName)
                ?? ActionUIResourceFolder.bundlePath(forResource: nameWithoutExt, ofType: "js") {
                do {
                    return try regularFileText(path)
                } catch {
                    logger.log("WebView userScript: failed to read bundle resource '\(resourceName)': \(error.localizedDescription)", .warning)
                    return nil
                }
            }
            // Fallback: try the name as-is (e.g. "MyScript" without extension, or unusual extension)
            if let path = ActionUIResourceFolder.bundlePath(forResource: resourceName, ofType: nil) {
                do {
                    return try regularFileText(path)
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
    static func makeWKConfiguration(properties: [String: Any], logger: any ActionUILogger,
                                    allows: (ActionUICapability) -> Bool = { _ in true },
                                    readsFile: (String) -> Bool = { _ in true }) -> WKWebViewConfiguration {
        makeWKConfiguration(props: WebView.Props(properties), logger: logger, allows: allows, readsFile: readsFile)
    }

    /// Builds a WKWebViewConfiguration for the native backing from parsed properties. `allows`:
    /// the trust policy's answer for the WebView's element; content that may not run its user
    /// scripts gets none, and content that may not keep the app's data store a private one.
    static func makeWKConfiguration(props: WebView.Props, logger: any ActionUILogger,
                                    allows: (ActionUICapability) -> Bool,
                                    readsFile: (String) -> Bool) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        if !WebViewTrust.keepsPersistentData(allows: allows) {
            config.websiteDataStore = .nonPersistent()
        }

        if let limits = props.limitsNavigationsToAppBoundDomains {
            config.limitsNavigationsToAppBoundDomains = limits
        }
        if let upgrade = props.upgradeKnownHostsToHTTPS {
            config.upgradeKnownHostsToHTTPS = upgrade
        }

        let runsScripts = WebViewTrust.runsUserScripts(count: props.userScripts.count, allows: allows, logger: logger)
        let scripts = runsScripts ? buildUserScripts(props.userScripts, logger: logger, readsFile: readsFile) : []
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
    let model: ViewModel
    let props: WebView.Props
    let element: any ActionUIElementBase
    let windowUUID: String
    let logger: any ActionUILogger

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, props: props, element: element, windowUUID: windowUUID, logger: logger)
    }

    /// Creates and configures the WKWebView, attaches the coordinator, and loads initial content.
    private func makeWebView(context: Context) -> WKWebView {
        // Whose trust this WebView has: in a template row, the container's (the row has no view model).
        let trustID = model.templateContext?.parentID ?? element.id
        let config = WebViewSupport.makeWKConfiguration(
            props: props, logger: logger,
            allows: { [windowUUID] in ActionUIModel.shared.allows($0, windowUUID: windowUUID, viewID: trustID) },
            readsFile: { [windowUUID] in ActionUIModel.shared.readsScriptFile($0, windowUUID: windowUUID, viewID: trustID) })
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

    /// Forwards SwiftUI update passes (triggered when model.value, read here, changes) to the coordinator,
    /// which interprets any new model.value as a navigation command.
    private func updateWebView(context: Context) {
        context.coordinator.updateNavigationDelegate()
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
    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        let model: ViewModel
        let props: WebView.Props
        let element: any ActionUIElementBase
        let windowUUID: String
        let logger: any ActionUILogger

        /// Whose trust this WebView has: in a template row, the container's (the row has no view model).
        private var trustID: Int { model.templateContext?.parentID ?? element.id }

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
            updateNavigationDelegate()

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
            webView?.navigationDelegate = nil
            webView = nil
        }

        // MARK: Navigation (less-trusted content only)

        /// Less-trusted content (or content of unknown origin): its page's navigations are decided
        /// here. Without a navigation delegate WebKit hands an address it cannot load to another
        /// app, which would let the page open any app's own scheme. Trusted content keeps WebKit's
        /// default handling, so it has no delegate. Asked again on each update: a LoadableView that
        /// loads another document can keep this WKWebView for an element of the same id whose
        /// origin differs.
        func updateNavigationDelegate() {
            guard let webView else { return }
            let lessTrusted = ActionUIModel.shared.origin(windowUUID: windowUUID, viewID: trustID)?.trust != .trusted
            if lessTrusted {
                if webView.navigationDelegate !== self { webView.navigationDelegate = self }
            } else if webView.navigationDelegate === self {
                webView.navigationDelegate = nil
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            switch WebViewTrust.navigation(url, isMainFrame: isMainFrame, allows: allows, logger: logger) {
            case .load:
                decisionHandler(.allow)
            case .open:
                decisionHandler(.cancel)
                #if canImport(AppKit) && !targetEnvironment(macCatalyst)
                NSWorkspace.shared.open(url)
                #elseif canImport(UIKit)
                UIApplication.shared.open(url)
                #endif
            case .refuse:
                decisionHandler(.cancel)
            }
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
                // about:blank unless baseURL is set and the trust policy allows it.
                let baseURL = WebViewTrust.base(props.baseURL.flatMap { URL(string: $0) }, allows: allows, logger: logger)
                webView.loadHTMLString(html, baseURL: baseURL)
            }
            // If neither url nor html is provided the page stays blank.
        }

        /// The trust policy's answer for this WebView's element.
        private func allows(_ capability: ActionUICapability) -> Bool {
            ActionUIModel.shared.allows(capability, windowUUID: windowUUID, viewID: trustID)
        }

        /// Loads a URL, using loadFileURL for file URLs so local resources are granted read access;
        /// the "Blocked" page instead when the trust policy refuses the address (false then).
        @discardableResult
        private func load(_ url: URL, into webView: WKWebView) -> Bool {
            guard WebViewTrust.showsAddress(url, allows: allows, logger: logger) else {
                webView.loadHTMLString(WebViewTrust.blockedPage(url), baseURL: WebViewTrust.blankBase)
                return false
            }
            if url.isFileURL {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            } else {
                webView.load(URLRequest(url: url))
            }
            return true
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
                ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, model: model)
            }
        }

        private func handleLoadingChange() {
            guard let webView else { return }
            model.states["isLoading"] = webView.isLoading
            model.states["estimatedProgress"] = webView.estimatedProgress
            syncBackForwardState()
            if let navActionID = props.navigationActionID {
                ActionUIModel.shared.actionHandler(navActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, model: model)
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
                    resetModelValueToCurrentURL(after: command)
                }
            case "#goForward":
                if webView.canGoForward {
                    webView.goForward()
                } else {
                    logger.log("WebView goForward: no forward item available", .warning)
                    resetModelValueToCurrentURL(after: command)
                }
            case "#reload":
                webView.reload()
                resetModelValueToCurrentURL(after: command)
            case "#stop":
                webView.stopLoading()
                resetModelValueToCurrentURL(after: command)
            default:
                if let url = URL(string: command) {
                    // model.value will be updated by handleURLChange when navigation completes. A
                    // refused address leaves the URL where it is when the page already was at
                    // about:blank, so no change comes, and every update pass would load it again.
                    if !load(url, into: webView) {
                        resetModelValueToCurrentURL(after: command)
                    }
                } else {
                    logger.log("WebView: unrecognized command or invalid URL '\(command)'; ignoring", .warning)
                    resetModelValueToCurrentURL(after: command)
                }
            }
        }

        /// Resets model.value back to the current page URL so command strings like "#reload" or "#stop"
        /// don't linger as the observable value.
        private func resetModelValueToCurrentURL(after command: String) {
            let urlString = webView?.url?.absoluteString ?? ""
            lastTrackedURL = urlString
            // Deferred: this runs inside updateNSView / updateUIView, which read model.value, and a
            // write there would invalidate the update that is running. Skipped if the host has set
            // another value meanwhile.
            DispatchQueue.main.async { [model] in
                if model.value as? String == command {
                    model.value = urlString
                }
            }
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
