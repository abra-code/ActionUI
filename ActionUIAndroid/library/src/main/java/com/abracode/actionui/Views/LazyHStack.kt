package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalStackAxis
import com.abracode.actionui.Common.StackAxis
import com.abracode.actionui.Common.applyCommonProperties
import com.abracode.actionui.Common.parseRowAlignment
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.TemplateHelper
import com.abracode.actionui.Helpers.templateRows
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * Horizontal stack that composes its children lazily - only those scrolled into
 * view are built - the Compose [LazyRow]. Mirror of the Apple `LazyHStack`
 * element (`ActionUI/Views/LazyHStack.swift`). The horizontal counterpart of
 * [LazyVStack]; see that file for the full SwiftUI-vs-Compose rationale.
 *
 * As with [LazyVStack], a `LazyRow` *is* both the lazy builder and the scroll
 * viewport, so it needs a **bounded main-axis (width)**. When JSON supplies
 * `frame.width` (already on [modifier]) it wins - including `"infinity"` to fill
 * a bounded parent; otherwise [DEFAULT_MAIN_EXTENT] is applied so an
 * unbounded-width parent cannot trip Compose's infinite-constraint error.
 *
 * **Supported properties.**
 *   * `spacing`   - gap between children (default 0).
 *   * `alignment` - vertical alignment, `top` / `center` / `bottom`
 *     (default `center`), resolved by [parseRowAlignment].
 *   * plus the universal modifiers resolved by `applyCommonProperties` (via
 *     [modifier]), notably `frame.width`.
 *
 * Children are placed via the lazy `items` DSL, whose item scope exposes neither
 * `weight` nor per-child `align`; each child receives only its
 * `applyCommonProperties` modifier.
 *
 * The stack also supports the data-driven `template` mode: when
 * [ActionUIElement.template] is present, one substituted template instance per
 * row in `states[`[ActionUIModel.ROWS_STATE_KEY]`]` (set via the rows API),
 * substituted lazily as rows scroll into view. See [LazyVStack] and
 * `Helpers/TemplateHelper.kt`.
 */
object LazyHStack : ActionUIViewConstruction {

    override fun initialStates(element: ActionUIElement): Map<String, Any> =
        mapOf(ActionUIModel.ROWS_STATE_KEY to emptyList<List<String>>())

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current

        val spacing = props?.get("spacing")?.jsonPrimitive?.doubleOrNull
        // SwiftUI LazyHStack default alignment is .center - match it.
        val verticalAlignment = props?.get("alignment")?.jsonPrimitive?.contentOrNull
            ?.let { parseRowAlignment(it, logger) }
            ?: Alignment.CenterVertically

        // A LazyRow is its own scroll viewport and needs a bounded width. An
        // inherited frame.width (already on `modifier`) wins; otherwise apply a
        // default so an unbounded-width parent cannot crash it.
        val hasExplicitWidth = (props?.get("frame") as? JsonObject)?.get("width") != null
        val listModifier = if (hasExplicitWidth) modifier else modifier.width(DEFAULT_MAIN_EXTENT)

        // Template (data-driven) mode wins over children, as on Apple. The rows
        // are read here (composable scope) so the lazy DSL below stays plain.
        val template = element.template
        val rows = if (template != null) templateRows(element.id) else emptyList()

        CompositionLocalProvider(LocalStackAxis provides StackAxis.Horizontal) {
            LazyRow(
                modifier = listModifier,
                horizontalArrangement = spacing
                    ?.let { Arrangement.spacedBy(it.dp) }
                    ?: Arrangement.Start,
                verticalAlignment = verticalAlignment,
            ) {
                if (template != null) {
                    itemsIndexed(rows) { rowIndex, row ->
                        TemplateHelper.BuildTemplateRow(
                            template = template, row = row, parentID = element.id, rowIndex = rowIndex,
                        )
                    }
                } else items(element.children.orEmpty()) { child ->
                    val builder = ActionUIRegistry.lookup(child.type) ?: return@items
                    ProvideTextStyleEnvironment(child.properties, logger) {
                        builder.BuildView(child, Modifier.applyCommonProperties(child.properties, logger))
                    }
                }
            }
        }
    }

    /** Default scroll-viewport width when JSON supplies no `frame.width`. */
    private val DEFAULT_MAIN_EXTENT = 320.dp
}
