package com.abracode.actionui.Common

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Helpers.dpProperty
import com.abracode.actionui.Helpers.floatProperty
import com.abracode.actionui.Helpers.parseColor
import com.abracode.actionui.Helpers.stringProperty
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * Translates an [ActionUIElement]'s `properties` JSON into a Compose [Modifier]
 * chain. Mirrors the role of `View.swift`'s shared modifier pipeline on the
 * Apple side - properties common to every element type are resolved once here
 * so individual element builders stay focused on their type-specific Composable.
 *
 * Compose has no inheritance equivalent to SwiftUI's `View` base class; instead,
 * universal modifiers chain on `Modifier.Companion` from any context, and a
 * second set is scope-restricted at compile time (e.g. `weight` only exists on
 * `RowScope`/`ColumnScope`, `align` is scope-specific). The resolver mirrors
 * that split:
 *
 *   * [applyCommonProperties] - extension on [Modifier], callable anywhere.
 *     Handles `frame` (SwiftUI sizing - `{width,height}`), `opacity`,
 *     `cornerRadius`, `background`, `padding`.
 *   * [buildChildModifier] - overloads on each layout scope receiver, applied
 *     inside the container's content lambda where `weight`/`align` are in
 *     scope. They additionally chain in [applyCommonProperties].
 *
 * **Chain order** (universal). Modifiers earlier in the chain are outer for
 * layout, later are inner. Picked to make the most common combination behave
 * intuitively - a "card" with a background, rounded corners, and inner content
 * padding:
 *
 * ```
 *   frame.width  ->  frame.height  ->  opacity  ->  clip(cornerRadius)
 *                ->  background  ->  padding
 * ```
 *
 * Opacity sits between size and clip so it fades the entire visual subtree
 * (including the background), not just inner content. Padding is innermost so
 * the background fills the full size and the inner element sits in a padded
 * area inside the colored region.
 *
 * Unknown values (e.g. `background: "not-a-color"`, `align: "wat"`) are skipped
 * and a warning is sent through the optional [logger]. Unrecognized property
 * names are ignored silently - they may be element-specific (e.g. `text` on
 * `Text`, `spacing` on `VStack`) and the element's own builder will pick them
 * up.
 */
fun Modifier.applyCommonProperties(
    properties: JsonObject?,
    logger: ActionUILogger? = null
): Modifier {
    if (properties == null) return this
    var m: Modifier = this

    (properties["frame"] as? JsonObject)?.let { frame ->
        m = m.applySizeAxis(frame["width"], horizontal = true, logger)
        m = m.applySizeAxis(frame["height"], horizontal = false, logger)
    }
    properties.floatProperty("opacity")?.let { m = m.alpha(it) }
    properties.dpProperty("cornerRadius")?.let { m = m.clip(RoundedCornerShape(it)) }
    properties.stringProperty("background")?.let { name ->
        val c = parseColor(name)
        if (c != null) m = m.background(c)
        else logger?.log(
            "Unknown color '$name' for property 'background'. Property ignored.",
            LoggerLevel.warning
        )
    }
    properties.dpProperty("padding")?.let { m = m.padding(it) }
    return m
}

/**
 * Builds a Modifier for a child rendered inside a [androidx.compose.foundation.layout.Row].
 * Resolves `weight` (proportional sizing) and `align` (vertical positioning),
 * then chains in [applyCommonProperties].
 *
 * Recognized `align` values: `top`, `center` / `centerVertically`, `bottom`.
 */
fun RowScope.buildChildModifier(
    properties: JsonObject?,
    logger: ActionUILogger? = null
): Modifier {
    var m: Modifier = Modifier
    if (properties != null) {
        properties.floatProperty("weight")?.let { m = m.weight(it) }
        properties.stringProperty("align")?.let { name ->
            val a = parseVerticalAlignment(name)
            if (a != null) m = m.align(a)
            else logger?.log(
                "Unknown vertical alignment '$name' for Row child. Property ignored.",
                LoggerLevel.warning
            )
        }
    }
    return m.applyCommonProperties(properties, logger)
}

/**
 * Builds a Modifier for a child rendered inside a [androidx.compose.foundation.layout.Column].
 * Resolves `weight` and `align` (horizontal positioning), then chains in
 * [applyCommonProperties].
 *
 * Recognized `align` values: `start` / `leading`, `center` / `centerHorizontally`,
 * `end` / `trailing`.
 */
fun ColumnScope.buildChildModifier(
    properties: JsonObject?,
    logger: ActionUILogger? = null
): Modifier {
    var m: Modifier = Modifier
    if (properties != null) {
        properties.floatProperty("weight")?.let { m = m.weight(it) }
        properties.stringProperty("align")?.let { name ->
            val a = parseHorizontalAlignment(name)
            if (a != null) m = m.align(a)
            else logger?.log(
                "Unknown horizontal alignment '$name' for Column child. Property ignored.",
                LoggerLevel.warning
            )
        }
    }
    return m.applyCommonProperties(properties, logger)
}

/**
 * Builds a Modifier for a child rendered inside a [androidx.compose.foundation.layout.Box].
 * Resolves `align` (2D positioning), then chains in [applyCommonProperties].
 *
 * Recognized `align` values: `topStart` / `topLeading`, `topCenter` / `top`,
 * `topEnd` / `topTrailing`, `centerStart` / `centerLeading`, `center`,
 * `centerEnd` / `centerTrailing`, `bottomStart` / `bottomLeading`,
 * `bottomCenter` / `bottom`, `bottomEnd` / `bottomTrailing`.
 */
