package com.abracode.actionui.Views

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.buildChildModifier
import com.abracode.actionui.Helpers.LocalActionUIEnabled
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.TemplateHelper
import com.abracode.actionui.Helpers.booleanProperty
import com.abracode.actionui.Helpers.stringProperty
import com.abracode.actionui.Helpers.templateRows

/**
 * Expand/collapse container with a clickable title header. Mirror of the Apple
 * `DisclosureGroup` element (`ActionUI/Views/DisclosureGroup.swift`), which wraps
 * `SwiftUI.DisclosureGroup`.
 *
 * The expanded/collapsed flag is **observable state** (not a value): it lives in
 * the element's [com.abracode.actionui.Common.ViewModel.states] under
 * `"isExpanded"`, seeded at load via [initialStates] so a host can read and drive
 * it through `ActionUIModel.getElementState(...)` /
 * `setElementStateFromString(..., "isExpanded", "true")`, and the control
 * recomposes. This is the first Android element to use the state (rather than
 * value) side of the bridge.
 *
 * Compose has no `DisclosureGroup`, so it is composed from a clickable header
 * [androidx.compose.foundation.layout.Row] (`title` + a rotating chevron drawn
 * with [Canvas], avoiding any icon-resolution dependency) and, when expanded, a
 * [Column] of `children`.
 *
 * **Supported properties.**
 *   * `title` - header label String (defaults to `""`).
 *   * `isExpanded` - initial expanded state (Boolean, defaults to `false`).
 *   * `valueChangeActionID` - dispatched through [ActionUIModel] on each user
 *     expand/collapse (parity with the Apple binding setter).
 *   * `children` - the disclosed views (shown only when expanded); each gets the
 *     [androidx.compose.foundation.layout.ColumnScope] child modifier.
 *
 * **State.** ViewModel-backed when a [com.abracode.actionui.Common.WindowModel]
 * is in scope (host binding; needs a positive `id`), else local
 * [rememberSaveable] - the same dual-path binding the controls use.
 *
 * The disclosed content also supports the data-driven `template` mode: when
 * [ActionUIElement.template] is present, one substituted template instance per
 * row in `states[`[ActionUIModel.ROWS_STATE_KEY]`]` (set via the rows API) fills
 * the expanded column. See `Helpers/TemplateHelper.kt`.
 */
object DisclosureGroup : ActionUIViewConstruction {
    override fun initialStates(element: ActionUIElement): Map<String, Any> =
        mapOf(
            "isExpanded" to (element.properties?.booleanProperty("isExpanded") ?: false),
            ActionUIModel.ROWS_STATE_KEY to emptyList<List<String>>(),
        )

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current
        val title = props?.stringProperty("title") ?: ""
        val valueChangeActionID = props?.stringProperty("valueChangeActionID")
        val initial = props?.booleanProperty("isExpanded") ?: false

        // Bind to the ViewModel state when a window is in scope; else local state.
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        var localExpanded by rememberSaveable(element.id) { mutableStateOf(initial) }
        val expanded = if (viewModel != null) {
            (viewModel.states["isExpanded"] as? Boolean) ?: initial
        } else {
            localExpanded
        }

        val onToggle: () -> Unit = {
            val new = !expanded
            if (viewModel != null) viewModel.states["isExpanded"] = new else localExpanded = new
            if (valueChangeActionID != null) {
                ActionUIModel.actionHandler(valueChangeActionID, viewID = element.id, viewPartID = 0)
            }
        }

        Column(modifier = modifier) {
            Row(
                // SwiftUI `.disabled` (set here or on any ancestor) blocks expand/collapse.
                modifier = Modifier.fillMaxWidth()
                    .clickable(enabled = LocalActionUIEnabled.current, onClick = onToggle),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                M3Text(title, modifier = Modifier.weight(1f))
                DisclosureChevron(expanded)
            }
            if (expanded) {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(start = 16.dp, top = 8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    // Template (data-driven) mode wins over children, as on Apple.
                    val template = element.template
                    if (template != null) {
                        templateRows(element.id).forEachIndexed { rowIndex, row ->
                            TemplateHelper.BuildTemplateRow(
                                template = template, row = row, parentID = element.id, rowIndex = rowIndex,
                            )
                        }
                    } else element.children.orEmpty().forEach { child ->
                        val builder = ActionUIRegistry.lookup(child.type) ?: return@forEach
                        ProvideTextStyleEnvironment(child.properties, logger) {
                            builder.BuildView(child, buildChildModifier(child.properties, logger))
                        }
                    }
                }
            }
        }
    }
}

/**
 * A small triangular disclosure indicator: points right when collapsed, rotates
 * to point down when expanded. Drawn with [Canvas] (no icon asset) and tinted
 * with the inherited [LocalContentColor], so it follows `foregroundStyle`.
 */
@Composable
private fun DisclosureChevron(expanded: Boolean) {
    val color = LocalContentColor.current
    Canvas(
        modifier = Modifier
            .size(10.dp)
            .rotate(if (expanded) 90f else 0f)
    ) {
        val path = Path().apply {
            moveTo(0f, 0f)
            lineTo(size.width, size.height / 2f)
            lineTo(0f, size.height)
            close()
        }
        drawPath(path, color = color)
    }
}
