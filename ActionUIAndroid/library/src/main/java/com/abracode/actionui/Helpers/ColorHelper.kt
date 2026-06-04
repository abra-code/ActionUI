package com.abracode.actionui.Helpers

import androidx.compose.ui.graphics.Color
import java.util.Locale
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
 * understands theme-derived **semantic** styles (`primary`, `tint`, ...); those
 * need a Compose theme and are not resolved here yet (see
 * `Private/Android_Porting_Notes.md` section 11).
 */
internal fun parseColor(name: String): Color? {
    val trimmed = name.trim()
    if (trimmed.startsWith("#")) return parseHexColor(trimmed)
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
