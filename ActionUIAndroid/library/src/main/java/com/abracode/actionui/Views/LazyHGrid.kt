package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.LazyHorizontalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.ContainerShape
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalStackAxis
import com.abracode.actionui.Common.StackAxis
import com.abracode.actionui.Common.parseRowAlignment
import com.abracode.actionui.Helpers.ActionUIGridCells
import com.abracode.actionui.Helpers.BuildViewWithModifiers
import com.abracode.actionui.Helpers.LocalActionUIInputEnabled
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.TemplateHelper
import com.abracode.actionui.Helpers.boundHeightIfUnbounded
import com.abracode.actionui.Helpers.boundWidthIfUnbounded
import com.abracode.actionui.Helpers.gridNaturalCrossExtent
import com.abracode.actionui.Helpers.resolveGridTracks
import com.abracode.actionui.Helpers.templateRows
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * Horizontal grid that composes its children lazily - the Compose
 * [LazyHorizontalGrid]. Mirror of the Apple `LazyHGrid` element
 * (`ActionUI/Views/LazyHGrid.swift`). The horizontal counterpart of
 * [LazyVGrid]; see that file for the track model and the SwiftUI-vs-Compose
 * rationale - here the `rows` property defines fixed/flexible *row heights*
 * and children flow into columns.
 *
 * As with [LazyHStack], a `LazyHorizontalGrid` *is* both the lazy builder and
 * the scroll viewport, so it needs a **bounded width**: a JSON `frame.width`
 * (already on [modifier]) wins, otherwise [DEFAULT_MAIN_EXTENT] is applied so
 * an unbounded parent cannot trip Compose's infinite-constraint error.
 *
 * **Supported properties.**
 *   * `rows`      - track list, `{ "minimum": n }` fixed / `{ "flexible": true }`
 *     equal share (default one flexible row).
 *   * `spacing`   - gap between *columns* (the main axis, matching SwiftUI; default 0).
 *   * `alignment` - vertical alignment, `top` / `center` / `bottom`
 *     (default `center`), visible only when fixed rows underfill the height.
 *   * plus the universal modifiers resolved by `applyCommonProperties` (via
 *     [modifier]), notably `frame.width`.
 *
 * The grid also supports the data-driven `template` mode: when
 * [ActionUIElement.template] is present, one substituted template instance per
 * row in `states[`[ActionUIModel.ROWS_STATE_KEY]`]` (set via the rows API)
 * fills the next grid cell, substituted lazily as cells scroll into view. See
 * [LazyVGrid] and `Helpers/TemplateHelper.kt`.
 */
object LazyHGrid : ActionUIViewConstruction {

    override val insertableContainers = mapOf("children" to ContainerShape.FLAT)

    override fun initialStates(element: ActionUIElement): Map<String, Any> =
        mapOf(ActionUIModel.ROWS_STATE_KEY to emptyList<List<String>>())

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current

        val spacing = props?.get("spacing")?.jsonPrimitive?.doubleOrNull
        // SwiftUI LazyHGrid default alignment is .center - match it.
        val verticalAlignment = props?.get("alignment")?.jsonPrimitive?.contentOrNull
            ?.let { parseRowAlignment(it, logger) }
            ?: Alignment.CenterVertically
        val tracks = resolveGridTracks(props?.get("rows"), "LazyHGrid", "rows", logger)

        // A LazyHorizontalGrid is its own scroll viewport and needs a bounded
        // width. An inherited frame.width (already on `modifier`) wins;
        // otherwise apply a default so an unbounded parent cannot crash it.
        // The default extent applies ONLY to an unbounded parent (see LazyVGrid): a
        // bounded one passes its constraint through, so the grid fills the width it
        // is given rather than being letterboxed at 320dp.
        val hasExplicitWidth = (props?.get("frame") as? JsonObject)?.get("width") != null
        val sized = if (hasExplicitWidth) modifier
            else modifier.boundWidthIfUnbounded(DEFAULT_MAIN_EXTENT)
        // It ALSO needs a bounded HEIGHT (cross axis). Under a vertically-scrollable
        // (or both-axis) ScrollView the proposed height is infinite, which Compose
        // crashes on; bound it to the grid's natural row-track height. A no-op under
        // a normal/finite-height parent (and an explicit frame.height bounds it).
        val gridModifier = sized.boundHeightIfUnbounded(
            gridNaturalCrossExtent(tracks, FLEXIBLE_FALLBACK_HEIGHT),
        )

        // Template (data-driven) mode wins over children, as on Apple. The rows
        // are read here (composable scope) so the lazy DSL below stays plain.
        val template = element.template
        val rows = if (template != null) templateRows(element.id) else emptyList()

        // A hidden scroll container must not consume touch (Apple/web make `hidden`
        // non-interactive) - see ListView and Missing_Features #34. When hidden, render a bare
        // Box that reserves the bounded viewport but carries no scrollable/pointer node, so
        // hit-testing falls through to a visible sibling behind it in an overlapping ZStack.
        if (!LocalActionUIInputEnabled.current) {
            Box(gridModifier)
            return
        }

        CompositionLocalProvider(LocalStackAxis provides StackAxis.Horizontal) {
            LazyHorizontalGrid(
                rows = ActionUIGridCells(tracks),
                modifier = gridModifier,
                horizontalArrangement = spacing
                    ?.let { Arrangement.spacedBy(it.dp) }
                    ?: Arrangement.Start,
                verticalArrangement = Arrangement.spacedBy(0.dp, verticalAlignment),
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

    /** Default scroll-viewport width when JSON supplies no `frame.width`. */
    private val DEFAULT_MAIN_EXTENT = 320.dp

    /** Per-flexible-row height used only to give the grid a finite cross extent
     *  when its parent proposes an unbounded height (see [gridNaturalCrossExtent]). */
    private val FLEXIBLE_FALLBACK_HEIGHT = 100.dp
}
