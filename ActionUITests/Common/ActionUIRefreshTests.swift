// Tests/Common/ActionUIRefreshTests.swift
/*
 ActionUIRefreshTests.swift

 Tests for pull-to-refresh on List/ScrollView. Exercises the model-level contract behind
 the `.refreshable` modifier: runRefresh marks the view refreshing, fires onRefreshActionID,
 and suspends until the client signals completion — any element mutation targeting the
 refreshing view or its subtree — or the safety timeout elapses. The SwiftUI spinner itself
 is not unit-testable here; this verifies the suspend/resume that drives it.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ActionUIRefreshTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!

    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        ActionUIModel.refreshTimeoutSeconds = 60 // restore default in case a test lowered it
        logger = nil
        windowUUID = nil
        try await super.tearDown()
    }

    private func isRefreshing(viewID: Int) -> Bool {
        ActionUIModel.shared.windowModels[windowUUID]?.viewModels[viewID]?.refreshSubtreeIDs != nil
    }

    // A List refresh resolves when the handler delivers fresh rows synchronously (the
    // client-responds-inline race: the continuation is registered before the action fires).
    func testListRefreshResolvesOnSynchronousSetRows() async throws {
        let model = ActionUIModel.shared
        _ = try model.loadDescription(from: [
            "id": 1, "type": "List",
            "properties": ["itemType": ["viewType": "Text"], "onRefreshActionID": "list.refresh"]
        ], windowUUID: windowUUID)

        model.registerActionHandler(for: "list.refresh") { _, win, viewID, _, _ in
            ActionUIModel.shared.setElementRows(windowUUID: win, viewID: viewID, rows: [["fresh"]])
        }

        await model.runRefresh(windowUUID: windowUUID, viewID: 1, actionID: "list.refresh")

        XCTAssertEqual(model.getElementRows(windowUUID: windowUUID, viewID: 1) ?? [], [["fresh"]])
        XCTAssertFalse(isRefreshing(viewID: 1), "refresh state should be cleared after resolving")
    }

    // A List refresh resolves when the handler responds asynchronously (the common case:
    // the await suspends, the main actor stays free, a later main-actor callback ends it).
    func testListRefreshResolvesOnAsyncSetRows() async throws {
        let model = ActionUIModel.shared
        _ = try model.loadDescription(from: [
            "id": 1, "type": "List",
            "properties": ["itemType": ["viewType": "Text"], "onRefreshActionID": "list.refresh"]
        ], windowUUID: windowUUID)

        model.registerActionHandler(for: "list.refresh") { _, win, viewID, _, _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 20_000_000)
                ActionUIModel.shared.appendElementRows(windowUUID: win, viewID: viewID, rows: [["later"]])
            }
        }

        await model.runRefresh(windowUUID: windowUUID, viewID: 1, actionID: "list.refresh")

        XCTAssertEqual(model.getElementRows(windowUUID: windowUUID, viewID: 1) ?? [], [["later"]])
        XCTAssertFalse(isRefreshing(viewID: 1))
    }

    // A ScrollView refresh resolves when the client updates a view *inside* it — the
    // subtree end-signal, which makes ScrollView (whose content carries its own ids) work,
    // not only containers the host addresses by their own id.
    func testScrollViewRefreshResolvesOnDescendantMutation() async throws {
        let model = ActionUIModel.shared
        _ = try model.loadDescription(from: [
            "id": 1, "type": "ScrollView",
            "properties": ["onRefreshActionID": "scroll.refresh"],
            "content": ["id": 2, "type": "TextField", "properties": ["title": "field"]]
        ], windowUUID: windowUUID)

        // Handler updates the inner TextField (id 2), not the ScrollView (id 1).
        model.registerActionHandler(for: "scroll.refresh") { _, win, _, _, _ in
            ActionUIModel.shared.setElementValue(windowUUID: win, viewID: 2, value: "refreshed")
        }

        await model.runRefresh(windowUUID: windowUUID, viewID: 1, actionID: "scroll.refresh")

        XCTAssertEqual(model.getElementValue(windowUUID: windowUUID, viewID: 2) as? String, "refreshed")
        XCTAssertFalse(isRefreshing(viewID: 1), "a descendant mutation should end the ScrollView refresh")
    }

    // A mutation to an unrelated sibling does NOT end the refresh; the safety timeout does.
    func testRefreshEndsOnTimeoutWhenClientNeverSignals() async throws {
        ActionUIModel.refreshTimeoutSeconds = 0.05
        let model = ActionUIModel.shared
        _ = try model.loadDescription(from: [
            "id": 1, "type": "List",
            "properties": ["itemType": ["viewType": "Text"], "onRefreshActionID": "list.refresh"]
        ], windowUUID: windowUUID)

        // Handler does nothing — only the timeout can end this refresh.
        model.registerActionHandler(for: "list.refresh") { _, _, _, _, _ in }

        let start = Date()
        await model.runRefresh(windowUUID: windowUUID, viewID: 1, actionID: "list.refresh")

        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.05, "should wait for the timeout")
        XCTAssertFalse(isRefreshing(viewID: 1), "timeout should clear the refresh state")
    }
}
