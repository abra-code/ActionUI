// Sources/Elements/WebView+Adwaita.swift
/*
 WebView on GTK: a WebKitGTK web view (Interop/WebKitLibrary.swift, loaded at run time), as large as
 it is offered in both axes, as a WKWebView in SwiftUI is. It follows ActionUI's native Apple backing
 (Views/WebViewNative.swift):
 - Made once from its properties: the first page is the value (the url property) when it is a URL,
   else the html with its baseURL (about:blank without one).
 - Before the first page: customUserAgent, backForwardNavigationGestures (a two-finger swipe on a
   touchpad; on by default, as on Apple) and the userScripts, each from its source, its filePath, or its
   resourceName in the resource folder (with or without ".js"; Linux has no app bundle), injected at
   documentStart or documentEnd, into the main frame only or all frames. A script that cannot be read
   is skipped and logged.
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
        guard let webKit = WebKitLibrary.shared, let view = webKit.newView() else {
            let label = gtk_label_new("WebView needs WebKitGTK (package \(WebKitLibrary.packageName))")!
            Gtk.Widget(label).setCSSClass("dim-label", true)
            gtk_label_set_wrap(opaque(label), 1)
            return label
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
        configure(webKit, view, Props(node.properties))
        loadInitialContent(webKit, view, node, state)
        return view
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        guard let webKit = WebKitLibrary.shared,
              let state = attached(on: UnsafeMutableRawPointer(widget), key: webViewStateKey) else { return }
        handleCommand(node.model.value as? String, webKit, widget, node, state)
    }

    /// The settings and the scripts the properties give, before the first page loads.
    private static func configure(_ webKit: WebKitLibrary, _ view: WidgetPointer, _ props: Props) {
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
        let manager = webKit.userContentManager(view)
        for script in props.userScripts {
            guard let source = scriptSource(script), let userScript = webKit.newScript(
                source, script.forMainFrameOnly ? WebKitLibrary.topFrame : WebKitLibrary.allFrames,
                script.injectionTime == .documentStart ? WebKitLibrary.documentStart : WebKitLibrary.documentEnd, nil, nil) else { continue }
            webKit.addScript(manager, userScript)
            webKit.releaseScript(userScript)
        }
    }

    /// A user script's JavaScript: its source, else its file, else its resource (as the Apple backing
    /// reads them, without an app bundle); nil, logged, when it cannot be read.
    static func scriptSource(_ script: Props.UserScript) -> String? {
        let logger = ActionUIModel.shared.logger
        func read(_ path: String) -> String? {
            (try? Data(contentsOf: URL(fileURLWithPath: path))).map { String(decoding: $0, as: UTF8.self) }
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
            let name = resourceName.lowercased().hasSuffix(".js") ? String(resourceName.dropLast(3)) : resourceName
            guard let path = ActionUIResourceFolder.file(name + ".js") ?? ActionUIResourceFolder.file(resourceName) else {
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
            webKit.loadURI(view, url.absoluteString)
        } else if let html = props.html {
            let baseURL = props.baseURL.flatMap { URL(string: $0) }?.absoluteString ?? "about:blank"
            webKit.loadHTML(view, html, baseURL)
        }
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
                webKit.loadURI(view, url.absoluteString)
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
            ActionUIModel.shared.actionHandler(actionID, windowUUID: node.windowUUID, viewID: node.element.id, viewPartID: 0)
        }
    }

    private static func loadingChanged(_ webKit: WebKitLibrary, _ view: WidgetPointer, _ state: WebViewState) {
        guard let node = state.node else { return }
        node.model.states["isLoading"] = webKit.isLoading(view) != 0
        node.model.states["estimatedProgress"] = webKit.progress(view)
        syncBackForward(webKit, view, node)
        if let actionID = Props(node.properties).navigationActionID {
            ActionUIModel.shared.actionHandler(actionID, windowUUID: node.windowUUID, viewID: node.element.id, viewPartID: 0)
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
