package com.abracode.actionui.Views

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.intProperty
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
 * Property mapping: `title` (the row label, defaults to `"Link"`).
 *
 * **Degrades vs. Apple.** Outside a `NavigationStack` (no [LocalNavPush]) a tap
 * is a no-op and warns. A link with neither a `destinationViewId` nor an
 * id-bearing inline `destination` has no addressable target and warns on tap.
 * Renders a plain title + chevron row (no `Label`/SF Symbol; icons are B2).
 */
object NavigationLink : ActionUIViewConstruction {

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val title = element.properties?.stringProperty("title") ?: "Link"
        val targetId = resolveLinkTarget(element)
        val push = LocalNavPush.current

        Row(
            modifier = modifier
                .fillMaxWidth()
                .clickable {
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
            M3Text(text = title, modifier = Modifier.weight(1f))
            // Plain chevron glyph as a tap affordance (avoids an icon dependency, B2).
            M3Text(text = ">", style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.End)
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
