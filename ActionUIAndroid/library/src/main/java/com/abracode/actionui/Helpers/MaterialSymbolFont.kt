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
 * ## The bundled fonts
 *
 * Both are made by the library's Gradle build (generateSymbolFonts, running
 * Tools/material_symbols/make_android_symbol_fonts.py) and packaged as generated
 * assets:
 *
 * - `assets/fonts/MaterialSymbols.ttf`: every glyph of Material Symbols Rounded,
 *   variable on `wght` and `FILL`, with `GRAD` pinned at 0 and `opsz` at 24 (as
 *   Linux and Windows draw it; the whole font is ~15 MB, this one ~4.3 MB). The
 *   `GRAD` and `opsz` values below are still sent; a font without those axes
 *   ignores them, so `materialGrade` has no effect.
 * - `assets/fonts/FluentSymbols.ttf`: the Fluent System Icons glyphs that stand
 *   in for the SF names Material has no glyph for ([SymbolFont.FLUENT] rows of the
 *   SF map), at their own code points, static (weight and fill do not apply).
 *   Its code points overlap Material's, so each glyph is drawn from the font its
 *   map row names ([symbolFontFamily]).
 *
 * ## Why a variable font + `setFontVariationSettings`, not Compose `FontVariation`
 *
 * The upstream font exposes four axes (two are pinned in the bundled one):
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
 * CSS-like variation string (via [android.graphics.fonts.Font.Builder.setFontVariationSettings])
 * and wrap it in a Compose [FontFamily]. This is bulletproof on minSdk 31
 * (variable fonts are guaranteed since API 26; `Font.Builder(ByteBuffer)` since
 * API 29) and accepts any axis name.
 *
 * ## Caching and memory
 *
 * Each distinct (wght, FILL, GRAD, opsz) tuple is a distinct [Typeface], so the
 * built [FontFamily] is cached by those axes (opsz rounded to an int to bound the
 * cache). The font BYTES, however, exist exactly ONCE: the asset is read into a
 * single shared direct [java.nio.ByteBuffer] and every axis instance is built
 * from it zero-copy via [android.graphics.fonts.Font.Builder] +
 * [Typeface.CustomFallbackBuilder]. (The previous `Typeface.Builder(assets, path)`
 * path copied the ~15 MB font into a fresh heap-accounted buffer PER INSTANCE -
 * since opsz tracks the rendered text size, an app whose glyphs appear at a
 * handful of sizes accumulated 15 MB each and could OOM outright.)
 */

internal const val MATERIAL_SYMBOLS_FONT_ASSET = "fonts/MaterialSymbols.ttf"
internal const val FLUENT_SYMBOLS_FONT_ASSET = "fonts/FluentSymbols.ttf"

/** The bundled font a symbol glyph's code point belongs to. */
internal enum class SymbolFont { MATERIAL, FLUENT }

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

// The font bytes, read from the asset ONCE and shared by every axis instance.
// Typeface.Builder(assets, path) copies the whole font into a fresh direct
// ByteBuffer PER BUILD (VMRuntime.newNonMovableArray counts against the Java
// heap), so an app whose glyphs appear at a handful of distinct sizes used to
// accumulate 15 MB (the font's size then) per (wght, FILL, GRAD, opsz) tuple
// and could OOM outright (observed: a 3-screen restore hit the 192 MB growth
// limit). Building each instance from one shared buffer via
// Font.Builder(ByteBuffer) keeps the font bytes in memory exactly once. The one-time load is synchronized: a first-use
// race would otherwise pin a SECOND copy permanently through the losing
// thread's cached Font (cheap - this is a cold path taken once per process).
// One buffer per font asset (Material's and Fluent's).
private val sharedFontBuffers = ConcurrentHashMap<String, java.nio.ByteBuffer>()
private val fontBufferLock = Any()

