package com.abracode.actionui.Helpers

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import androidx.compose.runtime.LaunchedEffect
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.WindowModel
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Renders [windowModel]'s active WindowToast over the window root - the Android
 * counterpart of Apple's `ToastOverlayView` (attached by `WindowModalView`).
 * `ActionUI`'s `RenderWindow` places one of these in every top-level window, so it
 * observes that window's [WindowModel.windowToast] (Compose snapshot state) and
 * appears the moment a host handler calls `ActionUIModel.presentToast`.
 *
 * Platform idiom (not a port): Apple pins the banner to the *top* of the window;
 * Android shows the native transient-message element - a Material3 **Snackbar** at
 * the **bottom**. The model-level API and queue behavior are identical across
 * platforms (see [com.abracode.actionui.Common.WindowToast]); only this placement
 * differs.
 *
 * Like the dialog / modal hosts, this escapes the surrounding layout via a [Popup]
 * (bottom-anchored, non-focusable so it never steals input) rather than relying on
 * the root being a stack, and pads for the navigation bar / IME so it floats above
 * the system chrome the way a `Scaffold`-hosted snackbar does.
 *
 * The show / auto-dismiss is driven by the snackbar's own suspend API: [SnackbarHostState.showSnackbar]
 * suspends until the bar is dismissed or its action tapped, and [withTimeoutOrNull]
 * caps it at the toast's numeric `duration` (Apple's auto-dismiss semantics, which a
 * raw [SnackbarDuration] enum can't express). When it ends we fire the inline action
 * (if that is why it ended) and call `dismissToast`, which promotes the next queued
 * toast - so the effect re-runs for the new [com.abracode.actionui.Common.WindowToast.id].
 */
@Composable
fun WindowToastHost(windowModel: WindowModel) {
    val toast = windowModel.windowToast ?: return
    val windowUUID = windowModel.windowUUID
    val hostState = remember { SnackbarHostState() }

    LaunchedEffect(toast.id) {
        val durationMillis = (toast.duration * 1000).toLong().coerceAtLeast(0)
        val result = withTimeoutOrNull(durationMillis) {
            hostState.showSnackbar(
                message = toast.message,
                actionLabel = toast.action?.title,
                withDismissAction = false,
                duration = SnackbarDuration.Indefinite,
            )
        }
        if (result == SnackbarResult.ActionPerformed) {
            toast.action?.let {
                ActionUIModel.actionHandler(
                    actionID = it.actionID,
                    windowUUID = windowUUID,
                    viewID = 0,
                    viewPartID = 0,
                    context = null,
                )
            }
        }
        ActionUIModel.dismissToast(windowUUID)
    }

    Popup(
        alignment = Alignment.BottomCenter,
        properties = PopupProperties(focusable = false, clippingEnabled = false),
    ) {
        SnackbarHost(
            hostState = hostState,
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .imePadding(),
        )
    }
}
