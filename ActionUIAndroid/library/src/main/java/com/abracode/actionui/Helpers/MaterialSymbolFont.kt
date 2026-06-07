package com.abracode.actionui.Helpers

import android.content.res.AssetManager
import android.graphics.Typeface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.TextUnit
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.roundToInt

/**
 * The Material Symbols glyph-rendering engine - the Android analog of how Apple's
 * `Image(systemName:)` draws an SF Symbol. SF Symbols ship as a font and the
 * system renders a glyph at a requested weight/scale (and `.fill` is a separate
 * glyph); this does the same with the bundled **MaterialSymbolsRounded** variable
 * font, which is visually closest to SF Symbols.
 *
 * Given a Unicode codepoint plus the variable-font axis values, this renders the
 * glyph as tinted, sized text. The caller resolves the codepoint
 * ([materialCodepoint]) and the axis values ([selectImageSource]); this file owns
 * the font instantiation and the draw.
 *
 * ## Why a variable font + `setFontVariationSettings`, not Compose `FontVariation`
 *
 * The font exposes four axes (confirmed from its `fvar` table):
 *
 * | Axis   | Range        | Default | Meaning                                  |
 * |--------|--------------|---------|------------------------------------------|
 * | `wght` | 100 .. 700   | 400     | weight (analog of SF Symbol weight)      |
 * | `FILL` | 0 .. 1       | 0       | fill (SF's `.fill` variant is `FILL` 1)  |
 * | `GRAD` | -50 .. 200   | 0       | grade (fine optical weight adjustment)   |
 * | `opsz` | 20 .. 48     | 24      | optical size (track the rendered px size)|
 *
 * `FILL`/`GRAD`/`opsz` are custom axes. Rather than depend on Compose's typed
 * `FontVariation` helpers covering them, we build a platform [Typeface] with the
 * CSS-like variation string via [Typeface.Builder.setFontVariationSettings] and
 * wrap it in a Compose [FontFamily]. This is bulletproof on minSdk 31 (variable
 * fonts are guaranteed since API 26) and accepts any axis name.
 *
 * ## Caching
 *
 * Each distinct (wght, FILL, GRAD, opsz) tuple is a distinct [Typeface], so the
 * built [FontFamily] is cached by those axes (opsz rounded to an int to bound the
 * cache). Building a typeface is not free; the cache keeps repeated glyphs and
 * recompositions cheap.
 */

internal const val MATERIAL_SYMBOLS_FONT_ASSET = "fonts/MaterialSymbolsRounded.ttf"

internal const val MATERIAL_WEIGHT_MIN = 100
internal const val MATERIAL_WEIGHT_MAX = 700
internal const val MATERIAL_WEIGHT_DEFAULT = 400
internal const val MATERIAL_FILL_MIN = 0f
internal const val MATERIAL_FILL_MAX = 1f
internal const val MATERIAL_FILL_DEFAULT = 0f
internal const val MATERIAL_GRADE_MIN = -50
internal const val MATERIAL_GRADE_MAX = 200
internal const val MATERIAL_GRADE_DEFAULT = 0
internal const val MATERIAL_OPSZ_MIN = 20f
internal const val MATERIAL_OPSZ_MAX = 48f

/**
 * Builds the `font-variation-settings` string the platform [Typeface.Builder]
 * expects. Forced to [Locale.US] so the decimal separator is always `.` - a
 * comma-decimal default locale would otherwise emit `'FILL' 1,000`, which the
 * parser rejects. Pure / unit-testable.
 */
internal fun materialVariationSettings(weight: Int, fill: Float, grade: Int, opsz: Float): String =
    String.format(
        Locale.US,
        "'wght' %d, 'FILL' %.3f, 'GRAD' %d, 'opsz' %.1f",
        weight, fill, grade, opsz
    )

private data class AxisKey(val weight: Int, val fill: Float, val grade: Int, val opsz: Int)

private val familyCache = ConcurrentHashMap<AxisKey, FontFamily>()

/**
 * Returns a [FontFamily] backed by the bundled variable font instanced at the
 * given axes, cached by (weight, fill, grade, opsz). If the font asset is missing
 * (e.g. the [fetchMaterialSymbols] Gradle task did not run), falls back to
 * [FontFamily.Default] without caching, so a later build that adds the font
 * recovers without a process restart.
 */
internal fun materialSymbolFontFamily(
    assets: AssetManager,
    weight: Int,
    fill: Float,
    grade: Int,
    opsz: Float,
): FontFamily {
    val key = AxisKey(weight, fill, grade, opsz.roundToInt())
    familyCache[key]?.let { return it }

    val typeface: Typeface? = try {
        Typeface.Builder(assets, MATERIAL_SYMBOLS_FONT_ASSET)
            .setFontVariationSettings(materialVariationSettings(weight, fill, grade, key.opsz.toFloat()))
            .build()
    } catch (e: Exception) {
        null
    }

    return if (typeface != null) {
        FontFamily(typeface).also { familyCache[key] = it }
    } else {
        FontFamily.Default
    }
}

/**
 * Renders the Material Symbol [codepoint] as a tinted glyph at [sizeSp], with the
 * given variable-font axes. The glyph is drawn as text (the faithful analog of
 * SF-Symbol rendering), so [tint] is the text color and [sizeSp] the font size;
 * `opsz` tracks [sizeSp] (clamped to the font's 20..48 range).
 *
 * Axis inputs are expected pre-clamped by the caller ([selectImageSource]).
 */
@Composable
fun MaterialSymbolGlyph(
    codepoint: Int,
    sizeSp: TextUnit,
    tint: Color,
    weight: Int = MATERIAL_WEIGHT_DEFAULT,
    fill: Float = MATERIAL_FILL_DEFAULT,
    grade: Int = MATERIAL_GRADE_DEFAULT,
    contentDescription: String? = null,
    modifier: Modifier = Modifier,
) {
    val assets = LocalContext.current.assets
    val opsz = sizeSp.value.coerceIn(MATERIAL_OPSZ_MIN, MATERIAL_OPSZ_MAX)
    val family = remember(weight, fill, grade, opsz.roundToInt(), assets) {
        materialSymbolFontFamily(assets, weight, fill, grade, opsz)
    }
    val glyph = remember(codepoint) { String(Character.toChars(codepoint)) }
    val described = if (contentDescription != null) {
        modifier.semantics { this.contentDescription = contentDescription }
    } else {
        modifier
    }

    Text(
        text = glyph,
        color = tint,
        fontSize = sizeSp,
        fontFamily = family,
        modifier = described,
    )
}
