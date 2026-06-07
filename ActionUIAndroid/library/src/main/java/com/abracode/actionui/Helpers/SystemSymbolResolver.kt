package com.abracode.actionui.Helpers

import android.content.res.AssetManager
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import java.io.IOException

/**
 * Resolves an SF Symbol *name* (Apple's `Image(systemName:)`, e.g. `"heart.fill"`)
 * to a Material glyph via the bundled `sf_to_material.map` - the Android stand-in
 * for the system's SF Symbol lookup. The map is compiled from the glyphsvg
 * SF->Material mapping by `Tools/material_symbols/build_sf_material_map.py`; each
 * row already carries the resolved Material *codepoint* (so the runtime does ONE
 * lookup, not name->name->codepoint) plus any per-symbol axis tuning the match
 * needs. [MaterialSymbolGlyph] then draws the codepoint, exactly as for
 * `materialName`.
 *
 * ## Format
 *
 * One row per SF symbol, in `assets/symbols/` next to the Material codepoints
 * table; `#` lines are comments:
 *
 * ```
 * magnifyingglass ef7a
 * heart.fill e87d 1
 * gearshape e8b8 600
 * ```
 *
 * `<sf_name> <codepoint_hex> [<fill>] [<weight>]`. The trailing axis tokens are
 * **bare integers, disambiguated by range** (no `key=` prefix) because the value
 * sets are disjoint: `1` => the FILL axis at 1 (SF's `.fill` variants), `100..700`
 * => a `wght` override the match needs. The hex codepoint always begins `e`/`f`
 * (Material private-use area), so it never collides with a decimal axis token.
 *
 * The per-row fill/weight are *defaults* the author gets for free; an explicit
 * `:android` knob (`materialFill` / `materialWeight` / ...) still overrides them
 * (see [selectImageSource] / the `Image` builder).
 *
 * The parse ([parseSystemSymbolMap]) is pure and unit-tested; the asset load
 * ([systemSymbol]) caches the parsed map once for the process. The map is a
 * generated artifact and is `.gitignore`d while the mapping is being finalized, so
 * a clean checkout without it simply warn-skips `systemName` (the same honest
 * degrade as a missing font).
 */

internal const val SF_MATERIAL_MAP_ASSET = "symbols/sf_to_material.map"

/** One resolved SF->Material row: the glyph [codepoint] plus the axis tuning the match needs. */
internal data class SystemSymbolEntry(
    val codepoint: Int,
    val fill: Boolean,
    val weight: Int?,
)

/**
 * Parses the `sf_to_material.map` text into an `sf_name -> [SystemSymbolEntry]`
 * map. Comment (`#`) lines, blank lines, and rows without a valid `name hex` pair
 * are skipped. Trailing integers are read by range (`1` => fill; [MATERIAL_WEIGHT_MIN]
 * ..[MATERIAL_WEIGHT_MAX] => weight); anything else on the line is ignored. Pure.
 */
internal fun parseSystemSymbolMap(text: String): Map<String, SystemSymbolEntry> {
    val map = HashMap<String, SystemSymbolEntry>(8192)
    for (rawLine in text.lineSequence()) {
        val line = rawLine.trim()
        if (line.isEmpty() || line.startsWith("#")) continue
        val tokens = line.split(' ')
        if (tokens.size < 2) continue
        val name = tokens[0]
        val codepoint = tokens[1].toIntOrNull(16) ?: continue

        var fill = false
        var weight: Int? = null
        for (i in 2 until tokens.size) {
            val value = tokens[i].toIntOrNull() ?: continue
            when {
                value == 1 -> fill = true
                value in MATERIAL_WEIGHT_MIN..MATERIAL_WEIGHT_MAX -> weight = value
                // Out-of-range / unexpected token: ignore, keep the row usable.
            }
        }
        map[name] = SystemSymbolEntry(codepoint, fill, weight)
    }
    return map
}

private val sfMapLock = Any()

@Volatile
private var sfMapCache: Map<String, SystemSymbolEntry>? = null

/**
 * Returns the [SystemSymbolEntry] for the SF Symbol [name], or `null` if the name
 * is not in the bundled map (no match was embedded, or the map asset is absent).
 * The map is loaded and parsed once and cached for the process lifetime.
 *
 * @param assets the app [AssetManager], for reading the bundled map.
 * @param logger receives a one-line warning if the map asset itself is missing.
 */
internal fun systemSymbol(
    name: String,
    assets: AssetManager,
    logger: ActionUILogger? = null,
): SystemSymbolEntry? {
    val map = sfMapCache ?: synchronized(sfMapLock) {
        sfMapCache ?: loadSystemSymbolMap(assets, logger).also { sfMapCache = it }
    }
    return map[name]
}

private fun loadSystemSymbolMap(assets: AssetManager, logger: ActionUILogger?): Map<String, SystemSymbolEntry> =
    try {
        val text = assets.open(SF_MATERIAL_MAP_ASSET)
            .use { it.readBytes().decodeToString() }
        parseSystemSymbolMap(text)
    } catch (e: IOException) {
        logger?.log(
            "SF->Material map '$SF_MATERIAL_MAP_ASSET' not found in assets/. " +
                "systemName images cannot resolve to a Material glyph without it " +
                "(it is a generated artifact - see Tools/material_symbols/). " +
                "Use 'materialName:android' for an explicit Android glyph.",
            LoggerLevel.warning
        )
        emptyMap()
    }
