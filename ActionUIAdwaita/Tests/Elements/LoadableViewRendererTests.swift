// Tests/Elements/LoadableViewRendererTests.swift
/*
 Tests for the LoadableView renderer on GTK: a file's description shown as the LoadableView's child,
 its elements' view models in the window; viewDidLoadActionID once per source; an http URL loading
 behind a spinner; a new source replacing the sub-view and its view models; messages for no source,
 a missing file (in the error color), a description that does not parse, a URL that fails, and a
 bundle name (Linux has no bundle); a document that loads itself, directly or through another,
 refused at the repeat while siblings showing one document both load it; a device refused.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class LoadableViewRendererTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []
    private var files: [String] = []
    private var server: TestImageServer?
    private var fired: [(actionID: String, viewID: Int)] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "loadable-\(name)"
        fired = []
        ActionUIModel.shared.registerActionHandler(for: "test.loaded") { [weak self] actionID, _, viewID, _, _ in
            MainActor.assumeIsolated { self?.fired.append((actionID, viewID)) }
        }
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIModel.shared.unregisterActionHandler(for: "test.loaded")
        server?.stop()
        server = nil
        for path in files {
            try? FileManager.default.removeItem(atPath: path)
        }
        files = []
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let window = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        windows.append(window)
        return try XCTUnwrap(window.root)
    }

    /// A description file with one Text, `id`, saying `text`.
    private func document(_ name: String, id: Int, text: String) throws -> String {
        let json = #"{"type": "Text", "id": \#(id), "properties": {"text": "\#(text)"}}"#
        let path = try TestImages.file(Array(json.utf8), name: name)
        files.append(path)
        return path
    }

    /// The LoadableView's only child widget.
    private func child(_ node: RenderNode) -> WidgetPointer? {
        let children = Gtk.Widget(node.widget).children.map(\.pointer)
        XCTAssertLessThanOrEqual(children.count, 1)
        return children.first
    }

    private func typeName(_ widget: WidgetPointer?) -> String? {
        widget.flatMap { swiftString(G_OBJECT_TYPE_NAME_of($0)) }
    }

    func testAFileIsShownAsTheChild() throws {
        let path = try document("loadable-a.json", id: 10, text: "Loaded")
        let node = try render(#"{"type": "LoadableView", "id": 1, "properties": {"filePath": "\#(path)"}}"#)
        let loaded = try XCTUnwrap(node.childNodes[10])
        XCTAssertEqual(Gtk.Label(loaded.widget).text, "Loaded")
        XCTAssertTrue(child(node) == loaded.outerWidget)
        XCTAssertNotNil(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[10], "the sub-view's model is in the window")
    }

    func testViewDidLoadFiresOncePerSource() throws {
        let first = try document("loadable-b.json", id: 10, text: "One")
        let second = try document("loadable-c.json", id: 20, text: "Two")
        _ = try render(#"{"type": "LoadableView", "id": 1, "properties": {"filePath": "\#(first)", "viewDidLoadActionID": "test.loaded"}}"#)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired.map(\.viewID), [1])
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "padding", value: 4)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired.count, 1, "the same source does not fire again")
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: second)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired.count, 2)
    }

    func testANewSourceReplacesTheSubViewAndItsModels() throws {
        let first = try document("loadable-d.json", id: 10, text: "One")
        let second = try document("loadable-e.json", id: 20, text: "Two")
        let node = try render(#"{"type": "LoadableView", "id": 1, "properties": {"filePath": "\#(first)"}}"#)
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: second)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(node.childNodes[10])
        XCTAssertEqual(node.childNodes[20].map { Gtk.Label($0.widget).text }, "Two")
        XCTAssertTrue(child(node) == node.childNodes[20]?.outerWidget)
        let models = ActionUIModel.shared.windowModels[windowUUID]?.viewModels
        XCTAssertNil(models?[10], "the old sub-view's model is gone")
        XCTAssertNotNil(models?[20])
    }

    func testAnHTTPURLLoadsBehindASpinner() throws {
        let server = try TestImageServer(png: [], document: #"{"type": "Text", "id": 30, "properties": {"text": "Remote"}}"#)
        self.server = server
        let node = try render(#"{"type": "LoadableView", "id": 1, "properties": {"url": "\#(server.base)/view.json", "viewDidLoadActionID": "test.loaded"}}"#)
        XCTAssertEqual(typeName(child(node)), "AdwSpinner")
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { node.childNodes[30] != nil }))
        XCTAssertEqual(node.childNodes[30].map { Gtk.Label($0.widget).text }, "Remote")
        XCTAssertTrue(child(node) == node.childNodes[30]?.outerWidget, "the spinner is gone")
        XCTAssertEqual(fired.map(\.viewID), [1])
    }

    func testAURLThatFinishesAfterANewSourceLoadsNothing() throws {
        let server = try TestImageServer(png: [], document: #"{"type": "Text", "id": 30, "properties": {"text": "Remote"}}"#)
        self.server = server
        let path = try document("loadable-f.json", id: 10, text: "File")
        let node = try render(#"{"type": "LoadableView", "id": 1, "properties": {"url": "\#(server.base)/view.json"}}"#)
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: path)
        SyncScheduler.shared.flush()
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { server.requests == 1 }))
        _ = AdwaitaTestHost.runMainLoop(until: { false }, timeoutMilliseconds: 300)
        let models = ActionUIModel.shared.windowModels[windowUUID]?.viewModels
        XCTAssertNil(models?[30], "the late URL loads nothing into the window")
        XCTAssertNotNil(models?[10], "the file's view models stay")
        XCTAssertTrue(child(node) == node.childNodes[10]?.outerWidget)
    }

    func testAURLThatFailsShowsTheFailure() throws {
        let server = try TestImageServer(png: [])
        self.server = server
        let node = try render(#"{"type": "LoadableView", "id": 1, "properties": {"url": "\#(server.base)/missing.json"}}"#)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { self.typeName(self.child(node)) == "GtkLabel" }))
        let label = try XCTUnwrap(child(node))
        XCTAssertTrue(Gtk.Label(label).text.hasPrefix("Failed to load view:"), Gtk.Label(label).text)
        XCTAssertTrue(Gtk.Widget(label).hasCSSClass("error"))
    }

    func testAMissingFileShowsTheFailureInTheErrorColor() throws {
        let node = try render(#"{"type": "LoadableView", "id": 1, "properties": {"filePath": "/no/such/view.json"}}"#)
        let label = try XCTUnwrap(child(node))
        XCTAssertEqual(Gtk.Label(label).text, "Failed to load view: The file \"view.json\" couldn't be opened because there is no such file.")
        XCTAssertTrue(Gtk.Widget(label).hasCSSClass("error"))
    }

    func testADescriptionThatDoesNotParseShowsTheFailure() throws {
        let path = try TestImages.file(Array("not json".utf8), name: "loadable-bad.json")
        files.append(path)
        let node = try render(#"{"type": "LoadableView", "id": 1, "properties": {"filePath": "\#(path)"}}"#)
        XCTAssertEqual(child(node).map { Gtk.Label($0).text }, "Failed to load view: The data couldn't be read because it isn't in the correct format.")
    }

    func testADocumentThatLoadsItselfIsRefusedAtTheRepeat() throws {
        let path = NSTemporaryDirectory() + "actionui-\(ProcessInfo.processInfo.processIdentifier)-loadable-self.json"
        let json = #"{"type": "VStack", "id": 20, "children": [{"type": "LoadableView", "id": 21, "properties": {"filePath": "\#(path)"}}]}"#
        try Data(json.utf8).write(to: URL(fileURLWithPath: path))
        files.append(path)
        let node = try render(#"{"type": "LoadableView", "id": 1, "properties": {"filePath": "\#(path)"}}"#)
        let inner = try XCTUnwrap(node.childNodes[20]?.childNodes[21], "the document loads once")
        let label = try XCTUnwrap(child(inner))
        XCTAssertEqual(Gtk.Label(label).text, "Failed to load view: it includes itself")
        XCTAssertTrue(Gtk.Widget(label).hasCSSClass("error"))
    }

    func testDocumentsThatLoadEachOtherAreRefusedAtTheRepeatAndSiblingsLoad() throws {
        let prefix = NSTemporaryDirectory() + "actionui-\(ProcessInfo.processInfo.processIdentifier)-loadable-"
        let a = prefix + "cycle-a.json", b = prefix + "cycle-b.json"
        try Data(#"{"type": "LoadableView", "id": 30, "properties": {"filePath": "\#(b)"}}"#.utf8).write(to: URL(fileURLWithPath: a))
        try Data(#"{"type": "LoadableView", "id": 31, "properties": {"filePath": "\#(a)"}}"#.utf8).write(to: URL(fileURLWithPath: b))
        files += [a, b]
        let text = try document("loadable-sibling.json", id: 40, text: "Sibling")
        let node = try render(#"{"type": "VStack", "id": 1, "children": ["#
            + #"{"type": "LoadableView", "id": 2, "properties": {"filePath": "\#(a)"}},"#
            + #"{"type": "LoadableView", "id": 3, "properties": {"filePath": "\#(text)"}},"#
            + #"{"type": "LoadableView", "id": 4, "properties": {"filePath": "\#(text)"}}]}"#)
        // a shows b, b shows a again: refused there.
        let repeated = try XCTUnwrap(node.childNodes[2]?.childNodes[30]?.childNodes[31])
        XCTAssertEqual(child(repeated).map { Gtk.Label($0).text }, "Failed to load view: it includes itself")
        // Two siblings showing the same document both load it.
        for id in [3, 4] {
            let sibling = try XCTUnwrap(node.childNodes[id])
            XCTAssertNotNil(sibling.childNodes[40], "sibling \(id) loads the shared document")
        }
    }

    func testAnOverlayOnALoadableViewMayShowTheSameDocument() throws {
        // SwiftUI applies the overlay around LoadableNestingGuard, so it is not inside the LoadableView.
        let text = try document("loadable-overlay.json", id: 50, text: "Shared")
        let node = try render(#"{"type": "LoadableView", "id": 1, "properties": {"filePath": "\#(text)"}, "#
            + #""overlay": {"type": "LoadableView", "id": 2, "properties": {"filePath": "\#(text)"}}}"#)
        XCTAssertNotNil(node.childNodes[50], "the LoadableView loads the document")
        let overlay = try XCTUnwrap(node.decorations?.overlay)
        XCTAssertNotNil(overlay.childNodes[50], "the overlay loads it too")
    }

    func testOnlyARegularFileIsLoaded() throws {
        let node = try render(#"{"type": "LoadableView", "id": 1, "properties": {"filePath": "/dev/zero"}}"#)
        let label = try XCTUnwrap(child(node))
        XCTAssertEqual(Gtk.Label(label).text, "Failed to load view: /dev/zero is not a regular file")
        XCTAssertTrue(Gtk.Widget(label).hasCSSClass("error"))
    }

    func testNoSourceAndABundleNameShowMessages() throws {
        let node = try render(#"{"type": "LoadableView", "id": 1, "properties": {}}"#)
        XCTAssertEqual(child(node).map { Gtk.Label($0).text }, "No valid source provided")
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "Settings.json")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(child(node).map { Gtk.Label($0).text }, "Bundle resource 'Settings.json' not found")
    }
}
