package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.LazyHorizontalGrid
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
import com.abracode.actionui.Common.parseRowAlignment
import com.abracode.actionui.Helpers.ActionUIGridCells
import com.abracode.actionui.Helpers.ProvideTextStyleEnvironment
import com.abracode.actionui.Helpers.resolveGridTracks
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
 */
object LazyHGrid : ActionUIViewConstruction {
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
        val hasExplicitWidth = (props?.get("frame") as? JsonObject)?.get("width") != null
        val gridModifier = if (hasExplicitWidth) modifier else modifier.width(DEFAULT_MAIN_EXTENT)

        CompositionLocalProvider(LocalStackAxis provides StackAxis.Horizontal) {
            LazyHorizontalGrid(
                rows = ActionUIGridCells(tracks),
                modifier = gridModifier,
                horizontalArrangement = spacing
                    ?.let { Arrangement.spacedBy(it.dp) }
                    ?: Arrangement.Start,
                verticalArrangement = Arrangement.spacedBy(0.dp, verticalAlignment),
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

    /** Default scroll-viewport width when JSON supplies no `frame.width`. */
    private val DEFAULT_MAIN_EXTENT = 320.dp
}
