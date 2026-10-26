// Tests/Elements/WebViewRendererTests.swift
/*
 Tests for the WebView renderer on GTK, over WebKitGTK loaded at run time: without the library, a
 placeholder naming its package; an html page loads, and the value, the states and the two actions
 follow it; URL values and the #goBack, #goForward, #reload commands navigate between two local
 pages, and a command with nothing to do puts the current URL back. The page loads need
 WebKitGTK (package libwebkitgtk-6.0-4) and skip without it.
*/

import XCTest
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
