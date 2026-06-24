package com.abracode.actionui.Views

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUIImageRegistry
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.ChromeSymbolIcon
import com.abracode.actionui.Helpers.LabelIcon
import com.abracode.actionui.Helpers.LocalActionUIEnabled
import com.abracode.actionui.Helpers.intProperty
import com.abracode.actionui.Helpers.selectLabelIcon
import com.abracode.actionui.Helpers.stringProperty

/**
 * Push trigger. Mirror of the Apple `NavigationLink` element
 * (`ActionUI/Views/NavigationLink.swift`), which wraps `SwiftUI.NavigationLink`.
 * Renders a tappable title row; on tap it asks the enclosing [NavigationStack] to
 * push a destination via [LocalNavPush].
 *
 * Target resolution ([resolveLinkTarget]):
 *   * `destinationViewId` (Int) - the by-reference form: pushes the
 *     `destinations[]` entry with that id (the native-fit form).
 *   * inline `destination` view - the inline form: pushes that view, which
 *     [NavigationStack] has hoisted into the same id-keyed registry by its `id`.
 *
 * Property mapping: `title` (the row label, defaults to `"Link"`) and an optional
 * leading `systemImage` (SF Symbol) / `materialName:android` icon, resolved through
 * the shared `SymbolIcon` helper ([LabelIcon]) like every other image-label.
 *
 * **Degrades vs. Apple.** Outside a `NavigationStack` (no [LocalNavPush]) a tap
 * is a no-op and warns. A link with neither a `destinationViewId` nor an
 * id-bearing inline `destination` has no addressable target and warns on tap.
 * Renders a title + a native drill-in chevron (the Material Symbols `chevron_right`,
 * mirrored to `chevron_left` under RTL).
 *
 * **Value bridge.** Like Apple, `NavigationLink` declares [ActionUIValueType.INT]
 * (Apple's `Int?`): the value is the **push target id** (`destinationViewId`), so
 * a host can re-point the link at runtime via
 * `ActionUIModel.setElementValue(id, <Int>)`. A runtime value takes precedence
 * over the `destinationViewId` property and the inline `destination` id; when
 * none is set the authored target is used, so static usage is unchanged.
 * `initialValue` returns the runtime value or the `destinationViewId` property,
 * matching Apple's `NavigationLink.swift`.
 */
object NavigationLink : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.INT

    override fun initialValue(element: ActionUIElement): Any? =
        element.properties?.intProperty("destinationViewId")

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val props = element.properties
        val title = props?.stringProperty("title") ?: "Link"
        // A runtime value (a host write) re-points the link; else the authored
        // target. Apple parity: model.value (Int) wins over destinationViewId.
        val runtimeTarget = LocalWindowModel.current?.viewModels?.get(element.id)?.value as? Int
        val targetId = runtimeTarget ?: resolveLinkTarget(element)
        val push = LocalNavPush.current

        val imageScale = props?.stringProperty("imageScale")
        val imageRegistry = LocalActionUIImageRegistry.current
        val iconSource = remember(props, imageRegistry) { selectLabelIcon(props, "imageName", "NavigationLink", logger, imageRegistry) }

        Row(
            modifier = modifier
                .fillMaxWidth()
                // SwiftUI `.disabled` (set here or on any ancestor) blocks the push.
                .clickable(enabled = LocalActionUIEnabled.current) {
                    if (targetId != null) {
                        push(targetId)
                    } else {
                        logger.log(
                            "NavigationLink '$title' has no destinationViewId or id-bearing inline destination",
                            LoggerLevel.warning,
                        )
                    }
                }
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // accessibilityLabel rides [modifier] as semantics via the shared
            // pipeline; the clickable row merges descendants, so a glyph-level
            // description from the same property would be announced twice.
            val iconDrawn = LabelIcon(
                source = iconSource,
                imageScale = imageScale,
                contentDescription = null,
                elementName = "NavigationLink",
                logger = logger,
            )
            if (iconDrawn) {
                Spacer(Modifier.width(8.dp))
            }
            M3Text(text = title, modifier = Modifier.weight(1f))
            // Native drill-in chevron, from the Material Symbols font (the app's icon
            // language); direction-aware so it points the right way under RTL, and
            // tinted onSurfaceVariant like a standard Material list-row affordance.
            val chevron = if (LocalLayoutDirection.current == LayoutDirection.Rtl) "chevron_left" else "chevron_right"
            ChromeSymbolIcon(
                name = chevron,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/**
 * The push target id for a link: its `destinationViewId` property, else its inline
 * `destination`'s id (when positive). `null` when neither is addressable. Pure, so
 * it is unit-testable.
 */
internal fun resolveLinkTarget(element: ActionUIElement): Int? =
    element.properties?.intProperty("destinationViewId")
        ?: element.destination?.id?.takeIf { it != 0 }
