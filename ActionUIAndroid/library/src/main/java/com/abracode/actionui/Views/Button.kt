package com.abracode.actionui.Views

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button as M3Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.material3.Text as M3Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.ActionUIButtonStyle
import com.abracode.actionui.Helpers.ActionUIControlSize
import com.abracode.actionui.Helpers.LabelIcon
import com.abracode.actionui.Helpers.LocalActionUIButtonStyle
import com.abracode.actionui.Helpers.LocalActionUIControlSize
import com.abracode.actionui.Helpers.LocalActionUIEnabled
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
 *     "buttonStyle": "bordered",   // Optional: SwiftUI button style (see below)
 *     "controlSize": "small",      // Optional: "mini" | "small" | "regular" | "large" | "extraLarge"
 *     "disabled": true,            // Optional: disables interaction (inherited)
 *     "actionID": "button.click"   // Optional: id dispatched on tap
 *   }
 * }
 * ```
 *
 * **Supported properties.** `title`, `role`, `actionID`, the image-label keys
 * (`systemImage` / `materialName:android`, `imageScale`, plus the `:android` axis
 * overrides), plus the universal modifiers resolved by `applyCommonProperties`
 * (the caller passes those in via [modifier]). `buttonStyle`, `controlSize`, and
 * `disabled` are environment modifiers (`Helpers/ControlEnvironment.kt`): they
 * arrive through CompositionLocals, so they apply whether set on the Button
 * itself or inherited from any ancestor, like SwiftUI.
 *
 * **Button style.** SwiftUI's emphasis ladder maps onto the native Material
 * button family rather than a custom look:
 *
 *   * `borderedProminent` -> filled [M3Button] (accent container)
 *   * `bordered`          -> [FilledTonalButton], tinted like iOS's translucent
 *                            accent fill when a `tint` is inherited
 *   * `borderless`        -> [androidx.compose.material3.TextButton] (accent text)
 *   * `plain`             -> `TextButton` in the inherited content color (iOS
 *                            plain renders as ordinary label text)
 *   * `automatic` / none  -> filled [M3Button]. Divergence: iOS resolves
 *                            `automatic` per-context (usually borderless); the
 *                            Material default button is filled, and native-first
 *                            keeps it.
 *
 * **Control size.** Compose has no ambient control-size; the metrics are local
 * ([controlSizeMetrics]): a min height (24/32/48/56dp around the 40dp Material
 * default), tighter/looser content padding, and the nearest Material label
 * typography step. `regular` (or none) leaves the Material defaults untouched.
 * Note Material's 48dp minimum *touch target* still applies below the visual
 * bounds of `mini`/`small` buttons - layout is compact, accessibility is not.
 *
 * **Disabled.** [LocalActionUIEnabled] feeds the M3 `enabled` parameter, which
 * renders the standard Material disabled colors and blocks the tap - set
 * directly or inherited from a disabled ancestor (SwiftUI `.disabled` semantics).
 *
 * **Image label.** A leading icon resolves through the shared `SymbolIcon` seam
 * ([selectLabelIcon] -> `SymbolIcon.kt`), the same glyph path as `Image` / `Label`:
 * `systemImage` (an SF Symbol -> closest Material glyph) or `materialName:android`
 * (an explicit Material Symbol, winning when both are present). With a `title` the
 * button is icon + title (Material `IconSpacing` between them, like SwiftUI
 * `Button(title, systemImage:)`); with an empty title it is icon-only. The glyph
 * inherits the button's content color and label font, so it matches the title and
 * tracks `role` / `tint` / `controlSize` automatically; `imageScale` and the
 * `material*:android` axes tune it, exactly as on `Image`.
 *
 * **Deferred vs. Apple** (warn-and-skip, not silent): `assetImage` (asset-catalog
 * image) maps to an Android `res/drawable` resource, pending the same
 * name->resource contract `Image`'s `assetName` waits on. A Button carrying only
 * `assetImage` renders title-only (or empty) with one warning.
 *
 * `role: "destructive"` maps to error coloring per style (filled error container,
 * tonal error container, error text); `role: "cancel"` has no distinct Material
 * styling (it is meaningful only inside dialogs on Apple) and renders as a normal
 * button. An explicit role wins over an inherited `tint`.
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
        val onClick = {
            if (actionID != null) {
                ActionUIModel.actionHandler(actionID, viewID = dispatchViewID, viewPartID = dispatchPartID)
            }
        }

        // The inherited control environment - the element's own properties were
        // already provided into it by the per-element seam, so reading the
        // locals covers both the inherited and the self-declared case.
        val style = LocalActionUIButtonStyle.current ?: ActionUIButtonStyle.AUTOMATIC
        val enabled = LocalActionUIEnabled.current
        val metrics = controlSizeMetrics(LocalActionUIControlSize.current)
        val tint = LocalActionUITint.current

        // A controlSize min height chains onto the caller's modifier (inner), so
        // an explicit `frame` stays outermost and wins, like SwiftUI.
        val sizedModifier = metrics?.let { modifier.heightIn(min = it.minHeight) } ?: modifier
        val textStyle = metrics?.let { controlSizeTextStyle(it) }

        val content: @Composable RowScope.() -> Unit = {
            // The glyph inherits the button's content color (LocalContentColor) and
            // label font (LocalTextStyle), so it tracks role/tint/controlSize and
            // matches the title without any explicit wiring - the same inheritance
            // Label relies on. A controlSize overrides the label style M3 provides.
            val label: @Composable () -> Unit = {
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
            if (textStyle != null) ProvideTextStyle(textStyle, label) else label()
        }

        // SwiftUI `.tint` colors the button's accent. An inherited tint applies
        // unless a `role` already dictates the color (destructive -> error),
        // matching that an explicit role wins.
        val destructive = role == "destructive"
        when (style) {
            ActionUIButtonStyle.AUTOMATIC, ActionUIButtonStyle.BORDERED_PROMINENT -> M3Button(
                onClick = onClick,
                modifier = sizedModifier,
                enabled = enabled,
                colors = when {
                    destructive -> ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.error,
                        contentColor = MaterialTheme.colorScheme.onError
                    )
                    tint != null -> ButtonDefaults.buttonColors(containerColor = tint)
                    else -> ButtonDefaults.buttonColors()
                },
                contentPadding = metrics?.contentPadding ?: ButtonDefaults.ContentPadding,
                content = content
            )

            ActionUIButtonStyle.BORDERED -> FilledTonalButton(
                onClick = onClick,
                modifier = sizedModifier,
                enabled = enabled,
                colors = when {
                    destructive -> ButtonDefaults.filledTonalButtonColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer,
                        contentColor = MaterialTheme.colorScheme.onErrorContainer
                    )
                    // iOS `.bordered` + tint is a translucent accent fill with
                    // accent text; the tonal container takes the same treatment.
                    tint != null -> ButtonDefaults.filledTonalButtonColors(
                        containerColor = tint.copy(alpha = 0.15f),
                        contentColor = tint
                    )
                    else -> ButtonDefaults.filledTonalButtonColors()
                },
                contentPadding = metrics?.contentPadding ?: ButtonDefaults.ContentPadding,
                content = content
            )

            ActionUIButtonStyle.BORDERLESS, ActionUIButtonStyle.PLAIN -> TextButton(
                onClick = onClick,
                modifier = sizedModifier,
                enabled = enabled,
                colors = when {
                    destructive -> ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                    tint != null -> ButtonDefaults.textButtonColors(contentColor = tint)
                    // iOS plain is ordinary label text, not accent-colored.
                    style == ActionUIButtonStyle.PLAIN -> ButtonDefaults.textButtonColors(
                        contentColor = LocalContentColor.current
                    )
                    else -> ButtonDefaults.textButtonColors()
                },
                contentPadding = metrics?.contentPadding ?: ButtonDefaults.TextButtonContentPadding,
                content = content
            )
        }
    }
}

/**
 * The Material metrics for a non-`regular` SwiftUI `controlSize` step: a minimum
 * container height around the 40dp Material default, and the content padding to
 * match. Pure data so the ladder is unit-testable without composition; the
 * typography step lives in [controlSizeTextStyle] (it needs [MaterialTheme]).
 */
internal data class ControlSizeMetrics(
    val size: ActionUIControlSize,
    val minHeight: Dp,
    val contentPadding: PaddingValues
)

/**
 * Maps a `controlSize` to its [ControlSizeMetrics]; `null` for `regular`/absent,
 * meaning the Material defaults stay untouched.
 */
internal fun controlSizeMetrics(size: ActionUIControlSize?): ControlSizeMetrics? = when (size) {
    null, ActionUIControlSize.REGULAR -> null
    ActionUIControlSize.MINI -> ControlSizeMetrics(
        size, 24.dp, PaddingValues(horizontal = 8.dp, vertical = 2.dp)
    )
    ActionUIControlSize.SMALL -> ControlSizeMetrics(
        size, 32.dp, PaddingValues(horizontal = 12.dp, vertical = 4.dp)
    )
    ActionUIControlSize.LARGE -> ControlSizeMetrics(
        size, 48.dp, PaddingValues(horizontal = 24.dp, vertical = 12.dp)
    )
    ActionUIControlSize.EXTRA_LARGE -> ControlSizeMetrics(
        size, 56.dp, PaddingValues(horizontal = 32.dp, vertical = 16.dp)
    )
}

/** The label typography step for a sized control (M3's default is `labelLarge`). */
@Composable
private fun controlSizeTextStyle(metrics: ControlSizeMetrics): TextStyle = when (metrics.size) {
    ActionUIControlSize.MINI        -> MaterialTheme.typography.labelSmall
    ActionUIControlSize.SMALL       -> MaterialTheme.typography.labelMedium
    ActionUIControlSize.EXTRA_LARGE -> MaterialTheme.typography.titleMedium
    else                            -> MaterialTheme.typography.labelLarge
}
