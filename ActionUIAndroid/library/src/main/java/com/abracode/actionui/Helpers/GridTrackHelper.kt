package com.abracode.actionui.Helpers

import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.layout
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * The cross-axis track model shared by [com.abracode.actionui.Views.LazyVGrid]
 * (`columns`) and [com.abracode.actionui.Views.LazyHGrid] (`rows`). The Android
 * counterpart of the SwiftUI `GridItem` mapping in `ActionUI/Views/LazyVGrid.swift`:
 * a JSON track dictionary with a numeric `minimum` becomes a fixed track
 * (`GridItem(.fixed(minimum))` on Apple) and `"flexible": true` becomes an
 * equal-share flexible track (`GridItem(.flexible())`).
 */
internal sealed interface GridTrack {
    data class Fixed(val size: Dp) : GridTrack
    object Flexible : GridTrack
}

/**
 * Resolves a grid's track-list property (`columns` on LazyVGrid, `rows` on
 * LazyHGrid) into [GridTrack]s, mirroring the Swift element's validation and
 * `GridItem` mapping:
 *   * absent property - one flexible track, silently (the Apple default).
 *   * not an array of objects - warn `"... must be an array of dictionaries"`,
 *     default to one flexible track.
 *   * per entry: numeric `minimum` wins over `flexible`; `"flexible": true`
 *     makes a flexible track; anything else is skipped. If nothing valid
 *     remains, warn `"... must contain valid minimum or flexible values"` and
 *     default to one flexible track.
 */
internal fun resolveGridTracks(
    tracksJson: JsonElement?,
    elementType: String,
    propertyName: String,
    logger: ActionUILogger? = null,
): List<GridTrack> {
    val defaultTracks = listOf<GridTrack>(GridTrack.Flexible)
    if (tracksJson == null) return defaultTracks

    val entries = (tracksJson as? JsonArray)?.takeIf { array -> array.all { it is JsonObject } }
    if (entries == null) {
        logger?.log(
            "$elementType $propertyName must be an array of dictionaries; ignoring",
            LoggerLevel.warning,
        )
        return defaultTracks
    }

    val tracks = entries.mapNotNull { entry ->
        val track = entry as JsonObject
        val minimum = track.numberProperty("minimum")
        when {
            minimum != null -> GridTrack.Fixed(minimum.toFloat().dp)
            track.booleanProperty("flexible") == true -> GridTrack.Flexible
            else -> null
        }
    }
    if (tracks.isEmpty()) {
        logger?.log(
            "$elementType $propertyName must contain valid minimum or flexible values; ignoring",
            LoggerLevel.warning,
        )
        return defaultTracks
    }
    return tracks
}

/**
 * A [GridCells] that lays out one cell per [GridTrack] - the piece Compose's
 * stock cells cannot express. [GridCells.Fixed]/[GridCells.Adaptive] only model
 * uniform tracks, while the Apple JSON allows a *mixed* list (e.g. a 100 dp
 * fixed column next to a flexible one), so the cross-axis sizes are computed
 * here: fixed tracks take their dp size, flexible tracks split the remaining
 * space evenly (leftover pixels go one each to the leading flexible tracks so
 * the row always fills exactly).
 */
internal data class ActionUIGridCells(private val tracks: List<GridTrack>) : GridCells {
    override fun Density.calculateCrossAxisCellSizes(availableSize: Int, spacing: Int): List<Int> {
        val fixedTotal = tracks.sumOf { if (it is GridTrack.Fixed) it.size.roundToPx() else 0 }
        val flexibleCount = tracks.count { it is GridTrack.Flexible }
        val totalSpacing = spacing * (tracks.size - 1)
        val remaining = (availableSize - totalSpacing - fixedTotal).coerceAtLeast(0)
        val flexibleBase = if (flexibleCount > 0) remaining / flexibleCount else 0
        var leftoverPixels = if (flexibleCount > 0) remaining % flexibleCount else 0
        return tracks.map { track ->
            when (track) {
                is GridTrack.Fixed -> track.size.roundToPx()
                GridTrack.Flexible -> flexibleBase + if (leftoverPixels-- > 0) 1 else 0
            }
        }
    }
}

/**
 * The grid's natural CROSS-axis extent: the sum of its track sizes - fixed tracks
 * take their dp size, flexible tracks use [flexibleFallback] (a flexible track
 * cannot size against an unbounded cross axis, so it falls back to a sensible
 * width). Cross-axis spacing is 0 here (tracks touch), so this is a plain sum.
 *
 * Used to give a lazy grid a finite cross extent when its parent proposes an
 * unbounded one - e.g. a LazyVGrid inside a horizontally-scrollable (or both-axis)
 * ScrollView - which Compose otherwise hard-crashes on.
 */
internal fun gridNaturalCrossExtent(tracks: List<GridTrack>, flexibleFallback: Dp): Dp =
    tracks.fold(0.dp) { acc, track ->
        acc + when (track) {
            is GridTrack.Fixed -> track.size
            GridTrack.Flexible -> flexibleFallback
        }
    }

/**
 * Bounds the measured width to [fallback] ONLY when the incoming maxWidth is
 * unbounded ([Constraints.Infinity]); a transparent pass-through otherwise.
 *
 * A [androidx.compose.foundation.lazy.grid.LazyVerticalGrid] requires a bounded
 * width; Compose throws "LazyVerticalGrid's width should be bound by parent" when
 * one is placed under a horizontally-scrollable parent that proposes infinite
 * width. This gives it a finite content width (see [gridNaturalCrossExtent])
 * instead of crashing. An explicit `frame.width` already bounds the axis, so this
 * stays a no-op there.
 */
internal fun Modifier.boundWidthIfUnbounded(fallback: Dp): Modifier = this.layout { measurable, constraints ->
    val bounded = if (constraints.maxWidth == Constraints.Infinity)
        constraints.copy(maxWidth = fallback.roundToPx().coerceAtLeast(constraints.minWidth))
    else constraints
    val placeable = measurable.measure(bounded)
    layout(placeable.width, placeable.height) { placeable.place(0, 0) }
}

/**
 * Height twin of [boundWidthIfUnbounded] - for a
 * [androidx.compose.foundation.lazy.grid.LazyHorizontalGrid] placed under a
 * vertically-scrollable parent that proposes infinite height.
 */
internal fun Modifier.boundHeightIfUnbounded(fallback: Dp): Modifier = this.layout { measurable, constraints ->
    val bounded = if (constraints.maxHeight == Constraints.Infinity)
        constraints.copy(maxHeight = fallback.roundToPx().coerceAtLeast(constraints.minHeight))
    else constraints
    val placeable = measurable.measure(bounded)
    layout(placeable.width, placeable.height) { placeable.place(0, 0) }
}
