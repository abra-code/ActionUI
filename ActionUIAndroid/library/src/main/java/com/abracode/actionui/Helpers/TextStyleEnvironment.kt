package com.abracode.actionui.Helpers

import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Inherited text/content styling - the Android counterpart of SwiftUI's
 * `.font`, `.foregroundStyle`, and `.tint`, which are *environment* modifiers:
 * applied to any view, they flow down to every descendant until overridden.
 *
 * Compose has no `View` base class to carry these, so unlike the geometry and
 * decoration properties (which resolve to a `Modifier` chain in
 * `ModifierResolver.applyCommonProperties`) these three cannot be expressed as
 * modifiers - a modifier only styles the node it is attached to, it does not
 * reach the descendant `Text`/controls the way SwiftUI's environment does.
 * Instead they propagate through [CompositionLocalProvider]s, the idiomatic
 * Compose mechanism for ambient, inheritable values:
 *
 *   * `font`            -> merged into [LocalTextStyle]   (read by `Text`)
 *   * `foregroundStyle` -> [LocalContentColor]            (read by `Text`)
 *   * `tint`            -> [LocalActionUITint]             (read by the controls)
 *
 * [LocalTextStyle] and [LocalContentColor] are Material3's own locals, which
 * `Text` already consults, so propagating through them styles descendant text
 * with no change to the `Text` builder. There is no universal "tint" local in
 * Compose (Material components take explicit color params), so [LocalActionUITint]
 * is introduced here and read by the interactive control builders (Button,
 * Toggle, Slider, ProgressView).
 *
 * The seam is [ProvideTextStyleEnvironment], applied once per element at the
 * point the element is built - in `ActionUI.Render` for the root and in each
 * container's child loop for the rest - so an element's own font/color/tint
 * style both itself and its subtree, exactly once.
 *
 * **Known divergences from SwiftUI** (Compose has no direct equivalent):
 *   * Named text styles (`title`, `body`, ...) map onto the nearest Material3
 *     typography token rather than iOS's Dynamic Type metrics, so exact sizes
 *     differ.
 *   * A custom font *name* (SwiftUI's `.custom("Menlo", ...)`, or the `name` key
 *     of the dictionary form) has no portable Android equivalent without a
 *     bundled font resource; it is warned and the inherited/system font is used.
 *   * `foregroundStyle`/`tint` resolve only literal colors (via [parseColor]);
 *     theme-derived semantic styles (`primary`, `tint`, ...) are not resolved
 *     yet, matching the `background` modifier's current limitation.
 */
val LocalActionUITint: ProvidableCompositionLocal<Color?> =
    compositionLocalOf { null }

/**
 * Wraps [content] in the inherited text-styling environment derived from
 * [properties]' `font`, `foregroundStyle`, and `tint`. When none of the three is
 * present the [content] is invoked directly with no provider, so the common case
 * (most elements carry none) adds no composition overhead.
 */
@Composable
fun ProvideTextStyleEnvironment(
    properties: JsonObject?,
    logger: ActionUILogger? = null,
    content: @Composable () -> Unit
) {
    if (properties == null) {
        content()
        return
    }

    val fontStyle = resolveFontStyle(properties["font"], logger)
    val foreground = resolveStyleColor(properties.stringProperty("foregroundStyle"), "foregroundStyle", logger)
    val tint = resolveStyleColor(properties.stringProperty("tint"), "tint", logger)

    if (fontStyle == null && foreground == null && tint == null) {
        content()
        return
    }

    val mergedTextStyle = fontStyle?.let { LocalTextStyle.current.merge(it) } ?: LocalTextStyle.current
    CompositionLocalProvider(
        LocalTextStyle provides mergedTextStyle,
        LocalContentColor provides (foreground ?: LocalContentColor.current),
        LocalActionUITint provides (tint ?: LocalActionUITint.current),
        content = content
    )
}

/** Resolves a `foregroundStyle`/`tint` color string, warning on an unknown color. */
private fun resolveStyleColor(name: String?, property: String, logger: ActionUILogger?): Color? {
    if (name == null) return null
    val color = parseColor(name)
    if (color == null) {
        logger?.log(
            "Unknown color '$name' for property '$property'. Property ignored.",
            LoggerLevel.warning
        )
    }
    return color
}

