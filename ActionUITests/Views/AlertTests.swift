// Tests/Views/AlertTests.swift
/*
 AlertTests.swift

 Tests for the window-level alert, confirmationDialog, and programmatic modal (presentModal)
 APIs added to ActionUIModel. These are all Tier-2 (detached) presentations.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class AlertTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!

    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString

        // Seed a WindowModel by loading a minimal root element
        let json = """
        { "id": 1, "type": "VStack", "children": [] }
        """.data(using: .utf8)!
        _ = try? ActionUIModel.shared.loadDescription(from: json, format: "json", windowUUID: windowUUID)
    }

    override func tearDown() {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        super.tearDown()
    }

    // MARK: - presentAlert

    func testPresentAlertSetsWindowDialog() {
        ActionUIModel.shared.presentAlert(windowUUID: windowUUID, title: "Error", message: "Something went wrong.")

        let dialog = ActionUIModel.shared.windowModels[windowUUID]?.windowDialog
        XCTAssertNotNil(dialog, "windowDialog should be set after presentAlert")
        XCTAssertEqual(dialog?.title, "Error")
        XCTAssertEqual(dialog?.message, "Something went wrong.")
        XCTAssertEqual(dialog?.style, .alert)
    }

    func testPresentAlertDefaultButtons() {
        ActionUIModel.shared.presentAlert(windowUUID: windowUUID, title: "Info")
        let dialog = ActionUIModel.shared.windowModels[windowUUID]?.windowDialog
        XCTAssertEqual(dialog?.buttons.count, 1, "Default alert should have one button")
        XCTAssertEqual(dialog?.buttons.first?.title, "OK")
        XCTAssertEqual(dialog?.buttons.first?.role, .cancel)
    }

    func testPresentAlertCustomButtons() {
        let buttons = [
            DialogButton(title: "Delete", role: .destructive, actionID: "delete.confirmed"),
            DialogButton(title: "Cancel", role: .cancel, actionID: nil)
        ]
        ActionUIModel.shared.presentAlert(windowUUID: windowUUID, title: "Delete?", buttons: buttons)
        let dialog = ActionUIModel.shared.windowModels[windowUUID]?.windowDialog
        XCTAssertEqual(dialog?.buttons.count, 2)
        XCTAssertEqual(dialog?.buttons[0].title, "Delete")
        XCTAssertEqual(dialog?.buttons[0].role, .destructive)
        XCTAssertEqual(dialog?.buttons[0].actionID, "delete.confirmed")
        XCTAssertEqual(dialog?.buttons[1].role, .cancel)
    }

    func testPresentAlertNoWindowModel() {
        // presentAlert with an unknown UUID logs an error and returns gracefully (no crash, no dialog set).
        // Swap to ConsoleLogger for this test so XCTestLogger doesn't fail on the expected error log.
        let savedLogger = ActionUIModel.shared.logger
        ActionUIModel.shared.logger = ConsoleLogger(maxLevel: .error)
        ActionUIModel.shared.presentAlert(windowUUID: "nonexistent-uuid", title: "Oops")
        ActionUIModel.shared.logger = savedLogger
        // Unknown UUID → no windowModel → no dialog set; nothing to assert beyond no crash
    }

    // MARK: - dismissDialog

    func testDismissDialogClearsWindowDialog() {
        ActionUIModel.shared.presentAlert(windowUUID: windowUUID, title: "Test")
        XCTAssertNotNil(ActionUIModel.shared.windowModels[windowUUID]?.windowDialog)

        ActionUIModel.shared.dismissDialog(windowUUID: windowUUID)
        XCTAssertNil(ActionUIModel.shared.windowModels[windowUUID]?.windowDialog, "windowDialog should be nil after dismissDialog")
    }

    func testDismissDialogIdempotent() {
        // Calling dismissDialog when no dialog is active should not crash
        ActionUIModel.shared.dismissDialog(windowUUID: windowUUID)
        ActionUIModel.shared.dismissDialog(windowUUID: windowUUID)
    }

    // MARK: - presentConfirmationDialog

    func testPresentConfirmationDialogSetsWindowDialog() {
        let buttons = [
            DialogButton(title: "Save", role: nil, actionID: "save"),
            DialogButton(title: "Don't Save", role: .destructive, actionID: "discard"),
            DialogButton(title: "Cancel", role: .cancel, actionID: nil)
        ]
        ActionUIModel.shared.presentConfirmationDialog(windowUUID: windowUUID, title: "Save changes?", message: "Unsaved changes will be lost.", buttons: buttons)

        let dialog = ActionUIModel.shared.windowModels[windowUUID]?.windowDialog
        XCTAssertNotNil(dialog)
        XCTAssertEqual(dialog?.style, .confirmationDialog)
        XCTAssertEqual(dialog?.title, "Save changes?")
        XCTAssertEqual(dialog?.message, "Unsaved changes will be lost.")
        XCTAssertEqual(dialog?.buttons.count, 3)
    }

    // MARK: - presentModal (Tier 2 window-level sheet)

    func testPresentModalSetsWindowModal() throws {
        let modalJSON = """
        { "id": 100, "type": "Text", "properties": { "text": "Modal content" } }
        """.data(using: .utf8)!

        try ActionUIModel.shared.presentModal(windowUUID: windowUUID, data: modalJSON, format: "json", style: .sheet)

        let modal = ActionUIModel.shared.windowModels[windowUUID]?.windowModal
        XCTAssertNotNil(modal, "windowModal should be set after presentModal")
        XCTAssertEqual(modal?.style, .sheet)
        XCTAssertEqual(modal?.element.id, 100)
        XCTAssertEqual(modal?.element.type, "Text")
    }

    func testPresentModalRegistersViewModels() throws {
        let modalJSON = """
        {
            "id": 200,
            "type": "VStack",
            "children": [
                { "id": 201, "type": "Text", "properties": { "text": "Hello" } },
                { "id": 202, "type": "Button", "properties": { "title": "Close" } }
            ]
        }
        """.data(using: .utf8)!

        try ActionUIModel.shared.presentModal(windowUUID: windowUUID, data: modalJSON, format: "json", style: .sheet)

        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID] else {
            XCTFail("WindowModel should exist"); return
        }
        XCTAssertNotNil(windowModel.viewModels[200], "Modal root ViewModel should be registered")
        XCTAssertNotNil(windowModel.viewModels[201], "Modal child ViewModel 201 should be registered")
        XCTAssertNotNil(windowModel.viewModels[202], "Modal child ViewModel 202 should be registered")
    }

    func testPresentModalWithOnDismissActionID() throws {
        var dismissFired = false
        ActionUIModel.shared.registerActionHandler(for: "modal.dismissed") { _, _, _, _, _ in
            dismissFired = true
        }

        let modalJSON = #"{ "id": 300, "type": "Text", "properties": { "text": "X" } }"#.data(using: .utf8)!
        try ActionUIModel.shared.presentModal(
            windowUUID: windowUUID, data: modalJSON, format: "json",
            style: .sheet, onDismissActionID: "modal.dismissed"
        )

        ActionUIModel.shared.dismissModal(windowUUID: windowUUID)
        XCTAssertTrue(dismissFired, "onDismissActionID should fire on dismissModal")
    }

    // MARK: - dismissModal

    func testDismissModalClearsWindowModal() throws {
        let modalJSON = #"{ "id": 400, "type": "Text", "properties": { "text": "X" } }"#.data(using: .utf8)!
        try ActionUIModel.shared.presentModal(windowUUID: windowUUID, data: modalJSON, format: "json", style: .sheet)
        XCTAssertNotNil(ActionUIModel.shared.windowModels[windowUUID]?.windowModal)

        ActionUIModel.shared.dismissModal(windowUUID: windowUUID)
        XCTAssertNil(ActionUIModel.shared.windowModels[windowUUID]?.windowModal)
    }

    func testDismissModalCleansUpViewModels() throws {
        let modalJSON = """
        {
            "id": 500,
            "type": "VStack",
            "children": [
                { "id": 501, "type": "Text", "properties": { "text": "X" } }
            ]
        }
        """.data(using: .utf8)!

        try ActionUIModel.shared.presentModal(windowUUID: windowUUID, data: modalJSON, format: "json", style: .sheet)

        guard let windowModel = ActionUIModel.shared.windowModels[windowUUID] else {
            XCTFail("WindowModel should exist"); return
        }
        XCTAssertNotNil(windowModel.viewModels[500])
        XCTAssertNotNil(windowModel.viewModels[501])

        ActionUIModel.shared.dismissModal(windowUUID: windowUUID)

        XCTAssertNil(windowModel.viewModels[500], "Modal root ViewModel should be removed after dismiss")
        XCTAssertNil(windowModel.viewModels[501], "Modal child ViewModel should be removed after dismiss")
    }

    func testDismissModalIdempotent() throws {
        // Dismissing when no modal is active should not crash
        ActionUIModel.shared.dismissModal(windowUUID: windowUUID)
        ActionUIModel.shared.dismissModal(windowUUID: windowUUID)
    }

    func testPresentModalFullScreenCoverStyle() throws {
        let modalJSON = #"{ "id": 600, "type": "Text", "properties": { "text": "Cover" } }"#.data(using: .utf8)!
        try ActionUIModel.shared.presentModal(windowUUID: windowUUID, data: modalJSON, format: "json", style: .fullScreenCover)

        XCTAssertEqual(ActionUIModel.shared.windowModels[windowUUID]?.windowModal?.style, .fullScreenCover)
    }

    func testPresentModalUnknownWindowUUID() {
        // presentModal throws when windowUUID is unknown and logs an error.
        // Swap to ConsoleLogger so XCTestLogger doesn't fail on the expected error log.
        let savedLogger = ActionUIModel.shared.logger
        ActionUIModel.shared.logger = ConsoleLogger(maxLevel: .error)
        defer { ActionUIModel.shared.logger = savedLogger }

        let json = #"{ "id": 1, "type": "Text", "properties": { "text": "X" } }"#.data(using: .utf8)!
        XCTAssertThrowsError(
            try ActionUIModel.shared.presentModal(windowUUID: "bad-uuid", data: json, format: "json", style: .sheet)
        )
    }
}
