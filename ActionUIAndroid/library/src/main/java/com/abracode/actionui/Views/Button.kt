package com.abracode.actionui.Views

import androidx.compose.material3.Button as M3Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.LocalActionUITint
import com.abracode.actionui.Helpers.LocalTemplateContext
import com.abracode.actionui.Helpers.stringProperty

/**
 * Renders a tappable button that dispatches an action through [ActionUIModel].
 *
 * Mirror of the Apple `Button` element (`ActionUI/Views/Button.swift`). Like
 * the Swift side, a Button carries no stateful value - it only triggers
 * actions. On tap, if the element declares an `actionID`, it is dispatched via
 * [ActionUIModel.actionHandler] with the element's `id` as the `viewID`, which
 * routes to the client's registered handler (or the default handler). Inside a
 * data-driven template row (see `Helpers/TemplateHelper.kt`) it instead
 * dispatches with the owning `List`/`Section` id as `viewID` and the row index
 * as `viewPartID`, read from [com.abracode.actionui.Helpers.LocalTemplateContext].
 *
 * Sample JSON:
 * ```
 * {
 *   "type": "Button",
 *   "id": 1,                       // Optional: positive id for action routing
 *   "properties": {
 *     "title": "Click Me",         // Optional: button label text
 *     "role": "destructive",       // Optional: "destructive" | "cancel"
 *     "actionID": "button.click"   // Optional: id dispatched on tap
 *   }
 * }
 * ```
 *
 * **Supported properties.** `title`, `role`, `actionID`, plus the universal
 * modifiers resolved by `applyCommonProperties` (the caller passes those in via
 * [modifier]).
 *
 * **Deferred vs. Apple.** SwiftUI's `systemImage` (SF Symbols), `assetImage`,
 * and `imageScale` have no direct Compose/Android equivalent and are not ported
 * yet - they are ignored here (consistent with the resolver's "unrecognized
 * property names are ignored silently" rule). `role: "destructive"` maps to an
 * error-colored button; `role: "cancel"` has no distinct Material styling (it
 * is meaningful only inside dialogs on Apple) and renders as a normal button.
 */
object Button : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current

        val title = props?.stringProperty("title") ?: ""

        // Validate role against the same vocabulary as the Apple side; an
        // unrecognized role is warned and ignored rather than applied.
        val role = props?.stringProperty("role")?.let { raw ->
            if (raw in setOf("destructive", "cancel")) {
                raw
            } else {
                logger.log("Invalid Button role '$raw', ignoring", LoggerLevel.warning)
                null
            }
        }

        val actionID = props?.stringProperty("actionID")
        // Inside a template row, a Button dispatches with the owning List/Section
        // id as viewID and the row index as viewPartID (Swift's convention);
        // outside a template it uses its own id with viewPartID 0.
        val templateContext = LocalTemplateContext.current
        val dispatchViewID = templateContext?.parentID ?: element.id
        val dispatchPartID = templateContext?.rowIndex ?: 0

        // SwiftUI `.tint` colors the button's accent (its filled background). An
        // inherited tint applies unless a `role` already dictates the color
        // (destructive -> error), matching that an explicit role wins.
        val tint = LocalActionUITint.current
        val colors = when {
            role == "destructive" -> ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.error,
                contentColor = MaterialTheme.colorScheme.onError
            )
            tint != null -> ButtonDefaults.buttonColors(containerColor = tint)
            else -> ButtonDefaults.buttonColors()
        }

        M3Button(
            onClick = {
                if (actionID != null) {
                    ActionUIModel.actionHandler(actionID, viewID = dispatchViewID, viewPartID = dispatchPartID)
                }
            },
            modifier = modifier,
            colors = colors
        ) {
            M3Text(text = title)
        }
    }
}
