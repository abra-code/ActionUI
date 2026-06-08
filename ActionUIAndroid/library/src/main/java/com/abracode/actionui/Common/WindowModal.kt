package com.abracode.actionui.Common

/**
 * Window-level modal support - the Android port of the *modal* half of Apple's
 * `WindowModal.swift`: the `sheet` / `fullScreenCover` presentation driven by
 * `ActionUIModel.presentModal` / `dismissModal` and rendered by
 * [com.abracode.actionui.Helpers.WindowModalHost].
 *
 * Unlike a [WindowDialog] (pure title / message / buttons), a modal loads a JSON
 * sub-document, registers its [ViewModel]s into the window pool so the value / state
 * API reaches the modal's controls, and removes exactly those on dismiss. See
 * `Private/Android_Porting_Notes.md`.
 */

/** Presentation style for a window-level modal. Mirror of Swift's `ModalStyle`. */
enum class ModalStyle { SHEET, FULL_SCREEN_COVER }

/**
 * An active window-level modal: the loaded [element], its presentation [style], an
 * optional [onDismissActionID] fired once when it closes, and [loadedViewIDs] - the
 * element ids whose [ViewModel]s this modal added to the window pool (removed on
 * dismiss). Held by [WindowModel.windowModal]; created by
 * `ActionUIModel.presentModal`, cleared by `dismissModal`. Mirror of Swift's
 * `WindowModal`.
 */
data class WindowModal(
    val element: ActionUIElement,
    val style: ModalStyle,
    val onDismissActionID: String? = null,
    val loadedViewIDs: Set<Int>,
)
