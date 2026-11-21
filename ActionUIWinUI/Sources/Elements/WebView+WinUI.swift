// Sources/Elements/WebView+WinUI.swift
/*
 WebView on WinUI: WinUI's WebView2 (the Edge WebView2 runtime Windows ships), as large as it is offered
 in both axes, as a WKWebView in SwiftUI is. It follows ActionUI's native Apple backing and the Linux
 renderer (WebView+Adwaita.swift):
 - Made once from its properties: the first page is the value (the url property) when it is a URL,
   else the html (about:blank as its URL: WebView2 shows a string with no base URL, so baseURL is
   ignored, logged once).
 - Before the first page: customUserAgent and the userScripts, each from its source, its filePath, or
   its resourceName (a file of that name, with or without ".js", in the current folder: Windows has no
   app bundle), injected at documentStart or documentEnd (when the document has been parsed, run as the
   browser runs a page's script, so a page's security policy does not refuse it), into the main frame
   only or all frames (a documentEnd script reaches the main frame's frames, not frames within those).
   A script that cannot be read is skipped and logged.
 - A later value is a command: a URL to load, or #goBack, #goForward, #reload, #stop. A command that
   leaves the page where it is, or a value that is no URL, is replaced by the current URL (logged when
   there is nothing to go back or forward to, or no URL).
 - The value follows the page's URL and fires valueChangeActionID; a change of isLoading fires
   navigationActionID; the states title, isLoading, estimatedProgress (0.1 at a navigation's start, 1
   at its end: WebView2 reports nothing between), canGoBack and canGoForward follow the view. The
   view's changes are handled after the main loop turn they come in, as the Apple backing handles its
   observations in a Task.

 A program showing a WebView needs WebView2's WinRT component, Microsoft.Web.WebView2.Core.dll (the
 microsoft.web.webview2 package's runtimes/win-<arch>/native_uap), beside it, where a WinUI app's build
 puts it; without it the browser fails to start ("The specified module could not be found"), logged
 once per WebView, and the WebView stays empty.

 Ignored: backForwardNavigationGestures and magnificationGestures (WebView2's own: the mouse's back
 and forward buttons, Ctrl and the wheel), and the Apple-only linkPreviews,
 limitsNavigationsToAppBoundDomains and upgradeKnownHostsToHTTPS.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CWinUI
import Dispatch

@MainActor private var reportedBaseURL = false

/// What a WebView's handler compares with, kept in its node's state.
@MainActor final class WebViewState {
    /// The URL the value was last set to from the view, so an update showing it again is no command.
    var lastTrackedURL = ""
    var shown = ActionUIWinUIWebViewState(loading: false, progress: 0, canGoBack: false, canGoForward: false)
    var shownTitle: String?
    var started = false
    /// The browser's start as last logged ("starting", "started", "failed: ...").
    var shownStatus = "starting"
}

extension WebView: ActionUIWinUIRenderer {
    static var defaultExpansion: Expansion { .both }

    static func makeView(_ node: RenderNode) throws(WinUIError) -> WinUIObject {
        guard let view = WinUIObject(adopting: actionUIWinUIWebViewCreate()) else {
            throw WinUIError.last("creating a WebView")
        }
        node.state = WebViewState()
        WinUIEvents.connect(view, actionUIWinUIWebViewOnChanged, "a WebView's page") { [weak node, weak view] in
            // After this turn of the main loop, as the Apple backing's Task.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let node, let view, node.isAttached else { return }
                    pageChanged(view, node)
                }
            }
        }
        return view
    }

    static func update(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? WebViewState else { return }
        if !state.started {
            state.started = true
            start(view, node, state)
            return
        }
        handleCommand(node.model.value as? String, view, node, state)
    }

    /// The settings, the scripts and the first page.
    private static func start(_ view: WinUIObject, _ node: RenderNode, _ state: WebViewState) {
        let props = Props(node.properties)
        let logger = ActionUIModel.shared.logger
        // A browser that neither starts nor fails says nothing on its own: said here after a while.
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5)) { [weak node, weak view, weak state] in
            MainActor.assumeIsolated {
                guard let node, let view, let state, node.isAttached, state.shownStatus == "starting" else { return }
                logStatus(view, node, state)
                if state.shownStatus == "starting" {
                    logger.log("WebView \(node.element.id): the browser has not started after 5 seconds", .warning)
                }
            }
        }
        if let userAgent = props.customUserAgent, !actionUIWinUIWebViewSetUserAgent(view.pointer, userAgent) {
            logger.log("WebView: \(WinUIError.last("setting the user agent"))", .error)
        }
        for script in props.userScripts {
            guard let source = scriptSource(script) else { continue }
            if !actionUIWinUIWebViewAddScript(view.pointer, source, script.injectionTime == .documentEnd, script.forMainFrameOnly) {
                logger.log("WebView: \(WinUIError.last("adding a user script"))", .error)
            }
        }
        if let urlString = node.model.value as? String, isLoadable(urlString) {
            state.lastTrackedURL = urlString
            if !actionUIWinUIWebViewNavigate(view.pointer, urlString) {
                logger.log("WebView: \(WinUIError.last("loading \(urlString)"))", .error)
            }
        } else if let html = props.html {
            if props.baseURL != nil, !reportedBaseURL {
                reportedBaseURL = true
                logger.log("WebView: baseURL is not used on Windows yet (WebView2 shows an HTML string without one)", .warning)
            }
            if !actionUIWinUIWebViewNavigateToString(view.pointer, html) {
                logger.log("WebView: \(WinUIError.last("showing the html"))", .error)
            }
        }
    }

    /// Whether `text` is a URL the web view can load: absolute, with a scheme ("foo" is a relative URL
    /// to Foundation, which WebView2 refuses).
    static func isLoadable(_ text: String) -> Bool {
        URL(string: text)?.scheme.map { !$0.isEmpty } ?? false
    }

    /// A user script's JavaScript: its source, else its file, else its resource (a file of that name in
    /// the current folder); nil, logged, when it cannot be read.
    static func scriptSource(_ script: Props.UserScript) -> String? {
        let logger = ActionUIModel.shared.logger
        // Only a regular file: a device or a named pipe the document names would block the window.
        func read(_ path: String) -> String? {
            (try? ActionUIDocumentLoader.readRegularFile(URL(fileURLWithPath: path))).map { String(decoding: $0, as: UTF8.self) }
        }
        if let source = script.source {
            return source
        }
        if let filePath = script.filePath {
            guard let source = read(filePath) else {
                logger.log("WebView userScript: failed to read file at '\(filePath)'", .warning)
                return nil
            }
            return source
        }
        if let resourceName = script.resourceName {
            let name = resourceName.lowercased().hasSuffix(".js") ? resourceName : resourceName + ".js"
            guard let source = read(name) ?? read(resourceName) else {
                logger.log("WebView userScript: resource '\(resourceName)' not found", .warning)
                return nil
            }
            return source
        }
        return nil
    }

    private static func handleCommand(_ command: String?, _ view: WinUIObject, _ node: RenderNode, _ state: WebViewState) {
        guard let command, !command.isEmpty, command != state.lastTrackedURL else { return }
        let logger = ActionUIModel.shared.logger
        var page = ActionUIWinUIWebViewState(loading: false, progress: 0, canGoBack: false, canGoForward: false)
        _ = actionUIWinUIWebViewGetState(view.pointer, &page)
        func run(_ what: ActionUIWinUIWebViewCommand) {
            if !actionUIWinUIWebViewRun(view.pointer, what) {
                logger.log("WebView: \(WinUIError.last("running \(command)"))", .error)
            }
        }
        switch command {
        case "#goBack":
            if page.canGoBack {
                run(ActionUIWinUIWebViewGoBack)
            } else {
                logger.log("WebView goBack: no back item available", .warning)
                resetValueToCurrentURL(after: command, view, node, state)
            }
        case "#goForward":
            if page.canGoForward {
                run(ActionUIWinUIWebViewGoForward)
            } else {
                logger.log("WebView goForward: no forward item available", .warning)
                resetValueToCurrentURL(after: command, view, node, state)
            }
        case "#reload":
            run(ActionUIWinUIWebViewReload)
            resetValueToCurrentURL(after: command, view, node, state)
        case "#stop":
            run(ActionUIWinUIWebViewStop)
            resetValueToCurrentURL(after: command, view, node, state)
        default:
            if isLoadable(command) {
                if !actionUIWinUIWebViewNavigate(view.pointer, command) {
                    logger.log("WebView: \(WinUIError.last("loading \(command)"))", .error)
                }
            } else {
                logger.log("WebView: unrecognized command or invalid URL '\(command)'; ignoring", .warning)
                resetValueToCurrentURL(after: command, view, node, state)
            }
        }
    }

    /// The page's URL, "" when there is none yet.
    private static func currentURL(_ view: WinUIObject) -> String {
        guard let copy = actionUIWinUIWebViewCopyURL(view.pointer) else { return "" }
        defer { actionUIWinUIFreeString(copy) }
        return String(cString: copy)
    }

    /// The value back to the page's URL after a command that leaves the page where it is, after this
    /// update (unless the value changed again by then).
    private static func resetValueToCurrentURL(after command: String, _ view: WinUIObject, _ node: RenderNode, _ state: WebViewState) {
        let urlString = currentURL(view)
        state.lastTrackedURL = urlString
        let model = node.model
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if model.value as? String == command {
                    model.value = urlString
                }
            }
        }
    }

    /// The page changed: the value, the states and the actions follow it.
    /// Logs the browser's start when it changed: started, or failed and why.
    private static func logStatus(_ view: WinUIObject, _ node: RenderNode, _ state: WebViewState) {
        guard let copy = actionUIWinUIWebViewCopyStatus(view.pointer) else { return }
        let status = String(cString: copy)
        actionUIWinUIFreeString(copy)
        guard status != state.shownStatus else { return }
        state.shownStatus = status
        ActionUIModel.shared.logger.log("WebView \(node.element.id): the browser \(status)", status.hasPrefix("failed") ? .error : .info)
    }

    private static func pageChanged(_ view: WinUIObject, _ node: RenderNode) {
        guard let state = node.state as? WebViewState else { return }
        logStatus(view, node, state)
        let props = Props(node.properties)
        let windowUUID = node.windowModel.windowUUID
        var page = ActionUIWinUIWebViewState(loading: false, progress: 0, canGoBack: false, canGoForward: false)
        // Fails once the browser could not start (no WebView2 runtime): the change that reports it.
        guard actionUIWinUIWebViewGetState(view.pointer, &page) else {
            ActionUIModel.shared.logger.log("WebView: \(WinUIError.last("reading the page"))", .error)
            return
        }
        let urlString = currentURL(view)
        if !urlString.isEmpty, urlString != state.lastTrackedURL {
            state.lastTrackedURL = urlString
            node.model.value = urlString
            if let actionID = props.valueChangeActionID {
                ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: node.element.id, viewPartID: 0)
            }
        }
        if page.canGoBack != state.shown.canGoBack || page.canGoForward != state.shown.canGoForward {
            node.model.states["canGoBack"] = page.canGoBack
            node.model.states["canGoForward"] = page.canGoForward
        }
        if page.progress != state.shown.progress {
            node.model.states["estimatedProgress"] = page.progress
        }
        let loadingChanged = page.loading != state.shown.loading
        state.shown = page
        if loadingChanged {
            node.model.states["isLoading"] = page.loading
            if let actionID = props.navigationActionID {
                ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: node.element.id, viewPartID: 0)
            }
        }
        if let copy = actionUIWinUIWebViewCopyTitle(view.pointer) {
            let title = String(cString: copy)
            actionUIWinUIFreeString(copy)
            if title != state.shownTitle {
                state.shownTitle = title
                node.model.states["title"] = title
            }
        }
    }
}
