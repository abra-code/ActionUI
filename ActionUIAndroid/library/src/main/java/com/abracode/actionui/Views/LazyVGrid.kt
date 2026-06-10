package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalStackAxis
import com.abracode.actionui.Common.StackAxis
import com.abracode.actionui.Common.applyCommonProperties
import com.abracode.actionui.Common.parseColumnAlignment
import com.abracode.actionui.Helpers.ActionUIGridCells
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.resolveGridTracks
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
 * (already on [modifier]) wins, otherwise [DEFAULT_MAIN_EXTENT] is applied so an
 * unbounded parent cannot trip Compose's infinite-constraint error.
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
 */
object LazyVGrid : ActionUIViewConstruction {
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
        // otherwise apply a default so an unbounded parent cannot crash it.
        val hasExplicitHeight = (props?.get("frame") as? JsonObject)?.get("height") != null
        val gridModifier = if (hasExplicitHeight) modifier else modifier.height(DEFAULT_MAIN_EXTENT)

        CompositionLocalProvider(LocalStackAxis provides StackAxis.Vertical) {
            LazyVerticalGrid(
                columns = ActionUIGridCells(tracks),
                modifier = gridModifier,
                verticalArrangement = spacing
                    ?.let { Arrangement.spacedBy(it.dp) }
                    ?: Arrangement.Top,
                horizontalArrangement = Arrangement.spacedBy(0.dp, horizontalAlignment),
            ) {
                items(element.children.orEmpty()) { child ->
                    val builder = ActionUIRegistry.lookup(child.type) ?: return@items
                    ProvideTextStyleEnvironment(child.properties, logger) {
                        builder.BuildView(child, Modifier.applyCommonProperties(child.properties, logger))
                    }
                }
            }
        }
    }

    /** Default scroll-viewport height when JSON supplies no `frame.height`. */
    private val DEFAULT_MAIN_EXTENT = 320.dp
}