private fun sharedFontBuffer(assets: AssetManager, asset: String): java.nio.ByteBuffer? {
    sharedFontBuffers[asset]?.let { return it }
    synchronized(fontBufferLock) {
        sharedFontBuffers[asset]?.let { return it }
        return try {
            val bytes = assets.open(asset).use { it.readBytes() }
            val buf = java.nio.ByteBuffer.allocateDirect(bytes.size)
            buf.put(bytes)
            buf.flip()
            sharedFontBuffers[asset] = buf
            buf
        } catch (e: Exception) {
            // Asset missing: do NOT cache the failure, so a later build that adds
            // the font recovers without a process restart - the pre-existing contract.
            null
        }
    }
}

/**
 * Returns a [FontFamily] backed by the bundled Material variable font instanced at
 * the given axes, cached by (weight, fill, grade, opsz). Every instance shares ONE
 * read-only copy of the font bytes ([sharedFontBuffer]); only the small platform
 * font objects differ per axis tuple. If the font asset is missing, falls back to
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
    val typeface = typefaceOf(assets, MATERIAL_SYMBOLS_FONT_ASSET) {
        setFontVariationSettings(materialVariationSettings(weight, fill, grade, key.opsz.toFloat()))
    }
    return if (typeface != null) {
        FontFamily(typeface).also { familyCache[key] = it }
    } else {
        FontFamily.Default
    }
}

@Volatile
private var fluentFamily: FontFamily? = null

/**
 * Returns the [FontFamily] of the bundled Fluent font (static: no axes), built once
 * from its shared bytes. Falls back to [FontFamily.Default] without caching when the
 * asset is missing, as [materialSymbolFontFamily] does.
 */
internal fun fluentSymbolFontFamily(assets: AssetManager): FontFamily {
    fluentFamily?.let { return it }
    val typeface = typefaceOf(assets, FLUENT_SYMBOLS_FONT_ASSET) { this }
        ?: return FontFamily.Default
    return FontFamily(typeface).also { fluentFamily = it }
}

/**
 * The [FontFamily] to draw a glyph of [font] with: the Material font at the given
 * axes, or the Fluent font, to which the axes do not apply.
 */
internal fun symbolFontFamily(
    assets: AssetManager,
    font: SymbolFont,
    weight: Int,
    fill: Float,
    grade: Int,
    opsz: Float,
): FontFamily = when (font) {
    SymbolFont.MATERIAL -> materialSymbolFontFamily(assets, weight, fill, grade, opsz)
    SymbolFont.FLUENT -> fluentSymbolFontFamily(assets)
}

/** A platform [Typeface] over the shared bytes of [asset], or null when it cannot be built. */
private fun typefaceOf(
    assets: AssetManager,
    asset: String,
    configure: android.graphics.fonts.Font.Builder.() -> android.graphics.fonts.Font.Builder,
): Typeface? = try {
    val buffer = sharedFontBuffer(assets, asset)
    if (buffer == null) {
        null
    } else {
        // slice(): an independent position/limit view of the SAME bytes, so
        // concurrent builds cannot disturb each other's read cursor.
        val font = android.graphics.fonts.Font.Builder(buffer.slice()).configure().build()
        Typeface.CustomFallbackBuilder(android.graphics.fonts.FontFamily.Builder(font).build()).build()
    }
} catch (e: Exception) {
    null
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
    SymbolFontGlyph(
        codepoint, SymbolFont.MATERIAL, sizeSp, tint, weight, fill, grade, contentDescription, modifier,
    )
}

/**
 * Renders [codepoint] of the bundled [font] as a tinted glyph at [sizeSp], as
 * [MaterialSymbolGlyph] does; for [SymbolFont.FLUENT] the axes are ignored.
 */
@Composable
internal fun SymbolFontGlyph(
    codepoint: Int,
    font: SymbolFont,
    sizeSp: TextUnit,
    tint: Color,
    weight: Int,
    fill: Float,
    grade: Int,
    contentDescription: String?,
    modifier: Modifier,
) {
    val assets = LocalContext.current.assets
    val opsz = sizeSp.value.coerceIn(MATERIAL_OPSZ_MIN, MATERIAL_OPSZ_MAX)
    val family = remember(font, weight, fill, grade, opsz.roundToInt(), assets) {
        symbolFontFamily(assets, font, weight, fill, grade, opsz)
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
