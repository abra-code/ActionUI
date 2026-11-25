// Sources/Elements/WebView+WinUI.swift
/*
 WebView on WinUI: WinUI's WebView2 (the Edge WebView2 runtime Windows ships), as large as it is offered
 in both axes, as a WKWebView in SwiftUI is. It follows ActionUI's native Apple backing and the Linux
 renderer (WebView+Adwaita.swift):
 - Made once from its properties: the first page is the value (the url property) when it is a URL,
   else the html, under its baseURL as WebKit's loadHTMLString(_:baseURL:) puts it (the page is that
   address: its origin, and relative links resolved against it; the web view goes to the base and is
   answered with the html once), else about:blank. Only an http or https base is used (WebView2 answers
   no file: request with the html; another base is logged once and the html shown without one).
 - Before the first page: customUserAgent and the userScripts, each from its source, its filePath, or
   its resourceName (a file of that name, with or without ".js", in the current folder: Windows has no
   app bundle), injected at documentStart or documentEnd (when the document has been parsed, run as the
   browser runs a page's script, so a page's security policy does not refuse it), into the main frame
   only or all frames (a documentEnd script reaches the main frame's frames, not frames within those).
   A script that cannot be read is skipped and logged.
 - Less-trusted content (ActionUI JSON from a server or from a file outside the app's resources), by
   the host's trust policy, as on Apple and Linux: shows only http and https addresses (.webView), a
   "Blocked" page in place of another, first or set later; runs none of its user scripts
   (.webViewUserScripts), and when a host's policy lets it run them, reads a user script's file only inside
   the app's resources (.webViewScriptFile), a script named by resource too, since Windows reads it
   from the current folder; its html keeps a base address only on the origin its JSON came from
   (.webViewBaseURL, Core's WebViewTrust.base), else about:blank, so it never runs as another site.
   Each navigation of its page (a link, a script, a form, a redirect, a frame) is decided as on Apple
   (WebViewTrust.navigation, for the element's origin at that moment): web addresses the policy shows
   and the page's own about, data and blob addresses load; another scheme is handed to its app only
   for the page itself and when the link rule allows it (mailto, by default), with
   WebView2's own prompt; anything else is refused and logged, and the page opens no new window and
   downloads nothing. (WebView2 alone would hand any scheme to the app registered for it and open
   windows of its own.) The page asks for nothing either, as on Apple and Linux: permissions are denied,
   a server's request for a password or a client certificate is canceled, script dialogs are dismissed
   (leaving the page is allowed), there is no fullscreen, printing, saving from its menu, developer
   tools, autofill or saved passwords. The page cannot send messages to the host or reach host objects,
   and a page with an invalid certificate is not shown. A file input can still ask the user to pick a
   file.
 - When the trust policy refuses .webViewPersistentData (by default, for less-trusted content), the
   WebView gets a separate, private browser profile (InPrivate), as on Apple and Linux. Its cookies,
   cache and storage are shared with no other WebView and never written to disk.
 - Every WebView runs in the process's one WebView2 environment, whose data folder is passed to it (the
   host's WEBVIEW2_USER_DATA_FOLDER, else %LOCALAPPDATA%\<program name>\WebView2), never written into
   the process's environment.

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
 puts it, or beside ActionUIWinUIShim.dll. The shim loads it only by its full path; without it, no
 WebView is made, and the log says why, once per WebView.

 Ignored: backForwardNavigationGestures and magnificationGestures (WebView2's own: the mouse's back
 and forward buttons, Ctrl and the wheel), and the Apple-only linkPreviews,
 limitsNavigationsToAppBoundDomains and upgradeKnownHostsToHTTPS.

 Not yet: a WebView with the app's normal profile signs in to a server with the user's Windows account
 (Negotiate, NTLM) on its own. A private profile does not (measured on Windows CI), so a less-trusted page
 signs in only when the host's policy allows .webViewPersistentData for it.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CWinUI
import Dispatch

@MainActor private var reportedBaseURL = false

/// A WebView's navigation decider, held by the shim (actionUIWinUIWebViewSetNavigationDecider).
@MainActor private final class NavigationBox {
    let decide: @MainActor (String, ActionUIWinUIWebViewNavigationKind) -> Bool

    init(_ decide: @escaping @MainActor (String, ActionUIWinUIWebViewNavigationKind) -> Bool) {
        self.decide = decide
    }
}

/// The box behind the decider's context, taken before entering the main actor (the raw pointer may
/// not cross).
private func navigationBox(_ context: UnsafeMutableRawPointer?) -> NavigationBox? {
    context.map { Unmanaged<NavigationBox>.fromOpaque($0).takeUnretainedValue() }
}

private let decideNavigation: ActionUIWinUIWebViewNavigationDecider = { context, url, kind in
    let box = navigationBox(context)
    let text = url.map { String(cString: $0) }
    return MainActor.assumeIsolated {
        guard let box, let text else { return false }
        return box.decide(text, kind)
    }
}

// Gives back the reference passRetained took, once the shim lets go of the decider.
private let releaseNavigation: ActionUIWinUICallback = { context in
    guard let context else { return }
    Unmanaged<NavigationBox>.fromOpaque(context).release()
}

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
        // Pages in less-trusted content get no permissions, sign-in, script dialogs, fullscreen, printing,
        // saving or autofill, as on Apple and Linux. When the policy refuses .webViewPersistentData (by
        // default, for less-trusted content), the WebView gets a private profile. Both are set before the
        // browser starts.
        let restricted = !LinkTrust.isTrusted(node)
        let privateData = !WebViewTrust.keepsPersistentData(allows: { LinkTrust.allows($0, node) })
        guard let view = WinUIObject(adopting: actionUIWinUIWebViewCreateWithOptions(restricted, privateData)) else {
            throw WinUIError.last("creating a WebView")
        }
        node.state = WebViewState()
        let decider = Unmanaged.passRetained(NavigationBox { [weak node] url, kind in
            decide(url, kind, node)
        }).toOpaque()
        // On failure the shim has already called releaseNavigation.
        if !actionUIWinUIWebViewSetNavigationDecider(view.pointer, decideNavigation, decider, releaseNavigation) {
            // Without the decider, a less-trusted page could open any app's scheme: no page at all.
            throw WinUIError.last("deciding a WebView's navigations")
        }
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
        // Content the trust policy does not let run its user scripts (.webViewUserScripts; less-trusted
        // content by default) runs none, as on Apple and Linux; asked once, as the view starts.
        let runsScripts = WebViewTrust.runsUserScripts(count: props.userScripts.count, allows: { LinkTrust.allows($0, node) },
                                                       logger: logger)
        for script in runsScripts ? props.userScripts : [] {
            guard let source = scriptSource(script, readsFile: { LinkTrust.reads(.webViewScriptFile($0), path: $0, node) }) else {
                continue
            }
            if !actionUIWinUIWebViewAddScript(view.pointer, source, script.injectionTime == .documentEnd, script.forMainFrameOnly) {
                logger.log("WebView: \(WinUIError.last("adding a user script"))", .error)
            }
        }
        if let urlString = node.model.value as? String, isLoadable(urlString) {
            state.lastTrackedURL = urlString
            show(urlString, view, node)
        } else if let html = props.html {
            // about:blank unless baseURL is set and the trust policy allows it (WebViewTrust.base).
            let base = WebViewTrust.base(props.baseURL.flatMap { URL(string: $0) }, allows: { LinkTrust.allows($0, node) },
                                         logger: logger)
            var usedBase: String?
            if base != WebViewTrust.blankBase {
                if ["http", "https"].contains(base.scheme?.lowercased() ?? "") {
                    usedBase = base.absoluteString
                } else if !reportedBaseURL {
                    // WebView2 answers no request of a file: or other address with the html.
                    reportedBaseURL = true
                    logger.log("WebView: the baseURL \(base.absoluteString) is not used on Windows (only http and https bases are)", .warning)
                }
            }
            if !actionUIWinUIWebViewNavigateToString(view.pointer, html, usedBase) {
                logger.log("WebView: \(WinUIError.last("showing the html"))", .error)
                // A base Windows' URI reader refuses (Foundation's took it): the html without one.
                if usedBase != nil, !actionUIWinUIWebViewNavigateToString(view.pointer, html, nil) {
                    logger.log("WebView: \(WinUIError.last("showing the html without its base"))", .error)
                }
            }
        }
    }

    /// Whether the WebView goes to `text` for `kind` (asked by WebView2 on the UI thread, for the
    /// element's origin now): trusted content's navigations go as WebView2 takes them; less-trusted
    /// content's as WebViewTrust.navigation decides, as on Apple: web addresses the policy shows, the
    /// page's own about, data and blob addresses, a local file only when the policy lets it be shown;
    /// another scheme only for the page itself and when the link rule allows it (mailto, by default),
    /// then handed on by WebView2 with its own prompt; no new window. Refusals are logged.
    private static func decide(_ text: String, _ kind: ActionUIWinUIWebViewNavigationKind, _ node: RenderNode?) -> Bool {
        guard let node, node.isAttached else { return false }
        if LinkTrust.isTrusted(node) {
            return true
        }
        let logger = ActionUIModel.shared.logger
        if kind == ActionUIWinUIWebViewNavigationNewWindow {
            logger.log("WebView \(node.element.id) not opening a window for \(text): less-trusted content opens none", .warning)
            return false
        }
        // As Apple's WebView, which saves nothing it cannot show.
        if kind == ActionUIWinUIWebViewNavigationDownload {
            logger.log("WebView \(node.element.id) not downloading \(text): less-trusted content downloads nothing", .warning)
            return false
        }
        guard let url = URL(string: text) else {
            logger.log("WebView \(node.element.id) not going to \(text): it is no URL", .warning)
            return false
        }
        let isMainFrame = kind != ActionUIWinUIWebViewNavigationFrame
        switch WebViewTrust.navigation(url, isMainFrame: isMainFrame, allows: { LinkTrust.allows($0, node) }, logger: logger) {
        case .load:
            return true
        case .open:
            // The page itself: WebView2 goes on to hand the address to its app (LaunchingExternalUriScheme,
            // asked here again), after its own prompt. Not a file: WebView2 would show it in the page
            // rather than hand it to an app.
            guard url.scheme?.lowercased() != "file" else {
                logger.log("WebView \(node.element.id) not going to \(text): it would show the file, not open it", .warning)
                return false
            }
            return kind == ActionUIWinUIWebViewNavigationPage || kind == ActionUIWinUIWebViewNavigationExternalScheme
        case .refuse:
            return false
        }
    }

    /// Loads `urlString` (loadable), or the "Blocked" page when the trust policy refuses the address
    /// (less-trusted content shows only web addresses): false then.
    @discardableResult
    private static func show(_ urlString: String, _ view: WinUIObject, _ node: RenderNode) -> Bool {
        let logger = ActionUIModel.shared.logger
        // Not loadable (the callers checked): nothing the policy could be asked about.
        guard let url = URL(string: urlString) else { return false }
        guard WebViewTrust.showsAddress(url, allows: { LinkTrust.allows($0, node) }, logger: logger) else {
            if !actionUIWinUIWebViewNavigateToString(view.pointer, WebViewTrust.blockedPage(url), nil) {
                logger.log("WebView: \(WinUIError.last("showing the blocked page"))", .error)
            }
            return false
        }
        // The address the policy was asked about, as Linux loads it: WebView2 reads a backslash as a
        // slash, so the text "https://a.example\@b.example/" is a.example to it and b.example to URL,
        // which absoluteString writes with the backslash encoded (%5C), read as URL reads it.
        if !actionUIWinUIWebViewNavigate(view.pointer, url.absoluteString) {
            logger.log("WebView: \(WinUIError.last("loading \(urlString)"))", .error)
        }
        return true
    }

    /// Whether `text` is a URL the web view can load: absolute, with a scheme ("foo" is a relative URL
    /// to Foundation, which WebView2 refuses).
    static func isLoadable(_ text: String) -> Bool {
        URL(string: text)?.scheme.map { !$0.isEmpty } ?? false
    }

    /// A user script's JavaScript: its source, else its file, else its resource (a file of that name in
    /// the current folder); nil, logged, when it cannot be read. A file, or a resource (which on
    /// Windows is a file in the current folder, not in the app's resources), is read only when
    /// `readsFile` allows its path (the element's trust: .webViewScriptFile).
    static func scriptSource(_ script: Props.UserScript, readsFile: (String) -> Bool) -> String? {
        let logger = ActionUIModel.shared.logger
        // Only a regular file: a device or a named pipe the ActionUI JSON names would block the window.
        func read(_ path: String) -> String? {
            guard readsFile(path) else { return nil }
            return (try? ActionUIContentLoader.readRegularFile(URL(fileURLWithPath: path))).map { String(decoding: $0, as: UTF8.self) }
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
                // A refused address shows the blocked page; the value goes back to the page's URL, so
                // the refused one is not loaded again at every update.
                if !show(command, view, node) {
                    resetValueToCurrentURL(after: command, view, node, state)
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
                ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: node.element.id, viewPartID: 0, origin: LinkTrust.origin(node))
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
                ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: node.element.id, viewPartID: 0, origin: LinkTrust.origin(node))
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
