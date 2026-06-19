// Tests/Views/ToastTests.swift
/*
 ToastTests.swift

 Tests for the window-level toast / snackbar API (presentToast / dismissToast) added to
 ActionUIModel. Like alert and presentModal, this is a Tier-2 (detached) presentation: it is
 triggered programmatically and renders as a top-pinned overlay via ToastOverlayView. These
 tests cover the model/queue behavior; the auto-dismiss timer and a11y announcement live in the
 SwiftUI view and are exercised manually.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ToastTests: XCTestCase {
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

        let json = """
        { "id": 1, "type": "VStack", "children": [] }
        """.data(using: .utf8)!
        _ = try? ActionUIModel.shared.loadDescription(from: json, format: "json", windowUUID: windowUUID)
    }

    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        try await super.tearDown()
    }

    // MARK: - presentToast

    func testPresentToastSetsWindowToast() {
        ActionUIModel.shared.presentToast(windowUUID: windowUUID, message: "Logged Evening meds")

        let toast = ActionUIModel.shared.windowModels[windowUUID]?.windowToast
        XCTAssertNotNil(toast, "windowToast should be set after presentToast")
        XCTAssertEqual(toast?.message, "Logged Evening meds")
        XCTAssertNil(toast?.action, "No inline action when actionTitle/actionID omitted")
    }

    func testPresentToastDefaultDuration() {
        ActionUIModel.shared.presentToast(windowUUID: windowUUID, message: "Hi")
        let toast = ActionUIModel.shared.windowModels[windowUUID]?.windowToast
        XCTAssertEqual(toast?.duration, 4.0, "Default duration should be 4.0 seconds")
    }

    func testPresentToastWithInlineAction() {
        ActionUIModel.shared.presentToast(
            windowUUID: windowUUID,
            message: "Logged Evening meds",
            duration: 5.0,
            actionTitle: "Undo",
            actionID: "task.undo"
        )
        let toast = ActionUIModel.shared.windowModels[windowUUID]?.windowToast
        XCTAssertEqual(toast?.duration, 5.0)
        XCTAssertEqual(toast?.action?.title, "Undo")
        XCTAssertEqual(toast?.action?.actionID, "task.undo")
    }

    func testPresentToastActionRequiresBothTitleAndID() {
        // actionTitle without actionID (or vice versa) yields no inline action.
        ActionUIModel.shared.presentToast(windowUUID: windowUUID, message: "x", actionTitle: "Undo")
        XCTAssertNil(ActionUIModel.shared.windowModels[windowUUID]?.windowToast?.action)
    }

    func testPresentToastQueuesWhenAlreadyVisible() {
        ActionUIModel.shared.presentToast(windowUUID: windowUUID, message: "first")
        ActionUIModel.shared.presentToast(windowUUID: windowUUID, message: "second")
        ActionUIModel.shared.presentToast(windowUUID: windowUUID, message: "third")

        let model = ActionUIModel.shared.windowModels[windowUUID]
        XCTAssertEqual(model?.windowToast?.message, "first", "First toast stays visible")
        XCTAssertEqual(model?.toastQueue.count, 2, "Subsequent toasts are queued")
        XCTAssertEqual(model?.toastQueue.first?.message, "second")
    }

    func testPresentToastNoWindowModel() {
        // Unknown UUID logs an error and returns gracefully (no crash, no toast set).
        let savedLogger = ActionUIModel.shared.logger
        ActionUIModel.shared.logger = ConsoleLogger(maxLevel: .error)
        ActionUIModel.shared.presentToast(windowUUID: "nonexistent-uuid", message: "nope")
        ActionUIModel.shared.logger = savedLogger
    }

    // MARK: - dismissToast

    func testDismissToastShowsNextQueued() {
        ActionUIModel.shared.presentToast(windowUUID: windowUUID, message: "first")
        ActionUIModel.shared.presentToast(windowUUID: windowUUID, message: "second")

        ActionUIModel.shared.dismissToast(windowUUID: windowUUID)

        let model = ActionUIModel.shared.windowModels[windowUUID]
        XCTAssertEqual(model?.windowToast?.message, "second", "Dismiss promotes the next queued toast")
        XCTAssertTrue(model?.toastQueue.isEmpty ?? false)
    }

    func testDismissToastClearsWhenQueueEmpty() {
        ActionUIModel.shared.presentToast(windowUUID: windowUUID, message: "only")
        ActionUIModel.shared.dismissToast(windowUUID: windowUUID)

        XCTAssertNil(ActionUIModel.shared.windowModels[windowUUID]?.windowToast, "windowToast cleared when no queue")
    }

    func testDismissToastNoWindowModelIsNoOp() {
        // Should not crash on an unknown UUID.
        ActionUIModel.shared.dismissToast(windowUUID: "nonexistent-uuid")
    }
}
