package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.buildChildModifier
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.TemplateHelper
import com.abracode.actionui.Helpers.stringProperty
import com.abracode.actionui.Helpers.templateRows

/**
 * Titled, visually grouped container around a set of children. Mirror of the
 * Apple `GroupBox` element (`ActionUI/Views/GroupBox.swift`), which wraps
 * `SwiftUI.GroupBox`.
 *
 * Compose has no `GroupBox`, so it is rendered as a Material3 [OutlinedCard]: an
 * optional `title` label at the top, then the `children` laid out vertically -
 * the default SwiftUI `GroupBoxStyle` shape (bordered box, label above content).
 *
 * **Supported properties.**
 *   * `title` - optional String shown above the content; absent / non-string
 *     omits the label (matching the Apple validator's warn-and-nil).
 *   * `children` - the grouped views, laid out in a [Column]; each gets the
 *     [androidx.compose.foundation.layout.ColumnScope] child modifier (so
 *     per-child `weight` / `align` work, as in [VStack]).
 *   * plus the universal modifiers resolved by `applyCommonProperties` (via
 *     [modifier]).
 *
 * The box also supports the data-driven `template` mode: when
 * [ActionUIElement.template] is present, one substituted template instance per
 * row in `states[`[ActionUIModel.ROWS_STATE_KEY]`]` (set via the rows API)
 * fills the content column. See `Helpers/TemplateHelper.kt`.
 */
object GroupBox : ActionUIViewConstruction {

    override fun initialStates(element: ActionUIElement): Map<String, Any> =
        mapOf(ActionUIModel.ROWS_STATE_KEY to emptyList<List<String>>())

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val title = element.properties?.stringProperty("title")

        OutlinedCard(modifier = modifier) {
            Column(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (!title.isNullOrEmpty()) {
                    M3Text(title, style = MaterialTheme.typography.titleSmall)
                }
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
