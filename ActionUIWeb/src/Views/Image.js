// Image.js — Image element.
// Web analog of ActionUI/Views/Image.swift (PoC subset), with the Android
// SF→Material symbol approach (ActionUIAndroid Views/Image.kt).
//
// Sources (mutually exclusive; priority filePath > resourceName > assetName >
// systemName > materialName, matching Image.swift + the web-only materialName):
//   systemName    SF Symbol name → Material glyph via the bundled SF→Material
//                 map, rendered through the Material Symbols web font.
//   materialName  Material Symbol name → rendered directly via the font's
//                 ligature (no lookup table needed on web).
//   assetName / resourceName / filePath  → <img src> (resolved as a URL; an
//                 absolute filePath only loads if reachable as a URL).
// Scaling: contentMode ("fit"/"fill") → object-fit (contain/cover); implies
//   resizable. imageScale ("small"/"medium"/"large") sizes symbol glyphs.
// Axis overrides for symbols: materialFill (0/1 or bool), materialWeight
//   (100..700) — default to the SF→Material map's per-symbol tuning.
// foregroundStyle tints symbols (handled by ModifierResolver). Runtime value
//   (setString) re-renders the source with simple "mixed" heuristics.

import { register } from "../Common/ActionUIRegistry.js";
import { materialNameGlyph, systemSymbolGlyph } from "../Helpers/SymbolIcon.js";

const SOURCE_KEYS = ["filePath", "resourceName", "assetName", "systemName", "materialName"];
const RASTER_KEYS = ["filePath", "resourceName", "assetName"];
const CONTENT_MODES = ["fit", "fill"];
const IMAGE_SCALES = ["small", "medium", "large"];

register("Image", {
    valueType: "string",

    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        for (const key of ["systemName", "materialName", "assetName", "resourceName", "filePath"]) {
            if (validated[key] !== undefined && typeof validated[key] !== "string") {
                logger.log(`Image ${key} must be a String; ignoring`, "warning");
                delete validated[key];
            }
        }

        // contentMode is preferred; scaleMode is a deprecated alias.
        if (validated.contentMode !== undefined) {
            if (typeof validated.contentMode !== "string" || !CONTENT_MODES.includes(validated.contentMode)) {
                logger.log(`Image contentMode '${JSON.stringify(validated.contentMode)}' invalid; ignoring`, "warning");
                delete validated.contentMode;
            }
        }
        if (validated.scaleMode !== undefined) {
            if (typeof validated.scaleMode !== "string" || !CONTENT_MODES.includes(validated.scaleMode)) {
                logger.log(`Image scaleMode '${JSON.stringify(validated.scaleMode)}' invalid; ignoring`, "warning");
                delete validated.scaleMode;
            } else if (validated.contentMode !== undefined) {
                logger.log(`Image: both contentMode and scaleMode set; using contentMode, cleared scaleMode`, "info");
                delete validated.scaleMode;
            } else {
                logger.log(`Image scaleMode is deprecated; use contentMode instead`, "info");
            }
        }

        if (validated.resizable !== undefined && typeof validated.resizable !== "boolean") {
            logger.log(`Image resizable must be a Bool; ignoring`, "warning");
            delete validated.resizable;
        }

        if (validated.imageScale !== undefined) {
            if (typeof validated.imageScale !== "string" || !IMAGE_SCALES.includes(validated.imageScale)) {
                logger.log(`Image imageScale '${JSON.stringify(validated.imageScale)}' invalid; ignoring`, "warning");
                delete validated.imageScale;
            }
        }

        // Enforce mutual exclusivity among source properties, keeping the most
        // specific one (priority order in SOURCE_KEYS).
        const present = SOURCE_KEYS.filter((k) => typeof validated[k] === "string");
        if (present.length > 1) {
            const [winner, ...rest] = present;
            for (const key of rest) delete validated[key];
            logger.log(`Image: multiple source properties set; using '${winner}', cleared ${rest.join(", ")}`, "info");
        } else if (present.length === 0) {
            logger.log(`Image requires one of 'systemName', 'materialName', 'assetName', 'resourceName' or 'filePath'; defaulting to empty image`, "warning");
        }

        return validated;
    },

    buildView: (element, properties, ctx) => {
        const node = document.createElement("span");
        node.className = "aui-image";

        render(node, properties, properties, ctx);

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => node.dataset.auiValue ?? "",
                setValue: (value) => {
                    node.dataset.auiValue = String(value ?? "");
                    // "mixed" heuristic: a path/URL-looking string is a raster
                    // source, otherwise treat it as a symbol name.
                    const override = looksLikePath(node.dataset.auiValue)
                        ? { filePath: node.dataset.auiValue }
                        : { systemName: node.dataset.auiValue };
                    render(node, override, properties, ctx);
                },
            });
        }
        return node;
    },
});

function looksLikePath(value) {
    return /^(https?:|\.{0,2}\/|data:)/.test(value) || /\.(png|jpe?g|gif|webp|svg|bmp|pdf)$/i.test(value);
}

// Renders the chosen source into `node`, replacing prior content. `source`
// holds the active source keys (static props, or a runtime override); `props`
// holds styling knobs (contentMode, imageScale, material axes).
function render(node, source, props, ctx) {
    node.replaceChildren();

    const rasterKey = RASTER_KEYS.find((k) => typeof source[k] === "string");
    if (rasterKey) {
        const img = document.createElement("img");
        img.src = source[rasterKey];
        img.alt = props.accessibilityLabel ?? "";
        const mode = props.contentMode ?? props.scaleMode;
        if (mode) {
            img.style.objectFit = mode === "fill" ? "cover" : "contain";
            img.style.width = "100%";
            img.style.height = "100%";
        }
        node.appendChild(img);
        return;
    }

    if (typeof source.materialName === "string") {
        node.appendChild(materialNameGlyph(source.materialName, props));
        return;
    }

    if (typeof source.systemName === "string") {
        node.appendChild(systemSymbolGlyph(source.systemName, props, ctx.logger, (name) =>
            `Image systemName '${name}' has no SF→Material mapping; nothing rendered. ` +
            `Use 'materialName' for an explicit Material glyph.`));
        return;
    }

    // No source: an empty placeholder (Apple falls back to the "photo" symbol).
    node.classList.add("aui-image-empty");
}
