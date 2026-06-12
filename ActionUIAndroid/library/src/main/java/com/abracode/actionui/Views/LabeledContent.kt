package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.buildChildModifier
import com.abracode.actionui.Helpers.BuildViewWithPopover
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.stringProperty

/**
 * Pairs a `title` label with content. Mirror of the Apple `LabeledContent`
 * element (`ActionUI/Views/LabeledContent.swift`), which wraps
 * `SwiftUI.LabeledContent` - a leading label and trailing content that stays
 * visible in any container (unlike a control's built-in, often-hidden label).
 *
 * Rendered as a [Row]: the `title` leads, a flexible [Spacer] pushes the
 * `children` to the trailing edge (the SwiftUI label-left / content-right
 * layout). The cross axis is centered.
 *
 * **Supported properties.**
 *   * `title` - the leading label String (defaults to `""`); an empty title
 *     renders content only.
 *   * `children` - one or more trailing views; each gets the
 *     [androidx.compose.foundation.layout.RowScope] child modifier (so per-child
 *     `weight` / `align` work, as in [HStack]).
 *   * plus the universal modifiers resolved by `applyCommonProperties` (via
 *     [modifier]).
 */
object LabeledContent : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val title = element.properties?.stringProperty("title") ?: ""

        Row(
            modifier = modifier,
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Start,
        ) {
            if (title.isNotEmpty()) {
                M3Text(title)
                Spacer(Modifier.width(8.dp))
            }
            Spacer(Modifier.weight(1f))
            element.children.orEmpty().forEach { child ->
                val builder = ActionUIRegistry.lookup(child.type) ?: return@forEach
                ProvideTextStyleEnvironment(child.properties, logger) {
                    builder.BuildViewWithPopover(child, buildChildModifier(child.properties, logger))
                }
            }
        }
    }
}
