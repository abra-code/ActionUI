// Sources/Runtime/WindowPresenter+WinUI.swift
/*
 The window-level presentations of one window: what ActionUIModel.presentAlert and
 presentConfirmationDialog put in the window model, as WindowPresenter does on Linux. presentModal and
 presentToast are not shown yet.

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
 - WinUI shows one dialog at a time in a window: a dialog asked for while a sheet or another dialog is
   open is not shown. It is logged and dismissed in the model, so a later one can be shown.

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
    private var isActive = true
    private var updateQueued = false

    private var dialog: PresentedDialog?

    private var windowUUID: String { windowModel.windowUUID }

    /// Starts showing `windowModel`'s presentations over the window `anchor` is in (or will be in: the
    /// shim's alert waits for the content to load).
    init(windowModel: WindowModel, anchor: WinUIObject) {
        self.windowModel = windowModel
        self.anchor = anchor
        update()
    }

    /// Stops watching and takes down what is shown, leaving the model as it is (the window closes or
    /// takes other content).
    func stop() {
        isActive = false
        closeDialog()
    }

    // MARK: Watching

    private func update() {
        guard isActive else { return }
        let dialog = withObservationTracking {
            windowModel.windowDialog
        } onChange: { [weak self] in
            MainActor.assumeIsolated { self?.queueUpdate() }
        }
        show(dialog)
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
}
