// CanvasRenderer.js — the Canvas draw-command interpreter.
// Web analog of ActionUI/Helpers/CanvasRenderer.swift and ActionUIAndroid
// Helpers/CanvasRenderer.kt. The `Canvas` element (Views/Canvas.js) carries a JSON
// display list (`operations`); this file turns it into HTML Canvas 2D drawing. The
// shared schema (Documentation/Schemas/Canvas.md) is platform-neutral - paths,
// fill/stroke, transforms, clips, layers map onto the common subset of Core
// Graphics, Skia, and Canvas 2D - so one authored drawing renders on all three.
//
// Two halves, like the Android port:
//   1. Parse (pure). `parseCanvasOperations` resolves the JSON into typed ops,
//      mirroring Apple's `Canvas.validateProperties` (which drops malformed ops)
//      plus the per-op guards inside the Swift renderer. Pure - the whole
//      vocabulary is unit-testable without a DOM.
//   2. Draw. `drawCanvasOperations` walks the typed list against a
//      CanvasRenderingContext2D.
//
// ## Units (matches the Swift/Android implementations, not the schema comments)
//
// Path/frame/gradient coordinates are normalized (0..1 of the canvas) unless
// `coordinateMode` is "points". Everything else - lineWidth, dash, fontSize,
// translate x/y, shadow radius/offsets, blur radius - is in raw points regardless
// of mode, because that is what the Swift renderer does (it passes them unscaled
// into the stroke style / font / filters; the demo JSON is authored that way,
// e.g. "lineWidth": 4). Points map to CSS px here (pt == px). Gradient geometry is
// always normalized, even in points mode - again matching Swift/Android.
//
// ## Divergences from Apple (documented, all small)
//   * Layer opacity/blend are applied per drawn element (alpha multiplied down,
//     blend replaced), not via a true transparency layer - Canvas 2D has no cheap
//     saveLayer. Heavily overlapping elements inside a translucent layer can differ
//     slightly. (Android made the same per-draw approximation.)
//   * Shadow ignores the optional `blendMode` / `drawAbove` knobs (Canvas shadows
//     composite normally, below content) - same as Android.
//   * `text.alignment` is accepted but not applied - same as Apple/Android, which
//     log it as unsupported. Text is centered in its frame (Apple's
//     `context.draw(text, in:)` centering); only explicit `\n` breaks lines (no
//     automatic word wrap).
//   * Variable-font axes (FILL / wght) cannot be set on a Canvas 2D font, so
//     `systemName` glyphs render at the font's default instance.

// SwiftUI semantic color names -> concrete hex for the canvas (it cannot read the
// theme.css CSS variables the DOM uses). #hex (3/6/8) and CSS color names pass
// through untouched; only these named tokens need a table. Light-mode values.
const NAMED_COLORS = {
    primary: "#000000", secondary: "rgba(60,60,67,0.6)", accentColor: "#007aff",
    red: "#ff3b30", orange: "#ff9500", yellow: "#ffcc00", green: "#34c759",
    mint: "#00c7be", teal: "#30b0c7", cyan: "#32ade6", blue: "#007aff",
    indigo: "#5856d6", purple: "#af52de", pink: "#ff2d55", brown: "#a2845e",
    gray: "#8e8e93", white: "#ffffff", black: "#000000", clear: "transparent",
};

