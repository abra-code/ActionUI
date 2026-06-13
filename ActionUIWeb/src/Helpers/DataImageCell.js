// DataImageCell.js — builds an image cell for the data-driven collections.
// Shared by Table (column cells) and List (homogeneous itemType cells) so both
// render an image from a raw row-data string identically.
//
// Reuses the shared glyph helper for SF Symbols and a plain <img> for raster
// paths. asset/resource catalog sources warn-and-skip on web (no name→URL
// contract yet), as in Image.js / SymbolIcon.js. "mixed" sniffs a path-looking
// string, falling back to a symbol name.

import { systemSymbolGlyph } from "./SymbolIcon.js";

// Builds the image node for `value` under `interpretation`
// ("path"|"systemName"|"assetName"|"resourceName"|"mixed"). `owner` ("Table" /
// "List") names the element in the asset-catalog / no-mapping warnings.
export function buildDataImageCell(value, interpretation, logger, owner) {
    const resolved = interpretation === "mixed"
        ? (looksLikePath(value) ? "path" : "systemName")
        : interpretation;

    if (resolved === "systemName") {
        return systemSymbolGlyph(value, {}, logger, (name) =>
            `${owner} image cell systemName '${name}' has no SF→Material mapping; icon omitted. ` +
            `Use 'materialName:web' for an explicit Material glyph.`);
    }
    if (resolved === "path") {
        const img = document.createElement("img");
        img.className = "aui-data-image";
        img.src = value;
        img.alt = "";
        return img;
    }
    // assetName / resourceName: asset-catalog images aren't supported on web yet.
    logger.log(
        `${owner} image cell '${value}' uses '${resolved}', an asset-catalog source not ` +
        `supported on web yet (pending a name→URL contract). No image rendered.`,
        "warning",
    );
    const empty = document.createElement("span");
    empty.className = "aui-image aui-image-empty";
    return empty;
}

export function looksLikePath(value) {
    return /^(https?:|\.{0,2}\/|data:)/.test(value) || /\.(png|jpe?g|gif|webp|svg|bmp|pdf)$/i.test(value);
}
