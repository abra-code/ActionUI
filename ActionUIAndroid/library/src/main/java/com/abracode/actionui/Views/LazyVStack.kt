package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
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
import com.abracode.actionui.Common.parseColumnAlignment
import com.abracode.actionui.Helpers.BuildViewWithModifiers
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.TemplateHelper
import com.abracode.actionui.Helpers.templateRows
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * Vertical stack that composes its children lazily - only those scrolled into
 * view are built - the Compose [LazyColumn]. Mirror of the Apple `LazyVStack`
 * element (`ActionUI/Views/LazyVStack.swift`).
 *
 * **SwiftUI vs. Compose (the load-bearing difference).** SwiftUI's `LazyVStack`
 * only defers child *creation*; it does not scroll, so authors wrap it in a
 * `ScrollView`. Compose has no such split: a `LazyColumn` *is* both the lazy
 * builder and the scroll viewport in one. That makes it the correct primitive for
 * the goal here ("many children, do not eagerly build the off-screen ones"), but
 * it also means the list needs a **bounded main-axis (height)** - a scroll
 * viewport cannot be infinitely tall. ActionUI has no `ScrollView` element yet, so
 * this single composable plays the `ScrollView { LazyVStack }` role.
 *
 * **Height resolution.** When JSON supplies `frame.height` (already on
 * [modifier]) it wins - including `"infinity"` to fill a bounded parent. Otherwise
 * a [DEFAULT_MAIN_EXTENT] is applied so there is always a finite scroll viewport
 * and we never trip Compose's infinite-constraint error (the same "always
 * something to scroll within" stance [TextEditor] takes). The cross axis (width)
 * wraps to content unless a child requests `frame.width`.
 *
 * **Supported properties.**
 *   * `spacing`   - gap between children (default 0, matching the Apple element).
 *   * `alignment` - horizontal alignment, `leading` / `center` / `trailing`
 *     (default `center`), resolved by [parseColumnAlignment].
 *   * plus the universal modifiers resolved by `applyCommonProperties` (via
 *     [modifier]), notably `frame.height`.
 *
 * Children are placed via the lazy `items` DSL, whose [androidx.compose.foundation.lazy.LazyItemScope]
 * exposes neither `weight` nor per-child `align` (unlike a plain [VStack]); each
 * child therefore receives only its `applyCommonProperties` modifier. A `Spacer`
 * inside a lazy stack cannot flex and renders at its intrinsic size.
 *
 * The stack also supports the data-driven `template` mode: when
 * [ActionUIElement.template] is present, one substituted template instance per
 * row in `states[`[ActionUIModel.ROWS_STATE_KEY]`]` (set via the rows API). The
 * rows go through the lazy `itemsIndexed` DSL, so substitution happens only for
 * rows scrolled into view - a refinement over the Apple element, which builds
 * every template instance eagerly. See `Helpers/TemplateHelper.kt`.
 */
object LazyVStack : ActionUIViewConstruction {

    override fun initialStates(element: ActionUIElement): Map<String, Any> =
        mapOf(ActionUIModel.ROWS_STATE_KEY to emptyList<List<String>>())

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current

        val spacing = props?.get("spacing")?.jsonPrimitive?.doubleOrNull
        // SwiftUI LazyVStack default alignment is .center - match it.
        val horizontalAlignment = props?.get("alignment")?.jsonPrimitive?.contentOrNull
            ?.let { parseColumnAlignment(it, logger) }
            ?: Alignment.CenterHorizontally

        // A LazyColumn is its own scroll viewport and needs a bounded height. An
        // inherited frame.height (already on `modifier`) wins; otherwise apply a
        // default so an unbounded parent (e.g. a verticalScroll) cannot crash it.
        val hasExplicitHeight = (props?.get("frame") as? JsonObject)?.get("height") != null
        val listModifier = if (hasExplicitHeight) modifier else modifier.height(DEFAULT_MAIN_EXTENT)

        // Template (data-driven) mode wins over children, as on Apple. The rows
        // are read here (composable scope) so the lazy DSL below stays plain.
        val template = element.template
        val rows = if (template != null) templateRows(element.id) else emptyList()

        CompositionLocalProvider(LocalStackAxis provides StackAxis.Vertical) {
            LazyColumn(
                modifier = listModifier,
                verticalArrangement = spacing
                    ?.let { Arrangement.spacedBy(it.dp) }
                    ?: Arrangement.Top,
                horizontalAlignment = horizontalAlignment,
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
                        builder.BuildViewWithModifiers(child, Modifier)
                    }
                }
            }
        }
    }

    /** Default scroll-viewport height when JSON supplies no `frame.height`. */
    private val DEFAULT_MAIN_EXTENT = 320.dp
}
