// Tests/Runtime/WindowPresenterTests.swift
/*
 Tests for WindowPresenter, the window-level presentations on Linux, in a window on screen: an
 alert's buttons become responses (destructive, suggested, cancel as the close response) in the
 GNOME order (cancel left, the main action right), a click
 dismisses it and then fires the button's action, which can present another; a dialog the host
 dismisses closes without an action; a confirmation dialog suggests no button; a modal shows its
 element in a dialog, closing it dismisses the modal and fires onDismissActionID once, and one the
 host dismisses closes; a toast shows for its duration, then the next queued one; a toast's button
 fires its action and dismisses it; stopping takes everything down and leaves the model alone, and
 resuming shows it again.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class WindowPresenterTests: XCTestCase {
    private var windowUUID = ""
    private var gtkWindow: UnsafeMutablePointer<GtkWindow>?
    private var renderTree: AdwaitaWindow?
    private var fired: [String] = []
    private var actionIDs: [String] = []

    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        windowUUID = "presenter-\(name)"
        fired = []
    }

    override func tearDown() async throws {
        renderTree?.detach()
        renderTree = nil
        if let gtkWindow {
            gtk_window_destroy(gtkWindow)
        }
        gtkWindow = nil
        for actionID in actionIDs {
            ActionUIModel.shared.unregisterActionHandler(for: actionID)
        }
        actionIDs = []
        AdwaitaTestHost.drainMainLoop()
        ActionUIModel.shared.windowModels[windowUUID] = nil
    }

    private static let document = #"{"type": "VStack", "id": 1, "properties": {"frame": {"width": 480, "height": 360}}, "children": [{"type": "Text", "id": 2, "properties": {"text": "Window"}}]}"#

    /// The document in a window on screen, its presentations shown.
    private func present() throws -> WindowPresenter {
        _ = try ActionUIModel.shared.loadDescription(from: Data(Self.document.utf8), format: "json", windowUUID: windowUUID)
        let tree = AdwaitaWindow(windowModel: try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]))
        renderTree = tree
        let window: UnsafeMutablePointer<GtkWindow> = typed(adw_window_new()!)
        gtkWindow = window
        let overlay = adw_toast_overlay_new()!
        adw_toast_overlay_set_child(OpaquePointer(overlay), tree.contentWidget)
        adw_window_set_content(typed(window), overlay)
        gtk_window_set_default_size(window, 480, 360)
        gtk_window_present(window)
        tree.startPresenting(over: overlay, toastOverlay: OpaquePointer(overlay))
        AdwaitaTestHost.drainMainLoop()
        return try XCTUnwrap(tree.presenter)
    }

    /// Records each firing of `actionID`.
    private func record(_ actionID: String, then run: (@MainActor () -> Void)? = nil) {
        actionIDs.append(actionID)
        ActionUIModel.shared.registerActionHandler(for: actionID) { [weak self] id, _, _, _, _ in
            MainActor.assumeIsolated {
                self?.fired.append(id)
                run?()
            }
        }
    }

    private var windowModel: WindowModel { ActionUIModel.shared.windowModels[windowUUID]! }

    /// The first button under `widget` whose label is `label`.
    private func button(_ label: String, in widget: WidgetPointer) -> WidgetPointer? {
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if Gtk.Widget(current).isA(gtk_button_get_type()), swiftString(gtk_button_get_label(typed(current))) == label {
                return current
            }
            if let found = button(label, in: current) {
                return found
            }
            child = gtk_widget_get_next_sibling(current)
        }
        return nil
    }

    /// The labels of the buttons under `widget`, in the widget tree's order.
    private func buttonLabels(in widget: WidgetPointer) -> [String] {
        var labels: [String] = []
        var child = gtk_widget_get_first_child(widget)
        while let current = child {
            if Gtk.Widget(current).isA(gtk_button_get_type()), let label = swiftString(gtk_button_get_label(typed(current))) {
                labels.append(label)
            } else {
                labels += buttonLabels(in: current)
            }
            child = gtk_widget_get_next_sibling(current)
        }
        return labels
    }

    private func wait(_ condition: () -> Bool) -> Bool {
        AdwaitaTestHost.runMainLoop(until: condition, timeoutMilliseconds: 3000)
    }

    // MARK: Alerts and confirmation dialogs

    func testAnAlertsButtonsAreResponsesAndAClickDismissesThenFiresTheAction() throws {
        let presenter = try present()
        record("test.delete")
        ActionUIModel.shared.presentAlert(windowUUID: windowUUID, title: "Delete Item?", message: "It cannot be undone.", buttons: [
            DialogButton(title: "Keep"),
            DialogButton(title: "Delete", role: .destructive, actionID: "test.delete"),
            DialogButton(title: "Cancel", role: .cancel),
        ])
        XCTAssertTrue(wait { presenter.dialogWidget != nil })
        let dialog = try XCTUnwrap(presenter.dialogWidget)
        // Held, so it can be asked about once the presenter lets it go.
        g_object_ref(dialog)
        defer { g_object_unref(dialog) }
        let alert: UnsafeMutablePointer<AdwAlertDialog> = typed(dialog)
        XCTAssertEqual(swiftString(adw_alert_dialog_get_heading(alert)), "Delete Item?")
        XCTAssertEqual(swiftString(adw_alert_dialog_get_body(alert)), "It cannot be undone.")
        XCTAssertEqual(swiftString(adw_alert_dialog_get_close_response(alert)), WindowPresenter.responseID(2), "Cancel answers Escape")
        XCTAssertEqual(swiftString(adw_alert_dialog_get_default_response(alert)), WindowPresenter.responseID(0), "the first plain button")
        XCTAssertEqual(adw_alert_dialog_get_response_appearance(alert, WindowPresenter.responseID(0)), ADW_RESPONSE_SUGGESTED)
        XCTAssertEqual(adw_alert_dialog_get_response_appearance(alert, WindowPresenter.responseID(1)), ADW_RESPONSE_DESTRUCTIVE)
        XCTAssertEqual(adw_alert_dialog_get_response_appearance(alert, WindowPresenter.responseID(2)), ADW_RESPONSE_DEFAULT)
        XCTAssertEqual(buttonLabels(in: dialog), ["Cancel", "Delete", "Keep"], "the GNOME order: cancel left, the main action right")

        let delete = try XCTUnwrap(button("Delete", in: dialog))
        AdwaitaTestHost.emit("clicked", on: delete)
        XCTAssertEqual(fired, ["test.delete"])
        XCTAssertNil(windowModel.windowDialog, "dismissed")
        XCTAssertTrue(wait { presenter.dialogWidget == nil && gtk_widget_get_parent(dialog) == nil }, "the dialog closed")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired, ["test.delete"], "once")
    }

    func testAButtonsActionCanPresentAnotherDialog() throws {
        let presenter = try present()
        record("test.save") { [windowUUID] in
            ActionUIModel.shared.presentAlert(windowUUID: windowUUID, title: "Saved")
        }
        ActionUIModel.shared.presentConfirmationDialog(windowUUID: windowUUID, title: "Save changes?", buttons: [
            DialogButton(title: "Save", actionID: "test.save"),
            DialogButton(title: "Cancel", role: .cancel),
        ])
        XCTAssertTrue(wait { presenter.dialogWidget != nil })
        let first = try XCTUnwrap(presenter.dialogWidget)
        XCTAssertNil(swiftString(adw_alert_dialog_get_default_response(typed(first))), "a confirmation dialog suggests no button")
        XCTAssertEqual(buttonLabels(in: first), ["Cancel", "Save"])
        AdwaitaTestHost.emit("clicked", on: try XCTUnwrap(button("Save", in: first)))
        XCTAssertEqual(windowModel.windowDialog?.title, "Saved", "the action's alert is not dismissed with the first")
        // The first dialog is freed, so the second can have its address: compared by heading.
        XCTAssertTrue(wait { presenter.dialogWidget.map { swiftString(adw_alert_dialog_get_heading(typed($0))) } == "Saved" })
        let second = try XCTUnwrap(presenter.dialogWidget)
        XCTAssertNotNil(button("OK", in: second), "an alert with the default buttons has OK")
    }

    func testADialogTheHostDismissesClosesWithoutAnAction() throws {
        let presenter = try present()
        record("test.never")
        ActionUIModel.shared.presentAlert(windowUUID: windowUUID, title: "Wait", buttons: [DialogButton(title: "Go", actionID: "test.never")])
        XCTAssertTrue(wait { presenter.dialogWidget != nil })
        let dialog = try XCTUnwrap(presenter.dialogWidget)
        // Held, so it can be asked about once the presenter lets it go.
        g_object_ref(dialog)
        defer { g_object_unref(dialog) }
        ActionUIModel.shared.dismissDialog(windowUUID: windowUUID)
        XCTAssertTrue(wait { presenter.dialogWidget == nil && gtk_widget_get_parent(dialog) == nil })
        XCTAssertEqual(fired, [])
    }

    // MARK: Modals

    private static let modal = #"{"type": "VStack", "id": 50, "children": [{"type": "Text", "id": 51, "properties": {"text": "In the sheet"}}]}"#

    func testClosingAModalDismissesItAndFiresItsDismissActionOnce() throws {
        let presenter = try present()
        record("test.dismissed")
        try ActionUIModel.shared.presentModal(windowUUID: windowUUID, data: Data(Self.modal.utf8), format: "json", style: .sheet, onDismissActionID: "test.dismissed")
        XCTAssertTrue(wait { presenter.modalRoot != nil })
        let root = try XCTUnwrap(presenter.modalRoot)
        XCTAssertEqual(root.element.id, 50)
        let label = try XCTUnwrap(root.childNodes[51]?.widget)
        XCTAssertEqual(swiftString(gtk_label_get_text(opaque(label))), "In the sheet")
        XCTAssertTrue(wait { gtk_widget_get_mapped(label) != 0 }, "shown over the window")

        // As the dialog's close button does.
        let dialog: UnsafeMutablePointer<AdwDialog> = typed(try XCTUnwrap(gtk_widget_get_ancestor(label, adw_dialog_get_type())))
        XCTAssertNotEqual(adw_dialog_close(dialog), 0)
        XCTAssertTrue(wait { presenter.modalRoot == nil })
        XCTAssertNil(windowModel.windowModal)
        XCTAssertNil(windowModel.viewModels[51], "the modal's view models are removed")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired, ["test.dismissed"])
    }

    func testAModalTheHostDismissesCloses() throws {
        let presenter = try present()
        record("test.dismissed")
        try ActionUIModel.shared.presentModal(windowUUID: windowUUID, data: Data(Self.modal.utf8), format: "json", style: .fullScreenCover, onDismissActionID: "test.dismissed")
        XCTAssertTrue(wait { presenter.modalRoot != nil })
        let label = try XCTUnwrap(presenter.modalRoot?.childNodes[51]?.widget)
        XCTAssertTrue(wait { gtk_widget_get_ancestor(label, adw_dialog_get_type()) != nil })
        // Held, so it can be asked about once the presenter lets it go.
        let dialog = try XCTUnwrap(gtk_widget_get_ancestor(label, adw_dialog_get_type()))
        g_object_ref(dialog)
        defer { g_object_unref(dialog) }
        ActionUIModel.shared.dismissModal(windowUUID: windowUUID)
        XCTAssertTrue(wait { presenter.modalRoot == nil && gtk_widget_get_parent(dialog) == nil })
        AdwaitaTestHost.drainMainLoop()
        XCTAssertEqual(fired, ["test.dismissed"], "fired by the model's dismissal, not again by the closed dialog")
    }

    // MARK: Toasts

    func testAToastShowsForItsDurationThenTheNextQueuedOne() throws {
        let presenter = try present()
        ActionUIModel.shared.presentToast(windowUUID: windowUUID, message: "First", duration: 0.2)
        ActionUIModel.shared.presentToast(windowUUID: windowUUID, message: "Second", duration: 0.2)
        XCTAssertTrue(wait { presenter.toastObject != nil })
        XCTAssertEqual(swiftString(adw_toast_get_title(try XCTUnwrap(presenter.toastObject))), "First")
        XCTAssertEqual(adw_toast_get_timeout(try XCTUnwrap(presenter.toastObject)), 0, "timed by the presenter")
        XCTAssertTrue(wait { presenter.toastObject.map { swiftString(adw_toast_get_title($0)) } == "Second" }, "after the first's duration")
        XCTAssertTrue(wait { windowModel.windowToast == nil && presenter.toastObject == nil }, "after the second's")
    }

    func testAToastsButtonFiresItsActionAndDismissesIt() throws {
        let presenter = try present()
        record("test.undo")
        ActionUIModel.shared.presentToast(windowUUID: windowUUID, message: "Deleted", duration: 30, actionTitle: "Undo", actionID: "test.undo")
        XCTAssertTrue(wait { presenter.toastObject != nil })
        XCTAssertEqual(swiftString(adw_toast_get_button_label(try XCTUnwrap(presenter.toastObject))), "Undo")
        let overlay = try XCTUnwrap(gtkWindow.flatMap { adw_window_get_content(typed($0)) })
        var undo: WidgetPointer?
        XCTAssertTrue(wait { undo = button("Undo", in: overlay); return undo != nil }, "the toast's button is on screen")
        AdwaitaTestHost.emit("clicked", on: try XCTUnwrap(undo))
        XCTAssertEqual(fired, ["test.undo"])
        XCTAssertTrue(wait { windowModel.windowToast == nil && presenter.toastObject == nil })
        XCTAssertEqual(fired, ["test.undo"], "once")
    }

    // MARK: Stopping

    func testStoppingTakesEverythingDownAndLeavesTheModel() throws {
        let presenter = try present()
        try ActionUIModel.shared.presentModal(windowUUID: windowUUID, data: Data(Self.modal.utf8), format: "json", style: .sheet)
        // An endless duration is a timer at its longest.
        ActionUIModel.shared.presentToast(windowUUID: windowUUID, message: "Toast", duration: .infinity)
        XCTAssertTrue(wait { presenter.modalRoot != nil && presenter.toastObject != nil })
        presenter.stop()
        XCTAssertNil(presenter.modalRoot)
        XCTAssertNil(presenter.toastObject)
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNotNil(windowModel.windowModal, "the window closes; the model is not dismissed")
        XCTAssertNotNil(windowModel.windowToast)
        ActionUIModel.shared.presentAlert(windowUUID: windowUUID, title: "Late")
        AdwaitaTestHost.drainMainLoop()
        XCTAssertNil(presenter.dialogWidget, "no longer watching")
        presenter.resume()
        XCTAssertNotNil(presenter.modalRoot, "resumed: what the model holds is shown again")
        XCTAssertNotNil(presenter.toastObject)
        XCTAssertEqual(presenter.dialogWidget.map { swiftString(adw_alert_dialog_get_heading(typed($0))) }, "Late")
    }
}
