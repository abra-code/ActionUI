package com.abracode.actionui.Helpers

import android.content.res.AssetManager
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import java.io.IOException

/**
 * Resolves a Material Symbol *name* (e.g. `"home"`) to its glyph *codepoint*,
 * using the bundled `MaterialSymbolsRounded.codepoints` table - the analog of the
 * name lookup the system does for SF Symbols. [MaterialSymbolGlyph] then renders
 * the codepoint.
 *
 * The table ships under `assets/symbols/` (downloaded by the `fetchMaterialSymbols`
 * Gradle task), next to the SF->Material map - both are name-lookup tables, while
 * the font binary itself lives under `assets/fonts/`. Its format is one entry per
 * line, `"<name> <hexcodepoint>"`, with lowercase hex and no `0x` prefix:
 *
 * ```
 * home e88a
 * settings e8b8
 * ```
 *
 * The parse ([parseCodepoints]) is pure and unit-tested; the asset load
 * ([materialCodepoint]) caches the parsed map once for the process, since the
 * table is ~4k entries and never changes at runtime.
 *
 * `materialName` carries a Material name directly (the Android-only authoring key
 * `materialName:android` is normalized to `materialName` by `PlatformFilter`).
 * The future `systemName` path resolves an SF name to a Material codepoint via a
 * separate SF->Material map (still being finalized) and then renders through the
 * same [MaterialSymbolGlyph].
 */

internal const val MATERIAL_SYMBOLS_CODEPOINTS_ASSET = "symbols/MaterialSymbolsRounded.codepoints"

/**
 * Parses the `.codepoints` table text into a `name -> codepoint` map. Blank lines,
 * lines without a name/codepoint pair, and lines whose codepoint is not valid hex
 * are skipped. Pure.
 */
internal fun parseCodepoints(text: String): Map<String, Int> {
    val map = HashMap<String, Int>(8192)
    for (rawLine in text.lineSequence()) {
        val line = rawLine.trim()
        if (line.isEmpty()) continue
        val space = line.indexOf(' ')
        if (space <= 0) continue
        val name = line.substring(0, space)
        val codepoint = line.substring(space + 1).trim().toIntOrNull(16) ?: continue
        map[name] = codepoint
    }
    return map
}

private val codepointsLock = Any()

@Volatile
private var codepointCache: Map<String, Int>? = null

/**
 * Returns the glyph codepoint for [name], or `null` if the name is not in the
 * bundled table (a name typo, or a name absent from this font release). The table
 * is loaded and parsed once and cached for the process lifetime.
 *
 * @param assets the app [AssetManager], for reading the bundled table.
 * @param logger receives a one-line warning if the table asset itself is missing.
 */
internal fun materialCodepoint(
    name: String,
    assets: AssetManager,
    logger: ActionUILogger? = null,
): Int? {
    val map = codepointCache ?: synchronized(codepointsLock) {
        codepointCache ?: loadCodepoints(assets, logger).also { codepointCache = it }
    }
    return map[name]
}

private fun loadCodepoints(assets: AssetManager, logger: ActionUILogger?): Map<String, Int> =
    try {
        val text = assets.open(MATERIAL_SYMBOLS_CODEPOINTS_ASSET)
            .use { it.readBytes().decodeToString() }
        parseCodepoints(text)
    } catch (e: IOException) {
        logger?.log(
            "Material Symbols codepoints table '$MATERIAL_SYMBOLS_CODEPOINTS_ASSET' not found " +
                "in assets/. Run the fetchMaterialSymbols Gradle task (it runs on build); " +
                "materialName glyphs cannot render without it.",
            LoggerLevel.warning
        )
        emptyMap()
    }
