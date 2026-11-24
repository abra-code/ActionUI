// Sources/Elements/WebView+Adwaita.swift
/*
 WebView on GTK: a WebKitGTK web view (Interop/WebKitLibrary.swift, loaded at run time), as large as
 it is offered in both axes, as a WKWebView in SwiftUI is. It follows ActionUI's native Apple backing
 (Views/WebViewNative.swift):
 - Made once from its properties: the first page is the value (the url property) when it is a URL,
   else the html with its baseURL (about:blank without one).
 - Before the first page: customUserAgent, backForwardNavigationGestures (a two-finger swipe on a
   touchpad; on by default, as on Apple) and the userScripts, each from its source, its filePath, or
   its resourceName in the app's bundle (the resource folder, else the program's folder, as for
   images; with or without ".js"), injected at documentStart or documentEnd, into the main frame only
   or all frames. A script that cannot be read is skipped and logged.
 - The back and forward gestures are on only while the web view is shown (mapped): with them on,
   WebKitGTK 2.54 snapshots the page at each navigation and crashes doing so in a view that is not
   shown (measured in the box: a URL value sent to a WebView in a window not presented).
 - magnificationGestures is ignored: WebKitGTK has no setting that turns pinch zoom off. linkPreviews,
   limitsNavigationsToAppBoundDomains and upgradeKnownHostsToHTTPS are Apple-only and ignored.
 - A later value is a command: a URL to load, or #goBack, #goForward, #reload, #stop. A command that
   leaves the page where it is, or a value that is no URL, is replaced by the current URL (logged when
   there is nothing to go back or forward to, or no URL).
 - The value follows the page's URL and fires valueChangeActionID; a change of isLoading fires
   navigationActionID; the states title, isLoading, estimatedProgress, canGoBack and canGoForward
   follow the view. The view's notifications are handled after the main loop turn they come in, as
   the Apple backing handles its observations in a Task.
 - Content the trust policy does not let keep its data in the app's persistent store
   (webViewPersistentData; less-trusted content by default) gets a view of its own ephemeral network
   session, and content it does not let run its user scripts (webViewUserScripts) runs none, as on
   Apple.
 - The pages of less-trusted content: navigations go where the trust policy allows (another app
   only for a navigation the user started), nothing is downloaded, permission requests are denied,
   and, as on Apple, they get no fullscreen, print, sign-in or script dialogs (guardLessTrustedPages).
 - Without WebKitGTK: a dimmed label naming the package to install (logged once, by WebKitLibrary).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

/// What a WebView's handlers share, kept on its web view.
@MainActor private final class WebViewState {
    weak var node: RenderNode?
    /// The URL the value was last set to from the view, so an update showing it again is no command.
    var lastTrackedURL = ""

    init(_ node: RenderNode) {
        self.node = node
    }
}

private let webViewStateKey = AttachKey<WebViewState>("actionui-webview")

extension WebView: ActionUIAdwaitaRenderer {
    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        guard let webKit = WebKitLibrary.shared else {
            return placeholder("WebView needs WebKitGTK (package \(WebKitLibrary.packageName))")
        }
        // Content that may not keep its data in the app's persistent store gets a private one.
        let allows: (ActionUICapability) -> Bool = { LinkTrust.allows($0, node) }
        let keepsData = WebViewTrust.keepsPersistentData(allows: allows)
        guard let view = keepsData ? webKit.newView() : webKit.newPrivateView() else {
            return placeholder(keepsData ? "WebView could not be made" : "WebView could not be given a private data store")
        }
        gtk_widget_set_hexpand(view, 1)
        gtk_widget_set_vexpand(view, 1)
        let state = WebViewState(node)
        attach(state, to: UnsafeMutableRawPointer(view), key: webViewStateKey)
        let handlers: [(String, @MainActor (WebKitLibrary, WidgetPointer, WebViewState) -> Void)] = [
            ("notify::uri", urlChanged),
            ("notify::is-loading", loadingChanged),
            ("notify::estimated-load-progress", progressChanged),
            ("notify::title", titleChanged),
        ]
        for (signal, handle) in handlers {
            connectSignal(UnsafeMutableRawPointer(view), signal, .instanceAndArgument) { [weak state] in
                // After this turn of the main loop, as the Apple backing's Task; the state goes with
                // the view, so a view gone by then is not touched.
                runAfter(milliseconds: 0) { [weak state] in
                    guard let state else { return }
                    handle(webKit, view, state)
                }
            }
        }
        configure(webKit, view, Props(node.properties), allows: allows) { LinkTrust.reads(.webViewScriptFile($0), path: $0, node) }
        guardLessTrustedPages(webKit, view, node)
        loadInitialContent(webKit, view, node, state)
        return view
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let webKit = WebKitLibrary.shared,
              let state = attached(on: UnsafeMutableRawPointer(widget), key: webViewStateKey) else { return }
        handleCommand(node.model.value as? String, webKit, widget, node, state)
    }

    /// Opens an address in another app, as GTK's own link handlers do, with the view's window as the
    /// parent. Tests replace it.
    static var openURI: @MainActor (String, WidgetPointer) -> Void = { uri, widget in
        let launcher = gtk_uri_launcher_new(uri)!
        gtk_uri_launcher_launch(launcher, gtk_widget_get_root(widget).map { typed($0) }, nil, nil, nil)
        g_object_unref(UnsafeMutableRawPointer(launcher))
    }

    /// What the pages of less-trusted content (or content of unknown origin) may do, decided at each
    /// event by the node's content then, as on Apple and Android; trusted content keeps WebKitGTK's
    /// own handling:
    /// - a navigation, the page's or a frame's or to a new window, goes where WebViewTrust.navigation
    ///   allows; WebKitGTK does not say whether a frame navigates, so another app is opened only for
    ///   a navigation the user started (a page can add frames without end, but cannot click);
    /// - a response the view cannot show is not downloaded, and a download the page starts is
    ///   canceled;
    /// - a permission request (camera, microphone, location, notifications) is denied;
    /// - as on Apple, which has none of them for any page: no fullscreen (the Fullscreen API is off
    ///   for content less trusted when the view is made, and a request is refused whenever made), no
    ///   print dialog, no sign-in dialog for a server's authentication request, and no script
    ///   dialogs (an alert returns at once, a confirm answers no and a prompt nothing, but "leave
    ///   this page?" answers yes, so a page cannot keep the user from going).
    private static func guardLessTrustedPages(_ webKit: WebKitLibrary, _ view: WidgetPointer, _ node: RenderNode) {
        let logger = ActionUIModel.shared.logger
        connectPolicySignal(UnsafeMutableRawPointer(view)) { [weak node] pointer, type in
            // A node gone (the view on its way out) counts as content of unknown origin.
            if let node, LinkTrust.isTrusted(node) { return false }
            let decision = OpaquePointer(pointer)
            switch type {
            case WebKitLibrary.navigationAction, WebKitLibrary.newWindowAction:
                let action = webKit.navigationActionOf(decision)
                let address = webKit.address(ofRequest: webKit.actionRequest(action))
                guard let node, let url = URL(string: address) else {
                    webKit.ignoreDecision(decision)
                    return true
                }
                var verdict = WebViewTrust.navigation(url, isMainFrame: true, allows: { LinkTrust.allows($0, node) }, logger: logger)
                if verdict == .open, webKit.isUserGesture(action) == 0 {
                    logger.log("WebView not opening \(address) in another app: the page did not open it from a click", .warning)
                    verdict = .refuse
                }
                switch verdict {
                case .load:
                    webKit.useDecision(decision)
                case .open:
                    webKit.ignoreDecision(decision)
                    openURI(address, view)
                case .refuse:
                    webKit.ignoreDecision(decision)
                }
                return true
            case WebKitLibrary.response:
                guard webKit.showsResponse(decision) == 0 else { return false }
                logger.log("WebView not downloading \(webKit.address(ofRequest: webKit.responseRequest(decision))): the trust policy allows less-trusted content no downloads", .warning)
                webKit.ignoreDecision(decision)
                return true
            default:
                return false
            }
        }
        connectObjectBooleanSignal(UnsafeMutableRawPointer(view), "permission-request") { [weak node] request in
            if let node, LinkTrust.isTrusted(node) { return false }
            logger.log("WebView permission request denied: less-trusted content is given no permissions", .warning)
            webKit.denyPermission(OpaquePointer(request))
            return true
        }
        if !LinkTrust.isTrusted(node) {
            webKit.setFullscreenEnabled(webKit.settings(view), 0)
        }
        connectBooleanSignal(UnsafeMutableRawPointer(view), "enter-fullscreen") { [weak node] in
            if let node, LinkTrust.isTrusted(node) { return false }
            logger.log("WebView not going fullscreen: less-trusted content may not fill the window", .warning)
            return true
        }
        connectObjectBooleanSignal(UnsafeMutableRawPointer(view), "print") { [weak node] _ in
            if let node, LinkTrust.isTrusted(node) { return false }
            logger.log("WebView not printing: less-trusted content may not open the print dialog", .warning)
            return true
        }
        connectObjectBooleanSignal(UnsafeMutableRawPointer(view), "script-dialog") { [weak node] pointer in
            if let node, LinkTrust.isTrusted(node) { return false }
            // Handled with no answer given: WebKit closes it with its default answers once the last
            // reference to it goes.
            let dialog = OpaquePointer(pointer)
            if webKit.dialogType(dialog) == WebKitLibrary.beforeUnloadDialog {
                webKit.setConfirmed(dialog, 1)
            }
            return true
        }
        connectObjectBooleanSignal(UnsafeMutableRawPointer(view), "authenticate") { [weak node] pointer in
            if let node, LinkTrust.isTrusted(node) { return false }
            logger.log("WebView not asking for a sign-in: less-trusted content may not show the sign-in dialog", .warning)
            webKit.cancelAuthentication(OpaquePointer(pointer))
            return true
        }
        // A download can also start without a response decision (a link's download attribute). The
        // session (the app's shared one, or the view's private one) is kept until the view goes, so
        // the handler can always be removed from it.
        guard let session = webKit.networkSession(view) else { return }
        let sessionPointer = UnsafeMutableRawPointer(session)
        g_object_ref(sessionPointer)
        let handler = connectObjectSignal(sessionPointer, "download-started") { [weak node] pointer in
            let download = OpaquePointer(pointer)
            guard webKit.downloadView(download) == view else { return }
            if let node, LinkTrust.isTrusted(node) { return }
            logger.log("WebView not downloading \(webKit.address(ofRequest: webKit.downloadRequest(download))): the trust policy allows less-trusted content no downloads", .warning)
            webKit.cancelDownload(download)
        }
        connectSignal(UnsafeMutableRawPointer(view), "destroy", .instanceOnly) {
            if handler != 0 { g_signal_handler_disconnect(sessionPointer, handler) }
            g_object_unref(sessionPointer)
        }
    }

    /// A dimmed, wrapping label in the WebView's place.
    private static func placeholder(_ text: String) -> WidgetPointer {
        let label = gtk_label_new(text)!
        Gtk.Widget(label).setCSSClass("dim-label", true)
        gtk_label_set_wrap(opaque(label), 1)
        return label
    }

    /// The settings and the scripts the properties give, before the first page loads.
    /// `allows`: the trust policy's answer for the element (content that may not run its user
    /// scripts runs none); `readsFile`: whether a user script may be read from a file.
    private static func configure(_ webKit: WebKitLibrary, _ view: WidgetPointer, _ props: Props,
                                  allows: (ActionUICapability) -> Bool, readsFile: (String) -> Bool) {
        let settings = webKit.settings(view)
        if let userAgent = props.customUserAgent {
            webKit.setUserAgent(settings, userAgent)
        }
        if props.backForwardNavigationGestures {
            // On while shown only: WebKitGTK crashes snapshotting a page it does not show.
            connectSignal(UnsafeMutableRawPointer(view), "map", .instanceOnly) {
                webKit.setBackForwardGestures(webKit.settings(view), 1)
            }
            connectSignal(UnsafeMutableRawPointer(view), "unmap", .instanceOnly) {
                webKit.setBackForwardGestures(webKit.settings(view), 0)
            }
        }
        webKit.setBackForwardGestures(settings, 0)
        guard WebViewTrust.runsUserScripts(count: props.userScripts.count, allows: allows,
                                           logger: ActionUIModel.shared.logger) else { return }
        let manager = webKit.userContentManager(view)
        for script in props.userScripts {
            guard let source = scriptSource(script, readsFile: readsFile), let userScript = webKit.newScript(
                source, script.forMainFrameOnly ? WebKitLibrary.topFrame : WebKitLibrary.allFrames,
                script.injectionTime == .documentStart ? WebKitLibrary.documentStart : WebKitLibrary.documentEnd, nil, nil) else { continue }
            webKit.addScript(manager, userScript)
            webKit.releaseScript(userScript)
        }
    }

    /// A user script's JavaScript: its source, else its file (when `readsFile` allows it), else its
    /// resource in the app's bundle (as the Apple backing reads them); nil, logged, when it cannot be
    /// read.
    static func scriptSource(_ script: Props.UserScript, readsFile: (String) -> Bool) -> String? {
        let logger = ActionUIModel.shared.logger
        // Only a regular file: a device or a named pipe the document names would block the window.
        func read(_ path: String) -> String? {
            (try? ActionUIContentLoader.readRegularFile(URL(fileURLWithPath: path))).map { String(decoding: $0, as: UTF8.self) }
        }
        if let source = script.source {
            return source
        }
        if let filePath = script.filePath {
            guard readsFile(filePath) else { return nil }
            guard let source = read(filePath) else {
                logger.log("WebView userScript: failed to read file at '\(filePath)'", .warning)
                return nil
            }
            return source
        }
        if let resourceName = script.resourceName {
            let name = resourceName.lowercased().hasSuffix(".js") ? String(resourceName.dropLast(3)) : resourceName
            guard let path = AppBundle.resource(name + ".js") ?? AppBundle.resource(resourceName) else {
                logger.log("WebView userScript: bundle resource '\(resourceName)' not found", .warning)
                return nil
            }
            guard let source = read(path) else {
                logger.log("WebView userScript: failed to read bundle resource '\(resourceName)'", .warning)
                return nil
            }
            return source
        }
        return nil
    }

    private static func loadInitialContent(_ webKit: WebKitLibrary, _ view: WidgetPointer, _ node: RenderNode, _ state: WebViewState) {
        let props = Props(node.properties)
        if let urlString = node.model.value as? String, !urlString.isEmpty, let url = URL(string: urlString) {
            state.lastTrackedURL = urlString
            show(url, webKit, view, node)
        } else if let html = props.html {
            // about:blank unless baseURL is set and the trust policy allows it.
            let baseURL = WebViewTrust.base(props.baseURL.flatMap { URL(string: $0) }, allows: { LinkTrust.allows($0, node) },
                                            logger: ActionUIModel.shared.logger)
            webKit.loadHTML(view, html, baseURL.absoluteString)
        }
    }

    /// Loads `url`, or the "Blocked" page when the trust policy refuses it (false then).
    @discardableResult
    private static func show(_ url: URL, _ webKit: WebKitLibrary, _ view: WidgetPointer, _ node: RenderNode) -> Bool {
        guard WebViewTrust.showsAddress(url, allows: { LinkTrust.allows($0, node) }, logger: ActionUIModel.shared.logger) else {
            webKit.loadHTML(view, WebViewTrust.blockedPage(url), WebViewTrust.blankBase.absoluteString)
            return false
        }
        webKit.loadURI(view, url.absoluteString)
        return true
    }

    private static func handleCommand(_ command: String?, _ webKit: WebKitLibrary, _ view: WidgetPointer, _ node: RenderNode,
                                      _ state: WebViewState) {
        guard let command, !command.isEmpty, command != state.lastTrackedURL else { return }
        let logger = ActionUIModel.shared.logger
        switch command {
        case "#goBack":
            if webKit.canGoBack(view) != 0 {
                webKit.goBack(view)
            } else {
                logger.log("WebView goBack: no back item available", .warning)
                resetValueToCurrentURL(after: command, webKit, view, node, state)
            }
        case "#goForward":
            if webKit.canGoForward(view) != 0 {
                webKit.goForward(view)
            } else {
                logger.log("WebView goForward: no forward item available", .warning)
                resetValueToCurrentURL(after: command, webKit, view, node, state)
            }
        case "#reload":
            webKit.reload(view)
            resetValueToCurrentURL(after: command, webKit, view, node, state)
        case "#stop":
            webKit.stopLoading(view)
            resetValueToCurrentURL(after: command, webKit, view, node, state)
        default:
            if let url = URL(string: command) {
                // A refused address may leave the URL where it is (already about:blank), so no change
                // would replace the refused value, and every update would load it again.
                if !show(url, webKit, view, node) {
                    resetValueToCurrentURL(after: command, webKit, view, node, state)
                }
            } else {
                logger.log("WebView: unrecognized command or invalid URL '\(command)'; ignoring", .warning)
                resetValueToCurrentURL(after: command, webKit, view, node, state)
            }
        }
    }

    /// The value back to the page's URL after a command that leaves the page where it is, after this
    /// update (unless the value changed again by then).
    private static func resetValueToCurrentURL(after command: String, _ webKit: WebKitLibrary, _ view: WidgetPointer,
                                               _ node: RenderNode, _ state: WebViewState) {
        let urlString = swiftString(webKit.uri(view)) ?? ""
        state.lastTrackedURL = urlString
        let model = node.model
        runAfter(milliseconds: 0) {
            if model.value as? String == command {
                model.value = urlString
            }
        }
    }

    private static func urlChanged(_ webKit: WebKitLibrary, _ view: WidgetPointer, _ state: WebViewState) {
        guard let node = state.node else { return }
        let urlString = swiftString(webKit.uri(view)) ?? ""
        state.lastTrackedURL = urlString
        node.model.value = urlString
        syncBackForward(webKit, view, node)
        if let actionID = Props(node.properties).valueChangeActionID, !urlString.isEmpty {
            ActionUIModel.shared.actionHandler(actionID, windowUUID: node.windowUUID, viewID: node.element.id, viewPartID: 0, origin: LinkTrust.origin(node))
        }
    }

    private static func loadingChanged(_ webKit: WebKitLibrary, _ view: WidgetPointer, _ state: WebViewState) {
        guard let node = state.node else { return }
        node.model.states["isLoading"] = webKit.isLoading(view) != 0
        node.model.states["estimatedProgress"] = webKit.progress(view)
        syncBackForward(webKit, view, node)
        if let actionID = Props(node.properties).navigationActionID {
            ActionUIModel.shared.actionHandler(actionID, windowUUID: node.windowUUID, viewID: node.element.id, viewPartID: 0, origin: LinkTrust.origin(node))
        }
    }

    private static func progressChanged(_ webKit: WebKitLibrary, _ view: WidgetPointer, _ state: WebViewState) {
        state.node?.model.states["estimatedProgress"] = webKit.progress(view)
    }

    private static func titleChanged(_ webKit: WebKitLibrary, _ view: WidgetPointer, _ state: WebViewState) {
        state.node?.model.states["title"] = swiftString(webKit.title(view))
    }

    private static func syncBackForward(_ webKit: WebKitLibrary, _ view: WidgetPointer, _ node: RenderNode) {
        node.model.states["canGoBack"] = webKit.canGoBack(view) != 0
        node.model.states["canGoForward"] = webKit.canGoForward(view) != 0
    }
}
