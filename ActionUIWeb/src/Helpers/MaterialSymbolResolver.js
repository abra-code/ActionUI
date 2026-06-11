// MaterialSymbolResolver.js — SF Symbol name → Material glyph resolution.
// Web analog of ActionUI/.../Helpers/SystemSymbolResolver.kt (Android).
//
// SF Symbols are Apple-licensed and unavailable off Apple platforms. Android
// maps an SF name (Image(systemName:), e.g. "heart.fill") to the closest
// Material Symbols glyph via a bundled `sf_to_material.map`, compiled by
// Tools/material_symbols/build_sf_material_map.py. The web port reuses that same
// map verbatim (copied to ActionUIWeb/assets/symbols/) and renders the resolved
// codepoint through the Material Symbols *web font* (OFL-licensed).
//
// On web the resolution differs from Android in two ways that simplify it:
//   * `materialName` needs NO lookup table — the Material Symbols web font
//     renders a glyph from its *ligature* (the name as text), so the Image
//     builder uses the name directly.
//   * Only `systemName` needs this map (SF name → codepoint + per-symbol axis
//     tuning), so this resolver carries just the SF→Material table.
//
// ## Map format (one row per SF symbol; `#` lines are comments)
//
//   magnifyingglass ef7a
//   heart.fill e87e 1
//   star f09a 200
//
// `<sf_name> <codepoint_hex> [<fill>] [<weight>]`. Trailing integers are axis
// overrides disambiguated by range — `1` ⇒ FILL 1 (SF `.fill` variants),
// 100..700 ⇒ a `wght` the match needs. The hex codepoint is in the Material
// private-use area (begins e/f), so it never collides with a decimal axis token.

export const MATERIAL_WEIGHT_MIN = 100;
export const MATERIAL_WEIGHT_MAX = 700;

// The map lives next to the renderer so it resolves regardless of the host
// page's base URL (import.meta.url is this module's absolute URL).
const SF_MATERIAL_MAP_URL = new URL("../../assets/symbols/sf_to_material.map", import.meta.url);

// One resolved SF→Material row: the glyph codepoint plus axis tuning.
//   { codepoint: number, fill: boolean, weight: number | null }

/**
 * Parses `sf_to_material.map` text into a `Map<name, entry>`. Comment (`#`)
 * lines, blank lines, and rows without a valid `name hex` pair are skipped.
 * Trailing integers are read by range (1 ⇒ fill; 100..700 ⇒ weight); anything
 * else is ignored. Pure — mirror of Kotlin `parseSystemSymbolMap`.
 */
export function parseSystemSymbolMap(text) {
    const map = new Map();
    for (const rawLine of text.split("\n")) {
        const line = rawLine.trim();
        if (line.length === 0 || line.startsWith("#")) continue;
        const tokens = line.split(" ");
        if (tokens.length < 2) continue;
        const name = tokens[0];
        const codepoint = parseInt(tokens[1], 16);
        if (Number.isNaN(codepoint)) continue;

        let fill = false;
        let weight = null;
        for (let i = 2; i < tokens.length; i++) {
            const value = parseInt(tokens[i], 10);
            if (Number.isNaN(value)) continue;
            if (value === 1) fill = true;
            else if (value >= MATERIAL_WEIGHT_MIN && value <= MATERIAL_WEIGHT_MAX) weight = value;
            // Out-of-range / unexpected token: ignore, keep the row usable.
        }
        map.set(name, { codepoint, fill, weight });
    }
    return map;
}

let mapCache = null;     // resolved Map once loaded
let loadPromise = null;  // in-flight load (dedupes concurrent callers)

/**
 * Loads and parses the SF→Material map once, caching it for the page lifetime.
 * Returns a Promise of the `Map<name, entry>`. On fetch failure logs one
 * warning and resolves to an empty map (honest degrade — systemName images then
 * warn-skip, same as a missing font).
 */
export function preloadSymbolMap(logger = null) {
    if (mapCache) return Promise.resolve(mapCache);
    if (loadPromise) return loadPromise;
    loadPromise = fetch(SF_MATERIAL_MAP_URL)
        .then((response) => {
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            return response.text();
        })
        .then((text) => { mapCache = parseSystemSymbolMap(text); return mapCache; })
        .catch((error) => {
            logger?.log(
                `SF→Material map '${SF_MATERIAL_MAP_URL.pathname}' could not be loaded ` +
                `(${error.message}). systemName images cannot resolve to a Material glyph ` +
                `without it (it is a generated artifact — see Tools/material_symbols/). ` +
                `Use 'materialName' for an explicit Material glyph.`,
                "warning",
            );
            mapCache = new Map();
            return mapCache;
        });
    return loadPromise;
}

/**
 * Synchronous lookup against the already-loaded map. Returns the entry, or
 * `undefined` if the name is absent OR the map has not finished loading yet.
 * Callers that need to wait should use `preloadSymbolMap()` and retry.
 */
export function resolveSystemSymbol(name) {
    return mapCache?.get(name);
}
