// Sources/Runtime/WindowPresenter.swift
/*
 The window-level presentations of one window: what ActionUIModel.presentModal, presentAlert,
 presentConfirmationDialog and presentToast put in the window model, shown the GNOME way.

 - A modal (sheet or fullScreenCover): an AdwDialog over the window, a header bar with a close
   button above the modal's element. Closing it (the close button, Escape) dismisses the modal,
   which fires its onDismissActionID; a modal the host dismisses closes. fullScreenCover is a
   dialog too, as it is a sheet on macOS.
 - An alert or a confirmation dialog: an AdwAlertDialog, one response per button. A destructive
   button looks destructive; an alert's first plain button is the suggested one (the default on
   Return); a cancel button is the close response (Escape). The buttons are in the GNOME order,
   cancel on the left and the main action on the right. A button fires its action after the
   dialog is dismissed, so the action can present another. GNOME has no action sheet, so a
   confirmation dialog is an alert dialog too.
 - A toast: an AdwToast in the window's AdwToastOverlay, at the bottom (the GNOME place; macOS puts
   it at the top), its optional action as the toast's button. It is dismissed after its duration,
   or when its button is clicked (after the action fires); the model then shows the next queued
   toast.

 The presenter watches the three model values with withObservationTracking and shows what they
 hold after each change, from the main queue (onChange runs before the new value is stored). Each
 presentation is matched by its model value's id: a GTK signal for a presentation the model has
 already replaced or dismissed changes nothing.
*/

import CAdwaita
import Dispatch
import Observation
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@MainActor
final class WindowPresenter {
    let windowModel: WindowModel
    /// A widget in the window, which AdwDialog presents over.
    private let parent: WidgetPointer
    private let toastOverlay: OpaquePointer
    private var isActive = true
    private var updateQueued = false

    private var modal: PresentedModal?
    private var dialog: PresentedDialog?
    private var toast: PresentedToast?

    private var windowUUID: String { windowModel.windowUUID }

    /// Starts showing `windowModel`'s presentations over `parent`'s window, toasts in
    /// `toastOverlay` (an AdwToastOverlay).
    init(windowModel: WindowModel, parent: WidgetPointer, toastOverlay: OpaquePointer) {
        self.windowModel = windowModel
        self.parent = parent
        self.toastOverlay = toastOverlay
        update()
    }

    /// Stops watching and takes down what is shown, leaving the model as it is (the window closes).
    func stop() {
        isActive = false
        closeModal()
        closeDialog()
        closeToast()
    }

    /// Watches again after stop, showing what the model holds (a window that did not close after all).
    func resume() {
        guard !isActive else { return }
        isActive = true
        update()
    }

    /// The modal's render tree, while a modal is shown.
    var modalRoot: RenderNode? { modal?.root }
    /// The alert dialog shown, while there is one.
    var dialogWidget: WidgetPointer? { dialog?.widget.widget }
    /// The toast shown, while there is one.
    var toastObject: OpaquePointer? { toast.map { OpaquePointer($0.object.pointer) } }

    // MARK: Watching

    private func update() {
        guard isActive else { return }
        let (modal, dialog, toast) = withObservationTracking {
            (windowModel.windowModal, windowModel.windowDialog, windowModel.windowToast)
        } onChange: { [weak self] in
            MainActor.assumeIsolated { self?.queueUpdate() }
        }
        show(modal)
        show(dialog)
        show(toast)
    }

