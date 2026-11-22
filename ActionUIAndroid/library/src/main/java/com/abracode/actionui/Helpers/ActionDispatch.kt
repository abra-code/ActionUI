package com.abracode.actionui.Helpers

import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.remember
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.JSONContentOrigin
import com.abracode.actionui.Common.LocalJSONContentOrigin
import com.abracode.actionui.Common.LocalWindowModel

/**
 * Fires actions for the composable that remembered it ([rememberActionDispatch]), with the window
 * it is in and the origin of the content it belongs to: the host's handler gets the right window,
 * and the trust policy is asked about the action with that origin. An element with no id, or in a
 * template row, is judged by the content it is in, which a lookup by id could not do.
 */
@Stable
class ActionDispatch internal constructor(val windowUUID: String, val origin: JSONContentOrigin) {
    /** Fires [actionID] for element [viewID] (and its part [viewPartID]), with [context]. */
    fun fire(actionID: String, viewID: Int, viewPartID: Int = 0, context: Any? = null) {
        ActionUIModel.actionHandler(actionID, windowUUID, viewID, viewPartID, context, origin)
    }
}

/** An [ActionDispatch] for this place in the composition: its window and its content's origin. */
@Composable
fun rememberActionDispatch(): ActionDispatch {
    val windowUUID = LocalWindowModel.current?.windowUUID ?: ""
    val origin = LocalJSONContentOrigin.current
    return remember(windowUUID, origin) { ActionDispatch(windowUUID, origin) }
}
