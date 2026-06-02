package com.abracode.actionui.Helpers

import androidx.compose.ui.graphics.Color

/**
 * Color-string parsing for ActionUI Android. The Android counterpart of Apple's
 * `ActionUI/Helpers/ColorHelper.swift` — the single place that turns a JSON
 * color string into a Compose [Color], used by the universal `background`
 * modifier and by the shape `fill`/`stroke` resolver.
 *
 * Accepts:
 *   * `#RRGGBB` — opaque
 *   * `#AARRGGBB` — with alpha
 *   * Named colors: `black`, `white`, `red`, `green`, `blue`, `yellow`, `cyan`,
 *     `magenta`, `gray`/`grey`, `lightgray`/`lightgrey`, `darkgray`/`darkgrey`,
 *     `orange`, `purple`, `pink`, `clear`/`transparent`. Case-insensitive.
 *
 * Returns `null` for any other input. Apple's `resolveShapeStyle` additionally
 * understands theme-derived **semantic** styles (`primary`, `tint`, …); those
 * are not resolved here yet (see `Private/Android_Porting_Notes.md` §11).
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
        else                     -> null
    }
}

private fun parseHexColor(hex: String): Color? {
    val h = hex.removePrefix("#")
    return try {
        when (h.length) {
            6 -> Color(0xFF000000.toInt() or h.toLong(16).toInt())     // #RRGGBB
            8 -> Color(h.toLong(16).toInt())                            // #AARRGGBB
            else -> null
        }
    } catch (e: NumberFormatException) {
        null
    }
}
