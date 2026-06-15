// SymbolIcon.js — shared symbol-glyph rendering for ActionUIWeb.
// Web analog of ActionUI/.../Helpers/SymbolIcon.kt (Android).
//
// The convergence point the porting notes called for: `Image` and the
// image-label controls (`Button`, and later `Label` / `NavigationLink` / `Tab`)
// draw an SF Symbol (`systemName` / `systemImage`) or an explicit Material glyph
// (`materialName`) through ONE path instead of each re-deriving icon handling
// (mirroring how Apple resolves images centrally).
//
// Two layers, matching the Android file:
//   * buildSymbolGlyph — the low-level draw: a Material Symbols font <span> with
//     FILL/wght axes, given already-resolved values.
//   * materialNameGlyph / systemSymbolGlyph — resolve a name to a glyph and
//     return the node. systemName/systemImage resolves through the bundled
//     SF→Material map; because the map loads via `fetch`, the glyph renders blank
//     for one frame then fills (and warns-and-skips when a name has no mapping).
//
// selectLabelIcon / labelIcon are the image-label seam (Android's
// `ImageResolver.selectLabelIcon` + `SymbolIcon.LabelIcon`). On web they live
// here rather than a separate `ImageResolver.js`: web has no raster-Painter
// resolver to share (raster sources are a plain <img> built inline in Image.js),
// so the only thing worth converging is the glyph path, which is this file.

import {
    resolveSystemSymbol, preloadSymbolMap,
    MATERIAL_WEIGHT_MIN, MATERIAL_WEIGHT_MAX,
} from "./MaterialSymbolResolver.js";
import { isDebugMode } from "../Common/Debug.js";

// Builds a Material Symbols font span. `content` is the ligature name
// (materialName) or the codepoint character (systemName).
export function buildSymbolGlyph(content, fill, weight, imageScale) {
    const span = document.createElement("span");
    span.className = "aui-symbol" + (imageScale ? ` aui-symbol-${imageScale}` : "");
    span.textContent = content;
    setAxes(span, fill, weight);
    return span;
}

function setAxes(span, fill, weight) {
    span.style.fontVariationSettings =
        `'FILL' ${fill ? 1 : 0}, 'wght' ${weight ?? 400}, 'GRAD' 0, 'opsz' 24`;
}

// material* axis overrides win over the SF→Material map's per-symbol defaults.
export function symbolFill(props, fallback) {
    const v = props.materialFill;
    if (typeof v === "boolean") return v;
    if (typeof v === "number") return v >= 1;
    return fallback;
}

export function symbolWeight(props, fallback) {
    const v = props.materialWeight;
    if (typeof v === "number" && v >= MATERIAL_WEIGHT_MIN && v <= MATERIAL_WEIGHT_MAX) return v;
    return fallback;
}

// materialName → glyph via the font's ligature (no lookup table needed). Always
// returns a node; an unknown name shows the font's notdef (tofu) — web cannot
// detect that without the codepoints table, unlike Android's materialCodepoint.
export function materialNameGlyph(name, props) {
    return buildSymbolGlyph(name, symbolFill(props, false), symbolWeight(props, null), props.imageScale);
}

// systemName/systemImage → mapped codepoint glyph. Returns the (initially blank)
// node immediately and fills it once the SF→Material map is available; when the
// name has no mapping, warns via `noMapping(name)` and (in debug mode) draws a
// visible broken-glyph placeholder rather than leaving it blank.
export function systemSymbolGlyph(name, props, logger, noMapping) {
    const glyph = buildSymbolGlyph("", false, null, props.imageScale); // placeholder until resolved
    const entry = resolveSystemSymbol(name);
    if (entry) {
        applySystemSymbol(glyph, entry, props);
    } else {
        preloadSymbolMap(logger).then((map) => {
            const resolved = map.get(name);
            if (resolved) {
                applySystemSymbol(glyph, resolved, props);
            } else {
                logger.log(noMapping(name), "warning");
                markMissingGlyph(glyph, name);
            }
        });
    }
    return glyph;
}

// In debug mode, turn an unmapped systemName glyph into a visible placeholder:
// the Material `broken_image` ligature, tinted via `.aui-symbol-missing`, with
// the original SF name on hover. Off in production, where a miss stays blank
// (Apple shows nothing for an unknown SF Symbol too) — the warning still logs.
function markMissingGlyph(glyph, name) {
    if (!isDebugMode()) return;
    glyph.classList.add("aui-symbol-missing");
    glyph.textContent = "broken_image";
    glyph.title = `Unmapped SF Symbol: ${name}`;
}

function applySystemSymbol(glyph, entry, props) {
    glyph.textContent = String.fromCodePoint(entry.codepoint);
    setAxes(glyph, symbolFill(props, entry.fill), symbolWeight(props, entry.weight));
}

// Picks the icon an image-label element (Button, later Label) should draw from
// its properties, or null when it carries no icon (title-only — not an error,
// unlike Image's no-source case). Mirrors Image's `materialName` > `systemName`
// priority but reads the SF name from `systemImage` — the Apple Label/Button
// spelling of `systemName`. The asset-catalog source (`assetImage` on Button,
// `imageName` on Label, named via `assetKey`) is the analog of Image's
// `assetName`: still deferred on web, so it warns-and-skips. Mirror of Android's
// selectLabelIcon.
export function selectLabelIcon(properties, assetKey, elementName, logger) {
    if (!properties) return null;
    const materialName = stringOrNull(properties.materialName);
    const systemImage = stringOrNull(properties.systemImage);
    const assetImage = stringOrNull(properties[assetKey]);
    if (materialName !== null) return { kind: "material", name: materialName };
    if (systemImage !== null) return { kind: "system", name: systemImage };
    if (assetImage !== null) {
        logger.log(
            `${elementName} '${assetKey}' ('${assetImage}') maps to an asset-catalog ` +
            `image, which is not supported on web yet (pending a name→URL contract). ` +
            `Use 'systemImage' (SF Symbol) or 'materialName:web' (Material Symbol). ` +
            `No icon rendered.`,
            "warning",
        );
        return null;
    }
    return null;
}

// Draws the leading / standalone icon for an image-label control from an
// already-picked `source` (selectLabelIcon). `props` carries the styling knobs
// (imageScale, material* axes). Returns the glyph node, or null for a
// null/raster source (title-only). Mirror of Android's LabelIcon.
export function labelIcon(source, props, elementName, logger) {
    if (!source) return null;
    if (source.kind === "material") {
        return materialNameGlyph(source.name, props);
    }
    if (source.kind === "system") {
        return systemSymbolGlyph(source.name, props, logger, (name) =>
            `${elementName} systemImage '${name}' has no SF→Material mapping; icon ` +
            `omitted. Use 'materialName:web' for an explicit Material glyph.`);
    }
    return null;
}

function stringOrNull(value) {
    return typeof value === "string" ? value : null;
}
