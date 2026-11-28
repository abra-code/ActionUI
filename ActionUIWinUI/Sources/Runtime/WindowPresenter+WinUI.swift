// Sources/Runtime/WindowPresenter+WinUI.swift
/*
 The window-level presentations of one window: what ActionUIModel.presentModal, presentAlert,
 presentConfirmationDialog and presentToast put in the window model, as WindowPresenter does on Linux.

 - A modal (sheet or fullScreenCover): a ContentDialog over the window showing the modal's element alone,
   as an element's own sheet is shown (NodePresentations): no title or buttons, as a macOS sheet shows its
   view alone, and a window smaller than the dialog grows to it while it is shown. fullScreenCover is a
   dialog too, as macOS makes it a sheet. Closing it (Escape) dismisses the modal in the model, which fires
   its onDismissActionID; a modal the host dismisses or replaces closes. A modal asked for before the
   window's content is in a window is shown once it is.

 - An alert or a confirmation dialog: a ContentDialog over the window (the shim's alert,
   actionUIWinUIAlertShow) with the title, the message and one button per DialogButton, in Fluent's
   places: the other buttons in the JSON's order from the left (the first is the primary button), and the
   cancel button last, as the close button, which Escape answers. Windows has no action sheet, so a
   confirmation dialog is an alert too, as on Linux.
 - The default button (Enter, and the first focus): an alert's first plain button, as on Linux; else the
   cancel button, so that Enter does not answer a destructive button when there is a cancel button. With
   neither, the first focus goes to the primary button, which Enter then answers (a lone button is the
   default on macOS too). A destructive button looks like the others: Fluent's dialog has no destructive
   style.
 - A dialog with no buttons gets "OK", as SwiftUI shows. A button fires its action after the dialog has
   closed, so the action can present another one.
 - WinUI shows one dialog at a time in a window: a modal or dialog asked for while a sheet or another dialog
   is open is not shown. It is logged and dismissed in the model (a modal's onDismissActionID fires), so a
   later one can be shown.

 - A toast: a Fluent InfoBar floating over the window's content at its top center, where macOS puts a toast
   (the shim's actionUIWinUIToastShow): the message, the optional action as the bar's button, and the bar's
   close button. It is taken down after its duration, after its action button fires its action, or when the
   user closes it; the model then shows the next queued toast. Narrator announces it as it opens. It is
   placed on the content below the window's toolbar rows, as macOS puts it below the toolbar. A toast shown
   while a dialog is open is above the dialog's dimming and takes clicks (the popups stack in the order they
   open), where on macOS the window behind a sheet takes none.

 The presenter watches the model values with withObservationTracking and shows what they hold after each
 change, from the main queue (onChange runs before the new value is stored). Each presentation is matched
 by its model value's id: an answer for a dialog the presenter has already taken down fires nothing. A
 dialog the model replaced is taken down at the next update, so an answer given before that still fires
 its action, as on Linux.
*/

