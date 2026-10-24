// Tests/Runtime/NodeAppearanceTests.swift
/*
 Tests for onAppearActionID and onDisappearActionID on GTK (NodeAppearance): the element's box
 mapped fires onAppearActionID, unmapped fires onDisappearActionID, each time, on the next turn of
 the main queue, with the element's id; leaving the tree fires onDisappearActionID; a tab switch
 makes a tab's content disappear and appear again.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class NodeAppearanceTests: XCTestCase {
    private var windowUUID = ""
    private var renderTree: AdwaitaWindow?
    private var gtkWindow: UnsafeMutablePointer<GtkWindow>?
    private var fired: [(actionID: String, viewID: Int)] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "node-appearance-\(name)"
        fired = []
        for id in ["test.appear", "test.disappear"] {
            ActionUIModel.shared.registerActionHandler(for: id) { [weak self] actionID, _, viewID, _, _ in
                MainActor.assumeIsolated { self?.fired.append((actionID, viewID)) }
            }
        }
    }

    override func tearDown() async throws {
        renderTree?.detach()
        renderTree = nil
        if let gtkWindow {
            gtk_window_destroy(gtkWindow)
        }
        gtkWindow = nil
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        for id in ["test.appear", "test.disappear"] {
            ActionUIModel.shared.unregisterActionHandler(for: id)
        }
    }

    private func present(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let tree = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        renderTree = tree
        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        gtkWindow = window
        adw_window_set_content(typed(window), tree.contentWidget)
        gtk_window_present(window)
        AdwaitaTestHost.drainMainLoop()
        return try XCTUnwrap(tree.root)
    }

    private func names() -> [String] { fired.map(\.actionID) }

    func testShowingAndHidingFiresEachTime() throws {
        let root = try present(#"""
            {"type": "VStack", "id": 1, "children": [{"type": "Text", "id": 2, "properties": {"text": "x",
              "onAppearActionID": "test.appear", "onDisappearActionID": "test.disappear"}}]}
            """#)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { names() == ["test.appear"] }), "\(names())")
        XCTAssertEqual(fired.first?.viewID, 2)
        let box = try XCTUnwrap(root.childNodes[2]).outerWidget!
        gtk_widget_set_visible(box, 0)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { names() == ["test.appear", "test.disappear"] }), "\(names())")
        gtk_widget_set_visible(box, 1)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { names() == ["test.appear", "test.disappear", "test.appear"] }), "\(names())")
    }

    func testLeavingTheTreeFiresDisappear() throws {
        _ = try present(#"""
            {"type": "VStack", "id": 1, "children": [{"type": "Text", "id": 2, "properties": {"text": "x", "onDisappearActionID": "test.disappear"}}]}
            """#)
        try ActionUIModel.shared.removeElement(windowUUID: windowUUID, viewID: 2)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { names() == ["test.disappear"] }), "\(names())")
    }

    func testATemplateRowLeavingAListFiresDisappear() throws {
        _ = try present(#"""
            {"type": "List", "id": 1, "template": {"type": "Text", "id": 3, "properties": {"text": "$1", "onDisappearActionID": "test.disappear"}}}
            """#)
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["a"], ["b"]])
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(names(), [])
        ActionUIModel.shared.setElementRows(windowUUID: windowUUID, viewID: 1, rows: [["a"]])
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { names() == ["test.disappear"] }), "\(names())")
    }

    func testClosingTheWindowFiresDisappear() throws {
        let app = AdwaitaApplication()
        app.handlers.didFinishLaunching = {
            // A watchdog: a window that stays open fails the test instead of hanging it.
            _ = runAfter(milliseconds: 5000) { app.terminate() }
            app.presentWindow(json: Data(#"""
                {"type": "VStack", "id": 1, "children": [{"type": "Text", "id": 2, "properties": {"text": "x",
                  "onAppearActionID": "test.appear", "onDisappearActionID": "test.disappear"}}]}
                """#.utf8), windowUUID: self.windowUUID, title: nil)
            // As the user closes it: nothing else holds the window's nodes meanwhile.
            _ = runAfter(milliseconds: 300) { app.gtkWindow(self.windowUUID).map { gtk_window_close($0) } }
        }
        XCTAssertEqual(app.run(), 0, "the last window closed: the application ended")
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { names() == ["test.appear", "test.disappear"] }), "\(names())")
        // Once: the window's tree is detached twice (the close, then its release).
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(names(), ["test.appear", "test.disappear"])
    }

    func testATabSwitchMakesItsContentDisappearAndAppear() throws {
        let tabs = try present(#"""
            {"type": "TabView", "id": 1, "children": [
              {"type": "Tab", "id": 2, "properties": {"title": "A"}, "content": {"type": "Text", "id": 20, "properties": {"text": "a",
                "onAppearActionID": "test.appear", "onDisappearActionID": "test.disappear"}}},
              {"type": "Tab", "id": 3, "properties": {"title": "B"}, "content": {"type": "Text", "id": 30, "properties": {"text": "b"}}}]}
            """#)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { names() == ["test.appear"] }), "\(names())")
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: tabs.element.id, value: 1)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { names() == ["test.appear", "test.disappear"] }), "\(names())")
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: tabs.element.id, value: 0)
        XCTAssertTrue(AdwaitaTestHost.runMainLoop(until: { names() == ["test.appear", "test.disappear", "test.appear"] }), "\(names())")
    }
}
