// Tests/Runtime/EnvironmentTests.swift
/*
 Tests for Environment: the inherited base modifiers resolve from the node and its ancestors, the
 nearest setting winning; labelsHidden from any ancestor; SwiftUI's defaults without one; and a
 change on an ancestor re-syncs a descendant that read its environment.
*/

import XCTest
import CAdwaita
@testable import ActionUI

/// Text as a label recording the environment its update saw, and how often it updated.
@MainActor
enum EnvironmentRecordingRenderer: ActionUIAdwaitaRenderer {
    static var seen: [Int: Environment] = [:]
    static var updates: [Int: Int] = [:]

    static func makeWidget(_ node: RenderNode) -> WidgetPointer {
        gtk_label_new(nil)!
    }

    static func update(_ widget: WidgetPointer, _ node: RenderNode) {
        seen[node.element.id] = node.environment
        updates[node.element.id, default: 0] += 1
    }
}

@MainActor
final class EnvironmentTests: XCTestCase {
    private var windowUUID = ""
    private var windows: [AdwaitaWindow] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        ActionUIRegistry.shared.renderers["Text"] = EnvironmentRecordingRenderer.self
        EnvironmentRecordingRenderer.seen = [:]
        EnvironmentRecordingRenderer.updates = [:]
        windowUUID = "environment-\(name)"
    }

    override func tearDown() async throws {
        windows = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
        ActionUIRegistry.shared.loadBuiltIns()
    }

    private func render(_ json: String) throws {
        _ = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID)
        windows.append(AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID])))
    }

    func testDefaultsAreSwiftUIs() throws {
        try render(#"{"type": "Text", "id": 1}"#)
        let environment = try XCTUnwrap(EnvironmentRecordingRenderer.seen[1])
        XCTAssertEqual(environment.multilineTextAlignment, .leading)
        XCTAssertFalse(environment.textSelectable)
        XCTAssertNil(environment.buttonStyle)
        XCTAssertFalse(environment.labelsHidden)
    }

    func testTheNearestSettingWins() throws {
        try render(#"""
            {"type": "VStack", "id": 1, "properties": {"multilineTextAlignment": "center", "textSelection": "enabled", "labelsHidden": true, "buttonStyle": "bordered"},
             "children": [{"type": "VStack", "id": 2, "properties": {"multilineTextAlignment": "trailing", "textSelection": "disabled"},
                           "children": [{"type": "Text", "id": 3, "properties": {"buttonStyle": "automatic"}}]},
                          {"type": "Text", "id": 4, "properties": {"buttonStyle": "plain"}}]}
            """#)
        let inner = try XCTUnwrap(EnvironmentRecordingRenderer.seen[3])
        XCTAssertEqual(inner.multilineTextAlignment, .trailing, "the nearer VStack's")
        XCTAssertFalse(inner.textSelectable, "disabled nearer wins over enabled further up")
        XCTAssertTrue(inner.labelsHidden, "from any ancestor")
        XCTAssertEqual(inner.buttonStyle, .bordered, "automatic sets nothing: the style from further up stays")
        let sibling = try XCTUnwrap(EnvironmentRecordingRenderer.seen[4])
        XCTAssertEqual(sibling.multilineTextAlignment, .center)
        XCTAssertTrue(sibling.textSelectable)
        XCTAssertEqual(sibling.buttonStyle, .plain, "its own setting")
    }

    func testAnAncestorsChangeResyncsTheDescendant() throws {
        try render(#"{"type": "VStack", "id": 1, "children": [{"type": "Text", "id": 2}]}"#)
        XCTAssertEqual(EnvironmentRecordingRenderer.seen[2]?.multilineTextAlignment, .leading)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "multilineTextAlignment", value: "center")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(EnvironmentRecordingRenderer.seen[2]?.multilineTextAlignment, .center)
    }

    func testAGrandchildGetsTheChangeAndOtherAncestorChangesResyncNoDescendant() throws {
        try render(#"{"type": "VStack", "id": 1, "children": [{"type": "VStack", "id": 2, "children": [{"type": "Text", "id": 3}]}]}"#)
        XCTAssertEqual(EnvironmentRecordingRenderer.updates[3], 1)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "padding", value: 4)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(EnvironmentRecordingRenderer.updates[3], 1, "a change outside the environment re-syncs no descendant")
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "textSelection", value: "enabled")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(EnvironmentRecordingRenderer.seen[3]?.textSelectable, true, "through the middle VStack")
        XCTAssertEqual(EnvironmentRecordingRenderer.updates[3], 2)
    }

    func testAChangeReachesEveryLevelInOneFlush() throws {
        try render(#"{"type": "VStack", "id": 1, "children": [{"type": "VStack", "id": 2, "children": [{"type": "VStack", "id": 3, "children": [{"type": "Text", "id": 4}]}]}]}"#)
        ActionUIModel.shared.setElementProperty(windowUUID: windowUUID, viewID: 1, propertyName: "multilineTextAlignment", value: "trailing")
        // One flush, run by hand, not the main loop's several.
        SyncScheduler.shared.flush()
        XCTAssertEqual(EnvironmentRecordingRenderer.seen[4]?.multilineTextAlignment, .trailing)
    }
}
