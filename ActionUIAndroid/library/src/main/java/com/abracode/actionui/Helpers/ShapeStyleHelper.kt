package com.abracode.actionui.Helpers

import androidx.compose.material3.ColorScheme
import androidx.compose.ui.graphics.Color
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.JsonObject

/**
 * Shared fill/stroke resolution for the stateless shape elements
 * (`Rectangle`, `RoundedRectangle`, `Capsule`, `Circle`, `Ellipse`). The single
 * place that turns a shape's `fill` / `stroke` / `strokeLineWidth` properties
 * into a concrete paint, so each shape builder only has to describe its
 * *geometry* (the `DrawScope` call) and converge on one color contract -
 * mirroring how the Apple side resolves shape styling through
 * `ColorHelper.resolveShapeStyle`.
 *
 * ## Fill vs. stroke (matches Apple priority)
 *
 * Apple's shape builders (`ActionUI/Views/Rectangle.swift` et al.) resolve in
 * this order: a resolvable `fill` wins; otherwise a resolvable `stroke` is used;
 * otherwise the bare shape is rendered, which SwiftUI fills with its foreground
 * style (`.primary`). [resolveShapePaint] reproduces that fall-through exactly -
 * including the subtle case where a *present-but-unresolvable* `fill` falls
 * through to `stroke` (Apple only enters the fill branch when the color
 * resolves).
 *
 * ## Color vocabulary
 *
 * Colors resolve through [resolveColorOrSemantic]: Apple **semantic** styles
 * (`primary`, `secondary`, `tint`, `fill`, `fill.tertiary`, `separator`, ...) map
 * to adaptive Material 3 roles when a [ColorScheme] is supplied (the builder
 * captures it from `MaterialTheme.colorScheme`), and literal named / `#RRGGBB` /
 * `#RRGGBBAA` hex fall through to `parseColor` - the same combined vocabulary the
 * universal `background` modifier now accepts. A genuinely unknown color still
 * warns and falls back to the [defaultColor] (the theme's foreground analog,
 * SwiftUI's `.primary` for an unstyled shape).
 */

/** A resolved shape paint: a [color] applied either as a fill or as a stroke. */
internal data class ShapePaint(
    val color: Color,
    /** Stroke line width in **dp**; `null` means fill the shape solidly. */
    val strokeWidthDp: Float?
)

/**
 * Resolves the [ShapePaint] for a shape element, honoring Apple's
 * fill-then-stroke-then-foreground fall-through (see file header).
 *
 * @param defaultColor the color used for a bare shape (no `fill`/`stroke`) or
 *   when a provided color string can't be parsed - the builder passes the
 *   theme's foreground analog (e.g. `MaterialTheme.colorScheme.onSurface`),
 *   matching SwiftUI's `.primary` default for an unstyled shape.
 * @param colorScheme the active `MaterialTheme.colorScheme`, captured by the
 *   builder so a semantic `fill`/`stroke` (e.g. `"tint"`, `"fill.tertiary"`)
 *   resolves to its adaptive Material role. `null` resolves literal colors only.
 */
internal fun resolveShapePaint(
    properties: JsonObject?,
    defaultColor: Color,
    logger: ActionUILogger? = null,
    colorScheme: ColorScheme? = null
): ShapePaint {
    if (properties != null) {
        properties.stringProperty("fill")?.let { fill ->
            resolveColorOrSemantic(fill, colorScheme)?.let { return ShapePaint(it, strokeWidthDp = null) }
            logger?.log(
                "Unknown shape fill '$fill'. Named colors, #RRGGBB/#RRGGBBAA hex, and " +
                    "Apple semantic styles (e.g. 'tint', 'fill.tertiary') are supported. " +
                    "Falling back to the default foreground color.",
                LoggerLevel.warning
            )
            // Fall through to stroke, mirroring Apple (the fill branch is only
            // taken when the color resolves).
        }
        properties.stringProperty("stroke")?.let { stroke ->
            resolveColorOrSemantic(stroke, colorScheme)?.let {
                val width = properties.floatProperty("strokeLineWidth") ?: 1f
                return ShapePaint(it, strokeWidthDp = width)
            }
            logger?.log(
                "Unknown shape stroke '$stroke'. Named colors, #RRGGBB/#RRGGBBAA hex, " +
                    "and Apple semantic styles are supported. Falling back to the default " +
                    "foreground fill.",
                LoggerLevel.warning
            )
        }
    }
    return ShapePaint(defaultColor, strokeWidthDp = null)
}

/**
 * Warns once that a `"continuous"` (squircle) corner style has no Compose
 * equivalent and the circular geometry will be used instead. Apple's
 * `RoundedRectangle.cornerStyle` / `Capsule.style` accept `circular`
 * (default) or `continuous`; Compose's [androidx.compose.foundation.shape.RoundedCornerShape]
 * and `drawRoundRect` only produce circular arcs, so `continuous` is
 * downgraded to `circular`.
 *
 * No-ops for an absent property or an explicit `"circular"`; an unrecognized
 * value (neither token) also warns so authors catch typos. Call from inside a
 * `remember(properties)` block so it fires once per properties change rather
 * than per recomposition.
 */
internal fun warnUnsupportedCornerStyle(
    properties: JsonObject?,
    key: String,
    shapeName: String,
    logger: ActionUILogger?
) {
    val style = properties?.stringProperty(key) ?: return
    when (style) {
        "circular" -> { /* native */ }
        "continuous" -> logger?.log(
            "$shapeName $key 'continuous' (squircle) has no Compose equivalent; " +
                "using 'circular' corners instead.",
            LoggerLevel.warning
        )
        else -> logger?.log(
            "$shapeName $key '$style' is invalid; expected 'circular' or " +
                "'continuous'. Using 'circular'.",
            LoggerLevel.warning
        )
    }
}
