// SwiftUI rendering of WebView; its portable part is in Core/Elements/WebView.swift.

import SwiftUI
import WebKit

extension WebView: ActionUISwiftUIRenderer {
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, _, _, _, _ in view }

    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        let props = Props(properties)
        let native = WKWebViewRepresentable(
            model: model,
            props: props,
            element: element,
            windowUUID: windowUUID,
            logger: logger
        )

        switch ActionUIRegistry.shared.webViewImplementation {
        case .native:
            return native
        case .swiftUI:
            if #available(iOS 26.0, macOS 26.0, *) {
                return WebViewContent(
                    model: model,
                    props: props,
                    element: element,
                    windowUUID: windowUUID,
                    logger: logger
                )
            } else {
                logger.log("WebView .swiftUI backing requires iOS 26 / macOS 26; falling back to .native", .warning)
                return native
            }
        }
    }
}

// MARK: - WebViewContent

@available(iOS 26.0, macOS 26.0, *)
private struct WebViewContent: SwiftUI.View {
    @State private var page: WebPage
    /// Tracks the last URL we pushed into model.value ourselves, so we can distinguish
    /// programmatic URL updates from host-app navigation commands in onChange(of: commandValue).
    @State private var lastTrackedURL: String
    let model: ViewModel
    let props: WebView.Props
    let element: any ActionUIElementBase
    let windowUUID: String
    let logger: any ActionUILogger

    init(model: ViewModel, props: WebView.Props, element: any ActionUIElementBase, windowUUID: String, logger: any ActionUILogger) {
        self.model = model
        self.props = props
        self.element = element
        self.windowUUID = windowUUID
        self.logger = logger
        _page = State(initialValue: WebPage(configuration: WebViewContent.makeConfiguration(props: props, logger: logger)))
        _lastTrackedURL = State(initialValue: "")
    }

    /// A convenience accessor for the current model value cast to String.
    private var commandValue: String? { model.value as? String }

    var body: some SwiftUI.View {
        let _ = model.trackAllChanges()
        makeWebView()
            // URL changed – update state and fire valueChangeActionID
            .onChange(of: page.url, initial: false) { _, newURL in
                handleURLChange(newURL)
            }
            // Loading state changed – sync progress/navigation state and fire navigationActionID
            .onChange(of: page.isLoading) { _, _ in
                syncNavigationState()
                if let navActionID = props.navigationActionID {
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
        let backForward = props.backForwardNavigationGestures
        let magnification = props.magnificationGestures
        let linkPreviews = props.linkPreviews
        // WebKit.WebView refers to the SDK's SwiftUI WebView type (from _WebKit_SwiftUI overlay).
        // The explicit module prefix disambiguates from our own ActionUI.WebView struct.
        WebKit.WebView(page)
            .webViewBackForwardNavigationGestures(backForward ? .enabled : .disabled)
            .webViewMagnificationGestures(magnification ? .enabled : .disabled)
            .webViewLinkPreviews(linkPreviews ? .enabled : .disabled)
    }

    // MARK: Configuration

    /// Builds a WebPage.Configuration from the parsed properties.
    /// Called once at init time so user scripts survive page reloads within the same view lifetime.
    private static func makeConfiguration(props: WebView.Props, logger: any ActionUILogger) -> WebPage.Configuration {
        var config = WebPage.Configuration()

        if let limits = props.limitsNavigationsToAppBoundDomains {
            config.limitsNavigationsToAppBoundDomains = limits
        }

        if let upgrade = props.upgradeKnownHostsToHTTPS {
            config.upgradeKnownHostsToHTTPS = upgrade
        }

        let scripts = WebViewSupport.buildUserScripts(props.userScripts, logger: logger)
        if !scripts.isEmpty {
            let userContentController = WKUserContentController()
            for script in scripts {
                userContentController.addUserScript(script)
            }
            config.userContentController = userContentController
        }

        return config
    }

    // MARK: Setup

    private func setupPage() {
        if let userAgent = props.customUserAgent {
            page.customUserAgent = userAgent
        }
    }

    private func loadInitialContent() {
        // model.value holds the result of initialValue(model): the properties["url"] string or
        // a previously persisted URL. Prefer it over re-reading properties directly.
        if let urlString = model.value as? String, !urlString.isEmpty, let url = URL(string: urlString) {
            page.load(URLRequest(url: url))
        } else if let html = props.html {
            // baseURL has a default of "about:blank" in the SDK, but we honour the property when set.
            let baseURL = props.baseURL.flatMap { URL(string: $0) }
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
            if let actionID = props.valueChangeActionID, !urlString.isEmpty {
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
        case "#goBack":
            if let backItem = page.backForwardList.backList.last {
                page.load(backItem)
            } else {
                logger.log("WebView goBack: no back item available", .warning)
                resetModelValueToCurrentURL()
            }
        case "#goForward":
            if let forwardItem = page.backForwardList.forwardList.first {
                page.load(forwardItem)
            } else {
                logger.log("WebView goForward: no forward item available", .warning)
                resetModelValueToCurrentURL()
            }
        case "#reload":
            page.reload()
            resetModelValueToCurrentURL()
        case "#stop":
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