fun BoxScope.buildChildModifier(
    properties: JsonObject?,
    logger: ActionUILogger? = null
): Modifier {
    var m: Modifier = Modifier
    if (properties != null) {
        properties.stringProperty("align")?.let { name ->
            val a = parseAlignment(name)
            if (a != null) m = m.align(a)
            else logger?.log(
                "Unknown alignment '$name' for Box child. Property ignored.",
                LoggerLevel.warning
            )
        }
    }
    return m.applyCommonProperties(properties, logger)
}

// ---------------------------------------------------------------------------
// Parsing helpers (internal so unit tests in the same package can reach them).
// Generic JSON accessors and color parsing live in `Helpers` (JsonProperty.kt,
// ColorHelper.kt); what stays here is the modifier-pipeline-specific parsing.
// ---------------------------------------------------------------------------

/**
 * Applies one axis of a SwiftUI `frame` to the Modifier. `frame` is ActionUI's
 * canonical, SwiftUI-named sizing property - `{ "width": N, "height": M }` -
 * mapped to `.frame(width:height:)` on Apple and to Compose `width`/`height`
 * here. There is deliberately no top-level `width`/`height` property; that is
 * not a SwiftUI modifier. The `"infinity"` sentinel fills the available axis.
 */
internal fun Modifier.applySizeAxis(
    value: JsonElement?,
    horizontal: Boolean,
    logger: ActionUILogger? = null
): Modifier {
    if (value == null) return this
    val prim = value.jsonPrimitive
    prim.doubleOrNull?.let { n ->
        val size = n.toFloat().dp
        return if (horizontal) this.width(size) else this.height(size)
    }
    if (prim.contentOrNull == "infinity") {
        return if (horizontal) this.fillMaxWidth() else this.fillMaxHeight()
    }
    logger?.log(
        "Unsupported frame.${if (horizontal) "width" else "height"} value " +
            "'${prim.contentOrNull}'. Expected a number or 'infinity'. Ignored.",
        LoggerLevel.warning
    )
    return this
}

internal fun parseVerticalAlignment(name: String): Alignment.Vertical? =
    when (name.lowercase()) {
        "top"                          -> Alignment.Top
        "center", "centervertically"   -> Alignment.CenterVertically
        "bottom"                       -> Alignment.Bottom
        else                           -> null
    }

internal fun parseHorizontalAlignment(name: String): Alignment.Horizontal? =
    when (name.lowercase()) {
        "start", "leading"              -> Alignment.Start
        "center", "centerhorizontally"  -> Alignment.CenterHorizontally
        "end", "trailing"               -> Alignment.End
        else                            -> null
    }

/**
 * Resolves a Row/HStack parent-level alignment name into the Compose value.
 * Accepts SwiftUI vocabulary so a single JSON file works on both platforms:
 *
 *   * `top`                                    -> [Alignment.Top]
 *   * `center` / `centerVertically`            -> [Alignment.CenterVertically]
 *   * `bottom`                                 -> [Alignment.Bottom]
 *   * `firstTextBaseline` / `lastTextBaseline` -> `null` (no direct Compose
 *     equivalent) + warning through [logger]. The caller's default alignment
 *     applies - matches "ignore unrecognized" semantics and avoids visually
 *     misleading the reader with an artificial Top fallback that doesn't
 *     reflect the SwiftUI intent.
 *
 * Returns `null` for unknown or unsupported names; the call site picks a
 * default and the warning is emitted here.
 *
 * See `Private/Android_Porting_Notes.md` for the deferred decision around
 * mapping baseline alignment to Compose's per-child `alignByBaseline()`.
 */
internal fun parseRowAlignment(
    name: String,
    logger: ActionUILogger? = null
): Alignment.Vertical? {
    parseVerticalAlignment(name)?.let { return it }
    if (isBaselineAlignmentName(name)) {
        logger?.log(
            "Row/HStack alignment '$name' has no direct Compose equivalent; " +
                "default alignment will be used. (SwiftUI baseline alignment " +
                "is Compose-incompatible at the parent level.)",
            LoggerLevel.warning
        )
        return null
    }
    logger?.log(
        "Unknown alignment '$name' for Row/HStack. Falling back to default.",
        LoggerLevel.warning
    )
    return null
}

/**
 * Resolves a Column/VStack parent-level alignment name. SwiftUI's
 * `HorizontalAlignment` only has `.leading` / `.center` / `.trailing` -
 * no baseline variants - so this is a thin wrapper that adds logging on
 * unknown values.
 *
 * Accepts: `start` / `leading`, `center` / `centerHorizontally`,
 * `end` / `trailing`.
 */
internal fun parseColumnAlignment(
    name: String,
    logger: ActionUILogger? = null
): Alignment.Horizontal? {
    parseHorizontalAlignment(name)?.let { return it }
    logger?.log(
        "Unknown alignment '$name' for Column/VStack. Falling back to default.",
        LoggerLevel.warning
    )
    return null
}

private fun isBaselineAlignmentName(name: String): Boolean =
    name.lowercase() in setOf("firsttextbaseline", "lasttextbaseline")

internal fun parseAlignment(name: String): Alignment? =
    when (name.lowercase()) {
        "topstart", "topleading"        -> Alignment.TopStart
        "topcenter", "top"              -> Alignment.TopCenter
        "topend", "toptrailing"         -> Alignment.TopEnd
        "centerstart", "centerleading"  -> Alignment.CenterStart
        "center"                        -> Alignment.Center
        "centerend", "centertrailing"   -> Alignment.CenterEnd
        "bottomstart", "bottomleading"  -> Alignment.BottomStart
        "bottomcenter", "bottom"        -> Alignment.BottomCenter
        "bottomend", "bottomtrailing"   -> Alignment.BottomEnd
        else                            -> null
    }
