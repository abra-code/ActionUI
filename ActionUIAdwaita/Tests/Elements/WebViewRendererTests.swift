// Tests/Elements/WebViewRendererTests.swift
/*
 Tests for the WebView renderer on GTK, over WebKitGTK loaded at run time: without the library, a
 placeholder naming its package; an html page loads, and the value, the states and the two actions
 follow it; user scripts from a source, a file and the resource folder run at their injection
 time; the user agent is set, and the back and forward gestures only while the view is shown; URL
 values and the #goBack, #goForward, #reload commands navigate between two local pages in a view
 never shown (where WebKitGTK crashed with the gestures on), and a command with nothing to do puts
 the current URL back; content the trust policy refuses them runs no user scripts, in a view of
 its own ephemeral network session. The page loads need WebKitGTK (package libwebkitgtk-6.0-4) and
 skip without it.
*/

import XCTest
import Glibc
import CAdwaita
@testable import ActionUI

@MainActor
final class WebViewRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var files: [String] = []
    private var fired: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "webview-\(name)"
        fired = []
        for actionID in ["test.url", "test.navigation"] {
            ActionUIModel.shared.registerActionHandler(for: actionID) { [weak self] actionID, _, _, _, _ in
                MainActor.assumeIsolated { self?.fired.append(actionID) }
            }
        }
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        for actionID in ["test.url", "test.navigation"] {
            ActionUIModel.shared.unregisterActionHandler(for: actionID)
        }
        WebKitLibrary.disabledForTesting = false
        ActionUIModel.shared.trustPolicy = DefaultTrustPolicy()
        for file in files {
            try? FileManager.default.removeItem(atPath: file)
        }
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ properties: String) throws -> RenderNode {
        let json = #"{"type": "WebView", "id": 1, "properties": {"# + properties + "}}"
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    private var model: ViewModel? {
        ActionUIModel.shared.windowModels[windowUUID]?.viewModels[1]
    }

    private func requireWebKit() throws {
        guard WebKitLibrary.shared != nil else {
            throw XCTSkip("WebKitGTK 6.0 is not installed (package \(WebKitLibrary.packageName))")
        }
    }

    /// Runs the main loop until the page with `title` has loaded.
    private func waitForPage(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let loaded = AdwaitaTestHost.runMainLoop(until: {
            model?.states["title"] as? String == title && model?.states["isLoading"] as? Bool == false
        }, timeoutMilliseconds: 20_000)
        XCTAssertTrue(loaded, "page \(title) did not load; title \(String(describing: model?.states["title"]))", file: file, line: line)
    }

    /// A local page with this title, removed after the test.
    private func page(_ title: String) throws -> String {
        let path = NSTemporaryDirectory() + "actionui-webview-\(ProcessInfo.processInfo.processIdentifier)-\(title).html"
        try Data("<html><head><title>\(title)</title></head><body>\(title)</body></html>".utf8).write(to: URL(fileURLWithPath: path))
        files.append(path)
        return URL(fileURLWithPath: path).absoluteString
    }

    func testWithoutWebKitAPlaceholderNamesThePackage() throws {
        WebKitLibrary.disabledForTesting = true
        let node = try render(#""url": "https://example.com""#)
        XCTAssertEqual(swiftString(G_OBJECT_TYPE_NAME_of(node.widget)), "GtkLabel")
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(node.widget))), "WebView needs WebKitGTK (package libwebkitgtk-6.0-4)")
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "#reload")
        AdwaitaTestHost.drainMainLoop()
    }

    func testAUserScriptFileIsReadOnlyWhenItIsARegularFile() throws {
        let path = try TestImages.file(Array("window.answer = 42".utf8), name: "webview-script.js")
        files.append(path)
        XCTAssertEqual(WebView.scriptSource(.init(["filePath": path]), readsFile: { _ in true }), "window.answer = 42")
        for device in ["/dev/zero", "/dev/null", NSTemporaryDirectory()] {
            XCTAssertNil(WebView.scriptSource(.init(["filePath": device]), readsFile: { _ in true }), device)
        }
    }

    func testAnHTMLPageLoadsAndTheStatesFollowIt() throws {
        try requireWebKit()
        let node = try render(#""html": "<title>Hello</title><p>Hi</p>", "valueChangeActionID": "test.url", "navigationActionID": "test.navigation""#)
        XCTAssertEqual(swiftString(G_OBJECT_TYPE_NAME_of(node.widget)), "WebKitWebView")
        XCTAssertNotEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_HORIZONTAL), 0)
        XCTAssertNotEqual(gtk_widget_compute_expand(node.widget, GTK_ORIENTATION_VERTICAL), 0, "greedy in both axes, as a WKWebView")
        waitForPage("Hello")
        XCTAssertEqual(model?.value as? String, "about:blank", "html without a baseURL")
        XCTAssertEqual(model?.states["estimatedProgress"] as? Double, 1)
        XCTAssertEqual(model?.states["canGoBack"] as? Bool, false)
        XCTAssertTrue(fired.contains("test.url"))
        XCTAssertGreaterThanOrEqual(fired.filter { $0 == "test.navigation" }.count, 2, "loading started and finished")
    }

    func testUserScriptsRunAtTheirTimeFromEachSource() throws {
        try requireWebKit()
        // documentStart scripts set window values before the page's own script reads them;
        // documentEnd ones see the finished page. The page title gathers what each script did.
        let file = NSTemporaryDirectory() + "actionui-webview-\(ProcessInfo.processInfo.processIdentifier)-file.js"
        try Data("window.fromFile = 'file';".utf8).write(to: URL(fileURLWithPath: file))
        files.append(file)
        let folder = NSTemporaryDirectory() + "actionui-webview-\(ProcessInfo.processInfo.processIdentifier)-resources"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        files.append(folder)
        try Data("document.title = document.title + ' ' + window.fromFile + ' resource';".utf8)
            .write(to: URL(fileURLWithPath: folder + "/ending.js"))
        let previousFolder = ActionUIResourceFolder.path
        ActionUIConfiguration.updateForTesting { $0.resourceFolder = folder }
        defer { ActionUIConfiguration.updateForTesting { $0.resourceFolder = previousFolder } }
        _ = try render(#"""
            "html": "<title>Page</title><script>document.title += ' ' + window.fromSource</script>",
            "userScripts": [
                {"injectionTime": "documentStart", "source": "window.fromSource = 'source';"},
                {"injectionTime": "documentStart", "filePath": "\#(file)"},
                {"injectionTime": "documentEnd", "resourceName": "ending"},
                {"injectionTime": "documentEnd", "resourceName": "missing.js"}
            ]
            """#)
        waitForPage("Page source file resource")
    }

    /// Refuses a WebView's user scripts and the app's data store, and keeps what it was asked.
    private final class PrivateWebViews: ActionUITrustPolicy, @unchecked Sendable {
        var asked: [String] = []
        func allows(_ capability: ActionUICapability, for origin: JSONContentOrigin) -> Bool {
            asked.append("\(capability)")
            return capability != .webViewUserScripts && capability != .webViewPersistentData
        }
    }

    /// Whether the web view's network session keeps its data in memory only, from WebKitGTK itself.
    private func isEphemeral(_ view: WidgetPointer) throws -> Bool {
        typealias Session = @convention(c) (WidgetPointer?) -> OpaquePointer?
        typealias IsEphemeral = @convention(c) (OpaquePointer?) -> gboolean
        let library = try XCTUnwrap(dlopen("libwebkitgtk-6.0.so.4", RTLD_NOW | RTLD_NOLOAD))
        let session = unsafeBitCast(try XCTUnwrap(dlsym(library, "webkit_web_view_get_network_session")), to: Session.self)
        let ephemeral = unsafeBitCast(try XCTUnwrap(dlsym(library, "webkit_network_session_is_ephemeral")), to: IsEphemeral.self)
        return ephemeral(session(view)) != 0
    }

    func testContentThePolicyRefusesRunsNoUserScriptsAndKeepsAPrivateStore() throws {
        try requireWebKit()
        let trusted = try render(#""html": "<title>Shared</title>""#)
        XCTAssertFalse(try isEphemeral(trusted.widget), "trusted content keeps the app's data store")
        windows = []
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let policy = PrivateWebViews()
        ActionUIModel.shared.trustPolicy = policy
        let node = try render(#"""
            "html": "<title>Page</title><script>document.title += ' ' + (window.fromSource || 'no script')</script>",
            "userScripts": [{"injectionTime": "documentStart", "source": "window.fromSource = 'script';"}]
            """#)
        XCTAssertEqual(swiftString(G_OBJECT_TYPE_NAME_of(node.widget)), "WebKitWebView")
        XCTAssertTrue(try isEphemeral(node.widget), "a private data store")
        waitForPage("Page no script")
        XCTAssertTrue(policy.asked.contains("webViewUserScripts") && policy.asked.contains("webViewPersistentData"), "\(policy.asked)")
    }

    func testTheUserAgentAndGesturesAreSet() throws {
        try requireWebKit()
        let webKit = try XCTUnwrap(WebKitLibrary.shared)
        let custom = try render(#""html": "<p>x</p>", "customUserAgent": "ActionUITest/1.0", "backForwardNavigationGestures": false"#)
        let settings = Gtk.Widget(typed(try XCTUnwrap(webKit.settings(custom.widget))))
        XCTAssertEqual(settings[PropertyKey<String?>("user-agent")], "ActionUITest/1.0")
        XCTAssertEqual(settings[PropertyKey<Bool>("enable-back-forward-navigation-gestures")], false)
        ActionUIModel.shared.windowModels[windowUUID] = nil
        let plain = try render(#""html": "<p>x</p>""#)
        let defaults = Gtk.Widget(typed(try XCTUnwrap(webKit.settings(plain.widget))))
        let gestures = PropertyKey<Bool>("enable-back-forward-navigation-gestures")
        XCTAssertEqual(defaults[gestures], false, "off while not shown: WebKitGTK crashes snapshotting a page it does not show")
        let window = gtk_window_new()!
        defer { gtk_window_destroy(typed(window)) }
        gtk_window_set_child(typed(window), plain.outerWidget)
        defer { gtk_window_set_child(typed(window), nil) }
        gtk_window_present(typed(window))
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { gtk_widget_get_mapped(plain.widget) != 0 }))
        XCTAssertEqual(defaults[gestures], true, "on by default while shown, as on Apple")
        gtk_widget_set_visible(window, 0)
        XCTAssertEqual(defaults[gestures], false, "off again when hidden")
        XCTAssertNotEqual(defaults[PropertyKey<String?>("user-agent")], "ActionUITest/1.0")
    }

    func testURLValuesAndCommandsNavigate() throws {
        try requireWebKit()
        let one = try page("One")
        let two = try page("Two")
        _ = try render(#""url": "\#(one)""#)
        waitForPage("One")
        XCTAssertEqual(model?.value as? String, one)

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: two)
        waitForPage("Two")
        XCTAssertEqual(model?.value as? String, two)
        XCTAssertEqual(model?.states["canGoBack"] as? Bool, true)

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "#goBack")
        waitForPage("One")
        XCTAssertEqual(model?.value as? String, one)
        XCTAssertEqual(model?.states["canGoForward"] as? Bool, true)

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "#goForward")
        waitForPage("Two")
        XCTAssertEqual(model?.value as? String, two)

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "#reload")
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { model?.value as? String == two }), "the command is replaced by the URL")
        waitForPage("Two")

        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "#goForward")
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { model?.value as? String == two }), "nothing forward: the URL comes back")
    }
}
