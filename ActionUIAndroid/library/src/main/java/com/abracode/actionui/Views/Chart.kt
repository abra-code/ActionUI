package com.abracode.actionui.Views

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * `Chart` on Android: a "Chart Unavailable" placeholder. Apple draws the element
 * with Swift Charts (`ActionUI/Views/Chart.swift`); Android has no chart renderer,
 * so it draws the [ContentUnavailableView] look in the chart's place, sized by the
 * element's own frame and padding, and logs one warning per process.
 *
 * The model keeps the parts of the Apple contract a host relies on: the value is a
 * String (the selection as JSON, `""` when nothing is selected; the user cannot
 * change it here), the rows (`states["content"]`) take the rows API, and
 * `setElementProperty(id, "chart", ...)` is stored like any property. The
 * description is not read: its inline `data` does not become the rows, and no
 * action fires.
 */
object Chart : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.STRING

    override fun initialValue(element: ActionUIElement): Any? = ""

    override fun initialStates(element: ActionUIElement): Map<String, Any> =
        mapOf(ActionUIModel.ROWS_STATE_KEY to emptyList<List<String>>())

    // Id 0: no view model, so the placeholder shows its own title, not the chart's value.
    internal val placeholder = ActionUIElement(
        type = "ContentUnavailableView",
        properties = buildJsonObject {
            put("title", "Chart Unavailable")
            put("description", "Charts are not supported on this platform.")
            put("systemImage", "chart.bar")
        },
    )

    @Volatile
    private var warned = false

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        LaunchedEffect(Unit) {
            if (!warned) {
                warned = true
                logger.log("Chart is not supported on Android; drawing a placeholder in its place", LoggerLevel.warning)
            }
        }
        ContentUnavailableView.BuildView(placeholder, modifier)
    }
}