import CWinUI
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
    /// An element in the window's content, which the dialogs open over.
    private let anchor: WinUIObject
    /// The content below the window's toolbar rows, whose top the toast is placed at (below the toolbar, as
    /// on macOS).
    private let toastAnchor: WinUIObject
    private var isActive = true
    private var updateQueued = false
    /// Whether the anchor entering a window updates again: connected the first time a modal or a toast
    /// finds it in no window, once.
    private var watchesLoaded = false

    private var modal: PresentedModal?
    private var dialog: PresentedDialog?
    private var toast: PresentedToast?

    private var windowUUID: String { windowModel.windowUUID }

    /// Starts showing `windowModel`'s presentations over the window `anchor` is in (or will be in: the
    /// shim's alert waits for the content to load), toasts at the top of `toastAnchor`.
    init(windowModel: WindowModel, anchor: WinUIObject, toastAnchor: WinUIObject) {
        self.windowModel = windowModel
        self.anchor = anchor
        self.toastAnchor = toastAnchor
        update()
    }

    /// Stops watching and takes down what is shown, leaving the model as it is (the window closes or
    /// takes other content).
    func stop() {
        isActive = false
        closeModal()
        closeDialog()
        closeToast()
    }

    // MARK: Watching

    private func update() {
        guard isActive else { return }
        let (modal, dialog, toast) = withObservationTracking {
            (windowModel.windowModal, windowModel.windowDialog, windowModel.windowToast)
        } onChange: { [weak self] in
            MainActor.assumeIsolated { self?.queueUpdate() }
        }
        show(modal)
        // A refused modal fires its onDismissActionID, whose handler may have closed the window or given it
        // other content (stop).
        guard isActive else { return }
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
        let shown: NodePresentations.Shown

        init(id: UUID, shown: NodePresentations.Shown) {
            self.id = id
            self.shown = shown
        }
    }

    private func show(_ windowModal: WindowModal?) {
        guard modal?.id != windowModal?.id else { return }
        closeModal()
        guard let windowModal else { return }
        guard actionUIWinUIElementIsInWindow(anchor.pointer) else {
            // The window is still being built: again once its content is in it.
            updateWhenLoaded()
            return
        }
        let id = windowModal.id
        guard let model = windowModel.viewModels[windowModal.element.id] else {
            ActionUIModel.shared.logger.log("WindowPresenter: no view model for the modal's element \(windowModal.element.id) in window \(windowUUID)", .error)
            return
        }
        let root = RenderNode(element: windowModal.element, model: model, windowModel: windowModel, parent: nil)
        root.sync()
        guard let content = root.outerView else {
            ActionUIModel.shared.logger.log("WindowPresenter: the modal's element \(windowModal.element.id) in window \(windowUUID) has no view", .error)
            root.detach()
            return
        }
        guard let host = WinUIObject(adopting: actionUIWinUIDialogCreate(content.pointer)) else {
            ActionUIModel.shared.logger.log("WindowPresenter: \(WinUIError.last("making a modal in window \(windowUUID)"))", .error)
            root.detach()
            return
        }
        WinUIEvents.connect(host, actionUIWinUIDialogOnClosed, "a modal's closing") { [weak self] in
            self?.modalClosed(id)
        }
        let presented = PresentedModal(id: id, shown: NodePresentations.Shown(host: host, root: root))
        modal = presented
        guard actionUIWinUIDialogShow(host.pointer, anchor.pointer) else {
            ActionUIModel.shared.logger.log("WindowPresenter: the modal was not shown in window \(windowUUID): \(WinUIError.last("showing it")) (WinUI shows one dialog at a time in a window)", .warning)
            takeDownModal()
            if windowModel.windowModal?.id == id {
                ActionUIModel.shared.dismissModal(windowUUID: windowUUID)
            }
            return
        }
        NodePresentations.growWindow(for: presented.shown, content: content, windowUUID: windowUUID)
    }

    /// Closed: the user closed the modal (Escape); one the presenter closed is no longer `modal`.
    private func modalClosed(_ id: UUID) {
        guard let presented = modal, presented.id == id else { return }
        takeDownModal()
        if windowModel.windowModal?.id == id {
            ActionUIModel.shared.dismissModal(windowUUID: windowUUID)
        }
    }

    /// Takes down the modal shown, firing nothing (the model replaced or dismissed it, or the window goes).
    private func closeModal() {
        guard let presented = modal else { return }
        takeDownModal()
        if !actionUIWinUIDialogHide(presented.shown.host.pointer) {
            ActionUIModel.shared.logger.log("WindowPresenter: \(WinUIError.last("closing a modal in window \(windowUUID)"))", .warning)
        }
    }

    /// Forgets the modal (so its Closed changes nothing) and detaches its tree; a window it grew gets its
    /// size back.
    private func takeDownModal() {
        guard let presented = modal else { return }
        modal = nil
        presented.shown.root.detach()
        if let grown = presented.shown.grown {
            WinUIWindow.shrinkAfterPresentation(windowUUID: windowUUID, from: grown)
        }
    }

    /// Updates again each time the anchor enters a window (WinUI's Loaded), on the main queue's next turn.
    private func updateWhenLoaded() {
        guard !watchesLoaded else { return }
        watchesLoaded = true
        WinUIEvents.connect(anchor, actionUIWinUIElementOnLoaded, "a window's content loading") { [weak self] in
            self?.queueUpdate()
        }
    }

    // MARK: Alert and confirmation dialog

    private final class PresentedDialog {
        let id: UUID
        /// The buttons in the order the shim was given them.
        let buttons: [DialogButton]
        /// The shim's dialog; nil until actionUIWinUIAlertShow returns it.
        var object: WinUIObject?

        init(id: UUID, buttons: [DialogButton]) {
            self.id = id
            self.buttons = buttons
        }
    }

    /// What the shim's completion needs: the presenter and the dialog it answers. Retained for the shim,
    /// which calls the completion exactly once.
    @MainActor
    private final class DialogContext {
        weak var presenter: WindowPresenter?
        let id: UUID

        init(presenter: WindowPresenter, id: UUID) {
            self.presenter = presenter
            self.id = id
        }
    }

    /// The buttons in Fluent's places, as the shim takes them: the others in the JSON's order, then the
    /// first cancel button (the close button); with the indices, in that order, of the button Escape
    /// answers and of the default one (nil: none).
    static func arranged(_ buttons: [DialogButton], style: DialogStyle) -> (buttons: [DialogButton], escape: Int?, defaultButton: Int?) {
        let cancel = buttons.firstIndex { $0.role == .cancel }
        var placed = buttons.indices.filter { $0 != cancel }.map { buttons[$0] }
        var escape: Int?
        if let cancel {
            escape = placed.count
            placed.append(buttons[cancel])
        }
        let plain = style == .alert ? placed.firstIndex { $0.role == nil } : nil
        return (placed, escape, plain ?? escape)
    }

    private func show(_ windowDialog: WindowDialog?) {
        guard dialog?.id != windowDialog?.id else { return }
        closeDialog()
        guard let windowDialog else { return }
        // A dialog with no buttons still needs one to be answered (SwiftUI shows "OK").
        let given = windowDialog.buttons.isEmpty ? [DialogButton(title: "OK", role: .cancel)] : windowDialog.buttons
        let (buttons, escape, defaultButton) = Self.arranged(given, style: windowDialog.style)

        let id = windowDialog.id
        let presented = PresentedDialog(id: id, buttons: buttons)
        dialog = presented
        let context = Unmanaged.passRetained(DialogContext(presenter: self, id: id)).toOpaque()
        let titles = CStrings(buttons.map(\.title))
        let shown = withExtendedLifetime(titles) {
            titles.pointers.withUnsafeBufferPointer { buffer in
                actionUIWinUIAlertShow(anchor.pointer, windowDialog.title, windowDialog.message, buffer.baseAddress,
                                       Int32(buffer.count), Int32(escape ?? -1), Int32(defaultButton ?? -1),
                                       Self.dialogAnswered, context)
            }
        }
        guard let object = WinUIObject(adopting: shown) else {
            // Not shown: the completion will not run.
            Unmanaged<DialogContext>.fromOpaque(context).release()
            ActionUIModel.shared.logger.log("WindowPresenter: the dialog \"\(windowDialog.title)\" was not shown in window \(windowUUID): \(WinUIError.last("showing it")) (WinUI shows one dialog at a time in a window)", .warning)
            dialog = nil
            if windowModel.windowDialog?.id == id {
                ActionUIModel.shared.dismissDialog(windowUUID: windowUUID)
            }
            return
        }
        presented.object = object
    }

    /// The shim's answer, on the UI thread, once per dialog: the index of the button chosen, or -1 when it
    /// closed unanswered (closeDialog dismissed it, or its window closed).
    private static let dialogAnswered: ActionUIWinUIAlertCompletion = { context, index in
        guard let context else { return }
        let answer = Unmanaged<DialogContext>.fromOpaque(context).takeRetainedValue()
        MainActor.assumeIsolated {
            answer.presenter?.dialogAnswered(answer.id, button: index >= 0 ? Int(index) : nil)
        }
    }

    /// A button (`index`) or a close with no answer (nil): dismisses the dialog in the model, then fires the
    /// button's action.
    private func dialogAnswered(_ id: UUID, button index: Int?) {
        guard let presented = dialog, presented.id == id else { return }
        dialog = nil
        if windowModel.windowDialog?.id == id {
            ActionUIModel.shared.dismissDialog(windowUUID: windowUUID)
        }
        if let index, presented.buttons.indices.contains(index), let actionID = presented.buttons[index].actionID {
            ActionUIModel.shared.actionHandler(actionID, windowUUID: windowUUID, viewID: 0, viewPartID: 0, origin: .host)
        }
    }

    /// Takes down the dialog shown, with no answer (its completion finds `dialog` cleared first).
    private func closeDialog() {
        guard let presented = dialog else { return }
        dialog = nil
        if let object = presented.object, !actionUIWinUIAlertDismiss(object.pointer) {
            ActionUIModel.shared.logger.log("WindowPresenter: \(WinUIError.last("closing a dialog in window \(windowUUID)"))", .warning)
        }
    }

    // MARK: Toast

    private final class PresentedToast {
        let id: UUID
        let object: WinUIObject
        /// Takes the toast down after its duration; canceled when it goes earlier.
        var timer: DispatchWorkItem?

        init(id: UUID, object: WinUIObject) {
            self.id = id
            self.object = object
        }
    }

    private func show(_ windowToast: WindowToast?) {
        guard toast?.id != windowToast?.id else { return }
        closeToast()
        guard let windowToast else { return }
        guard actionUIWinUIElementIsInWindow(anchor.pointer), actionUIWinUIElementIsInWindow(toastAnchor.pointer) else {
            // The window is still being built: again once its content is in it.
            updateWhenLoaded()
            return
        }
        let id = windowToast.id
        guard let object = WinUIObject(adopting: actionUIWinUIToastShow(toastAnchor.pointer, windowToast.message, windowToast.action?.title)) else {
            ActionUIModel.shared.logger.log("WindowPresenter: \(WinUIError.last("showing a toast in window \(windowUUID)")); it is skipped", .warning)
            // On to the next queued toast.
            if windowModel.windowToast?.id == id {
                ActionUIModel.shared.dismissToast(windowUUID: windowUUID)
            }
            return
        }
        let presented = PresentedToast(id: id, object: object)
        toast = presented
        if let action = windowToast.action {
            WinUIEvents.connect(object, actionUIWinUIToastOnAction, "a toast's action") { [weak self] in
                guard let self, self.toast?.id == id else { return }
                ActionUIModel.shared.actionHandler(action.actionID, windowUUID: self.windowUUID, viewID: 0, viewPartID: 0, origin: .host)
                self.toastDismissed(id)
            }
        }
        WinUIEvents.connect(object, actionUIWinUIToastOnClosed, "a toast's closing") { [weak self] in
            self?.toastDismissed(id)
        }
        // Clamped: NaN and a negative duration are 0, an infinite or huge one about 49 days, as on Linux.
        let seconds = windowToast.duration > 0 ? min(windowToast.duration, Double(UInt32.max) / 1000) : 0
        let timer = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.toastDismissed(id) }
        }
        presented.timer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: timer)
    }

    /// The toast's duration ran out, its action fired, or the user closed it: it comes down and the model
    /// moves on to the next queued toast.
    private func toastDismissed(_ id: UUID) {
        guard let presented = toast, presented.id == id else { return }
        closeToast()
        if windowModel.windowToast?.id == id {
            ActionUIModel.shared.dismissToast(windowUUID: windowUUID)
        }
    }

    /// Takes down the toast shown, leaving the model as it is.
    private func closeToast() {
        guard let presented = toast else { return }
        toast = nil
        presented.timer?.cancel()
        if !actionUIWinUIToastHide(presented.object.pointer) {
            ActionUIModel.shared.logger.log("WindowPresenter: \(WinUIError.last("closing a toast in window \(windowUUID)"))", .warning)
        }
    }
}