    private func queueUpdate() {
        guard isActive, !updateQueued else { return }
        updateQueued = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updateQueued = false
                self.update()
            }
        }
    }

    // MARK: Modal

    private final class PresentedModal {
        let id: UUID
        let widget: OwnedObject
        let root: RenderNode

        init(id: UUID, widget: consuming OwnedObject, root: RenderNode) {
            self.id = id
            self.widget = widget
            self.root = root
        }
    }

    private func show(_ windowModal: WindowModal?) {
        guard modal?.id != windowModal?.id else { return }
        closeModal()
        guard let windowModal else { return }
        guard let model = windowModel.viewModels[windowModal.element.id] else {
            ActionUIModel.shared.logger.log("WindowPresenter: no view model for the modal's element \(windowModal.element.id) in window \(windowUUID)", .error)
            return
        }
        let root = RenderNode(element: windowModal.element, model: model, windowModel: windowModel, parent: nil)
        // A NavigationStack brings the dialog's header bars itself (its pages').
        root.isWindowRoot = AdwaitaWindow.headerBarTypes.contains(windowModal.element.type)
        root.sync()

        // Sized by its content's natural size (the header bar's included), as AdwDialog does by default.
        let widget = OwnedObject(retaining: UnsafeMutableRawPointer(adw_dialog_new()!))
        let dialog: UnsafeMutablePointer<AdwDialog> = widget.typed()
        let toolbar = adw_toolbar_view_new()!
        if !root.isWindowRoot {
            let header = adw_header_bar_new()!
            adw_toolbar_view_add_top_bar(OpaquePointer(toolbar), header)
            // The modal's toolbars show in it.
            root.screenBar = ScreenBar(header: header, toolbarView: toolbar)
        }
        adw_toolbar_view_set_content(OpaquePointer(toolbar), root.outerWidget)
        adw_dialog_set_child(dialog, toolbar)

        let id = windowModal.id
        connectSignal(widget.pointer, "closed", .instanceOnly) { [weak self] in
            self?.modalClosed(id)
        }
        modal = PresentedModal(id: id, widget: widget, root: root)
        adw_dialog_present(dialog, parent)
    }

    /// "closed": the user closed the modal (or the presenter did, which cleared `modal` first).
    private func modalClosed(_ id: UUID) {
        guard let presented = modal, presented.id == id else { return }
        modal = nil
        presented.root.detach()
        if windowModel.windowModal?.id == id {
            ActionUIModel.shared.dismissModal(windowUUID: windowUUID)
        }
    }

    private func closeModal() {
        guard let presented = modal else { return }
        modal = nil
        adw_dialog_force_close(presented.widget.typed())
        presented.root.detach()
    }

    // MARK: Alert and confirmation dialog

    private final class PresentedDialog {
        let id: UUID
        let widget: OwnedObject
        let buttons: [DialogButton]

        init(id: UUID, widget: consuming OwnedObject, buttons: [DialogButton]) {
            self.id = id
            self.widget = widget
            self.buttons = buttons
        }
    }

    /// The response ID of the button at `index`.
    static func responseID(_ index: Int) -> String { "button-\(index)" }

    /// The order the buttons are added in, which libadwaita shows from left to right: the GNOME
    /// order, cancel first and the main action last (as on macOS). A document lists the main
    /// action first, as SwiftUI places buttons by role, so the others come in reverse.
    static func displayOrder(_ buttons: [DialogButton]) -> [Int] {
        let cancel = buttons.indices.filter { buttons[$0].role == .cancel }
        let others = buttons.indices.filter { buttons[$0].role != .cancel }
        return cancel + others.reversed()
    }

    private func show(_ windowDialog: WindowDialog?) {
        guard dialog?.id != windowDialog?.id else { return }
        closeDialog()
        guard let windowDialog else { return }
        // A dialog with no buttons still needs one to be answered (SwiftUI shows "OK").
        let buttons = windowDialog.buttons.isEmpty ? [DialogButton(title: "OK", role: .cancel)] : windowDialog.buttons

        let widget = OwnedObject(retaining: UnsafeMutableRawPointer(adw_alert_dialog_new(windowDialog.title, windowDialog.message)!))
        let alert: UnsafeMutablePointer<AdwAlertDialog> = widget.typed()
        for index in Self.displayOrder(buttons) {
            let button = buttons[index]
            adw_alert_dialog_add_response(alert, Self.responseID(index), button.title)
            if button.role == .destructive {
                adw_alert_dialog_set_response_appearance(alert, Self.responseID(index), ADW_RESPONSE_DESTRUCTIVE)
            }
        }
        if let cancel = buttons.firstIndex(where: { $0.role == .cancel }) {
            adw_alert_dialog_set_close_response(alert, Self.responseID(cancel))
        }
        if windowDialog.style == .alert, let plain = buttons.firstIndex(where: { $0.role == nil }) {
            adw_alert_dialog_set_response_appearance(alert, Self.responseID(plain), ADW_RESPONSE_SUGGESTED)
            adw_alert_dialog_set_default_response(alert, Self.responseID(plain))
        }

        let id = windowDialog.id
        for index in buttons.indices {
            connectSignal(widget.pointer, "response::\(Self.responseID(index))", .instanceAndArgument) { [weak self] in
                self?.dialogAnswered(id, button: index)
            }
        }
        // Closed without a response that is a button (Escape with no cancel button). AdwAlertDialog
        // emits "closed" before the response of a clicked button, so it waits a turn of the main
        // queue, by which time a response has been taken.
        connectSignal(widget.pointer, "closed", .instanceOnly) { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.dialogAnswered(id, button: nil) }
            }
        }
        dialog = PresentedDialog(id: id, widget: widget, buttons: buttons)
        adw_dialog_present(typed(alert), parent)
    }

    /// A response (`button`) or "closed" (nil): dismisses the dialog, then fires the button's action.
    private func dialogAnswered(_ id: UUID, button index: Int?) {
        guard let presented = dialog, presented.id == id else { return }
        dialog = nil
        if windowModel.windowDialog?.id == id {
            ActionUIModel.shared.dismissDialog(windowUUID: windowUUID)
        }
        if let index, let actionID = presented.buttons[index].actionID {
            ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: 0, viewPartID: 0)
        }
    }

    private func closeDialog() {
        guard let presented = dialog else { return }
        dialog = nil
        adw_dialog_force_close(presented.widget.typed())
    }

    // MARK: Toast

    private final class PresentedToast {
        let id: UUID
        let object: OwnedObject
        /// The duration's timer source; 0 once it has run.
        var timer: guint = 0

        init(id: UUID, object: consuming OwnedObject) {
            self.id = id
            self.object = object
        }
    }

    private func show(_ windowToast: WindowToast?) {
        guard toast?.id != windowToast?.id else { return }
        closeToast()
        guard let windowToast else { return }
        // adw_toast_new's reference goes to the overlay; the presenter keeps one of its own.
        let pointer = adw_toast_new(windowToast.message)!
        let object = OwnedObject(retaining: pointer)
        // The presenter times the toast: AdwToast counts whole seconds only.
        adw_toast_set_timeout(pointer, 0)
        let id = windowToast.id
        if let action = windowToast.action {
            adw_toast_set_button_label(pointer, action.title)
            // The toast dismisses itself after this; "dismissed" moves the model on.
            connectSignal(object.pointer, "button-clicked", .instanceOnly) { [weak self] in
                guard let self, self.toast?.id == id else { return }
                ActionUIModel.shared.actionHandler(action.actionID, windowUUID: self.windowUUID, viewID: 0, viewPartID: 0)
            }
        }
        connectSignal(object.pointer, "dismissed", .instanceOnly) { [weak self] in
            self?.toastDismissed(id)
        }
        let presented = PresentedToast(id: id, object: object)
        toast = presented
        adw_toast_overlay_add_toast(toastOverlay, pointer)
        // Clamped as a Double: Int(_:) stops the process on an infinite or huge duration (NaN is 0).
        let milliseconds = (windowToast.duration * 1000).rounded()
        let timeout: UInt32 = milliseconds > 0 ? UInt32(min(milliseconds, Double(UInt32.max))) : 0
        presented.timer = runAfter(milliseconds: timeout) { [weak self, weak presented] in
            presented?.timer = 0
            guard let self, let presented, self.toast === presented else { return }
            adw_toast_dismiss(OpaquePointer(presented.object.pointer))
        }
    }

    /// "dismissed": by its duration, its button or the user; the model shows the next toast.
    private func toastDismissed(_ id: UUID) {
        guard let presented = toast, presented.id == id else { return }
        toast = nil
        cancelTimer(presented)
        if windowModel.windowToast?.id == id {
            ActionUIModel.shared.dismissToast(windowUUID: windowUUID)
        }
    }

    private func closeToast() {
        guard let presented = toast else { return }
        toast = nil
        cancelTimer(presented)
        adw_toast_dismiss(OpaquePointer(presented.object.pointer))
    }

    private func cancelTimer(_ presented: PresentedToast) {
        if presented.timer != 0 {
            g_source_remove(presented.timer)
            presented.timer = 0
        }
    }
}
