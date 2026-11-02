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
 alert closes the window; the icon is the windows' default icon; a closed window's model is
 readable in the close handler and its elements' disappear actions and removed after them, unless
 a window is reopened under its UUID; a subtitle shows in every kind of window, whatever its
 document does with the header bar, and in a sheet that covers the window, in view however large
 the bars or the sheet; a content size opens the window at that size, capped by the
 monitor; a window that is not resizable keeps its size; the options survive the wait for the start
 and for a remote document; with keepsRunningWithoutWindows the user's close of the last window
 leaves the application running; a document prepared but not presented is loaded with nothing on
 screen, fetches nothing, and can be dropped; presented, it shows once, and waits for the start
 like any window; preparing replaces a window that waits under its UUID, closes one on screen as
 the host's close does, keeping the application running, and keeps its model from a closed
 window's removal.
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
            app.terminate()
        }
        app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil)
        XCTAssertEqual(app.windowUUIDs, [], "before the start the window waits")
        XCTAssertEqual(app.run(), 0, "terminate ended the application")
        XCTAssertEqual(events, ["willFinishLaunching", "present app-w1", "didFinishLaunching", "close app-w1"])
        XCTAssertEqual(size.0, 360, "the root frame's ideal width")
        XCTAssertGreaterThan(size.1, 320, "the ideal height plus the header bar")
        XCTAssertEqual(title, "Linux Test App", "a JSON document is titled by the application's name")
    }

    func testAClosedWindowsModelGoesAfterItsHandlerUnlessTheWindowIsReopened() throws {
        let app = AdwaitaApplication()
        var inHandler: Bool?
        var afterClose: Bool?
        var reopened = false
        var keptWhenReopened: Bool?
        app.handlers.windowWillClose = { uuid in
            if uuid == "app-w1" {
                inHandler = ActionUIModel.shared.hasWindow("app-w1")
            } else if uuid == "app-w2", !reopened {
                // The client opens a window under the same UUID from the handler.
                reopened = true
                app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w2", title: nil)
            }
        }
        app.handlers.didFinishLaunching = {
            app.closeWindow("app-w1")
            runAfter(milliseconds: 50) {
                afterClose = ActionUIModel.shared.hasWindow("app-w1")
                app.closeWindow("app-w2")
                runAfter(milliseconds: 50) {
                    keptWhenReopened = ActionUIModel.shared.hasWindow("app-w2") && app.windowUUIDs == ["app-w2"]
                    app.closeWindow("app-w2")
                    app.terminate()
                }
            }
        }
        app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil)
        app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w2", title: nil)
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(inHandler, true, "the handler reads the closing window's model")
        XCTAssertEqual(afterClose, false, "the model goes after the handler")
        XCTAssertTrue(reopened)
        XCTAssertEqual(keptWhenReopened, true, "a window reopened under the UUID keeps its model")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertFalse(ActionUIModel.shared.hasWindow("app-w2"), "and loses it when it closes for good")
    }

    func testAClosingWindowsDisappearActionsReadItsValuesBeforeItsModelGoes() throws {
        let app = AdwaitaApplication()
        let document = #"{"type": "VStack", "id": 1, "children": [{"type": "TextField", "id": 2, "properties": {"onDisappearActionID": "app.gone"}}]}"#
        var seen: [String] = []
        ActionUIModel.shared.registerActionHandler(for: "app.gone") { _, uuid, _, _, _ in
            seen.append("\(uuid) \(ActionUIModel.shared.getElementValue(windowUUID: uuid, viewID: 2) as? String ?? "nil")")
        }
        defer { ActionUIModel.shared.unregisterActionHandler(for: "app.gone") }
        app.handlers.windowWillPresent = { ActionUIModel.shared.setElementValue(windowUUID: $0, viewID: 2, value: "typed") }
        app.handlers.didFinishLaunching = {
            app.closeWindow("app-w1")
            // As a binding closes a window: from the main queue.
            DispatchQueue.main.async {
                app.closeWindow("app-w2")
                app.terminate()
            }
        }
        app.presentWindow(json: Data(document.utf8), windowUUID: "app-w1", title: nil)
        app.presentWindow(json: Data(document.utf8), windowUUID: "app-w2", title: nil)
        XCTAssertEqual(app.run(), 0)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(seen, ["app-w1 typed", "app-w2 typed"], "the disappear actions run before the model goes")
        XCTAssertFalse(ActionUIModel.shared.hasWindow("app-w1"))
        XCTAssertFalse(ActionUIModel.shared.hasWindow("app-w2"))
    }

    func testAPreparedDocumentIsLoadedWithNothingOnScreen() throws {
        let app = AdwaitaApplication()
        var shown: WidgetPointer?
        var title: String?
        var showsDocument = false
        var subtitle: WidgetPointer?
        var presentedBefore: [String] = []
        app.handlers.didFinishLaunching = {
            let prepared = app.prepareWindow(json: Data(Self.document.utf8), windowUUID: "app-w1")
            XCTAssertNil(prepared.error)
            XCTAssertTrue(ActionUIModel.shared.hasWindow("app-w1"), "its model is loaded")
            presentedBefore = app.windowUUIDs
            app.presentWindow(prepared: prepared, title: "Prepared", options: AdwaitaApplication.WindowOptions(subtitle: "Requested by a test"))
            shown = app.contentWidget("app-w1")
            showsDocument = app.showsDocument("app-w1")
            if let window = app.gtkWindow("app-w1") {
                title = swiftString(gtk_window_get_title(window))
                subtitle = self.label(showing: "Requested by a test", in: typed(window))
            }
            app.closeWindow("app-w1")
            app.terminate()
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(presentedBefore, [], "preparing shows nothing")
        XCTAssertNotNil(shown)
        XCTAssertTrue(showsDocument)
        XCTAssertEqual(title, "Prepared")
        XCTAssertNotNil(subtitle, "the options apply")
    }

    func testPreparingFetchesNothingUntilTheWindowShows() throws {
        let server = try TestImageServer(png: TestImages.png(width: 20, height: 20))
        defer { server.stop() }
        let document = #"{"type": "AsyncImage", "id": 1, "properties": {"url": "\#(server.base)/image.png"}}"#
        let app = AdwaitaApplication()
        var afterPreparing: Int?
        var afterShowing: Int?
        app.handlers.didFinishLaunching = {
            let prepared = app.prepareWindow(json: Data(document.utf8), windowUUID: "app-w1")
            _ = runAfter(milliseconds: 300) {
                afterPreparing = server.requests
                app.presentWindow(prepared: prepared, title: nil)
                _ = runAfter(milliseconds: 500) {
                    afterShowing = server.requests
                    app.closeWindow("app-w1")
                    app.terminate()
                }
            }
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(afterPreparing, 0, "a document that is only checked reaches no server")
        XCTAssertEqual(afterShowing, 1, "the check above could fail: the window does fetch")
    }

    func testADocumentThatCannotBeLoadedPreparesWithItsErrorAndShowsIt() throws {
        let app = AdwaitaApplication()
        var error: String?
        var shownError: String?
        var showsDocument: Bool?
        app.handlers.didFinishLaunching = {
            let prepared = app.prepareWindow(json: Data("not json".utf8), windowUUID: "app-bad")
            error = prepared.error
            app.presentWindow(prepared: prepared, title: "Bad")
            if let window = app.gtkWindow("app-bad"), let label = self.content(window) {
                shownError = swiftString(gtk_label_get_text(opaque(label)))
            }
            showsDocument = app.showsDocument("app-bad")
            app.closeWindow("app-bad")
            app.terminate()
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertTrue(error?.contains("could not be loaded") ?? false, "\(error ?? "nil")")
        XCTAssertEqual(shownError, error, "as a document that cannot be loaded does through presentWindow")
        XCTAssertEqual(showsDocument, false)
    }

    func testAPreparedWindowShowsOnce() throws {
        let app = AdwaitaApplication()
        var presented: [String] = []
        var first: WidgetPointer?
        var afterSecond: WidgetPointer?
        app.handlers.windowWillPresent = { presented.append($0) }
        app.handlers.didFinishLaunching = {
            let prepared = app.prepareWindow(json: Data(Self.document.utf8), windowUUID: "app-w1")
            app.presentWindow(prepared: prepared, title: nil)
            first = app.contentWidget("app-w1")
            app.presentWindow(prepared: prepared, title: nil)
            afterSecond = app.contentWidget("app-w1")
            app.closeWindow("app-w1")
            app.terminate()
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(presented, ["app-w1"], "the second is refused")
        XCTAssertNotNil(first)
        XCTAssertEqual(afterSecond, first, "and leaves the window alone")
    }

    func testAPreparedWindowThatIsDroppedLeavesItsModelAndFiresNothing() throws {
        let document = #"{"type": "VStack", "id": 1, "children": [{"type": "TextField", "id": 2, "properties": {"onAppearActionID": "app.seen", "onDisappearActionID": "app.seen"}}]}"#
        var fired = 0
        ActionUIModel.shared.registerActionHandler(for: "app.seen") { _, _, _, _, _ in fired += 1 }
        defer { ActionUIModel.shared.unregisterActionHandler(for: "app.seen") }
        let app = AdwaitaApplication()
        _ = app.prepareWindow(json: Data(document.utf8), windowUUID: "app-w1")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired, 0, "the document never appeared")
        XCTAssertEqual(app.windowUUIDs, [])
        XCTAssertTrue(ActionUIModel.shared.hasWindow("app-w1"), "the model is the caller's to remove")
    }

    func testALoadableViewInADroppedPreparedWindowFiresNothing() throws {
        let path = NSTemporaryDirectory() + "actionui-app-test-sub-\(ProcessInfo.processInfo.processIdentifier).json"
        try Self.document.write(toFile: path, atomically: true, encoding: .utf8)
        files.append(path)
        let document = #"{"type": "LoadableView", "id": 1, "properties": {"filePath": "\#(path)", "viewDidLoadActionID": "app.loaded"}}"#
        var fired = 0
        ActionUIModel.shared.registerActionHandler(for: "app.loaded") { _, _, _, _, _ in fired += 1 }
        defer { ActionUIModel.shared.unregisterActionHandler(for: "app.loaded") }
        _ = AdwaitaApplication().prepareWindow(json: Data(document.utf8), windowUUID: "app-w1")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired, 0, "the document never showed")
    }

    func testAPreparedWindowWaitsForTheStart() throws {
        let app = AdwaitaApplication()
        var events: [String] = []
        var shown: WidgetPointer?
        app.handlers.willFinishLaunching = { events.append("willFinishLaunching") }
        app.handlers.windowWillPresent = { events.append("present \($0)") }
        app.handlers.didFinishLaunching = {
            events.append("didFinishLaunching")
            shown = app.contentWidget("app-w1")
            app.closeWindow("app-w1")
            app.terminate()
        }
        let prepared = app.prepareWindow(json: Data(Self.document.utf8), windowUUID: "app-w1")
        app.presentWindow(prepared: prepared, title: nil)
        XCTAssertEqual(app.windowUUIDs, [], "before the start the window waits")
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(events, ["willFinishLaunching", "present app-w1", "didFinishLaunching"])
        XCTAssertNotNil(shown)
    }

    func testPreparingReplacesAWindowThatWaitsForTheStart() throws {
        let app = AdwaitaApplication()
        var presented: [String] = []
        var shown: WidgetPointer?
        var modelType: String?
        app.handlers.windowWillPresent = { presented.append($0) }
        app.handlers.didFinishLaunching = {
            shown = app.contentWidget("app-w1")
            modelType = ActionUIModel.shared.windowModels["app-w1"]?.element?.type
            app.closeWindow("app-w1")
            app.terminate()
        }
        app.presentWindow(json: Data(#"{"type": "Text", "id": 1}"#.utf8), windowUUID: "app-w1", title: nil)
        let prepared = app.prepareWindow(json: Data(Self.document.utf8), windowUUID: "app-w1")
        app.presentWindow(prepared: prepared, title: nil)
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(presented, ["app-w1"], "the waiting window's document never loads over the prepared one")
        XCTAssertEqual(modelType, "VStack")
        XCTAssertNotNil(shown)
    }

    func testPreparingUnderTheUUIDOfTheLastWindowLeavesTheApplicationRunning() throws {
        let app = AdwaitaApplication()
        var presented: [String] = []
        var running = false
        app.handlers.windowWillPresent = { presented.append($0) }
        app.handlers.didFinishLaunching = {
            // A watchdog: an application kept open for good ends here instead of hanging.
            _ = runAfter(milliseconds: 5000) { app.terminate() }
            // The document is refused: no window takes the closed one's place.
            let refused = app.prepareWindow(json: Data("not json".utf8), windowUUID: "app-w1")
            XCTAssertNotNil(refused.error)
            // Never runs if the application ended with its last window.
            _ = runAfter(milliseconds: 300) {
                running = true
                let prepared = app.prepareWindow(json: Data(Self.document.utf8), windowUUID: "app-w2")
                app.presentWindow(prepared: prepared, title: nil)
                app.closeWindow("app-w2")
                app.terminate()
            }
        }
        app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil)
        XCTAssertEqual(app.run(), 0)
        XCTAssertTrue(running, "the host closed its last window: the application keeps running")
        XCTAssertEqual(presented, ["app-w1", "app-w2"], "and a later window releases the hold")
    }

    func testPreparingUnderTheUUIDOfTheLastLoadLeavesTheApplicationRunning() throws {
        let server = try TestImageServer(png: [], document: Self.document)
        defer { server.stop() }
        let app = AdwaitaApplication()
        var presented: [String] = []
        var running = false
        app.handlers.windowWillPresent = { presented.append($0) }
        app.handlers.didFinishLaunching = {
            _ = runAfter(milliseconds: 5000) { app.terminate() }
            app.presentWindow(url: server.base + "/view.json", windowUUID: "app-w2", title: nil)
            // The open window goes while the other loads, then the load: nothing is left but the hold.
            app.closeWindow("app-w1")
            _ = app.prepareWindow(json: Data("not json".utf8), windowUUID: "app-w2")
            _ = runAfter(milliseconds: 500) {
                running = true
                app.terminate()
            }
        }
        app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil)
        XCTAssertEqual(app.run(), 0)
        XCTAssertTrue(running, "the host dropped its last load: the application keeps running")
        XCTAssertEqual(presented, ["app-w1"], "the dropped load presents nothing")
    }

    func testAClosedWindowsModelRemovalSparesADocumentPreparedUnderItsUUID() throws {
        let app = AdwaitaApplication()
        var hadModel = false
        var showsDocument = false
        app.handlers.didFinishLaunching = {
            app.closeWindow("app-w1")
            let prepared = app.prepareWindow(json: Data(Self.document.utf8), windowUUID: "app-w1")
            // After the removal the close queued.
            _ = runAfter(milliseconds: 50) {
                hadModel = ActionUIModel.shared.hasWindow("app-w1")
                app.presentWindow(prepared: prepared, title: nil)
                showsDocument = app.showsDocument("app-w1")
                app.closeWindow("app-w1")
                app.terminate()
            }
        }
        app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil)
        XCTAssertEqual(app.run(), 0)
        XCTAssertTrue(hadModel, "the host reopened the window: its model stays")
        XCTAssertTrue(showsDocument)
    }

    func testPreparingUnderTheUUIDOfAnOpenWindowClosesIt() throws {
        let app = AdwaitaApplication()
        var closed: [String] = []
        var afterPreparing: [String]?
        app.handlers.windowWillClose = { closed.append($0) }
        app.handlers.didFinishLaunching = {
            app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil)
            let prepared = app.prepareWindow(json: Data(Self.document.utf8), windowUUID: "app-w1")
            afterPreparing = app.windowUUIDs
            app.presentWindow(prepared: prepared, title: nil)
            app.closeWindow("app-w1")
            app.terminate()
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(afterPreparing, [], "its model is the new document's now, as for presentWindow")
        XCTAssertEqual(closed, ["app-w1"], "no handler for the replaced window, as for presentWindow")
    }

    func testACaptureIsScaledDownToItsLimitAndSaysItsSize() throws {
        let app = AdwaitaApplication()
        let path = NSTemporaryDirectory() + "actionui-app-test-capture-\(ProcessInfo.processInfo.processIdentifier).png"
        files.append(path)
        var full: (width: Int, height: Int)?
        var limited: (width: Int, height: Int)?
        var fileWidth: Int32 = 0
        var missing: (width: Int, height: Int)?
        app.handlers.didFinishLaunching = {
            missing = app.capturePNG(windowUUID: "no-such-window", path: path)
            app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: "Capture")
            _ = runAfter(milliseconds: 300) {
                full = app.capturePNG(windowUUID: "app-w1", path: path)
                limited = app.capturePNG(windowUUID: "app-w1", path: path, maxPixels: 100)
                if let texture = gdk_texture_new_from_filename(path, nil) {
                    fileWidth = gdk_texture_get_width(texture)
                    g_object_unref(UnsafeMutableRawPointer(texture))
                }
                app.closeWindow("app-w1")
                app.terminate()
            }
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertNil(missing, "no such window")
        let large = try XCTUnwrap(full)
        let small = try XCTUnwrap(limited)
        XCTAssertGreaterThan(max(large.width, large.height), 100)
        XCTAssertEqual(max(small.width, small.height), 100, "the longest side is at the limit")
        XCTAssertEqual(Double(small.width) / Double(small.height), Double(large.width) / Double(large.height), accuracy: 0.05, "in proportion")
        XCTAssertEqual(Int(fileWidth), small.width, "the size is the file's")
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
            app.terminate()
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
            app.terminate()
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
            app.terminate()
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
            app.terminate()
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
            app.terminate()
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
            app.terminate()
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

    func testTheHostsCloseOfTheLastWindowLeavesTheApplicationRunningUntilTerminate() throws {
        let app = AdwaitaApplication()
        var asked = 0
        var runningAfterClose = false
        var modelAfterClose: Bool?
        var events: [String] = []
        app.handlers.shouldTerminate = {
            asked += 1
            return true
        }
        app.handlers.windowWillClose = { events.append("close \($0)") }
        app.handlers.willTerminate = { events.append("willTerminate") }
        app.handlers.didFinishLaunching = {
            // A watchdog: an application kept open for good fails the count below instead of hanging.
            _ = runAfter(milliseconds: 5000) { app.terminate() }
            app.closeWindow("app-w1")
            // Never runs if the close ended the application.
            _ = runAfter(milliseconds: 200) {
                runningAfterClose = true
                modelAfterClose = ActionUIModel.shared.hasWindow("app-w1")
                app.terminate()
            }
        }
        app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil)
        XCTAssertEqual(app.run(), 0)
        XCTAssertTrue(runningAfterClose, "the host's close of the last window leaves the application running, as on Apple")
        XCTAssertEqual(modelAfterClose, false, "the closed window's model goes meanwhile")
        XCTAssertEqual(asked, 1, "terminate asks shouldTerminate")
        XCTAssertEqual(events, ["close app-w1", "willTerminate"])
    }

    func testAWindowPresentedAfterTheHostClosedTheLastOneReleasesTheHold() throws {
        let app = AdwaitaApplication()
        var asked = 0
        var events: [String] = []
        app.handlers.shouldTerminate = {
            asked += 1
            return true
        }
        app.handlers.windowWillClose = { events.append("close \($0)") }
        app.handlers.didFinishLaunching = {
            // A watchdog: a hold left behind fails the count below (it asks a second time).
            _ = runAfter(milliseconds: 5000) { app.terminate() }
            app.closeWindow("app-w1")
            _ = runAfter(milliseconds: 100) {
                app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w2", title: nil)
                // The user's close of the last window: asked, and the application ends.
                if let window = app.gtkWindow("app-w2") { gtk_window_close(window) }
            }
        }
        app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil)
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(events, ["close app-w1", "close app-w2"], "the user's close was carried out, not left to the watchdog")
        XCTAssertEqual(asked, 1, "the user's close of the new window asked and ended the application: no hold was left")
    }

    func testTheHostClosingItsLastWindowWhileItsDocumentLoadsLeavesTheApplicationRunning() throws {
        let server = try TestImageServer(png: [], document: Self.document)
        defer { server.stop() }
        let app = AdwaitaApplication()
        var presented: [String] = []
        var runningAfterClose = false
        app.handlers.windowWillPresent = { presented.append($0) }
        app.handlers.didFinishLaunching = {
            // A watchdog: an application kept open for good ends here instead of hanging.
            _ = runAfter(milliseconds: 5000) { app.terminate() }
            app.presentWindow(url: server.base + "/view.json", windowUUID: "app-w2", title: nil)
            // The open window goes while the other loads (the load holds the application), then
            // the loading one: nothing is left but the hold.
            app.closeWindow("app-w1")
            app.closeWindow("app-w2")
            // Never runs if the second close ended the application.
            _ = runAfter(milliseconds: 500) {
                runningAfterClose = true
                app.terminate()
            }
        }
        app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil)
        XCTAssertEqual(app.run(), 0)
        XCTAssertTrue(runningAfterClose, "the host dropped its last load: the application keeps running")
        XCTAssertEqual(presented, ["app-w1"], "the dropped load presents nothing")
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
                app.terminate()
                stillOpen = app.gtkWindow("app-w1") != nil
            }
        }
        XCTAssertEqual(app.run(), 0, "terminate ended the application")
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
                app.terminate()
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
            // The only window closes, then the next one loads: the hold the close takes, and then the
            // load's, keep the application running meanwhile.
            app.closeWindow("app-w1")
            app.presentWindow(url: server.base + "/view.json", windowUUID: "app-w2", title: nil)
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(events, ["present app-w1", "present app-w2", "present app-big", "present app-bad"])
        XCTAssertEqual(title, "view", "titled by the URL's file name")
        XCTAssertTrue(replacedShowsDocument, "a replaced load does not replace the newer window")
        XCTAssertEqual(errorText, server.base + "/missing.json could not be loaded")
    }

    /// The label in `widget` showing `text`.
    private func label(showing text: String, in widget: WidgetPointer) -> WidgetPointer? {
        if g_type_check_instance_is_a(widget.withMemoryRebound(to: GTypeInstance.self, capacity: 1) { $0 }, gtk_label_get_type()) != 0,
           swiftString(gtk_label_get_text(opaque(widget))) == text {
            return widget
        }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if let found = label(showing: text, in: current) { return found }
            child = gtk_widget_get_next_sibling(current)
        }
        return nil
    }

    func testASubtitleShowsInEveryKindOfWindow() throws {
        let app = AdwaitaApplication()
        let subtitle = "Requested by a test"
        let options = AdwaitaApplication.WindowOptions(subtitle: subtitle)
        let documents: [(String, String)] = [
            ("app-w1", Self.document),
            ("app-w2", #"{"type": "NavigationStack", "id": 1, "properties": {"navigationTitle": "Own bars"}, "content": {"type": "Text", "id": 2, "properties": {"text": "Page"}}}"#),
            ("app-text", #"{"type": "NavigationSplitView", "id": 1, "sidebar": {"type": "Text", "id": 2, "properties": {"text": "Side"}}, "detail": {"type": "Text", "id": 3, "properties": {"text": "Detail"}}}"#),
            ("app-wide", #"{"type": "Text", "id": 1, "properties": {"text": "Own title"}, "toolbar": [{"type": "ToolbarItem", "id": 2, "properties": {"placement": "principal"}, "content": {"type": "Text", "id": 3, "properties": {"text": "Principal"}}}]}"#),
            ("app-bad", "{ not json"),
        ]
        var mapped: [String: Bool] = [:]
        var loaded: [String] = []
        app.handlers.didFinishLaunching = {
            for (uuid, document) in documents {
                app.presentWindow(json: Data(document.utf8), windowUUID: uuid, title: "Title", options: options)
            }
            _ = runAfter(milliseconds: 500) {
                for (uuid, _) in documents {
                    let line = app.gtkWindow(uuid).flatMap { self.label(showing: subtitle, in: typed($0)) }
                    mapped[uuid] = line.map { gtk_widget_get_mapped($0) != 0 } ?? false
                    if app.showsDocument(uuid) { loaded.append(uuid) }
                    app.closeWindow(uuid)
                }
                app.terminate()
            }
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(mapped, ["app-w1": true, "app-w2": true, "app-text": true, "app-wide": true, "app-bad": true])
        XCTAssertEqual(loaded, ["app-w1", "app-w2", "app-text", "app-wide"], "the documents themselves loaded")
    }

    /// The labels in `widget` showing `text`: the window's first, then those of what is over it.
    private func labels(showing text: String, in widget: WidgetPointer) -> [WidgetPointer] {
        var found: [WidgetPointer] = []
        if g_type_check_instance_is_a(widget.withMemoryRebound(to: GTypeInstance.self, capacity: 1) { $0 }, gtk_label_get_type()) != 0,
           swiftString(gtk_label_get_text(opaque(widget))) == text {
            found.append(widget)
        }
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            found += labels(showing: text, in: current)
            child = gtk_widget_get_next_sibling(current)
        }
        return found
    }

    /// Whether the start of `line`'s text is on screen in `window`. A label found in the tree says
    /// nothing about that: it can be below the screen, or in the middle of a sheet wider than its
    /// window.
    private func startIsInView(_ line: WidgetPointer, of window: UnsafeMutablePointer<GtkWindow>) -> Bool {
        var origin = graphene_point_t(x: 0, y: 0)
        var point = graphene_point_t(x: 0, y: 0)
        guard gtk_widget_get_mapped(line) != 0, gtk_widget_compute_point(line, typed(window), &origin, &point) != 0 else { return false }
        var textX: Int32 = 0
        var textY: Int32 = 0
        gtk_label_get_layout_offsets(opaque(line), &textX, &textY)
        var monitor = GdkRectangle()
        if let display = gdk_display_get_default(), let item = g_list_model_get_item(gdk_display_get_monitors(display), 0) {
            gdk_monitor_get_geometry(OpaquePointer(item), &monitor)
            g_object_unref(item)
        }
        let visibleWidth = min(gtk_widget_get_width(typed(window)), monitor.width)
        let visibleHeight = min(gtk_widget_get_height(typed(window)), monitor.height)
        let left = Int32(point.x) + textX
        return left >= 0 && left + 100 <= visibleWidth && point.y >= 0 && Int32(point.y) + gtk_widget_get_height(line) <= visibleHeight
    }

    func testAToolbarItemDoesNotPushTheSubtitleOutOfView() throws {
        let app = AdwaitaApplication()
        let subtitle = "Requested by a test"
        let options = AdwaitaApplication.WindowOptions(subtitle: subtitle, contentSize: (500, 400))
        func document(width: Int, height: Int) -> Data {
            Data(#"{"type": "Text", "id": 1, "properties": {"text": "Document"}, "toolbar": [{"type": "ToolbarItem", "id": 2, "properties": {"placement": "principal"}, "content": {"type": "Color", "id": 3, "properties": {"color": "gray", "frame": {"width": \#(width), "height": \#(height)}}}}]}"#.utf8)
        }
        var inView: [String: Bool] = [:]
        app.handlers.didFinishLaunching = {
            app.presentWindow(json: document(width: 100, height: 3000), windowUUID: "app-tall", title: nil, options: options)
            app.presentWindow(json: document(width: 5000, height: 20), windowUUID: "app-wide", title: nil, options: options)
            _ = runAfter(milliseconds: 500) {
                for uuid in ["app-tall", "app-wide"] {
                    guard let window = app.gtkWindow(uuid), let line = self.label(showing: subtitle, in: typed(window)) else { continue }
                    inView[uuid] = self.startIsInView(line, of: window)
                    app.closeWindow(uuid)
                }
                app.terminate()
            }
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(inView, ["app-tall": true, "app-wide": true])
    }

    func testASheetThatCoversTheWindowShowsTheSubtitleToo() throws {
        let app = AdwaitaApplication()
        let subtitle = String(repeating: "Requested by a test ", count: 20)
        let options = AdwaitaApplication.WindowOptions(subtitle: subtitle, contentSize: (500, 400))
        let cover = #"{"type": "Color", "id": 20, "properties": {"color": "red", "frame": {"width": 2000, "height": 2000}}}"#
        let document = #"{"type": "VStack", "id": 1, "children": [{"type": "Button", "id": 2, "properties": {"title": "Sheet"}, "sheet": \#(cover)}, {"type": "Button", "id": 3, "properties": {"title": "Cover"}, "fullScreenCover": {"type": "NavigationStack", "id": 30, "content": {"type": "Color", "id": 31, "properties": {"color": "blue", "frame": {"width": 3000, "height": 3000}}}}}]}"#
        var counts: [Int] = []
        var inView: [Bool] = []
        var windowCount = 0
        var plain: Int?
        app.handlers.didFinishLaunching = {
            // A watchdog: a test that goes wrong ends here instead of hanging.
            _ = runAfter(milliseconds: 8000) { app.terminate() }
            app.presentWindow(json: Data(document.utf8), windowUUID: "app-w1", title: "Sheets", options: options)
            app.presentWindow(json: Data(document.utf8), windowUUID: "app-w2", title: "Plain")
            @MainActor func show(_ uuid: String, _ id: Int, _ key: String, then next: @escaping @MainActor () -> Void) {
                _ = ActionUIModel.shared.setElementState(windowUUID: uuid, viewID: id, key: key, value: true)
                _ = runAfter(milliseconds: 400) {
                    let lines = app.gtkWindow(uuid).map { self.labels(showing: subtitle, in: typed($0)) } ?? []
                    if uuid == "app-w1", let window = app.gtkWindow(uuid), let line = lines.last {
                        // The window's own line, under the sheet, comes first.
                        inView.append(self.startIsInView(line, of: window))
                    }
                    _ = ActionUIModel.shared.setElementState(windowUUID: uuid, viewID: id, key: key, value: false)
                    if uuid == "app-w1" { counts.append(lines.count) } else { plain = lines.count }
                    _ = runAfter(milliseconds: 400) { next() }
                }
            }
            _ = runAfter(milliseconds: 200) {
                windowCount = app.gtkWindow("app-w1").map { self.labels(showing: subtitle, in: typed($0)).count } ?? 0
                show("app-w1", 2, "sheetVisible") {
                    show("app-w1", 3, "fullScreenCoverVisible") {
                        // No subtitle, no line, in the same document's sheet.
                        show("app-w2", 2, "sheetVisible") {
                            app.closeWindow("app-w1")
                            app.closeWindow("app-w2")
                            app.terminate()
                        }
                    }
                }
            }
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(windowCount, 1)
        XCTAssertEqual(counts, [2, 2], "the window's line and the sheet's, with a header bar and with its own")
        XCTAssertEqual(inView, [true, true], "the sheet's line is in view, however large the sheet")
        XCTAssertEqual(plain, 0)
    }

    func testALargeSheetShowsTheSubtitleInViewInARightToLeftLanguage() throws {
        gtk_widget_set_default_direction(GTK_TEXT_DIR_RTL)
        defer { gtk_widget_set_default_direction(GTK_TEXT_DIR_LTR) }
        let app = AdwaitaApplication()
        let subtitle = "Requested by a test"
        let document = #"{"type": "Button", "id": 1, "properties": {"title": "Sheet"}, "sheet": {"type": "Color", "id": 2, "properties": {"color": "red", "frame": {"width": 2000, "height": 2000}}}}"#
        var inView = false
        app.handlers.didFinishLaunching = {
            _ = runAfter(milliseconds: 8000) { app.terminate() }
            app.presentWindow(json: Data(document.utf8), windowUUID: "app-w1", title: "Sheet",
                              options: AdwaitaApplication.WindowOptions(subtitle: subtitle, contentSize: (500, 400)))
            _ = ActionUIModel.shared.setElementState(windowUUID: "app-w1", viewID: 1, key: "sheetVisible", value: true)
            _ = runAfter(milliseconds: 500) {
                if let window = app.gtkWindow("app-w1"), let line = self.labels(showing: subtitle, in: typed(window)).last {
                    inView = self.startIsInView(line, of: window)
                }
                _ = ActionUIModel.shared.setElementState(windowUUID: "app-w1", viewID: 1, key: "sheetVisible", value: false)
                _ = runAfter(milliseconds: 300) {
                    app.closeWindow("app-w1")
                    app.terminate()
                }
            }
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertTrue(inView)
    }

    func testALongSubtitleDoesNotWidenASheet() throws {
        let app = AdwaitaApplication()
        let subtitle = String(repeating: "Requested by a test ", count: 40)
        let document = #"{"type": "Button", "id": 1, "properties": {"title": "Sheet"}, "sheet": {"type": "Color", "id": 2, "properties": {"color": "red", "frame": {"width": 300, "height": 100}}}}"#
        var width: Int32 = 0
        var lineCount = 0
        app.handlers.didFinishLaunching = {
            _ = runAfter(milliseconds: 8000) { app.terminate() }
            app.presentWindow(json: Data(document.utf8), windowUUID: "app-w1", title: "Sheets",
                              options: AdwaitaApplication.WindowOptions(subtitle: subtitle, contentSize: (800, 600)))
            _ = ActionUIModel.shared.setElementState(windowUUID: "app-w1", viewID: 1, key: "sheetVisible", value: true)
            _ = runAfter(milliseconds: 600) {
                if let window = app.gtkWindow("app-w1") {
                    let lines = self.labels(showing: subtitle, in: typed(window))
                    lineCount = lines.count
                    width = lines.last.map { gtk_widget_get_width($0) } ?? 0
                }
                _ = ActionUIModel.shared.setElementState(windowUUID: "app-w1", viewID: 1, key: "sheetVisible", value: false)
                _ = runAfter(milliseconds: 300) {
                    app.closeWindow("app-w1")
                    app.terminate()
                }
            }
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(lineCount, 2)
        XCTAssertGreaterThan(width, 0)
        XCTAssertLessThan(width, 400, "the sheet stays the width of its content")
    }

    func testAPrincipalToolbarItemLeavesTheSubtitleWhereItIs() throws {
        let app = AdwaitaApplication()
        let subtitle = "Requested by a test"
        var principal = false
        app.handlers.didFinishLaunching = {
            app.presentWindow(json: Data(#"{"type": "Text", "id": 1, "properties": {"text": "Own title"}, "toolbar": [{"type": "ToolbarItem", "id": 2, "properties": {"placement": "principal"}, "content": {"type": "Text", "id": 3, "properties": {"text": "Principal"}}}]}"#.utf8),
                              windowUUID: "app-w1", title: "Title", options: AdwaitaApplication.WindowOptions(subtitle: subtitle))
            _ = runAfter(milliseconds: 300) {
                if let window = app.gtkWindow("app-w1") {
                    principal = self.label(showing: "Principal", in: typed(window)) != nil && self.label(showing: subtitle, in: typed(window)) != nil
                }
                app.closeWindow("app-w1")
                app.terminate()
            }
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertTrue(principal, "the document's title item and the subtitle both show")
    }

    func testALongSubtitleDoesNotWidenTheWindow() throws {
        let app = AdwaitaApplication()
        let subtitle = String(repeating: "Requested by a test ", count: 40)
        var plain: (Int32, Int32) = (0, 0)
        var withLine: (Int32, Int32) = (0, 0)
        var tooltip: String?
        var allocated: Int32 = 0
        var allocatedNotResizable: Int32 = 0
        app.handlers.didFinishLaunching = {
            app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil)
            app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w2", title: nil, options: AdwaitaApplication.WindowOptions(subtitle: subtitle))
            app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-big", title: nil, options: AdwaitaApplication.WindowOptions(subtitle: subtitle, isResizable: false))
            if let window = app.gtkWindow("app-w1") { plain = self.defaultSize(window) }
            if let window = app.gtkWindow("app-w2") {
                withLine = self.defaultSize(window)
                tooltip = self.label(showing: subtitle, in: typed(window)).flatMap { swiftString(gtk_widget_get_tooltip_text($0)) }
            }
            _ = runAfter(milliseconds: 300) {
                if let window = app.gtkWindow("app-w2") { allocated = gtk_widget_get_width(typed(window)) }
                if let window = app.gtkWindow("app-big") { allocatedNotResizable = gtk_widget_get_width(typed(window)) }
                app.closeWindow("app-w1")
                app.closeWindow("app-w2")
                app.closeWindow("app-big")
                app.terminate()
            }
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(withLine.0, plain.0, "the document sets the width")
        XCTAssertEqual(allocated, plain.0, "and it opens at that width")
        XCTAssertEqual(allocatedNotResizable, plain.0, "resizable or not")
        XCTAssertGreaterThan(withLine.1, plain.1, "the line adds to the height")
        XCTAssertEqual(tooltip, subtitle, "all of it in the tooltip")
    }

    func testAContentSizeOpensTheWindowAtThatSizeAndTheMonitorCapsIt() throws {
        let app = AdwaitaApplication()
        var plain: (Int32, Int32) = (0, 0)
        var sized: (Int32, Int32) = (0, 0)
        var large: (Int32, Int32) = (0, 0)
        var oneSide: (Int32, Int32) = (0, 0)
        var resizable: gboolean = 0
        var monitor = GdkRectangle()
        if let display = gdk_display_get_default(), let item = g_list_model_get_item(gdk_display_get_monitors(display), 0) {
            gdk_monitor_get_geometry(OpaquePointer(item), &monitor)
            g_object_unref(item)
        }
        app.handlers.didFinishLaunching = {
            app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil)
            app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w2", title: nil, options: AdwaitaApplication.WindowOptions(contentSize: (500, 400)))
            app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-big", title: nil, options: AdwaitaApplication.WindowOptions(contentSize: (50000, 50000)))
            app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-tall", title: nil, options: AdwaitaApplication.WindowOptions(contentSize: (0, 400)))
            if let window = app.gtkWindow("app-w1") { plain = self.defaultSize(window) }
            if let window = app.gtkWindow("app-w2") {
                sized = self.defaultSize(window)
                resizable = gtk_window_get_resizable(window)
            }
            if let window = app.gtkWindow("app-big") { large = self.defaultSize(window) }
            if let window = app.gtkWindow("app-tall") { oneSide = self.defaultSize(window) }
            for uuid in ["app-w1", "app-w2", "app-big", "app-tall"] {
                app.closeWindow(uuid)
            }
            app.terminate()
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(sized.0, 500)
        XCTAssertGreaterThan(sized.1, 400, "the size is the content's: the header bar comes on top")
        XCTAssertEqual(resizable, 1, "a size given does not fix it")
        XCTAssertEqual(large.0, monitor.width)
        XCTAssertEqual(large.1, monitor.height)
        XCTAssertEqual(oneSide.0, plain.0, "a side not given stays the document's")
        XCTAssertEqual(oneSide.1, sized.1)
    }

    func testAContentSizeIsTheContentsWhateverBarsTheWindowHas() throws {
        let app = AdwaitaApplication()
        let stack = #"{"type": "NavigationStack", "id": 1, "properties": {"navigationTitle": "Own bars"}, "content": {"type": "Text", "id": 2, "properties": {"text": "Page"}}}"#
        let plain = AdwaitaApplication.WindowOptions(contentSize: (500, 400))
        let withLine = AdwaitaApplication.WindowOptions(subtitle: "Requested by a test", contentSize: (500, 400))
        let windows: [(String, String, AdwaitaApplication.WindowOptions)] = [
            ("app-w1", Self.document, plain), ("app-w2", Self.document, withLine), ("app-text", stack, plain), ("app-big", stack, withLine),
        ]
        var sizes: [String: (Int32, Int32)] = [:]
        app.handlers.didFinishLaunching = {
            for (uuid, document, options) in windows {
                app.presentWindow(json: Data(document.utf8), windowUUID: uuid, title: nil, options: options)
            }
            _ = runAfter(milliseconds: 500) {
                for (uuid, _, _) in windows {
                    if let content = app.contentWidget(uuid) {
                        sizes[uuid] = (gtk_widget_get_width(content), gtk_widget_get_height(content))
                    }
                    app.closeWindow(uuid)
                }
                app.terminate()
            }
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(sizes.count, 4)
        for (uuid, size) in sizes {
            XCTAssertEqual(size.0, 500, uuid)
            XCTAssertEqual(size.1, 400, uuid)
        }
    }

    func testASubtitleCountsWhenTheMinimumIsCloseToTheMonitorsHeight() throws {
        var monitor = GdkRectangle()
        if let display = gdk_display_get_default(), let item = g_list_model_get_item(gdk_display_get_monitors(display), 0) {
            gdk_monitor_get_geometry(OpaquePointer(item), &monitor)
            g_object_unref(item)
        }
        let app = AdwaitaApplication()
        var plainScrolls = true
        var withLineScrolls = false
        app.handlers.didFinishLaunching = {
            app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil)
            let headerBar = app.gtkWindow("app-w1").map { self.defaultSize($0).1 - 320 } ?? 0
            // Fits under the header bar, but not under the header bar and the line.
            let tall = Data(#"{"type": "Color", "id": 1, "properties": {"color": "red", "frame": {"minWidth": 100, "minHeight": \#(monitor.height - headerBar - 5)}}}"#.utf8)
            app.presentWindow(json: tall, windowUUID: "app-tall", title: nil)
            app.presentWindow(json: tall, windowUUID: "app-big", title: nil, options: AdwaitaApplication.WindowOptions(subtitle: "Requested by a test"))
            if let window = app.gtkWindow("app-tall"), let content = self.content(window) {
                plainScrolls = swiftString(G_OBJECT_TYPE_NAME_of(content)) == "GtkScrolledWindow"
            }
            if let window = app.gtkWindow("app-big"), let content = self.content(window) {
                withLineScrolls = swiftString(G_OBJECT_TYPE_NAME_of(content)) == "GtkScrolledWindow"
            }
            for uuid in ["app-w1", "app-tall", "app-big"] {
                app.closeWindow(uuid)
            }
            app.terminate()
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertFalse(plainScrolls)
        XCTAssertTrue(withLineScrolls)
    }

    func testAMinimumTooLargeToAddUpScrolls() throws {
        let app = AdwaitaApplication()
        var scrolls = false
        // Each row is as tall as a frame goes: together they are past what a C int holds.
        let rows = (0..<4).map { #"{"type": "Color", "id": \#($0 + 2), "properties": {"color": "red", "frame": {"minWidth": 100, "minHeight": 1073741823}}}"# }
        app.handlers.didFinishLaunching = {
            app.presentWindow(json: Data(#"{"type": "VStack", "id": 1, "children": [\#(rows.joined(separator: ","))]}"#.utf8), windowUUID: "app-tall", title: nil)
            if let window = app.gtkWindow("app-tall"), let content = self.content(window) {
                scrolls = swiftString(G_OBJECT_TYPE_NAME_of(content)) == "GtkScrolledWindow"
            }
            app.closeWindow("app-tall")
            app.terminate()
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertTrue(scrolls)
    }

    func testAWindowThatIsNotResizableOpensAtItsSize() throws {
        let app = AdwaitaApplication()
        let rows = (0..<12).map { #"{"type": "Color", "id": \#($0 + 3), "properties": {"color": "red", "frame": {"width": 500, "height": 40}}}"# }
        let scrolling = #"{"type": "ScrollView", "id": 1, "content": {"type": "VStack", "id": 2, "children": [\#(rows.joined(separator: ","))]}}"#
        var results: [String: (resizable: gboolean, wanted: (Int32, Int32), got: (Int32, Int32))] = [:]
        let notResizable = AdwaitaApplication.WindowOptions(isResizable: false)
        app.handlers.didFinishLaunching = {
            app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil, options: notResizable)
            app.presentWindow(json: Data(scrolling.utf8), windowUUID: "app-scroll", title: nil, options: notResizable)
            app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w2", title: nil, options: AdwaitaApplication.WindowOptions(contentSize: (500, 400), isResizable: false))
            _ = runAfter(milliseconds: 500) {
                for uuid in ["app-w1", "app-scroll", "app-w2"] {
                    guard let window = app.gtkWindow(uuid) else { continue }
                    results[uuid] = (gtk_window_get_resizable(window), self.defaultSize(window),
                                     (gtk_widget_get_width(typed(window)), gtk_widget_get_height(typed(window))))
                    app.closeWindow(uuid)
                }
                app.terminate()
            }
        }
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(results.count, 3)
        for (uuid, result) in results {
            XCTAssertEqual(result.resizable, 0, uuid)
            XCTAssertEqual(result.got.0, result.wanted.0, "\(uuid) opens at the width it was given")
            XCTAssertEqual(result.got.1, result.wanted.1, "\(uuid) opens at the height it was given")
        }
    }

    func testWithKeepsRunningTheUsersCloseOfTheLastWindowLeavesTheApplicationRunning() throws {
        let app = AdwaitaApplication()
        app.keepsRunningWithoutWindows = true
        var asked = 0
        var events: [String] = []
        var runningAfterClose = false
        app.handlers.shouldTerminate = {
            asked += 1
            return true
        }
        app.handlers.windowWillClose = { events.append("close \($0)") }
        app.handlers.didFinishLaunching = {
            // A watchdog: a hold left behind fails the count below (it asks a second time).
            _ = runAfter(milliseconds: 5000) { app.terminate() }
            if let window = app.gtkWindow("app-w1") { gtk_window_close(window) }
            _ = runAfter(milliseconds: 200) {
                runningAfterClose = true
                app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w2", title: nil)
                if let window = app.gtkWindow("app-w2") { gtk_window_close(window) }
                _ = runAfter(milliseconds: 200) {
                    // Without the flag, the user's close asks and ends the application, as no hold is left.
                    app.keepsRunningWithoutWindows = false
                    app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-big", title: nil)
                    if let window = app.gtkWindow("app-big") { gtk_window_close(window) }
                }
            }
        }
        app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil)
        XCTAssertEqual(app.run(), 0)
        XCTAssertTrue(runningAfterClose, "the application outlives the user's close")
        XCTAssertEqual(events, ["close app-w1", "close app-w2", "close app-big"])
        XCTAssertEqual(asked, 1, "only the close without the flag asks")
    }

    func testWithKeepsRunningALoadingDocumentHoldsTheApplicationAsAWindowWould() throws {
        let server = try TestImageServer(png: [], document: Self.document)
        defer { server.stop() }
        let app = AdwaitaApplication()
        app.keepsRunningWithoutWindows = true
        var asked = 0
        var events: [String] = []
        app.handlers.shouldTerminate = {
            asked += 1
            return true
        }
        app.handlers.windowWillClose = { events.append("close \($0)") }
        app.handlers.windowWillPresent = { uuid in
            events.append("present \(uuid)")
            guard uuid == "app-big" else { return }
            DispatchQueue.main.async {
                if let window = app.gtkWindow("app-big") { gtk_window_close(window) }
                _ = runAfter(milliseconds: 200) {
                    // Without the flag, the user's close asks and ends the application, as no hold is left.
                    app.keepsRunningWithoutWindows = false
                    app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w2", title: nil)
                    if let window = app.gtkWindow("app-w2") { gtk_window_close(window) }
                }
            }
        }
        app.handlers.didFinishLaunching = {
            // A watchdog: a hold left behind fails the count below (it asks a second time).
            _ = runAfter(milliseconds: 5000) { app.terminate() }
            // The user closes the only window while its replacement loads: the load is dropped.
            app.presentWindow(url: server.base + "/view.json", windowUUID: "app-w1", title: nil)
            if let window = app.gtkWindow("app-w1") { gtk_window_close(window) }
            _ = runAfter(milliseconds: 200) {
                // The user closes the only window while another loads: that one opens.
                app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil)
                app.presentWindow(url: server.base + "/view.json", windowUUID: "app-big", title: nil)
                if let window = app.gtkWindow("app-w1") { gtk_window_close(window) }
            }
        }
        app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil)
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(events, ["present app-w1", "close app-w1", "present app-w1", "close app-w1", "present app-big", "close app-big",
                                "present app-w2", "close app-w2"])
        XCTAssertEqual(asked, 1, "only the close without the flag asks")
    }

    func testOptionsSurviveTheWaitForTheStartAndForARemoteDocument() throws {
        let server = try TestImageServer(png: [], document: Self.document)
        defer { server.stop() }
        let app = AdwaitaApplication()
        let subtitle = "Requested by a test"
        let options = AdwaitaApplication.WindowOptions(subtitle: subtitle, contentSize: (500, 400), isResizable: false)
        var seen: [String: (width: Int32, resizable: gboolean, showsSubtitle: Bool)] = [:]
        app.handlers.windowWillPresent = { uuid in
            guard let window = app.gtkWindow(uuid) else { return }
            seen[uuid] = (self.defaultSize(window).0, gtk_window_get_resizable(window), self.label(showing: subtitle, in: typed(window)) != nil)
            if seen.count == 3 {
                DispatchQueue.main.async { app.terminate() }
            }
        }
        app.handlers.didFinishLaunching = {
            // A watchdog: a window that never opens fails the count below instead of hanging.
            _ = runAfter(milliseconds: 5000) { app.terminate() }
            app.presentWindow(url: server.base + "/view.json", windowUUID: "app-big", title: nil, options: options)
        }
        app.presentWindow(json: Data(Self.document.utf8), windowUUID: "app-w1", title: nil, options: options)
        app.presentWindow(url: server.base + "/view.json", windowUUID: "app-w2", title: nil, options: options)
        XCTAssertEqual(app.run(), 0)
        XCTAssertEqual(Set(seen.keys), ["app-w1", "app-w2", "app-big"])
        for (uuid, window) in seen {
            XCTAssertEqual(window.width, 500, uuid)
            XCTAssertEqual(window.resizable, 0, uuid)
            XCTAssertTrue(window.showsSubtitle, uuid)
        }
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

/// For `swift test` with no display, where the renderer tests skip: a server over SSH still checks
/// documents.
@MainActor
final class AdwaitaApplicationNoDisplayTests: XCTestCase {
    override func tearDown() async throws {
        ActionUIModel.shared.windowModels["app-no-display"] = nil
    }

    func testWithNoDisplayPreparingLoads() throws {
        try XCTSkipIf(gdk_display_get_default() != nil, "a display is open; this one is for the runs that have none")
        ActionUIRegistry.shared.loadBuiltIns()
        let app = AdwaitaApplication()
        let good = app.prepareWindow(json: Data(#"{"type": "VStack", "id": 1, "children": [{"type": "Text", "id": 2, "properties": {"text": "Hello"}}]}"#.utf8),
                                     windowUUID: "app-no-display")
        XCTAssertNil(good.error)
        XCTAssertTrue(ActionUIModel.shared.hasWindow("app-no-display"), "the document loads")
        let bad = app.prepareWindow(json: Data("not json".utf8), windowUUID: "app-no-display")
        XCTAssertNotNil(bad.error, "a bad document is still found")
    }

    func testWithNoDisplayARunServesTheMainQueueUntilTerminate() throws {
        let app = AdwaitaApplication()
        try XCTSkipIf(app.hasDisplay, "a display is open; this one is for the runs that have none")
        app.runsWithoutDisplay = true
        var served = false
        var asked = false
        var secondRun: Int32?
        app.handlers.shouldTerminate = {
            asked = true
            return true
        }
        DispatchQueue.main.async {
            served = true
            secondRun = app.run()
            app.terminate()
        }
        XCTAssertEqual(app.run(), 0, "terminate ended the run")
        XCTAssertTrue(served, "work on the main queue ran")
        XCTAssertEqual(secondRun, 1, "a second run is refused, as with a display")
        XCTAssertTrue(asked, "shouldTerminate is asked, as with a display")
        XCTAssertFalse(app.hasDisplay, "and asking twice gives the same answer")
    }
}
