package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
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
 * Named group of rows within a `Form`, `List`, or other container. Mirror of the
 * Apple `Section` element (`ActionUI/Views/Section.swift`).
 *
 * Rendered as a [Column]: an optional `header` (styled like a Material section
 * label - `titleSmall`, `onSurfaceVariant`) above the body. The body is either
 *
 *   * **static** - the element's `children`, each built through the registry; or
 *   * **template (data-driven)** - when a [ActionUIElement.template] is present,
 *     one substituted template instance per row in
 *     `states[`[ActionUIModel.ROWS_STATE_KEY]`]` (set via the rows API). See
 *     `Helpers/TemplateHelper.kt`.
 *
 * The rows are seeded empty via [initialStates] so a host can address them by id
 * before any data arrives (the element needs a positive `id` for the rows API to
 * resolve it, as on Apple).
 *
 * **Divergence.** A `Section` body is a plain (eager) `Column`, not a lazy list;
 * sections are small groupings, and the lazy viewport belongs to an enclosing
 * `List` / `ScrollView`. SwiftUI's footer is not modeled by this element.
 */
object Section : ActionUIViewConstruction {

    override fun initialStates(element: ActionUIElement): Map<String, Any> =
        mapOf(ActionUIModel.ROWS_STATE_KEY to emptyList<List<String>>())

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val header = element.properties?.stringProperty("header")
        val template = element.template

        Column(modifier = modifier) {
            if (header != null) {
                M3Text(
                    text = header,
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(HEADER_PADDING),
                )
            }

            if (template != null) {
                templateRows(element.id).forEachIndexed { rowIndex, row ->
                    TemplateHelper.BuildTemplateRow(
                        template = template, row = row, parentID = element.id, rowIndex = rowIndex,
                    )
                }
            } else {
                element.children.orEmpty().forEach { child ->
                    val builder = ActionUIRegistry.lookup(child.type) ?: return@forEach
                    val childModifier = buildChildModifier(child.properties, logger)
                        .let { if (child.type == "Spacer") it.weight(1f) else it }
                    ProvideTextStyleEnvironment(child.properties, logger) {
                        builder.BuildView(child, childModifier)
                    }
                }
            }
        }
    }

    /** Insets the header like a Material list-section label. */
    private val HEADER_PADDING = PaddingValues(top = 8.dp, bottom = 4.dp)
}
