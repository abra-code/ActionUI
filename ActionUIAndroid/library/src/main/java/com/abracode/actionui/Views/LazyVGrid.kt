package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
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
import com.abracode.actionui.Common.parseColumnAlignment
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
 * Vertical grid that composes its children lazily - the Compose
 * [LazyVerticalGrid]. Mirror of the Apple `LazyVGrid` element
 * (`ActionUI/Views/LazyVGrid.swift`).
 *
 * **Column model.** The `columns` property is an array of track dictionaries,
 * each either `{ "minimum": 100.0 }` (a fixed-width column - Apple maps it to
 * `GridItem(.fixed(minimum))`) or `{ "flexible": true }` (an equal share of the
 * leftover width - `GridItem(.flexible())`). Compose's stock
 * [androidx.compose.foundation.lazy.grid.GridCells] only model *uniform*
 * tracks, so a mixed list resolves through the custom [ActionUIGridCells]
 * (see `Helpers/GridTrackHelper.kt`). No/invalid `columns` defaults to a single
 * flexible column, matching the Apple element.
 *
 * As with [LazyVStack], a `LazyVerticalGrid` *is* both the lazy builder and the
 * scroll viewport, so it needs a **bounded height**: a JSON `frame.height`
 * (already on [modifier]) wins, otherwise the incoming height is used when the
 * parent bounds it - so a full-screen grid FILLS, as it does on Apple and web -
 * and only an UNBOUNDED parent falls back to [DEFAULT_MAIN_EXTENT], which is what
 * keeps Compose's infinite-constraint error off the table.
 *
 * **Supported properties.**
 *   * `columns`   - track list as above (default one flexible column).
 *   * `spacing`   - gap between *rows* (the main axis, matching SwiftUI; default 0).
 *   * `alignment` - horizontal alignment, `leading` / `center` / `trailing`
 *     (default `center`), visible only when fixed columns underfill the width.
 *   * plus the universal modifiers resolved by `applyCommonProperties` (via
 *     [modifier]), notably `frame.height`.
 *
 * **Divergence vs. Apple.** SwiftUI inserts its default system spacing between
 * columns when `GridItem.spacing` is nil; the JSON schema does not expose that
 * knob, so columns here touch (cross-axis spacing 0).
 *
 * Children are placed via the lazy `items` DSL, whose item scope exposes neither
 * `weight` nor per-child `align`; each child receives only its
 * `applyCommonProperties` modifier.
 *
 * The grid also supports the data-driven `template` mode: when
 * [ActionUIElement.template] is present, one substituted template instance per
 * row in `states[`[ActionUIModel.ROWS_STATE_KEY]`]` (set via the rows API)
 * fills the next grid cell, substituted lazily as cells scroll into view. See
 * `Helpers/TemplateHelper.kt`.
 */
object LazyVGrid : ActionUIViewConstruction {

    override val insertableContainers = mapOf("children" to ContainerShape.FLAT)

    override fun initialStates(element: ActionUIElement): Map<String, Any> =
        mapOf(ActionUIModel.ROWS_STATE_KEY to emptyList<List<String>>())

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current

        val spacing = props?.get("spacing")?.jsonPrimitive?.doubleOrNull
        // SwiftUI LazyVGrid default alignment is .center - match it.
        val horizontalAlignment = props?.get("alignment")?.jsonPrimitive?.contentOrNull
            ?.let { parseColumnAlignment(it, logger) }
            ?: Alignment.CenterHorizontally
        val tracks = resolveGridTracks(props?.get("columns"), "LazyVGrid", "columns", logger)

        // A LazyVerticalGrid is its own scroll viewport and needs a bounded
        // height. An inherited frame.height (already on `modifier`) wins;
        // otherwise the default extent applies ONLY where it was meant to - to an
        // UNBOUNDED parent, which would otherwise trip Compose's infinite-constraint
        // error. Under a bounded parent the incoming constraint passes through and the
        // grid fills the space it is given, matching the Apple and web elements (both
        // grow to their parent and let an enclosing ScrollView handle the overflow).
        // This used to be an unconditional `.height(DEFAULT_MAIN_EXTENT)`, which
        // letterboxed every full-screen grid at 320dp with dead space beneath it.
        val hasExplicitHeight = (props?.get("frame") as? JsonObject)?.get("height") != null
        val sized = if (hasExplicitHeight) modifier
            else modifier.boundHeightIfUnbounded(DEFAULT_MAIN_EXTENT)
        // It ALSO needs a bounded WIDTH. Under a horizontally-scrollable (or
        // both-axis) ScrollView the proposed width is infinite, which Compose
        // crashes on ("...width should be bound by parent"). Bound it to the grid's
        // natural track width in that case; a no-op under a normal/finite-width
        // parent (and an explicit frame.width already bounds it).
        val gridModifier = sized.boundWidthIfUnbounded(
            gridNaturalCrossExtent(tracks, FLEXIBLE_FALLBACK_WIDTH),
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

        CompositionLocalProvider(LocalStackAxis provides StackAxis.Vertical) {
            LazyVerticalGrid(
                columns = ActionUIGridCells(tracks),
                modifier = gridModifier,
                verticalArrangement = spacing
                    ?.let { Arrangement.spacedBy(it.dp) }
                    ?: Arrangement.Top,
                horizontalArrangement = Arrangement.spacedBy(0.dp, horizontalAlignment),
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

    /** Fallback scroll-viewport height when the parent bounds nothing and JSON
     *  supplies no `frame.height`. */
    private val DEFAULT_MAIN_EXTENT = 320.dp

    /** Per-flexible-column width used only to give the grid a finite cross extent
     *  when its parent proposes an unbounded width (see [gridNaturalCrossExtent]). */
    private val FLEXIBLE_FALLBACK_WIDTH = 100.dp
}
