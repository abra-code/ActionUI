package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button as M3Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.LabelIcon
import com.abracode.actionui.Helpers.LocalActionUITint
import com.abracode.actionui.Helpers.LocalTemplateContext
import com.abracode.actionui.Helpers.selectLabelIcon
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
 *     "systemImage": "star.fill",  // Optional: leading SF Symbol icon
 *     "role": "destructive",       // Optional: "destructive" | "cancel"
 *     "actionID": "button.click"   // Optional: id dispatched on tap
 *   }
 * }
 * ```
 *
 * **Supported properties.** `title`, `role`, `actionID`, the image-label keys
 * (`systemImage` / `materialName:android`, `imageScale`, plus the `:android` axis
 * overrides), plus the universal modifiers resolved by `applyCommonProperties`
 * (the caller passes those in via [modifier]).
 *
 * **Image label.** A leading icon resolves through the shared `SymbolIcon` seam
 * ([selectLabelIcon] -> `SymbolIcon.kt`), the same glyph path as `Image` / `Label`:
 * `systemImage` (an SF Symbol -> closest Material glyph) or `materialName:android`
 * (an explicit Material Symbol, winning when both are present). With a `title` the
 * button is icon + title (Material `IconSpacing` between them, like SwiftUI
 * `Button(title, systemImage:)`); with an empty title it is icon-only. The glyph
 * inherits the button's content color and label font, so it matches the title and
 * tracks `role` / `tint` automatically; `imageScale` and the `material*:android`
 * axes tune it, exactly as on `Image`.
 *
 * **Deferred vs. Apple** (warn-and-skip, not silent): `assetImage` (asset-catalog
 * image) maps to an Android `res/drawable` resource, pending the same
 * name->resource contract `Image`'s `assetName` waits on. A Button carrying only
 * `assetImage` renders title-only (or empty) with one warning.
 *
 * `role: "destructive"` maps to an error-colored button; `role: "cancel"` has no
 * distinct Material styling (it is meaningful only inside dialogs on Apple) and
 * renders as a normal button.
 */
object Button : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current

        val title = props?.stringProperty("title") ?: ""
        val imageScale = props?.stringProperty("imageScale")
        val contentDescription = props?.stringProperty("accessibilityLabel")

        // Leading icon (+ its deferred assetImage warning) resolved once per change.
        // A null result is title-only - a Button needs no icon (unlike Image).
        val iconSource = remember(props) { selectLabelIcon(props, "assetImage", "Button", logger) }

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
            // The glyph inherits the button's content color (LocalContentColor) and
            // label font (LocalTextStyle), so it tracks role/tint and matches the
            // title without any explicit wiring - the same inheritance Label relies on.
            val iconDrawn = LabelIcon(
                source = iconSource,
                imageScale = imageScale,
                contentDescription = contentDescription,
                elementName = "Button",
                logger = logger,
            )

            // Material's icon-button spacing, but only between an actual glyph and text.
            if (iconDrawn && title.isNotEmpty()) {
                Spacer(Modifier.size(ButtonDefaults.IconSpacing))
            }
            if (title.isNotEmpty()) {
                M3Text(text = title)
            }
        }
    }
}
