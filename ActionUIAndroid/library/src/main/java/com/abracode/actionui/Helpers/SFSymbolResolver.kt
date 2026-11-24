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
 * The parse ([parseSFSymbolMap]) is pure and unit-tested; the asset load
 * ([sfSymbol]) caches the parsed map once for the process. Without the map
 * asset `systemName` warn-skips (the same honest degrade as a missing font).
 *
 * ## Fluent fill-ins
 *
 * An SF name the map has no row for is looked up next in `sf_to_fluent.map`
 * (same format, no fill or weight; a copy of Tools/fluent_symbols/sf_to_fluent.map
 * the build packages): the Fluent System Icons glyph that table gives it, as on
 * Windows and Linux. Its code point is one of the bundled Fluent font, which
 * overlaps Material's code points, so the entry names its font
 * ([SymbolFont.FLUENT]); Material's rows always win ([withFluentRows]).
 */

internal const val SF_MATERIAL_MAP_ASSET = "symbols/sf_to_material.map"
internal const val SF_FLUENT_MAP_ASSET = "symbols/sf_to_fluent.map"

/**
 * One resolved SF row: the glyph [codepoint] of the bundled [font], plus the axis
 * tuning the match needs (Material rows only; the Fluent font has no axes).
 */
internal data class SFSymbolEntry(
    val codepoint: Int,
    val fill: Boolean,
    val weight: Int?,
    val font: SymbolFont = SymbolFont.MATERIAL,
)

/**
 * Parses the `sf_to_material.map` text into an `sf_name -> [SFSymbolEntry]`
 * map. Comment (`#`) lines, blank lines, and rows without a valid `name hex` pair
 * are skipped. Trailing integers are read by range (`1` => fill; [MATERIAL_WEIGHT_MIN]
 * ..[MATERIAL_WEIGHT_MAX] => weight); anything else on the line is ignored. Pure.
 */
internal fun parseSFSymbolMap(text: String): Map<String, SFSymbolEntry> {
    val map = HashMap<String, SFSymbolEntry>(8192)
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
        map[name] = SFSymbolEntry(codepoint, fill, weight)
    }
    return map
}

private val sfMapLock = Any()

@Volatile
private var sfMapCache: Map<String, SFSymbolEntry>? = null

/**
 * Returns the [SFSymbolEntry] for the SF Symbol [name], or `null` if the name
 * is not in the bundled map (no match was embedded, or the map asset is absent).
 * The map is loaded and parsed once and cached for the process lifetime.
 *
 * @param assets the app [AssetManager], for reading the bundled map.
 * @param logger receives a one-line warning if the map asset itself is missing.
 */
internal fun sfSymbol(
    name: String,
    assets: AssetManager,
    logger: ActionUILogger? = null,
): SFSymbolEntry? {
    val map = sfMapCache ?: synchronized(sfMapLock) {
        sfMapCache ?: loadSFSymbolMap(assets, logger).also { sfMapCache = it }
    }
    return map[name]
}

/**
 * [material]'s rows, plus a [SymbolFont.FLUENT] row for each name of [fluentText]
 * (an `sf_to_fluent.map`) that [material] lacks. Pure.
 */
internal fun withFluentRows(
    material: Map<String, SFSymbolEntry>,
    fluentText: String,
): Map<String, SFSymbolEntry> {
    val merged = HashMap(material)
    for ((name, entry) in parseSFSymbolMap(fluentText)) {
        merged.putIfAbsent(name, entry.copy(font = SymbolFont.FLUENT))
    }
    return merged
}

private fun loadSFSymbolMap(assets: AssetManager, logger: ActionUILogger?): Map<String, SFSymbolEntry> =
    try {
        val text = assets.open(SF_MATERIAL_MAP_ASSET)
            .use { it.readBytes().decodeToString() }
        val fluentText = try {
            assets.open(SF_FLUENT_MAP_ASSET).use { it.readBytes().decodeToString() }
        } catch (e: IOException) {
            logger?.log(
                "SF->Fluent map '$SF_FLUENT_MAP_ASSET' not found in assets/; SF names " +
                    "without a Material glyph draw nothing.",
                LoggerLevel.warning
            )
            ""
        }
        withFluentRows(parseSFSymbolMap(text), fluentText)
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
