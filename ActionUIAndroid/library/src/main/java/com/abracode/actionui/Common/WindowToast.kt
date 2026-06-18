package com.abracode.actionui.Common

/**
 * Window-level toast (snackbar) support - the Android port of Apple's
 * `WindowToast` (`ActionUI/Common/WindowToast.swift`): the transient,
 * auto-dismissing message driven by `ActionUIModel.presentToast` /
 * `dismissToast` and rendered by
 * [com.abracode.actionui.Helpers.WindowToastHost].
 *
 * Platform idiom (not a port): Apple pins the banner to the *top* of the window
 * (the notification-banner idiom); Android shows it as a *bottom* Material3
 * Snackbar, the native transient-message element - which also natively carries
 * the single optional action. The data shape and the model-level API are
 * identical across platforms; only the host's placement differs.
 */

/**
 * An optional inline action shown alongside a toast (for example "Undo"). Tapping
 * it fires [actionID] and dismisses the toast. Mirror of Swift's `ToastAction`.
 */
data class ToastAction(
    val title: String,
    val actionID: String,
)

/**
 * Pure data for an active window-level toast: a [message], an auto-dismiss
 * [duration] in seconds, and an optional inline [action]. No [ViewModel]s are
 * allocated. Held by [WindowModel.windowToast]; created by
 * `ActionUIModel.presentToast` and cleared (or promoted from the queue) by
 * `dismissToast`. Mirror of Swift's `WindowToast`.
 *
 * Each instance carries a unique [id]. It keys the host's show / auto-dismiss
 * effect so a replacing or queued toast re-runs it, and - because it is part of
 * the data-class identity - guarantees that assigning a structurally identical
 * toast (e.g. the same message posted twice) still triggers recomposition of the
 * snapshot-state [WindowModel.windowToast].
 */
data class WindowToast(
    val message: String,
    val duration: Double = 4.0,
    val action: ToastAction? = null,
    val id: Long = nextId(),
) {
    companion object {
        // Monotonic id source. All ActionUIModel presentation calls run on the
        // main thread (see the ActionUIModel class doc), so no synchronization is
        // needed - matching the rest of the model.
        private var counter: Long = 0
        private fun nextId(): Long = ++counter
    }
}