/**
 * Resolves a `font` value into a [TextStyle] to merge over the inherited one, or
 * `null` to leave the inherited style untouched. String form is a named text
 * style (mapped to a Material3 typography token) or a custom font name
 * (unsupported on Android - warned); object form is `{ name, size, weight,
 * design }`, mirroring `FontHelper.swift`.
 */
@Composable
internal fun resolveFontStyle(element: JsonElement?, logger: ActionUILogger?): TextStyle? {
    when (element) {
        null -> return null
        is JsonPrimitive -> if (element.isString) return resolveNamedTextStyle(element.content, logger)
        is JsonObject -> return resolveFontDictionary(element, logger)
        else -> {}
    }
    logger?.log("font must be a string or object; ignored.", LoggerLevel.warning)
    return null
}

/**
 * Maps a SwiftUI named text style onto the nearest Material3 typography token.
 * An unrecognized name is treated as a custom font family, which Android cannot
 * resolve without a bundled resource - warned, and the inherited style is kept.
 */
@Composable
private fun resolveNamedTextStyle(name: String, logger: ActionUILogger?): TextStyle? {
    val type = MaterialTheme.typography
    return when (name) {
        "largeTitle"  -> type.displaySmall
        "title"       -> type.headlineMedium
        "title2"      -> type.headlineSmall
        "title3"      -> type.titleLarge
        "headline"    -> type.titleMedium
        "subheadline" -> type.titleSmall
        "body"        -> type.bodyLarge
        "callout"     -> type.bodyMedium
        "footnote"    -> type.bodySmall
        "caption"     -> type.labelMedium
        "caption2"    -> type.labelSmall
        else -> {
            logger?.log(
                "Custom font name '$name' is not supported on Android (no bundled " +
                    "font resource); using the inherited text style.",
                LoggerLevel.warning
            )
            null
        }
    }
}

/** Builds a [TextStyle] from the `{ name, size, weight, design }` font object form. */
private fun resolveFontDictionary(dict: JsonObject, logger: ActionUILogger?): TextStyle? {
    val size = dict.numberProperty("size")
    if (size == null) {
        logger?.log("font object requires 'size'; ignored.", LoggerLevel.warning)
        return null
    }
    dict.stringProperty("name")?.let { name ->
        logger?.log(
            "Custom font name '$name' is not supported on Android (no bundled " +
                "font resource); using the system font at the requested size/weight.",
            LoggerLevel.warning
        )
    }
    return TextStyle(
        fontSize = size.toFloat().sp,
        fontWeight = resolveFontWeight(dict.stringProperty("weight"), logger),
        fontFamily = resolveFontDesign(dict.stringProperty("design"), logger)
    )
}

/**
 * Maps SwiftUI's nine `Font.Weight` names onto Compose's nine [FontWeight]
 * constants by order (ultraLight -> Thin (W100) ... black -> Black (W900)).
 * Returns `null` (inherit) for an unknown weight, with a warning.
 */
internal fun resolveFontWeight(name: String?, logger: ActionUILogger? = null): FontWeight? =
    when (name) {
        null         -> null
        "ultraLight" -> FontWeight.Thin
        "thin"       -> FontWeight.ExtraLight
        "light"      -> FontWeight.Light
        "regular"    -> FontWeight.Normal
        "medium"     -> FontWeight.Medium
        "semibold"   -> FontWeight.SemiBold
        "bold"       -> FontWeight.Bold
        "heavy"      -> FontWeight.ExtraBold
        "black"      -> FontWeight.Black
        else -> {
            logger?.log("Unknown font weight '$name'; ignored.", LoggerLevel.warning)
            null
        }
    }

/**
 * Maps SwiftUI's `Font.Design` onto a Compose [FontFamily]. `rounded` has no
 * built-in Compose family, so it warns and falls back to the default; `null`
 * (no design) also yields the default family.
 */
internal fun resolveFontDesign(name: String?, logger: ActionUILogger? = null): FontFamily =
    when (name) {
        null, "default" -> FontFamily.Default
        "monospaced"    -> FontFamily.Monospace
        "serif"         -> FontFamily.Serif
        "rounded" -> {
            logger?.log(
                "font design 'rounded' has no built-in Compose font family; using default.",
                LoggerLevel.warning
            )
            FontFamily.Default
        }
        else -> {
            logger?.log("Unknown font design '$name'; using default.", LoggerLevel.warning)
            FontFamily.Default
        }
    }
