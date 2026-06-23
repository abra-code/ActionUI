package com.abracode.actionui.Helpers

import androidx.compose.animation.EnterTransition
import androidx.compose.animation.fadeIn
import androidx.compose.animation.scaleIn
import androidx.compose.animation.slideIn
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideInVertically
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.unit.IntOffset
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlin.math.roundToInt

/**
 * The `transition` modifier - how a view animates when it is inserted at runtime
 * (via `insertElement`), the Android port of the Apple implementation in
 * `ActionUI/Views/View.swift`. An element declaring
 *
 * ```
 * "transition": "opacity"                                   // shorthand
 * "transition": { "type": "move", "edge": "bottom" }        // dict
 * "transition": ["opacity", { "type": "scale" }]            // combined
 * ```
 *
 * plays the matching entrance once when the host inserts it; an `asymmetric`
 * declaration uses its `insertion` half. A view without `transition`, or one
 * present at initial load, appears instantly (the gap-#21 default).
 *
 * **How it animates.** SwiftUI's `.transition()` rides the `withAnimation`
 * transaction that wraps the insert; Compose has no equivalent, so the entrance
 * is an [androidx.compose.animation.AnimatedVisibility] wrapper around the
 * freshly-inserted element (`ViewModifierHelper.kt`), gated by
 * [com.abracode.actionui.Common.WindowModel.wasDynamicallyInserted] so only
 * runtime inserts animate. This helper maps the declaration to the
 * [EnterTransition] that wrapper plays.
 *
 * **Type mapping** (SwiftUI -> Compose enter): `opacity` -> [fadeIn]; `slide` ->
 * [slideInHorizontally] from the leading edge (SwiftUI's default slide
 * direction); `scale` -> [scaleIn] (optional `scale` start factor + `anchor`
 * transform origin); `move` -> a [slideInVertically]/[slideInHorizontally] from
 * the named `edge` (default bottom); `offset` -> [slideIn] by the fixed `x`/`y`
 * (rounded to px); `identity` -> no entrance (instant); `asymmetric` -> its
 * `insertion` half; an array -> the entries combined with `+`.
 *
 * **Known divergences from SwiftUI** (documented, not silent):
 *   * **Removal/exit is instant.** When the host removes an element the diff
 *     drops its node before an exit can play (Compose removes from the tree on
 *     recomposition); there is no retained-exit manager, so the `removal` half of
 *     an `asymmetric` transition and plain exits are no-ops. Entrances are the
 *     supported half. (Apple gets exit for free from SwiftUI.)
 *   * Only flat-container inserts (`children` / `destinations`) animate cleanly;
 *     a `Grid` cell wrapped in `AnimatedVisibility` can misplace during the run.
 */
internal val VALID_TRANSITION_TYPES = setOf(
    "opacity", "slide", "scale", "move", "offset", "identity", "asymmetric",
)

/**
 * Resolves a `transition` declaration ([value]: a shorthand string, a dict, or
 * an array = combined) to the [EnterTransition] for its insertion entrance, or
 * null when absent, invalid, or a pure `identity` (nothing to animate).
 */
internal fun resolveEnterTransition(value: JsonElement?): EnterTransition? = when (value) {
    null -> null
    is JsonArray -> {
        var combined: EnterTransition? = null
        for (entry in value) {
            val enter = resolveEnterTransition(entry) ?: continue
            combined = combined?.plus(enter) ?: enter
        }
        combined
    }
    is JsonPrimitive -> {
        val type = if (value.isString) value.content else null
        if (type != null && type in VALID_TRANSITION_TYPES) enterFor(type, null) else null
    }
    is JsonObject -> {
        val type = value.stringProperty("type")
        if (type != null && type in VALID_TRANSITION_TYPES) enterFor(type, value) else null
    }
}

/** The [EnterTransition] for a single [type] (+ its [obj] params), or null for identity. */
private fun enterFor(type: String, obj: JsonObject?): EnterTransition? = when (type) {
    "identity" -> null
    "opacity" -> fadeIn()
    // SwiftUI .slide inserts from the leading edge.
    "slide" -> slideInHorizontally(initialOffsetX = { -it })
    "scale" -> {
        val origin = transformOriginFor(obj?.stringProperty("anchor"))
        val factor = obj?.floatProperty("scale")
        if (factor != null) scaleIn(initialScale = factor, transformOrigin = origin)
        else scaleIn(transformOrigin = origin)
    }
    "move" -> when (obj?.stringProperty("edge")) {
        "top" -> slideInVertically(initialOffsetY = { -it })
        "leading" -> slideInHorizontally(initialOffsetX = { -it })
        "trailing" -> slideInHorizontally(initialOffsetX = { it })
        else -> slideInVertically(initialOffsetY = { it }) // bottom (default)
    }
    "offset" -> {
        val x = obj?.numberProperty("x")?.roundToInt() ?: 0
        val y = obj?.numberProperty("y")?.roundToInt() ?: 0
        slideIn(initialOffset = { IntOffset(x, y) })
    }
    "asymmetric" -> resolveEnterTransition(obj?.get("insertion"))
    else -> null
}

/** Maps a UnitPoint anchor name to a Compose [TransformOrigin] (default center). */
private fun transformOriginFor(anchor: String?): TransformOrigin = when (anchor) {
    "leading" -> TransformOrigin(0f, 0.5f)
    "trailing" -> TransformOrigin(1f, 0.5f)
    "top" -> TransformOrigin(0.5f, 0f)
    "bottom" -> TransformOrigin(0.5f, 1f)
    "topLeading" -> TransformOrigin(0f, 0f)
    "topTrailing" -> TransformOrigin(1f, 0f)
    "bottomLeading" -> TransformOrigin(0f, 1f)
    "bottomTrailing" -> TransformOrigin(1f, 1f)
    else -> TransformOrigin.Center
}
