// Tests/Runtime/AdwaitaApplicationTests.swift
/*
 Tests for the application on Linux, each running a real AdwApplication until it ends: windows
 asked for before the start wait for it and open between willFinishLaunching and
 didFinishLaunching; a window opens at its document's ideal size, titled by the application's
 name; no wider than 900 (SwiftUI's opening width) unless its minimum needs more, a long text
 wrapping there; a document in a ScrollView opens tall enough to show it; a minimum larger than
 the monitor scrolls; a file's
 document is titled by its name, and one that cannot be loaded shows its error; the user's close
 of the last window asks shouldTerminate; terminate ends the application and willTerminate fires;
 a second run while running is refused; the host's close of a window showing a modal and an
 alert closes the window; the icon is the windows' default icon.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class AdwaitaApplicationTests: XCTestCase {
    private var files: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
    }

    override func tearDown() async throws {
        for uuid in ["app-w1", "app-w2", "app-big", "app-file", "app-bad", "app-tall", "app-wide", "app-text", "app-scroll"] {
            ActionUIModel.shared.windowModels[uuid] = nil
        }
        for file in files {
            try? FileManager.default.removeItem(atPath: file)
        }
        AdwaitaTestHost.drainMainLoop()
    }

    private static let document = #"{"type": "VStack", "id": 1, "properties": {"frame": {"minWidth": 300, "idealWidth": 360, "minHeight": 280, "idealHeight": 320}}, "children": [{"type": "Text", "id": 2, "properties": {"text": "Hello"}}]}"#

    private func defaultSize(_ window: UnsafeMutablePointer<GtkWindow>) -> (Int32, Int32) {
        var width: Int32 = 0
        var height: Int32 = 0
        gtk_window_get_default_size(window, &width, &height)
        return (width, height)
    }

    /// The toolbar view's content: the document's box, or what holds it.
    private func content(_ window: UnsafeMutablePointer<GtkWindow>) -> WidgetPointer? {
        guard let toolbar = adw_application_window_get_content(typed(window)),
              let overlay = adw_toolbar_view_get_content(OpaquePointer(toolbar)) else { return nil }
        return adw_toast_overlay_get_child(OpaquePointer(overlay))
    }

    func testWindowsWaitForTheStartAndOpenAtTheIdealSize() throws {
        let app = AdwaitaApplication()
        app.name = "Linux Test App"
        var events: [String] = []
        var size: (Int32, Int32) = (0, 0)
        var title: String?
        app.handlers.willFinishLaunching = { events.append("willFinishLaunching") }
        app.handlers.windowWillPresent = { events.append("present \($0)") }
        app.handlers.windowWillClose = { events.append("close \($0)") }
        app.handlers.didFinishLaunching = {
            events.append("didFinishLaunching")
            if let window = app.gtkWindow("app-w1") {
                size = self.defaultSize(window)
                title = swiftString(gtk_window_get_title(window))
            }
            app.closeWindow("app-w1")
        }
        app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil)
        XCTAssertEqual(app.windowUUIDs, [], "before the start the window waits")
        XCTAssertEqual(app.run(), 0, "the last window closed: the application ended")
        XCTAssertEqual(events, ["willFinishLaunching", "present app-w1", "didFinishLaunching", "close app-w1"])
        XCTAssertEqual(size.0, 360, "the root frame's ideal width")
        XCTAssertGreaterThan(size.1, 320, "the ideal height plus the header bar")
        XCTAssertEqual(title, "Linux Test App", "a JSON document is titled by the application's name")
    }

    func testAWindowOpensNoWiderThan900UnlessItsMinimumNeedsMore() throws {
        let app = AdwaitaApplication()
        var wide: (Int32, Int32) = (0, 0)
        var text: (Int32, Int32) = (0, 0)
        let caption = String(repeating: "A long caption that wraps. ", count: 60)
        app.handlers.didFinishLaunching = {
            app.presentWindow(json: Data(#"{"type": "Color", "id": 1, "properties": {"color": "red", "frame": {"minWidth": 1000, "minHeight": 100}}}"#.utf8),
                              windowUUID: "app-wide", title: "Wide")
            app.presentWindow(json: Data(#"{"type": "VStack", "id": 1, "children": [{"type": "Text", "id": 2, "properties": {"text": "\#(caption)"}}]}"#.utf8),
                              windowUUID: "app-text", title: "Text")
            if let window = app.gtkWindow("app-wide") { wide = self.defaultSize(window) }
            if let window = app.gtkWindow("app-text") { text = self.defaultSize(window) }
            app.closeWindow("app-wide")
            app.closeWindow("app-text")
        }
        app.run()
        XCTAssertEqual(wide.0, 1000, "its minimum, wider than 900")
        XCTAssertEqual(text.0, 900, "a long text opens 900 wide, as on macOS")
        XCTAssertGreaterThan(text.1, 100, "the text wraps to several lines there")
    }

    func testADocumentInAScrollViewOpensTallEnoughToShowIt() throws {
        let app = AdwaitaApplication()
        var size: (Int32, Int32) = (0, 0)
        var propagates: gboolean = 1
        let rows = (0..<12).map { #"{"type": "Color", "id": \#($0 + 3), "properties": {"color": "red", "frame": {"width": 200, "height": 40}}}"# }
        app.handlers.didFinishLaunching = {
            app.presentWindow(json: Data(#"{"type": "ScrollView", "id": 1, "content": {"type": "VStack", "id": 2, "children": [\#(rows.joined(separator: ","))]}}"#.utf8),
                              windowUUID: "app-scroll", title: "Scroll")
            if let window = app.gtkWindow("app-scroll") {
                size = self.defaultSize(window)
                if let scroller = self.content(window).flatMap(self.firstScrolledWindow) {
                    propagates = gtk_scrolled_window_get_propagate_natural_height(OpaquePointer(scroller))
                }
            }
            app.closeWindow("app-scroll")
        }
        app.run()
        // Twelve rows 40 tall (Colors have no spacing between them): 480 and the header bar, under
        // the box's 800-tall monitor.
        XCTAssertGreaterThan(size.1, 480, "its content's height and the header bar, not a strip")
        XCTAssertEqual(propagates, 0, "afterwards it scrolls as before")
    }

    func testContentThatGrowsOpensAtLeastAsTallAsSwiftUIs() throws {
        let app = AdwaitaApplication()
        var list: (Int32, Int32) = (0, 0)
        var text: (Int32, Int32) = (0, 0)
        app.handlers.didFinishLaunching = {
            app.presentWindow(json: Data(#"{"type": "VStack", "id": 1, "children": [{"type": "Button", "id": 2, "properties": {"title": "Load"}}, {"type": "List", "id": 3}]}"#.utf8),
                              windowUUID: "app-w1", title: "List")
            app.presentWindow(json: Data(#"{"type": "VStack", "id": 1, "children": [{"type": "Text", "id": 2, "properties": {"text": "Hello"}}]}"#.utf8),
                              windowUUID: "app-w2", title: "Text")
            if let window = app.gtkWindow("app-w1") { list = self.defaultSize(window) }
            if let window = app.gtkWindow("app-w2") { text = self.defaultSize(window) }
            app.closeWindow("app-w1")
            app.closeWindow("app-w2")
        }
        app.run()
        XCTAssertGreaterThan(list.1, AdwaitaApplication.openingHeight, "an empty List: SwiftUI's 418 and the header bar")
        XCTAssertLessThan(text.1, 200, "content that does not grow keeps its own height")
    }

    func testATextTallerThanTheMonitorAtTheOpeningWidthScrolls() throws {
        let app = AdwaitaApplication()
        var scrolls = false
        // About 40000 characters: thousands of points tall wrapped at 900, one line unwrapped.
        let caption = String(repeating: "A long caption that wraps. ", count: 1500)
        app.handlers.didFinishLaunching = {
            app.presentWindow(json: Data(#"{"type": "VStack", "id": 1, "children": [{"type": "Text", "id": 2, "properties": {"text": "\#(caption)"}}]}"#.utf8),
                              windowUUID: "app-text", title: "Text")
            if let window = app.gtkWindow("app-text"), let content = self.content(window) {
                scrolls = swiftString(G_OBJECT_TYPE_NAME_of(content)) == "GtkScrolledWindow"
            }
            app.closeWindow("app-text")
        }
        app.run()
        XCTAssertTrue(scrolls, "its minimum height is the wrapped text's at the opening width")
    }

    private func firstScrolledWindow(_ widget: WidgetPointer) -> WidgetPointer? {
        if g_type_check_instance_is_a(widget.withMemoryRebound(to: GTypeInstance.self, capacity: 1) { $0 }, gtk_scrolled_window_get_type()) != 0 {
            return widget
        }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if let found = firstScrolledWindow(current) { return found }
            child = gtk_widget_get_next_sibling(current)
        }
        return nil
    }

    func testASizeLargerThanTheMonitorIsCappedAndALargerMinimumScrolls() throws {
        var monitorWidth: Int32 = 0
        var monitorHeight: Int32 = 0
        if let display = gdk_display_get_default(), let item = g_list_model_get_item(gdk_display_get_monitors(display), 0) {
            var geometry = GdkRectangle()
            gdk_monitor_get_geometry(OpaquePointer(item), &geometry)
            monitorWidth = geometry.width
            monitorHeight = geometry.height
            g_object_unref(item)
        }
        let app = AdwaitaApplication()
        var size: (Int32, Int32) = (0, 0)
        var bigSize: (Int32, Int32) = (0, 0)
        var scrolls = false
        var tallScrolls = false
        app.handlers.didFinishLaunching = {
            app.presentWindow(json: Data(#"{"type": "Color", "id": 1, "properties": {"color": "red", "frame": {"idealWidth": 50000, "idealHeight": 200}}}"#.utf8),
                              windowUUID: "app-w1", title: "Ideal")
            app.presentWindow(json: Data(#"{"type": "Color", "id": 1, "properties": {"color": "red", "frame": {"minWidth": 50000, "minHeight": 100}}}"#.utf8),
                              windowUUID: "app-big", title: "Minimum")
            // Under the monitor's height, but not with the header bar on top.
            app.presentWindow(json: Data(#"{"type": "Color", "id": 1, "properties": {"color": "red", "frame": {"minWidth": 100, "minHeight": \#(monitorHeight - 10)}}}"#.utf8),
                              windowUUID: "app-tall", title: "Tall")
            if let window = app.gtkWindow("app-w1") { size = self.defaultSize(window) }
            if let window = app.gtkWindow("app-big"), let content = self.content(window) {
                bigSize = self.defaultSize(window)
                scrolls = swiftString(G_OBJECT_TYPE_NAME_of(content)) == "GtkScrolledWindow"
            }
            if let window = app.gtkWindow("app-tall"), let content = self.content(window) {
                tallScrolls = swiftString(G_OBJECT_TYPE_NAME_of(content)) == "GtkScrolledWindow"
            }
            app.closeWindow("app-w1")
            app.closeWindow("app-big")
            app.closeWindow("app-tall")
        }
        app.run()
        XCTAssertGreaterThan(monitorWidth, 0)
        XCTAssertEqual(size.0, min(monitorWidth, Int32(AdwaitaApplication.openingWidth)), "capped at the opening width and the monitor")
        XCTAssertEqual(bigSize.0, monitorWidth, "a minimum wider than the monitor opens as wide as the monitor")
        XCTAssertTrue(scrolls, "a minimum wider than the monitor scrolls")
        XCTAssertTrue(tallScrolls, "a minimum taller than the monitor with the header bar scrolls")
    }

    func testAFileIsTitledByItsNameAndABadDocumentShowsItsError() throws {
        let path = NSTemporaryDirectory() + "actionui-app-test-\(ProcessInfo.processInfo.processIdentifier).json"
        try Self.document.write(toFile: path, atomically: true, encoding: .utf8)
        files.append(path)
        let app = AdwaitaApplication()
        var title: String?
        var errorText: String?
        var documentFolder: String?
        var folderAfterClose: String?
        app.handlers.didFinishLaunching = {
            app.presentWindow(url: path, windowUUID: "app-file", title: nil)
            documentFolder = AppBundle.documentFolder(window: "app-file")
            app.presentWindow(json: Data("{ not json".utf8), windowUUID: "app-bad", title: "Bad")
            title = app.gtkWindow("app-file").flatMap { swiftString(gtk_window_get_title($0)) }
            if let window = app.gtkWindow("app-bad"), let label = self.content(window) {
                errorText = swiftString(gtk_label_get_text(opaque(label)))
            }
            app.closeWindow("app-file")
            folderAfterClose = AppBundle.documentFolder(window: "app-file")
            app.closeWindow("app-bad")
        }
        app.run()
        XCTAssertEqual(title, "actionui-app-test-\(ProcessInfo.processInfo.processIdentifier)")
        XCTAssertTrue(errorText?.hasPrefix("The document could not be loaded") == true, "got \(errorText ?? "nil")")
        XCTAssertEqual(documentFolder, URL(fileURLWithPath: path).deletingLastPathComponent().path, "the file's folder, where its LoadableViews find their names")
        XCTAssertNil(folderAfterClose, "dropped when the window closes")
    }

    func testClosingTheLastWindowAsksAndTerminateEndsTheApplication() throws {
        let app = AdwaitaApplication()
        var allow = false
        var asked = 0
        var stillOpen = false
        var terminated = false
        var secondRun: Int32 = 0
        app.handlers.shouldTerminate = {
            asked += 1
            return allow
        }
        app.handlers.willTerminate = { terminated = true }
        let toplevels = g_list_model_get_n_items(gtk_window_get_toplevels())
        app.handlers.didFinishLaunching = {
            app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil)
            secondRun = app.run()
            // The user's close of the last window: refused.
            if let window = app.gtkWindow("app-w1") { gtk_window_close(window) }
            stillOpen = app.gtkWindow("app-w1") != nil
            allow = true
            app.terminate()
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(secondRun, 1, "a second run while running is refused")
        XCTAssertTrue(stillOpen, "shouldTerminate said no: the window stays")
        XCTAssertEqual(asked, 2, "asked for the close and for terminate")
        XCTAssertTrue(terminated, "willTerminate fired")
        XCTAssertEqual(g_list_model_get_n_items(gtk_window_get_toplevels()), toplevels, "the window open at terminate is gone")
    }

    func testTheHostClosesAWindowShowingAModalAndAnAlert() throws {
        let app = AdwaitaApplication()
        var events: [String] = []
        var shown = false
        var stillOpen = true
        app.handlers.windowWillClose = { events.append("close \($0)") }
        ActionUIModel.shared.registerActionHandler(for: "app.dismissed") { id, _, _, _, _ in
            MainActor.assumeIsolated { events.append(id) }
        }
        defer { ActionUIModel.shared.unregisterActionHandler(for: "app.dismissed") }
        app.handlers.didFinishLaunching = {
            // A watchdog: a window that stays open fails the test instead of hanging it.
            _ = runAfter(milliseconds: 5000) { app.terminate() }
            app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil)
            try? ActionUIModel.shared.presentModal(windowUUID: "app-w1", data: Data(#"{"type": "Text", "id": 50, "properties": {"text": "Sheet"}}"#.utf8),
                                                   format: "json", style: .sheet, onDismissActionID: "app.dismissed")
            ActionUIModel.shared.presentAlert(windowUUID: "app-w1", title: "Alert", buttons: [DialogButton(title: "Cancel", role: .cancel, actionID: "app.dismissed")])
            _ = runAfter(milliseconds: 300) {
                shown = app.presenter("app-w1")?.modalRoot != nil && app.presenter("app-w1")?.dialogWidget != nil
                // AdwDialogHost would close the top dialog instead of the window.
                app.closeWindow("app-w1")
                stillOpen = app.gtkWindow("app-w1") != nil
            }
        }
        XCTAssertEqual(app.run(), 0, "the last window closed: the application ended")
        XCTAssertTrue(shown)
        XCTAssertFalse(stillOpen)
        XCTAssertEqual(events, ["close app-w1"], "no dialog's action fired")
    }

    func testAnApplicationWithNoWindowYetWaitsForItsFirst() throws {
        let app = AdwaitaApplication()
        var presented = false
        app.handlers.didFinishLaunching = {
            // A watchdog: a hold never released, or a close that does not end the application,
            // fails the test instead of hanging it.
            _ = runAfter(milliseconds: 5000) { app.terminate() }
            // As a host whose document arrives later: no window when launching ends.
            _ = runAfter(milliseconds: 50) {
                app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w2", title: "Later")
                presented = app.gtkWindow("app-w2") != nil
                app.closeWindow("app-w2")
            }
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertTrue(presented, "the application waited for its first window")
    }

    func testAnHTTPDocumentOpensOnceLoadedAndHoldsTheApplicationMeanwhile() throws {
        let server = try TestImageServer(png: [], document: Self.document)
        defer { server.stop() }
        let app = AdwaitaApplication()
        var events: [String] = []
        var title: String?
        var replacedShowsDocument = false
        var errorText: String?
        app.handlers.windowWillPresent = { uuid in
            events.append("present \(uuid)")
            switch uuid {
            case "app-w2":
                title = app.gtkWindow(uuid).flatMap { swiftString(gtk_window_get_title($0)) }
                DispatchQueue.main.async {
                    // Closed while it loads: dropped.
                    app.presentWindow(url: server.base + "/view.json", windowUUID: "app-w1", title: nil)
                    app.closeWindow("app-w1")
                    // Presented again while it loads: the newer window stays.
                    app.presentWindow(url: server.base + "/missing.json", windowUUID: "app-big", title: nil)
                    app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-big", title: nil)
                    app.presentWindow(url: server.base + "/missing.json", windowUUID: "app-bad", title: nil)
                }
            case "app-bad":
                // Once every request is answered, and a while for the answers to arrive.
                @MainActor func settle() {
                    guard server.requests >= 4 else {
                        _ = runAfter(milliseconds: 50) { settle() }
                        return
                    }
                    _ = runAfter(milliseconds: 300) {
                        replacedShowsDocument = app.showsDocument("app-big")
                        if let window = app.gtkWindow("app-bad"), let label = self.content(window) {
                            errorText = swiftString(gtk_label_get_text(opaque(label)))
                        }
                        app.terminate()
                    }
                }
                settle()
            default:
                break
            }
        }
        app.handlers.didFinishLaunching = {
            _ = runAfter(milliseconds: 10000) { app.terminate() }
            app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil)
            // The only window closes while the next one loads: the application waits for it.
            app.closeWindow("app-w1")
            app.presentWindow(url: server.base + "/view.json", windowUUID: "app-w2", title: nil)
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(events, ["present app-w1", "present app-w2", "present app-big", "present app-bad"])
        XCTAssertEqual(title, "view", "titled by the URL's file name")
        XCTAssertTrue(replacedShowsDocument, "a replaced load does not replace the newer window")
        XCTAssertEqual(errorText, server.base + "/missing.json could not be loaded")
    }

    func testTheIconIsTheWindowsDefaultIcon() throws {
        let app = AdwaitaApplication()
        app.icon = "applications-science"
        var icon: String?
        app.handlers.didFinishLaunching = {
            icon = swiftString(gtk_window_get_default_icon_name())
            app.terminate()
        }
        app.run()
        XCTAssertEqual(icon, "applications-science")
    }
}
