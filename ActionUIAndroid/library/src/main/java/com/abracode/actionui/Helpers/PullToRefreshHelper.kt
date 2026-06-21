package com.abracode.actionui.Helpers

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.LocalWindowModel
import kotlinx.coroutines.delay

/**
 * Wraps a scrollable element's content in a Material3 [PullToRefreshBox] when the element
 * carries an `onRefreshActionID`, otherwise renders [content] unchanged. The Android side of
 * pull-to-refresh, shared by `List` and `ScrollView` (the Apple parity is the `.refreshable`
 * modifier on the same two elements).
 *
 * On a pull, [ActionUIModel.beginRefresh] flips the snapshot-backed
 * `states[`[ActionUIModel.REFRESHING_STATE_KEY]`]` (read here, so this recomposes) and fires
 * the actionID. The indicator retracts when the client delivers data to this view or anything
 * inside it - any element mutation, see [ActionUIModel.endRefreshTargeting] - so no dedicated
 * "done" API is needed. A safety timeout (driven from the [LaunchedEffect] below) ends a refresh
 * whose client never responds, mirroring Swift's `refreshTimeoutSeconds`.
 *
 * [content] keeps its own modifier (the `List`'s bounded `LazyColumn`, the `ScrollView`'s
 * scroll `Box`); the box wraps it without altering the non-refresh layout.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun RefreshableScrollContainer(
    element: ActionUIElement,
    content: @Composable () -> Unit,
) {
    val onRefreshActionID = element.properties?.stringProperty("onRefreshActionID")
    if (onRefreshActionID == null) {
        content()
        return
    }

    val windowModel = LocalWindowModel.current
    val windowUUID = windowModel?.windowUUID ?: ""
    val viewModel = windowModel?.viewModels?.get(element.id)
    val refreshing = (viewModel?.states?.get(ActionUIModel.REFRESHING_STATE_KEY) as? Boolean) ?: false

    // Safety net: end the refresh if the client never signals within the timeout (keyed on
    // `refreshing`, so it is armed when a refresh starts and cancelled when it ends).
    LaunchedEffect(refreshing) {
        if (refreshing) {
            delay(ActionUIModel.refreshTimeoutMillis)
            ActionUIModel.endRefreshTargeting(windowUUID, element.id)
        }
    }

    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = { ActionUIModel.beginRefresh(windowUUID, element.id, onRefreshActionID) },
    ) {
        content()
    }
}