// Resolves a color string to something the canvas accepts, or null (skip, like
// Apple's resolveColor returning nil). Mirrors ColorHelper.resolveColor's intent.
export function resolveCanvasColor(value) {
    if (typeof value !== "string") return null;
    if (/^#[0-9a-fA-F]{3,8}$/.test(value)) return value;        // hex (Canvas takes #RRGGBBAA)
    const named = NAMED_COLORS[value];
    if (named) return named;
    return value; // a CSS color name (red, etc.); an invalid one is a no-op on assign
}

// ============================== Parsing ==============================

function numberOr(value, fallback) {
    return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function numberArray(value, length) {
    if (!Array.isArray(value) || value.length !== length) return null;
    if (!value.every((n) => typeof n === "number" && Number.isFinite(n))) return null;
    return value;
}

// Parses the element's `operations` JSON into typed ops, dropping (with a warning)
// anything malformed. Mirrors Apple's validateOperations + the Swift renderer's
// per-op guards; like Apple, a single non-object item invalidates the whole array.
export function parseCanvasOperations(opsJson, logger) {
    return parseOps(opsJson, logger);
}

function parseOps(value, logger) {
    if (value == null) return [];
    if (!Array.isArray(value) || value.some((op) => typeof op !== "object" || op === null || Array.isArray(op))) {
        logger?.log("Canvas operations must be an array of operation objects; ignoring.", "warning");
        return [];
    }
    const out = [];
    for (const op of value) {
        const parsed = parseOp(op, logger);
        if (parsed) out.push(parsed);
    }
    return out;
}

function parseOp(op, logger) {
    const type = typeof op.type === "string" ? op.type.toLowerCase() : null;
    if (!type) {
        logger?.log("Canvas operation without a 'type' string skipped.", "warning");
        return null;
    }
    switch (type) {
        case "fill": return parseFill(op, logger);
        case "stroke": return parseStroke(op, logger);
        case "text": return parseText(op, logger);
        case "image": return parseImage(op, logger);
        case "clip": {
            const path = parsePathSpec(op.path, logger);
            return path ? { type: "clip", path } : null;
        }
        case "translate": return { type: "translate", x: numberOr(op.x, 0), y: numberOr(op.y, 0) };
        case "scale": return { type: "scale", x: numberOr(op.x, 1), y: numberOr(op.y, 1) };
        case "rotate": {
            const angle = numberOr(op.angle, null);
            return angle === null ? null : { type: "rotate", angle };
        }
        case "shadow": return {
            type: "shadow",
            color: resolveCanvasColor(op.color) ?? "#000000",
            radius: numberOr(op.radius, 0.005),
            x: numberOr(op.x, 0.002),
            y: numberOr(op.y, 0.004),
        };
        case "blur": {
            const radius = numberOr(op.radius, null);
            if (radius === null) {
                logger?.log("Canvas blur missing valid 'radius' (expected number); skipped.", "warning");
                return null;
            }
            if (radius <= 0) logger?.log(`Canvas blur radius should be > 0, got ${radius}`, "warning");
            return { type: "blur", radius };
        }
        case "layer": return parseLayer(op, logger);
        default:
            logger?.log(`Unknown Canvas operation type: ${type}`, "warning");
            return null;
    }
}

function parseFill(op, logger) {
    const path = parsePathSpec(op.path, logger);
    if (!path) return null;
    // Gradient wins; an invalid gradient falls through to the color (Swift branch order).
    const gradient = (typeof op.gradient === "object" && op.gradient !== null)
        ? parseGradient(op.gradient, logger) : null;
    if (gradient) return { type: "fill", path, color: null, gradient };
    const color = resolveCanvasColor(op.color);
    if (!color) {
        logger?.log("No valid color or gradient for Canvas fill; skipped.", "warning");
        return null;
    }
    return { type: "fill", path, color, gradient: null };
}

function parseStroke(op, logger) {
    const path = parsePathSpec(op.path, logger);
    if (!path) return null;
    const color = resolveCanvasColor(op.color);
    if (!color) {
        logger?.log("Missing/invalid color for Canvas stroke; skipped.", "warning");
        return null;
    }
    const dash = Array.isArray(op.dash) && op.dash.every((n) => typeof n === "number") ? op.dash : [];
    return {
        type: "stroke", path, color,
        lineWidth: numberOr(op.lineWidth, 1),
        lineCap: lineCapFromString(op.lineCap),
        lineJoin: lineJoinFromString(op.lineJoin),
        miterLimit: numberOr(op.miterLimit, 10),
        dash,
        dashPhase: numberOr(op.dashPhase, 0),
    };
}

function parseText(op, logger) {
    const text = typeof op.text === "string" ? op.text : null;
    const frame = numberArray(op.frame, 4);
    if (text === null || !frame) {
        logger?.log("Canvas text needs 'text' and a 4-number 'frame'; skipped.", "warning");
        return null;
    }
    if (op.alignment != null) {
        // Same status as Apple/Android: alignment is logged as unsupported.
        logger?.log("Text alignment currently not supported in Canvas - default alignment used", "info");
    }
    return {
        type: "text", text, frame,
        fontSize: numberOr(op.fontSize, null),
        fontWeight: fontWeightFromString(op.fontWeight),
        color: resolveCanvasColor(op.color) ?? "#000000",
    };
}

function parseImage(op, logger) {
    const frame = numberArray(op.frame, 4);
    // The web-only `materialName:web` glyph wins over any shared source (the Image
    // element's priority; PlatformFilter recurses into the operations array).
    if (typeof op.materialName === "string") {
        if (!frame) {
            logger?.log("Canvas image needs a 4-number 'frame'; skipped.", "warning");
            return null;
        }
        return { type: "image", source: { kind: "material", name: op.materialName }, frame, opacity: numberOr(op.opacity, 1) };
    }
    const sources = ["systemName", "assetName", "resourceName", "filePath"].filter((k) => op[k] != null);
    if (!frame || sources.length !== 1) {
        logger?.log(
            "Canvas image needs a 4-number 'frame' and exactly one source " +
            "(systemName/assetName/resourceName/filePath); skipped.",
            "warning",
        );
        return null;
    }
    const key = sources[0];
    let source = null;
    if (key === "systemName" && typeof op.systemName === "string") source = { kind: "system", name: op.systemName };
    else if (key === "resourceName" && typeof op.resourceName === "string") source = { kind: "url", url: op.resourceName };
    else if (key === "filePath" && typeof op.filePath === "string") source = { kind: "url", url: op.filePath };
    else if (key === "assetName") {
        // Deferred like the Image element's assetName (needs a name->URL contract).
        logger?.log(
            "Canvas image 'assetName' maps to an asset-catalog image, not supported on web yet. " +
            "Use 'resourceName'/'filePath' (a URL), 'systemName', or 'materialName:web'. Skipped.",
            "warning",
        );
        return null;
    }
    if (!source) return null;
    return { type: "image", source, frame, opacity: numberOr(op.opacity, 1) };
}

function parseLayer(op, logger) {
    const frame = numberArray(op.frame, 4);
    if (!frame) {
        logger?.log("Canvas layer needs a 4-number 'frame'; skipped.", "warning");
        return null;
    }
    return {
        type: "layer", frame,
        opacity: numberOr(op.opacity, 1),
        blendMode: blendModeFromString(op.blendMode),
        operations: parseOps(op.operations, logger),
    };
}

// Parses a `"path"` shape dictionary, warning with Apple's reasons on failure.
export function parsePathSpec(spec, logger) {
    const type = (spec && typeof spec === "object" && typeof spec.type === "string") ? spec.type.toLowerCase() : null;
    if (!type) {
        logger?.log("Missing or invalid Canvas path type", "warning");
        return null;
    }
    switch (type) {
        case "circle": {
            const center = numberArray(spec.center, 2);
            const radius = numberOr(spec.radius, null);
            if (!center || radius === null) {
                logger?.log("Invalid circle: missing center or radius", "warning");
                return null;
            }
            return { shape: "circle", cx: center[0], cy: center[1], radius };
        }
        case "ellipse": {
            const frame = numberArray(spec.frame, 4);
            if (!frame) { logger?.log("Invalid ellipse: frame must be [x,y,w,h]", "warning"); return null; }
            return { shape: "ellipse", frame };
        }
        case "rect": {
            const frame = xywh(spec);
            if (!frame) { logger?.log("Invalid rect: missing x/y/width/height", "warning"); return null; }
            return { shape: "rect", frame };
        }
        case "roundedrect": {
            const frame = xywh(spec);
            if (!frame) { logger?.log("Invalid roundedRect: missing x/y/width/height", "warning"); return null; }
            // Like Apple: a single cornerRadius, or the first of cornerRadii.
            const radii = numberArray(spec.cornerRadii, 4);
            const corner = numberOr(spec.cornerRadius, radii ? radii[0] : 0);
            return { shape: "roundedRect", frame, corner };
        }
        case "path": {
            const commandsJson = spec.commands;
            if (!Array.isArray(commandsJson) || commandsJson.some((c) => !Array.isArray(c))) {
                logger?.log("Custom Canvas path missing 'commands' array", "warning");
                return null;
            }
            const commands = [];
            for (const c of commandsJson) {
                const cmd = parsePathCommand(c, logger);
                if (cmd) commands.push(cmd);
            }
            return commands.length ? { shape: "commands", commands } : null; // empty path == nil on Apple
        }
        default:
            logger?.log(`Unsupported Canvas path type: ${type}`, "warning");
            return null;
    }
}

function parsePathCommand(command, logger) {
    const name = typeof command[0] === "string" ? command[0].toLowerCase() : null;
    if (!name) return null;
    // Like Apple's numbers(from:): a non-numeric argument warns and reads as 0.
    const args = command.slice(1).map((a) => {
        if (typeof a === "number" && Number.isFinite(a)) return a;
        logger?.log(`Invalid number in Canvas path command: ${a}`, "warning");
        return 0;
    });
    switch (name) {
        case "moveto": return args.length >= 2 ? { c: "moveTo", a: args } : null;
        case "lineto": return args.length >= 2 ? { c: "lineTo", a: args } : null;
        case "quadraticcurveto": case "quadcurveto": return args.length >= 4 ? { c: "quad", a: args } : null;
        case "curveto": case "cubiccurveto": return args.length >= 6 ? { c: "cubic", a: args } : null;
        case "arc": return args.length >= 6 ? { c: "arc", a: args } : null;
        case "closepath": case "close": return { c: "close", a: [] };
        default:
            logger?.log(`Unknown Canvas path command: ${name}`, "warning");
            return null;
    }
}

// Mirrors the Swift makeShading: at least two color *strings*, unresolvable ones
// dropped, optional `locations` ignored (Apple distributes colors evenly).
function parseGradient(spec, logger) {
    const type = typeof spec.type === "string" ? spec.type.toLowerCase() : null;
    const rawColors = Array.isArray(spec.colors) ? spec.colors : null;
    // Apple's `colors as? [String]`: any non-string item invalidates the list.
    if (!type || !rawColors || rawColors.some((c) => typeof c !== "string") || rawColors.length < 2) {
        logger?.log("Invalid Canvas gradient: missing type or colors", "warning");
        return null;
    }
    const colors = rawColors.map(resolveCanvasColor).filter((c) => c !== null);
    if (colors.length === 0) return null;
    if (type === "linear") {
        const start = numberArray(spec.start, 2);
        const end = numberArray(spec.end, 2);
        if (!start || !end) return null;
        return { kind: "linear", start, end, colors };
    }
    if (type === "radial") {
        const center = numberArray(spec.center, 2);
        const endRadius = numberOr(spec.endRadius, null);
        if (!center || endRadius === null) return null;
        return { kind: "radial", center, startRadius: numberOr(spec.startRadius, 0), endRadius, colors };
    }
    logger?.log(`Unsupported Canvas gradient type: ${type}`, "warning");
    return null;
}

function xywh(spec) {
    const x = numberOr(spec.x, null), y = numberOr(spec.y, null);
    const w = numberOr(spec.width, null), h = numberOr(spec.height, null);
    if (x === null || y === null || w === null || h === null) return null;
    return [x, y, w, h];
}

function lineCapFromString(name) {
    switch (typeof name === "string" ? name.toLowerCase() : "") {
        case "round": return "round";
        case "square": return "square";
        default: return "butt";
    }
}

function lineJoinFromString(name) {
    switch (typeof name === "string" ? name.toLowerCase() : "") {
        case "round": return "round";
        case "bevel": return "bevel";
        default: return "miter";
    }
}

// The blend vocabulary the Swift renderer resolves, mapped to Canvas 2D
// globalCompositeOperation; anything else is normal ("source-over").
function blendModeFromString(name) {
    switch (typeof name === "string" ? name.toLowerCase() : "") {
        case "multiply": return "multiply";
        case "screen": return "screen";
        case "overlay": return "overlay";
        default: return "source-over";
    }
}

// SwiftUI's nine weight names by lightness rank -> CSS numeric weight; unknown is
// null (the font's default weight), like Apple leaving the font weight unset.
function fontWeightFromString(name) {
    switch (typeof name === "string" ? name.toLowerCase() : "") {
        case "ultralight": return 100;
        case "thin": return 200;
        case "light": return 300;
        case "regular": return 400;
        case "medium": return 500;
        case "semibold": return 600;
        case "bold": return 700;
        case "heavy": return 800;
        case "black": return 900;
        default: return null;
    }
}

// ============================== Drawing ==============================

const DEG = Math.PI / 180;
const DEFAULT_FONT_SIZE = 17; // px, when a text op omits fontSize (Apple uses the platform default)
const MATERIAL_FONT = '"Material Symbols Rounded"';

// Walks the typed operations against `ctx`. `size` = {width, height} is the
// normalization space (the element size, or a layer frame inside a layer);
// `pointsMode` switches coordinates to raw px. `env` carries the async/host hooks
// (see Views/Canvas.js): { logger, glyphColor, resolveSymbol, image, fontReady,
// warned }. `state` threads the inherited filter + layer state into nested layers.
export function drawCanvasOperations(ctx, ops, size, pointsMode, env, state = {}) {
    const { shadow = null, blur = null, layerAlpha = 1, layerBlend = "source-over" } = state;
    let activeShadow = shadow;
    let activeBlur = blur;

    const sx = (v) => (pointsMode ? v : v * size.width);
    const sy = (v) => (pointsMode ? v : v * size.height);
    const rect = (f) => ({ x: sx(f[0]), y: sy(f[1]), w: sx(f[2]), h: sy(f[3]) });

    // Applies the per-draw style (layer alpha/blend + active shadow/blur) inside a
    // save/restore so it never leaks, while transforms/clips accumulate on ctx.
    const withDrawState = (extraAlpha, fn) => {
        ctx.save();
        ctx.globalAlpha = layerAlpha * extraAlpha;
        ctx.globalCompositeOperation = layerBlend;
        if (activeShadow) {
            ctx.shadowColor = activeShadow.color;
            ctx.shadowBlur = activeShadow.radius;
            ctx.shadowOffsetX = activeShadow.x;
            ctx.shadowOffsetY = activeShadow.y;
        }
        if (activeBlur != null && activeBlur > 0) ctx.filter = `blur(${activeBlur}px)`;
        fn();
        ctx.restore();
    };

    for (const op of ops) {
        switch (op.type) {
            case "fill": {
                const path = buildPath(op.path, size, pointsMode);
                withDrawState(1, () => {
                    ctx.fillStyle = op.gradient ? makeGradient(ctx, op.gradient, size) : op.color;
                    ctx.fill(path);
                });
                break;
            }
            case "stroke": {
                const path = buildPath(op.path, size, pointsMode);
                withDrawState(1, () => {
                    ctx.strokeStyle = op.color;
                    ctx.lineWidth = op.lineWidth;
                    ctx.lineCap = op.lineCap;
                    ctx.lineJoin = op.lineJoin;
                    ctx.miterLimit = op.miterLimit;
                    ctx.setLineDash(op.dash);
                    ctx.lineDashOffset = op.dashPhase;
                    ctx.stroke(path);
                });
                break;
            }
            case "text":
                withDrawState(1, () => drawText(ctx, op, rect(op.frame)));
                break;
            case "image":
                drawImage(ctx, op, rect(op.frame), env, (alpha, fn) => withDrawState(alpha, fn));
                break;
            case "clip":
                ctx.clip(buildPath(op.path, size, pointsMode));
                break;
            // translate x/y are raw points regardless of coordMode (the Swift
            // renderer passes them unscaled; pt == px on web).
            case "translate": ctx.translate(op.x, op.y); break;
            case "scale": ctx.scale(op.x, op.y); break;
            case "rotate": ctx.rotate(op.angle * DEG); break;
            case "shadow": activeShadow = op; break;
            case "blur": activeBlur = op.radius; break;
            case "layer": {
                const r = rect(op.frame);
                ctx.save();
                ctx.translate(r.x, r.y);
                drawCanvasOperations(ctx, op.operations, { width: r.w, height: r.h }, pointsMode, env, {
                    shadow: activeShadow,
                    blur: activeBlur,
                    layerAlpha: layerAlpha * op.opacity, // approximate nested transparency layers
                    layerBlend: op.blendMode,
                });
                ctx.restore();
                break;
            }
            default: break;
        }
    }
}

function drawText(ctx, op, frame) {
    const size = op.fontSize ?? DEFAULT_FONT_SIZE;
    const weight = op.fontWeight ?? "";
    ctx.font = `${weight} ${size}px -apple-system, system-ui, sans-serif`.trim();
    ctx.fillStyle = op.color;
    ctx.textAlign = "center";       // Apple centers text in its frame (alignment key ignored)
    ctx.textBaseline = "middle";
    const lines = op.text.split("\n");
    const lineHeight = size * 1.2;
    const cx = frame.x + frame.w / 2;
    const cy = frame.y + frame.h / 2;
    const startY = cy - (lines.length - 1) * lineHeight / 2;
    lines.forEach((line, i) => ctx.fillText(line, cx, startY + i * lineHeight));
}

// Draws an image op: raster sources stretch into the frame (Apple's
// context.draw(img, in:); resizingMode is accepted-but-ignored there too), a
// systemName/materialName draws the mapped Material glyph centered in the frame,
// sized to its height. Async resources draw nothing until ready (env schedules a
// redraw when the symbol map / font / raster loads).
function drawImage(ctx, op, frame, env, withDrawState) {
    if (op.source.kind === "url") {
        const img = env.image(op.source.url);
        if (!img) return; // loading, failed, or absent - drawn on the redraw after load
        withDrawState(op.opacity, () => ctx.drawImage(img, frame.x, frame.y, Math.max(1, frame.w), Math.max(1, frame.h)));
        return;
    }
    // Glyph (systemName mapped codepoint, or materialName ligature).
    if (!env.fontReady) return; // redraw fires when the Material Symbols font loads
    let glyph = null;
    if (op.source.kind === "system") {
        const entry = env.resolveSymbol(op.source.name);
        if (entry) glyph = String.fromCodePoint(entry.codepoint);
    } else if (op.source.kind === "material") {
        glyph = op.source.name; // the font renders the ligature
    }
    if (glyph === null) {
        const id = `${op.source.kind}:${op.source.name}`;
        if (env.warned && !env.warned.has(id)) {
            env.warned.add(id);
            env.logger?.log(`Canvas image glyph '${op.source.name}' has no Material mapping (or the map is still loading). Nothing rendered.`, "warning");
        }
        return;
    }
    const fontSize = frame.h;
    withDrawState(op.opacity, () => {
        ctx.font = `${fontSize}px ${MATERIAL_FONT}`;
        ctx.fillStyle = env.glyphColor;
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillText(glyph, frame.x + frame.w / 2, frame.y + frame.h / 2);
    });
}

function makeGradient(ctx, gradient, size) {
    // Gradient geometry is always normalized, even in points mode (Apple parity).
    let g;
    if (gradient.kind === "linear") {
        g = ctx.createLinearGradient(
            gradient.start[0] * size.width, gradient.start[1] * size.height,
            gradient.end[0] * size.width, gradient.end[1] * size.height,
        );
    } else {
        const cx = gradient.center[0] * size.width;
        const cy = gradient.center[1] * size.height;
        const minDim = Math.min(size.width, size.height);
        g = ctx.createRadialGradient(
            cx, cy, Math.max(0, gradient.startRadius * minDim),
            cx, cy, Math.max(0.01, gradient.endRadius * minDim),
        );
    }
    // Distribute colors evenly (locations ignored, like Apple/Android).
    const n = gradient.colors.length;
    gradient.colors.forEach((c, i) => g.addColorStop(n === 1 ? 0 : i / (n - 1), c));
    return g;
}

// Builds a Path2D for a shape spec in the current coordinate space.
function buildPath(spec, size, pointsMode) {
    const sx = (v) => (pointsMode ? v : v * size.width);
    const sy = (v) => (pointsMode ? v : v * size.height);
    const smin = (v) => (pointsMode ? v : v * Math.min(size.width, size.height));
    const path = new Path2D();
    switch (spec.shape) {
        case "circle": {
            const r = smin(spec.radius);
            path.arc(sx(spec.cx), sy(spec.cy), Math.max(0, r), 0, Math.PI * 2);
            break;
        }
        case "ellipse": {
            const f = spec.frame;
            const w = sx(f[2]), h = sy(f[3]);
            path.ellipse(sx(f[0]) + w / 2, sy(f[1]) + h / 2, Math.abs(w / 2), Math.abs(h / 2), 0, 0, Math.PI * 2);
            break;
        }
        case "rect": {
            const f = spec.frame;
            path.rect(sx(f[0]), sy(f[1]), sx(f[2]), sy(f[3]));
            break;
        }
        case "roundedRect": {
            const f = spec.frame;
            path.roundRect(sx(f[0]), sy(f[1]), sx(f[2]), sy(f[3]), Math.max(0, smin(spec.corner)));
            break;
        }
        case "commands":
            for (const cmd of spec.commands) {
                const a = cmd.a;
                switch (cmd.c) {
                    case "moveTo": path.moveTo(sx(a[0]), sy(a[1])); break;
                    case "lineTo": path.lineTo(sx(a[0]), sy(a[1])); break;
                    case "quad": path.quadraticCurveTo(sx(a[0]), sy(a[1]), sx(a[2]), sy(a[3])); break;
                    case "cubic": path.bezierCurveTo(sx(a[0]), sy(a[1]), sx(a[2]), sy(a[3]), sx(a[4]), sy(a[5])); break;
                    case "arc": {
                        // Apple's `clockwise` flag is in y-up space, so in the y-down
                        // canvas it maps directly to ctx.arc's anticlockwise param
                        // (see CanvasRenderer.kt arcSweepDegrees for the same note).
                        const clockwise = a[5] !== 0;
                        path.arc(sx(a[0]), sy(a[1]), Math.max(0, smin(a[2])), a[3] * DEG, a[4] * DEG, clockwise);
                        break;
                    }
                    case "close": path.closePath(); break;
                    default: break;
                }
            }
            break;
        default: break;
    }
    return path;
}
