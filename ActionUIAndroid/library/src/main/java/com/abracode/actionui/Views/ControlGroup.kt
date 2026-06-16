package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.ContainerShape
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.buildChildModifier
import com.abracode.actionui.Helpers.BuildViewWithModifiers
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.stringProperty

/**
 * A visually grouped cluster of controls. Mirror of the Apple `ControlGroup`
 * element (`ActionUI/Views/ControlGroup.swift`), which wraps
 * `SwiftUI.ControlGroup`.
 *
 * SwiftUI's default `ControlGroup` style lays its controls out **horizontally**
 * as a connected cluster (the toolbar/segmented idiom), optionally under a
 * `title` label. Compose has no `ControlGroup`, so it renders as a [Row] of the
 * `children` (each a full ActionUI view through the registry); when a `title` is
 * present the row sits under a small label inside a [Column], the same
 * title-above-content shape [GroupBox] uses.
 *
 * **Supported properties.**
 *   * `title` - optional String shown above the controls; absent / non-string
 *     omits the label (matching the Apple validator's warn-and-nil).
 *   * `children` - the grouped controls, laid out in a [Row]; each gets the
 *     [androidx.compose.foundation.layout.RowScope] child modifier (so per-child
 *     `weight` / `align` work, as in [HStack]).
 *   * plus the universal modifiers resolved by `applyCommonProperties` (via
 *     [modifier]).
 *
 * Children-only, matching the Apple element (no value bridge, no `template`
 * mode - `ControlGroup` is a static cluster); `children` is insertable so the
 * runtime structural-mutation API can add controls to it.
 */
object ControlGroup : ActionUIViewConstruction {

    override val insertableContainers = mapOf("children" to ContainerShape.FLAT)

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val title = element.properties?.stringProperty("title")

        if (!title.isNullOrEmpty()) {
            Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                M3Text(title, style = MaterialTheme.typography.labelMedium)
                ControlRow(element, logger, Modifier)
            }
        } else {
            ControlRow(element, logger, modifier)
        }
    }

    /** The horizontal cluster of `children`, the SwiftUI default ControlGroup layout. */
    @Composable
    private fun ControlRow(element: ActionUIElement, logger: ActionUILogger, modifier: Modifier) {
        Row(
            modifier = modifier,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            element.children.orEmpty().forEach { child ->
                val builder = ActionUIRegistry.lookup(child.type) ?: return@forEach
                ProvideTextStyleEnvironment(child.properties, logger) {
                    builder.BuildViewWithModifiers(child, buildChildModifier(child.properties, logger))
                }
            }
        }
    }
}
