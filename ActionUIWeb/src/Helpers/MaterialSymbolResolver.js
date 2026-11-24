// MaterialSymbolResolver.js — SF Symbol name → Material glyph resolution.
// Web analog of ActionUI/.../Helpers/SFSymbolResolver.kt (Android).
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
//
// ## Fluent fill-ins
//
// For an SF name the Material map has no row for, `sf_to_fluent.map`
// (`<sf_name> <codepoint_hex>`, a copy of Tools/fluent_symbols/sf_to_fluent.map)
// names a Fluent System Icons glyph, drawn from the "ActionUI Fluent Symbols"
// font (assets/fonts/FluentSymbols.woff2, declared in theme.css). Its code
// points overlap Material's, so each entry names its font. Both files are made
// by scripts/make-symbol-fonts.sh and are not committed; without them only the
// Material rows resolve.

export const MATERIAL_WEIGHT_MIN = 100;
export const MATERIAL_WEIGHT_MAX = 700;

// The maps live next to the renderer so they resolve regardless of the host
// page's base URL (import.meta.url is this module's absolute URL).
const SF_MATERIAL_MAP_URL = new URL("../../assets/symbols/sf_to_material.map", import.meta.url);
const SF_FLUENT_MAP_URL = new URL("../../assets/symbols/sf_to_fluent.map", import.meta.url);

// One resolved SF row: the glyph codepoint, axis tuning, and its font.
//   { codepoint: number, fill: boolean, weight: number | null, font: "material" | "fluent" }

/**
 * Parses `sf_to_material.map` text into a `Map<name, entry>`. Comment (`#`)
 * lines, blank lines, and rows without a valid `name hex` pair are skipped.
 * Trailing integers are read by range (1 ⇒ fill; 100..700 ⇒ weight); anything
 * else is ignored. Pure - mirror of Kotlin `parseSFSymbolMap`.
 */
export function parseSFSymbolMap(text) {
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
        map.set(name, { codepoint, fill, weight, font: "material" });
    }
    return map;
}

/**
 * Adds the rows of `sf_to_fluent.map` text to `map` (in place) for the names
 * it has no row for: the Material rows win. Fluent glyphs have no axes, so a
 * Fluent entry carries no fill or weight. Malformed rows are skipped. Pure -
 * mirror of Kotlin `withFluentRows`. Returns `map`.
 */
export function withFluentRows(map, text) {
    for (const rawLine of text.split("\n")) {
        const line = rawLine.trim();
        if (line.length === 0 || line.startsWith("#")) continue;
        const tokens = line.split(/\s+/);
        if (tokens.length !== 2 || map.has(tokens[0])) continue;
        const codepoint = parseInt(tokens[1], 16);
        if (Number.isNaN(codepoint)) continue;
        map.set(tokens[0], { codepoint, fill: false, weight: null, font: "fluent" });
    }
    return map;
}

let mapCache = null;     // resolved Map once loaded
let loadPromise = null;  // in-flight load (dedupes concurrent callers)

function fetchText(url) {
    return fetch(url).then((response) => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        return response.text();
    });
}

/**
 * Loads and parses the SF->Material map and the Fluent fill-in map once,
 * caching the merged map for the page lifetime. Returns a Promise of the
 * `Map<name, entry>`. Each map that cannot be loaded logs one warning: without
 * the Material map the result has the Fluent rows only (the other systemName
 * images then warn-skip, as with a missing font); without the Fluent map it has
 * the Material rows only.
 */
export function preloadSymbolMap(logger = null) {
    if (mapCache) return Promise.resolve(mapCache);
    if (loadPromise) return loadPromise;
    const material = fetchText(SF_MATERIAL_MAP_URL)
        .then(parseSFSymbolMap)
        .catch((error) => {
            logger?.log(
                `SF→Material map '${SF_MATERIAL_MAP_URL.pathname}' could not be loaded ` +
                `(${error.message}). systemName images cannot resolve to a Material glyph ` +
                `without it (it is a generated artifact — see Tools/material_symbols/). ` +
                `Use 'materialName' for an explicit Material glyph.`,
                "warning",
            );
            return new Map();
        });
    const fluent = fetchText(SF_FLUENT_MAP_URL).catch((error) => {
        logger?.log(
            `SF->Fluent map '${SF_FLUENT_MAP_URL.pathname}' could not be loaded ` +
            `(${error.message}). The SF Symbols that Material Symbols has no glyph for ` +
            `will not be drawn; run scripts/make-symbol-fonts.sh to make the Fluent ` +
            `System Icons font and map.`,
            "warning",
        );
        return "";
    });
    loadPromise = Promise.all([material, fluent]).then(([map, fluentText]) => {
        mapCache = withFluentRows(map, fluentText);
        return mapCache;
    });
    return loadPromise;
}

/**
 * Synchronous lookup against the already-loaded map. Returns the entry, or
 * `undefined` if the name is absent OR the map has not finished loading yet.
 * Callers that need to wait should use `preloadSymbolMap()` and retry.
 */
export function resolveSFSymbol(name) {
    return mapCache?.get(name);
}
