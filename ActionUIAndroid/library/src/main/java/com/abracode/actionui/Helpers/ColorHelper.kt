package com.abracode.actionui.Helpers

import androidx.compose.material3.ColorScheme
import androidx.compose.ui.graphics.Color
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Color-string parsing/serialization for ActionUI Android. The Android
 * counterpart of Apple's `ActionUI/Helpers/ColorHelper.swift` - the single place
 * that turns a JSON color string into a Compose [Color], used by the universal
 * `background` modifier, the shape `fill`/`stroke` resolver, and the `ColorPicker`
 * element / `COLOR` value bridge.
 *
 * [parseColor] accepts (case-insensitive, trimmed):
 *   * `#RGB`        - 3-digit, each nibble doubled; opaque.
 *   * `#RGBA`       - 4-digit, each nibble doubled; alpha last.
 *   * `#RRGGBB`     - opaque.
 *   * `#RRGGBBAA`   - **alpha last**, matching Apple's canonical hex form.
 *   * Named colors: `black`, `white`, `red`, `green`, `blue`, `yellow`, `cyan`,
 *     `magenta`, `orange`, `purple`, `pink`, `mint`, `teal`, `indigo`, `brown`,
 *     `gray`/`grey`, `lightgray`/`lightgrey`, `darkgray`/`darkgrey`,
 *     `clear`/`transparent`.
 *
 * The hex byte order is the **canonical Apple order** (`#RRGGBBAA`, alpha last),
 * so a color string authored once renders identically on both platforms; this is
 * the convention `parseColor`/[colorToHex] round-trip on. (An earlier Android-only
 * build read 8-digit hex as `#AARRGGBB`; that divergence was removed.) `mint` /
 * `teal` / `indigo` / `brown` are reasonable approximations of SwiftUI's palette
 * (SwiftUI's exact component values are private).
 *
 * Returns `null` for any other input. Apple's `resolveShapeStyle` additionally
 * understands theme-derived **semantic** styles (`primary`, `tint`, ...). Those
 * cannot be resolved here because [parseColor] is a pure, context-free function,
 * while the Material adaptive roles live in `MaterialTheme.colorScheme` (readable
 * only inside composition). [resolveSemanticColor] - which takes a [ColorScheme]
 * captured at the modifier-application site - handles the semantic set, and
 * [resolveColorOrSemantic] is the combined entry point callers use (semantic
 * first, then this `parseColor` fallback). See `Private/Android_Porting_Notes.md`
 * section 11 / the semantic-color entry.
 */
internal fun parseColor(name: String): Color? {
    val trimmed = name.trim()
    if (trimmed.startsWith("#")) return parseHexColor(trimmed)
    // SwiftUI's `<color>.opacity(<fraction>)` (e.g. "gray.opacity(0.15)") - the canonical way
    // to make a translucent tint. Resolve the base color and scale its alpha by the fraction.
    // Mirrors Swift's Color.opacity(_:) and web's CSS color-mix.
    Regex("""^(.+)\.opacity\(\s*([0-9]*\.?[0-9]+)\s*\)$""").matchEntire(trimmed)?.let { m ->
        val base = parseColor(m.groupValues[1]) ?: return null
        val fraction = m.groupValues[2].toFloatOrNull()?.coerceIn(0f, 1f) ?: return null
        return base.copy(alpha = base.alpha * fraction)
    }
    return when (trimmed.lowercase()) {
        "black"                  -> Color.Black
        "white"                  -> Color.White
        "red"                    -> Color.Red
        "green"                  -> Color.Green
        "blue"                   -> Color.Blue
        "yellow"                 -> Color.Yellow
        "cyan"                   -> Color.Cyan
        "magenta"                -> Color.Magenta
        "gray", "grey"           -> Color.Gray
        "lightgray", "lightgrey" -> Color.LightGray
        "darkgray", "darkgrey"   -> Color.DarkGray
        "clear", "transparent"   -> Color.Transparent
        "orange"                 -> Color(0xFFFFA500.toInt())
        "purple"                 -> Color(0xFF800080.toInt())
        "pink"                   -> Color(0xFFFFC0CB.toInt())
        "mint"                   -> Color(0xFF3EB489.toInt())
        "teal"                   -> Color(0xFF008080.toInt())
        "indigo"                 -> Color(0xFF4B0082.toInt())
        "brown"                  -> Color(0xFFA52A2A.toInt())
        else                     -> null
    }
}

/**
 * Resolves an Apple **semantic** color name into an adaptive Compose [Color]
 * drawn from a Material 3 [colorScheme]. This is the composition-aware companion
 * to [parseColor]: Apple's `ColorHelper.resolveShapeStyle` understands a set of
 * theme-derived styles (`primary`, `secondary`, `background`, `fill`, `tint`,
 * `separator`, ...) that adapt to light/dark automatically; Material 3 supplies
 * the same adaptive primitives, so the names map onto roles rather than to any
 * hardcoded hex - light/dark and dynamic color then Just Work, as on Apple.
 *
 * The [colorScheme] must be captured inside composition (e.g.
 * `MaterialTheme.colorScheme` at the modifier-application site); the function
 * itself is pure so it stays unit-testable.
 *
 * ## Final mapping (Apple semantic -> Material 3 role)
 *
 * SwiftUI's hierarchical content levels (`primary`..`quinary`) are *translucent
 * grays over the content color*; Apple's `fill.*` are likewise translucent grays;
 * Apple's `background.*` are *opaque layered surfaces*. So:
 *   * the content levels map to `onSurface`/`onSurfaceVariant` at decreasing
 *     alpha (the iOS label-opacity ladder: 1.0 / ~0.6 / ~0.3 / ~0.18 / ~0.10),
 *   * the `fill.*` levels map to `onSurface` at the iOS fill-opacity ladder
 *     (~0.20 / 0.16 / 0.12 / 0.08) - the alpha-over-onSurface form tracks the
 *     iOS translucent grays more faithfully than the opaque `surfaceContainer*`
 *     tones would,
 *   * the opaque `background.*` levels map to the Material surface-container
 *     tonal roles (`surface` / `surfaceContainerLow` / `surfaceContainer` /
 *     `surfaceContainerHigh`), which ARE the idiomatic Material layered surfaces.
 *
 * `tint` / `link` -> `primary` (the accent role; `tint` is also carried by
 * `LocalActionUITint` for controls). `separator` -> `outlineVariant`.
 * `placeholder` -> `onSurfaceVariant` @ 0.5. `selection` -> `secondaryContainer`.
 * `windowBackground` -> `surfaceDim` (a dimmed surface, the desktop-window
 * analog). `foreground.*` track the content levels (SwiftUI's `.foreground` is
 * the primary content style); `background` (bare) -> `surface`.
 *
 * Returns `null` for any non-semantic name (the caller then tries [parseColor]).
 */
internal fun resolveSemanticColor(name: String, colorScheme: ColorScheme): Color? {
    return when (name.trim().lowercase()) {
        // ---- Hierarchical content levels (translucent over onSurface) ----
        "primary"                 -> colorScheme.onSurface
        "secondary"               -> colorScheme.onSurfaceVariant
        "tertiary"                -> colorScheme.onSurfaceVariant.copy(alpha = 0.75f)
        "quaternary"              -> colorScheme.onSurface.copy(alpha = 0.18f)
        "quinary"                 -> colorScheme.onSurface.copy(alpha = 0.10f)
        // ---- foreground.* == the content levels (foreground is the primary style) ----
        "foreground"              -> colorScheme.onSurface
        "foreground.secondary"    -> colorScheme.onSurfaceVariant
        "foreground.tertiary"     -> colorScheme.onSurfaceVariant.copy(alpha = 0.75f)
        "foreground.quaternary"   -> colorScheme.onSurface.copy(alpha = 0.18f)
        // ---- Opaque layered surfaces -> Material surface-container tonal roles ----
        "background"              -> colorScheme.surface
        "background.secondary"    -> colorScheme.surfaceContainerLow
        "background.tertiary"     -> colorScheme.surfaceContainer
        "background.quaternary"   -> colorScheme.surfaceContainerHigh
        "windowbackground"        -> colorScheme.surfaceDim
        // ---- Translucent fills (over onSurface, the iOS fill-opacity ladder) ----
        "fill"                    -> colorScheme.onSurface.copy(alpha = 0.20f)
        "fill.secondary"          -> colorScheme.onSurface.copy(alpha = 0.16f)
        "fill.tertiary"           -> colorScheme.onSurface.copy(alpha = 0.12f)
        "fill.quaternary"         -> colorScheme.onSurface.copy(alpha = 0.08f)
        // ---- Discrete semantic roles ----
        "separator"               -> colorScheme.outlineVariant
        "tint", "link"            -> colorScheme.primary
        "placeholder"             -> colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
        "selection"               -> colorScheme.secondaryContainer
        else                      -> null
    }
}

/**
 * The combined color entry point for color-applying modifiers: tries the
 * composition-aware [resolveSemanticColor] first (so a known Apple semantic name
 * like `secondary` or `fill.tertiary` resolves to an adaptive Material role),
 * then falls back to the pure [parseColor] (hex / named / `.opacity()`).
 *
 * Also makes the SwiftUI `<name>.opacity(<fraction>)` suffix work on a *semantic*
 * base (e.g. `secondary.opacity(0.5)`, `tint.opacity(0.3)`): [parseColor] cannot
 * resolve the semantic base, so the suffix is peeled here and the base is routed
 * back through this function, scaling the resolved role's alpha by the fraction -
 * mirroring SwiftUI's `Color.opacity(_:)` and the web `color-mix` path.
 *
 * Pass `colorScheme = null` to skip the semantic step entirely (the pre-existing
 * pure behavior), e.g. from a non-composition context.
 */
internal fun resolveColorOrSemantic(name: String, colorScheme: ColorScheme?): Color? {
    if (colorScheme == null) return parseColor(name)
    val trimmed = name.trim()
    resolveSemanticColor(trimmed, colorScheme)?.let { return it }
    // `<semantic>.opacity(<fraction>)` - parseColor only handles a parseable base,
    // so resolve a semantic base here and scale its alpha.
    SEMANTIC_OPACITY_REGEX.matchEntire(trimmed)?.let { m ->
        val base = resolveSemanticColor(m.groupValues[1], colorScheme) ?: return@let
        val fraction = m.groupValues[2].toFloatOrNull()?.coerceIn(0f, 1f) ?: return@let
        return base.copy(alpha = base.alpha * fraction)
    }
    return parseColor(name)
}

private val SEMANTIC_OPACITY_REGEX =
    Regex("""^(.+)\.opacity\(\s*([0-9]*\.?[0-9]+)\s*\)$""")

/**
 * Serializes [color] to a hex string in the canonical Apple form: `#RRGGBB` when
 * opaque, `#RRGGBBAA` (alpha last) otherwise. The inverse of [parseColor]; backs
 * the `COLOR` branch of `ActionUIModel.getElementValueAsString`. Mirrors Apple's
 * `ColorHelper.colorToHex`.
 */
internal fun colorToHex(color: Color): String {
    val r = (color.red * 255f).roundToInt()
    val g = (color.green * 255f).roundToInt()
    val b = (color.blue * 255f).roundToInt()
    return if (color.alpha >= 1f) {
        String.format(Locale.ROOT, "#%02X%02X%02X", r, g, b)
    } else {
        val a = (color.alpha * 255f).roundToInt()
        String.format(Locale.ROOT, "#%02X%02X%02X%02X", r, g, b, a)
    }
}

/**
 * A color in HSV (hue/saturation/value) space - the model the `ColorPicker`'s
 * free-form dialog edits. `hue` is in degrees `[0, 360)`, `saturation` and
 * `value` (brightness) are fractions `[0, 1]`. Alpha is kept on the Compose
 * [Color] and carried separately (see [hsvToColor]), so HSV stays the picker's
 * single source of truth while a control drags - converting RGB->HSV->RGB
 * round-trips losslessly for the hue/sat/value the picker holds, but a *gray*
 * (saturation 0) or *black* (value 0) color has no recoverable hue, which is
 * why the picker seeds HSV once and edits it directly rather than re-deriving it
 * from the bound color on every change.
 */
internal data class Hsv(val hue: Float, val saturation: Float, val value: Float)

/**
 * Decomposes this opaque-or-translucent [Color] into [Hsv]. The standard
 * RGB->HSV transform; `hue` is `0` for a grayscale color (no chroma). Pure (no
 * Android framework call - unlike `android.graphics.Color.colorToHSV`), so it is
 * unit-testable and matches [hsvToColor] exactly.
 */
internal fun Color.toHsv(): Hsv {
    val r = red
    val g = green
    val b = blue
    val max = maxOf(r, g, b)
    val min = minOf(r, g, b)
    val delta = max - min
    val hue = when {
        delta == 0f -> 0f
        max == r -> 60f * (((g - b) / delta) % 6f)
        max == g -> 60f * (((b - r) / delta) + 2f)
        else -> 60f * (((r - g) / delta) + 4f)
    }.let { if (it < 0f) it + 360f else it }
    val saturation = if (max == 0f) 0f else delta / max
    return Hsv(hue, saturation, max)
}

/**
 * Builds a Compose [Color] from HSV components plus [alpha]. [hue] wraps into
 * `[0, 360)`; [saturation] / [value] / [alpha] are clamped to `[0, 1]`. The
 * inverse of [Color.toHsv]; backs the `ColorPicker` HSV dialog's
 * saturation/brightness area, hue track, and alpha track. Pure, so the dialog's
 * canvases need no Android framework color call.
 */
internal fun hsvToColor(hue: Float, saturation: Float, value: Float, alpha: Float = 1f): Color {
    val h = ((hue % 360f) + 360f) % 360f
    val s = saturation.coerceIn(0f, 1f)
    val v = value.coerceIn(0f, 1f)
    val c = v * s
    val x = c * (1f - abs((h / 60f) % 2f - 1f))
    val m = v - c
    val (r1, g1, b1) = when {
        h < 60f  -> Triple(c, x, 0f)
        h < 120f -> Triple(x, c, 0f)
        h < 180f -> Triple(0f, c, x)
        h < 240f -> Triple(0f, x, c)
        h < 300f -> Triple(x, 0f, c)
        else     -> Triple(c, 0f, x)
    }
    return Color(
        red = (r1 + m).coerceIn(0f, 1f),
        green = (g1 + m).coerceIn(0f, 1f),
        blue = (b1 + m).coerceIn(0f, 1f),
        alpha = alpha.coerceIn(0f, 1f),
    )
}

private fun parseHexColor(hex: String): Color? {
    val h = hex.removePrefix("#")
    return try {
        when (h.length) {
            3 -> Color(                                      // #RGB
                red = nibble(h, 0), green = nibble(h, 1), blue = nibble(h, 2),
            )
            4 -> Color(                                      // #RGBA (alpha last)
                red = nibble(h, 0), green = nibble(h, 1), blue = nibble(h, 2), alpha = nibble(h, 3),
            )
            6 -> Color(                                      // #RRGGBB
                red = byte(h, 0), green = byte(h, 2), blue = byte(h, 4),
            )
            8 -> Color(                                      // #RRGGBBAA (alpha last)
                red = byte(h, 0), green = byte(h, 2), blue = byte(h, 4), alpha = byte(h, 6),
            )
            else -> null
        }
    } catch (e: NumberFormatException) {
        null
    }
}

/** Expands a single hex nibble at [index] to a 0-255 component (`F` -> 255). */
private fun nibble(h: String, index: Int): Int = h.substring(index, index + 1).repeat(2).toInt(16)

/** Reads a two-digit hex byte starting at [index] as a 0-255 component. */
private fun byte(h: String, index: Int): Int = h.substring(index, index + 2).toInt(16)
