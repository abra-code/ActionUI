package com.abracode.actionui.Helpers

import androidx.compose.foundation.text.selection.DisableSelection
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.ColorScheme
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
import androidx.compose.ui.text.style.TextAlign
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
 *   * `foregroundStyle` -> `LocalContentColor`            (read by `Text`)
 *   * `tint`            -> [LocalActionUITint]             (read by the controls)
 *   * `multilineTextAlignment` -> `textAlign` merged into [LocalTextStyle]
 *     (SwiftUI's environment alignment for wrapped lines: leading/center/trailing)
 *   * `textSelection`   -> a [SelectionContainer] / [DisableSelection] wrap
 *     (SwiftUI's `.textSelection(.enabled/.disabled)`: descendant text becomes
 *     long-press selectable; `disabled` opts a subtree back out inside an
 *     enabled ancestor, exactly Compose's `DisableSelection` contract)
 *
 * [LocalTextStyle] and `LocalContentColor` are Material3's own locals, which
 * `Text` already consults, so propagating through them styles descendant text
 * with no change to the `Text` builder. There is no universal "tint" local in
 * Compose (Material components take explicit color params), so [LocalActionUITint]
 * is introduced here and read by the interactive control builders (Button,
 * Toggle, Slider, ProgressView).
 *
 * `font`, `multilineTextAlignment`, and `textSelection` - plus the static control
 * environment (`buttonStyle` / `controlSize` / `labelsHidden`, locals and parsing
 * in `ControlEnvironment.kt`) - ride [ProvideTextStyleEnvironment], applied once
 * per element at the point it is built (in `ActionUI.Render` for the root and in
 * each container's child loop for the rest, off the parent's static child
 * properties), so an element's own font/alignment/selection style both itself and
 * its subtree, exactly once.
 *
 * `foregroundStyle` and `tint` are NOT here: like `disabled` / `hidden`, they must
 * be RUNTIME-REACTIVE (`setElementProperty(foregroundStyle/tint, ...)`), matching
 * Apple (which reads them off the mutated `validatedProperties` every render) and
 * web (whose runtime applier recolors). So they are resolved and provided - together
 * with `disabled` / `hidden` - by [ProvideReactiveEnvironment] at the shared build
 * entry point (`ViewModifierHelper.BuildViewWithModifiers`), on the host-merged
 * *effective* element (`ViewModel.propertyOverrides`), NOT off the parent's static
 * child properties. (The per-row `template` path, which builds throw-away instances
 * directly, applies the same provider on the substituted row properties in
 * `TemplateHelper`.) See `ReactiveEnvironment.kt` for why the reactive environment
 * is one provider rather than one per property.
 *
 * **Known divergences from SwiftUI** (Compose has no direct equivalent):
 *   * Named text styles (`title`, `body`, ...) map onto the nearest Material3
 *     typography token rather than iOS's Dynamic Type metrics, so exact sizes
 *     differ.
 *   * A custom font *name* (SwiftUI's `.custom("Menlo", ...)`, or the `name` key
 *     of the dictionary form) has no portable Android equivalent without a
 *     bundled font resource; it is warned and the inherited/system font is used.
 *   * `foregroundStyle`/`tint` resolve both literal colors AND theme-derived Apple
 *     semantic styles (`primary`, `secondary`, `tint`, `link`, `fill.*`, ...): the
 *     `colorScheme` captured here is passed to `resolveColorOrSemantic`, so a
 *     semantic name maps to an adaptive Material role exactly as the `background`
 *     modifier now does.
 */
val LocalActionUITint: ProvidableCompositionLocal<Color?> =
    compositionLocalOf { null }

/**
 * Wraps [content] in the STATIC inherited environment derived from the parent's
 * authored [properties] - `font`, `multilineTextAlignment`, `textSelection`, and
 * the static control environment (`buttonStyle`, `controlSize`, `labelsHidden`;
 * locals and parsing in `ControlEnvironment.kt`). The runtime-reactive properties
 * (`foregroundStyle`, `tint`, `disabled`, `hidden`) are NOT here: they are provided
 * off the host-merged effective element by [ProvideReactiveEnvironment]
 * (`ReactiveEnvironment.kt`). When none is present the [content] is invoked directly
 * with no provider, so the common case (most elements carry none) adds no
 * composition overhead.
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
    // `foregroundStyle` / `tint` (and `disabled` / `hidden`) are NOT resolved here:
    // they are runtime-reactive and provided on the host-merged effective element by
    // [ProvideReactiveEnvironment] (see the class note), not off the parent's static
    // child properties this provider reads.
    // `labelsHidden: false` provides nothing - `.labelsHidden()` has no inverse.
    val labelsHidden = resolveLabelsHidden(properties, logger)
    val buttonStyle = properties.stringProperty("buttonStyle")?.let { parseButtonStyle(it, logger) }
    val controlSize = properties.stringProperty("controlSize")?.let { parseControlSize(it, logger) }
    val textAlign = resolveMultilineTextAlignment(properties.stringProperty("multilineTextAlignment"), logger)
    val selectable = resolveTextSelection(properties.stringProperty("textSelection"), logger)

    val provided = buildList {
        if (fontStyle != null || textAlign != null) {
            var merged = LocalTextStyle.current
            fontStyle?.let { merged = merged.merge(it) }
            textAlign?.let { merged = merged.copy(textAlign = it) }
            add(LocalTextStyle provides merged)
        }
        if (labelsHidden) add(LocalActionUILabelsHidden provides true)
        buttonStyle?.let { add(LocalActionUIButtonStyle provides it) }
        controlSize?.let { add(LocalActionUIControlSize provides it) }
    }
    val wrapped: @Composable () -> Unit = when (selectable) {
        null -> content
        true -> ({ SelectionContainer { content() } })
        false -> ({ DisableSelection { content() } })
    }
    if (provided.isEmpty()) {
        wrapped()
        return
    }
    CompositionLocalProvider(*provided.toTypedArray()) { wrapped() }
}

/**
 * Maps `multilineTextAlignment` (SwiftUI: how *wrapped lines* align within a
 * text block) onto Compose's [TextAlign]. Apple's validation: an unknown value
 * warns and is ignored (inherit).
 */
internal fun resolveMultilineTextAlignment(name: String?, logger: ActionUILogger? = null): TextAlign? =
    when (name) {
        null       -> null
        "leading"  -> TextAlign.Start
        "center"   -> TextAlign.Center
        "trailing" -> TextAlign.End
        else -> {
            logger?.log(
                "Invalid multilineTextAlignment '$name'; expected 'leading', 'center', or 'trailing', ignoring",
                LoggerLevel.warning
            )
            null
        }
    }

/**
 * Maps `textSelection` onto the selection wrap: `true` ([SelectionContainer]),
 * `false` ([DisableSelection]), or `null` (no wrap). Apple's validation: an
 * unknown value warns and is ignored.
 */
internal fun resolveTextSelection(name: String?, logger: ActionUILogger? = null): Boolean? =
    when (name) {
        null       -> null
        "enabled"  -> true
        "disabled" -> false
        else -> {
            logger?.log(
                "Invalid textSelection '$name'; expected 'enabled' or 'disabled', ignoring",
                LoggerLevel.warning
            )
            null
        }
    }

/**
 * Resolves a `foregroundStyle`/`tint` color string, warning on an unknown color.
 * Apple semantic names (`secondary`, `tint`, `link`, `fill.tertiary`, ...) resolve
 * to adaptive Material roles via [resolveColorOrSemantic] using the [colorScheme]
 * captured at the (composable) call site; literal hex/named colors fall through to
 * `parseColor`. Called by [ProvideReactiveEnvironment] (the runtime-reactive
 * foregroundStyle/tint provider on the host-merged effective element).
 */
internal fun resolveStyleColor(
    name: String?,
    property: String,
    colorScheme: ColorScheme,
    logger: ActionUILogger?
): Color? {
    if (name == null) return null
    val color = resolveColorOrSemantic(name, colorScheme)
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
