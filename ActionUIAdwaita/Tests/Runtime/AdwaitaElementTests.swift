// Tests/Runtime/AdwaitaElementTests.swift
/*
 Tests for what an add-on registers (ActionUIAdwaitaElement), through FixtureBadge, an element in a
 module of its own: its token renders its widget instead of the placeholder, it gets its spec's
 initial value and states, what update reads re-syncs it, setNeedsUpdate re-syncs it, a node held
 after its window closed runs no update, and a later registration replaces the first. Its token is
 gone again once the built-ins are reloaded, as every test leaves them.
*/

import XCTest
import CAdwaita
import ActionUIAdwaitaAddOnFixture
@testable import ActionUI

@MainActor
final class AdwaitaElementTests: XCTestCase {
    private var windowUUID = ""
    private var window: AdwaitaWindow?

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        FixtureBadge.register()
        FixtureBadge.node = nil
        FixtureBadge.updates = 0
        FixtureBadge.seenType = ""
        FixtureBadge.seenWindow = ""
        FixtureBadge.suffix = ""
        windowUUID = "adwaita-element-\(name)"
    }

    override func tearDown() async throws {
        window = nil
        FixtureBadge.node = nil
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private let document = """
        {"type": "FixtureBadge", "id": 1, "properties": {"text": "seed"}}
        """

    /// The label a badge's node shows.
    private func render(_ json: String) throws -> RenderNode {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        let windowModel = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID])
        let window = AdwaitaWindow(windowModel: windowModel)
        self.window = window
        return try XCTUnwrap(window.root)
    }

    private func text(_ node: RenderNode) -> String? {
        swiftString(gtk_label_get_text(opaque(node.widget)))
    }

    func testARegisteredTokenShowsTheElementsWidgetInsteadOfThePlaceholder() throws {
        XCTAssertEqual(text(try render(document)), "seed")
    }

    func testAnUnregisteredTokenStillShowsThePlaceholder() throws {
        ActionUIRegistry.shared.loadBuiltIns()
        let node = try render(document)
        XCTAssertEqual(text(node), "FixtureBadge is not available on Linux yet")
    }

    func testTheSpecGivesTheElementItsInitialValueAndStates() throws {
        let node = try render(document)
        XCTAssertEqual(node.model.value as? String, "")
        XCTAssertEqual(node.model.states["prefix"] as? String, "")
    }

    func testTheElementSeesItsProperties() throws {
        let node = try render(document)
        XCTAssertEqual(node.properties["text"] as? String, "seed")
        XCTAssertEqual(FixtureBadge.seenWindow, windowUUID)
        XCTAssertEqual(FixtureBadge.seenType, "FixtureBadge")
    }

    func testAValueChangeRunsUpdateAgain() throws {
        let node = try render(document)
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: "changed")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(text(node), "changed")
    }

    func testAStateChangeRunsUpdateAgain() throws {
        let node = try render(document)
        ActionUIModel.shared.setElementState(windowUUID: windowUUID, viewID: 1, key: "prefix", value: "> ")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(text(node), "> seed")
    }

    func testAPropertyChangeRunsUpdateAgain() throws {
        let node = try render(document)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "text", value: "new")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(text(node), "new")
    }

    func testSetNeedsUpdateRunsUpdateForAChangeTheModelCannotReport() throws {
        let node = try render(document)
        FixtureBadge.suffix = "!"
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(text(node), "seed", "nothing the model tracks changed")
        FixtureBadge.refresh()
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(text(node), "seed!")
    }

    /// The badge's node, which outside code holds, updates while its window is open, and no more
    /// from the time the window starts closing.
    private func assertTheHeldNodeStopsUpdatingWhenTheWindowCloses(file: StaticString = #filePath, line: UInt = #line) {
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNotNil(FixtureBadge.node, "no badge was made", file: file, line: line)
        let updates = FixtureBadge.updates
        FixtureBadge.refresh()
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(FixtureBadge.updates, updates + 1, "in the tree", file: file, line: line)
        window?.detach()
        FixtureBadge.refresh()
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(FixtureBadge.updates, updates + 1, "the window is closing", file: file, line: line)
        window = nil
        AdwaitaTestHost.drainMainLoop()
        FixtureBadge.refresh()
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(FixtureBadge.updates, updates + 1, "the window is gone", file: file, line: line)
    }

    func testANodeHeldAfterItsWindowClosedRunsNoUpdate() throws {
        _ = try render(document)
        assertTheHeldNodeStopsUpdatingWhenTheWindowCloses()
    }

    func testAChildHeldAfterItsWindowClosedRunsNoUpdate() throws {
        _ = try render("""
            {"type": "VStack", "id": 1, "children": [{"type": "FixtureBadge", "id": 2, "properties": {"text": "seed"}}]}
            """)
        assertTheHeldNodeStopsUpdatingWhenTheWindowCloses()
    }

    func testAListTemplateRowHeldAfterItsWindowClosedRunsNoUpdate() throws {
        _ = try render("""
            {"type": "List", "id": 1, "template": {"type": "FixtureBadge", "properties": {"text": "$1"}}}
            """)
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: [["a"], ["b"]])
        assertTheHeldNodeStopsUpdatingWhenTheWindowCloses()
    }

    func testAStackTemplateRowHeldAfterItsWindowClosedRunsNoUpdate() throws {
        _ = try render("""
            {"type": "VStack", "id": 1, "template": {"type": "FixtureBadge", "properties": {"text": "$1"}}}
            """)
        ActionUIModel.shared.setElementValue(windowUUID: windowUUID, viewID: 1, value: [["a"], ["b"]])
        assertTheHeldNodeStopsUpdatingWhenTheWindowCloses()
    }

    func testTheElementsStateGoesWithItsNode() throws {
        let node = try render(document)
        XCTAssertNotNil(node.state)
        XCTAssertTrue(FixtureBadge.kept === node.state, "the node keeps what makeWidget gave it")
        FixtureBadge.node = nil
    }

    func testTheElementsStateIsReleasedWithTheWindow() throws {
        _ = try render(document)
        XCTAssertNotNil(FixtureBadge.kept)
        FixtureBadge.node = nil
        window = nil
        ActionUIModel.shared.windowModels[windowUUID] = nil
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(FixtureBadge.kept, "nothing keeps it once its node is gone")
    }

    func testBaseModifiersApplyAroundTheElementsWidget() throws {
        let node = try render("""
            {"type": "FixtureBadge", "id": 1, "properties": {"text": "seed", "hidden": true}}
            """)
        XCTAssertEqual(gtk_widget_get_opacity(node.outerWidget), 0, "ModifierBox hides the box, as for a built-in")
    }

    func testALaterRegistrationReplacesTheFirst() throws {
        ActionUIRegistry.shared.register(FixtureBadge.Replacement.self, as: "FixtureBadge")
        XCTAssertEqual(text(try render(document)), "replacement")
    }

    func testTheTokenDefaultsToTheTypesName() throws {
        // setUp registered this very token.
        ActionUIRegistry.shared.loadBuiltIns()
        XCTAssertNil(ActionUIRegistry.shared.renderers["FixtureBadge"])
        XCTAssertNil(ActionUIRegistry.shared.specs["FixtureBadge"])
        ActionUIRegistry.shared.register(FixtureBadge.self)
        XCTAssertNotNil(ActionUIRegistry.shared.renderers["FixtureBadge"])
        XCTAssertNotNil(ActionUIRegistry.shared.specs["FixtureBadge"])
    }
}
