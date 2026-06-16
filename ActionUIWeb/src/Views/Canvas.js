// Canvas.js — Canvas element.
// Web analog of ActionUI/Views/Canvas.swift (and ActionUIAndroid Views/Canvas.kt).
//
// An immediate-mode drawing surface: the element carries a JSON `operations`
// display list that Helpers/CanvasRenderer.js interprets onto a native <canvas>
// 2D context (the web's CanvasRenderer counterpart). One authored drawing renders
// on SwiftUI, Compose, and the web - the schema is the shared subset of Core
// Graphics, Skia, and Canvas 2D (see Documentation/Schemas/Canvas.md).
//
// Web specifics:
//   * The backing store is sized to the element's CSS box times devicePixelRatio
//     and re-rendered on resize (ResizeObserver), so the drawing stays crisp and
//     responsive without a JS layout loop.
//   * Async resources trigger a redraw when they become available: the
//     SF->Material symbol map (systemName glyphs), the Material Symbols web font
//     (any glyph), and raster images (resourceName/filePath -> a URL <img>). Until
//     then the affected op draws nothing (no layout shift), matching the
//     "blank for one frame then fills" stance of the Image element.
//   * `coordinateMode` ("normalized" default | "points"), `backgroundColor`, and
//     `actionID` (a tap fires it, viewID = element id) match Apple. valueType is
//     none (no value/state bridge).

import { register } from "../Common/ActionUIRegistry.js";
import { drawCanvasOperations, parseCanvasOperations } from "../Helpers/CanvasRenderer.js";
import { resolveSystemSymbol, preloadSymbolMap } from "../Helpers/MaterialSymbolResolver.js";

const VALID_COORDINATE_MODES = ["normalized", "points"];
const MATERIAL_FONT_SPEC = '24px "Material Symbols Rounded"';

register("Canvas", {
    valueType: "none",

    // Mirrors Canvas.swift validateProperties: coordinateMode + backgroundColor are
    // type/enum checked; operations are validated per-op at parse time in buildView
    // (parseCanvasOperations, which drops malformed ops with a warning).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.operations !== undefined && !Array.isArray(validated.operations)) {
            logger.log("Invalid operations type", "warning");
            delete validated.operations;
        }
        if (validated.backgroundColor !== undefined && typeof validated.backgroundColor !== "string") {
            delete validated.backgroundColor;
        }
        if (validated.coordinateMode !== undefined
            && !(typeof validated.coordinateMode === "string" && VALID_COORDINATE_MODES.includes(validated.coordinateMode))) {
            logger.log(`Invalid coordinateMode value: ${validated.coordinateMode}, defaulting to normalized`, "warning");
            delete validated.coordinateMode;
        }
        return validated;
    },

    buildView: (element, properties, ctx) => {
        const canvas = document.createElement("canvas");
        canvas.className = "aui-canvas";

        const ops = parseCanvasOperations(properties.operations, ctx.logger);
        const pointsMode = properties.coordinateMode === "points";
        const background = typeof properties.backgroundColor === "string" ? properties.backgroundColor : null;

        // Async resource state, shared across redraws. `warned` dedupes per-source
        // glyph warnings; `images` caches raster loads.
        const warned = new Set();
        const images = new Map(); // url -> { img, status: "loading"|"ready"|"failed" }
        let fontReady = false;
        let destroyed = false;

        const scheduleRedraw = () => {
            if (destroyed) return;
            requestAnimationFrame(redraw);
        };

        // The raster-image loader: returns a ready <img>, or null while loading /
        // on failure (the op draws nothing until the load redraw). Mirrors the
        // Image element's plain-<img> handling; cross-origin images draw fine
        // (the canvas taints, but we never read it back).
        const image = (rawURL) => {
            let url;
            try { url = new URL(rawURL, document.baseURI).href; } catch { url = rawURL; }
            const cached = images.get(url);
            if (cached) return cached.status === "ready" ? cached.img : null;
            const img = new Image();
            const record = { img, status: "loading" };
            images.set(url, record);
            img.onload = () => { record.status = "ready"; scheduleRedraw(); };
            img.onerror = () => {
                record.status = "failed";
                if (!warned.has(url)) {
                    warned.add(url);
                    ctx.logger.log(`Canvas image failed to load: ${url}. Nothing rendered.`, "warning");
                }
            };
            img.src = url;
            return null;
        };

        const env = {
            logger: ctx.logger,
            get glyphColor() { return getComputedStyle(canvas).color || "#000000"; },
            resolveSymbol: resolveSystemSymbol,
            image,
            get fontReady() { return fontReady; },
            warned,
        };

        const redraw = () => {
            if (destroyed) return;
            const cssW = canvas.clientWidth || parseFloat(getComputedStyle(canvas).width) || 0;
            const cssH = canvas.clientHeight || parseFloat(getComputedStyle(canvas).height) || 0;
            if (cssW <= 0 || cssH <= 0) return; // not laid out yet; ResizeObserver redraws
            const dpr = window.devicePixelRatio || 1;
            const pxW = Math.round(cssW * dpr);
            const pxH = Math.round(cssH * dpr);
            if (canvas.width !== pxW) canvas.width = pxW;
            if (canvas.height !== pxH) canvas.height = pxH;

            const c2d = canvas.getContext("2d");
            c2d.setTransform(dpr, 0, 0, dpr, 0, 0); // author in CSS px; crisp on HiDPI
            c2d.clearRect(0, 0, cssW, cssH);
            if (background && background !== "transparent" && background !== "clear") {
                c2d.fillStyle = background;
                c2d.fillRect(0, 0, cssW, cssH);
            }
            drawCanvasOperations(c2d, ops, { width: cssW, height: cssH }, pointsMode, env);
        };

        // Load the async resources the ops need, then redraw. Only systemName
        // glyphs need the SF->Material map; any glyph needs the Material font.
        if (opsNeedSymbolMap(ops)) preloadSymbolMap(ctx.logger).then(scheduleRedraw);
        if (opsNeedFont(ops)) {
            if (document.fonts && document.fonts.load) {
                document.fonts.load(MATERIAL_FONT_SPEC).then(() => { fontReady = true; scheduleRedraw(); }).catch(() => {});
            } else {
                fontReady = true; // no Font Loading API; assume the @font-face is present
            }
        }

        // Re-render on size changes (the frame modifier sizes the box). The first
        // observation fires after layout, which is also the initial draw.
        const observer = new ResizeObserver(() => redraw());
        observer.observe(canvas);

        if (typeof properties.actionID === "string") {
            canvas.addEventListener("click", () => ctx.model.dispatchAction(properties.actionID, element.id, 0, null));
        }

        // Best-effort cleanup if the element is removed (the model has no destroy
        // hook yet; the observer is GC'd with the node, this just stops redraws).
        canvas._auiDestroy = () => { destroyed = true; observer.disconnect(); };
        return canvas;
    },
});

// Whether any op (recursing into layers) draws a systemName glyph (needs the map).
function opsNeedSymbolMap(ops) {
    return ops.some((op) =>
        (op.type === "image" && op.source.kind === "system")
        || (op.type === "layer" && opsNeedSymbolMap(op.operations)));
}

// Whether any op (recursing into layers) draws a glyph (needs the Material font).
function opsNeedFont(ops) {
    return ops.some((op) =>
        (op.type === "image" && (op.source.kind === "system" || op.source.kind === "material"))
        || (op.type === "layer" && opsNeedFont(op.operations)));
}
