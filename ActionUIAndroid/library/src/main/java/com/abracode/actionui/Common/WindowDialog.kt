package com.abracode.actionui.Common

/**
 * Window-level dialog support - the Android port of the *dialog* half of Apple's
 * `WindowModal.swift`: the `alert` / `confirmationDialog` types driven by
 * `ActionUIModel.presentAlert` / `presentConfirmationDialog` / `dismissDialog` and
 * rendered by [com.abracode.actionui.Helpers.WindowDialogHost].
 *
 * The *modal* half (`sheet` / `fullScreenCover`, which load a JSON sub-document)
 * lands separately. See `Private/Android_Porting_Notes.md`.
 */

/** Distinguishes a system alert from a confirmation dialog (iOS action sheet). */
enum class DialogStyle { ALERT, CONFIRMATION_DIALOG }

/**
 * The semantic role of a [DialogButton], mirroring SwiftUI's `ButtonRole`:
 * [DEFAULT] (no role), [DESTRUCTIVE] (shown in the error color), and [CANCEL] (the
 * dismissing / least-emphasized action).
 */
enum class DialogButtonRole { DEFAULT, DESTRUCTIVE, CANCEL }

/**
 * A button in a window-level alert or confirmation dialog. [actionID] fires on tap
 * (null = dismiss only). Mirror of Swift's `DialogButton`.
 */
data class DialogButton(
    val title: String,
    val role: DialogButtonRole = DialogButtonRole.DEFAULT,
    val actionID: String? = null,
)

/**
 * Pure data for an active window-level dialog: no [ViewModel]s are allocated (the
 * content is [title] / [message] / [buttons] only). Held by
 * [WindowModel.windowDialog]; created by `ActionUIModel.presentAlert` /
 * `presentConfirmationDialog` and cleared by `dismissDialog`. Mirror of Swift's
 * `WindowDialog`.
 */
data class WindowDialog(
    val style: DialogStyle,
    val title: String,
    val message: String? = null,
    val buttons: List<DialogButton>,
)
