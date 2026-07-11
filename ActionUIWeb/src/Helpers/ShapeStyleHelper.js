// ShapeStyleHelper.js — shared fill/stroke resolution for the stateless shape
// elements (Rectangle, RoundedRectangle, Capsule, Circle, Ellipse).
// Web analog of ActionUIAndroid Helpers/ShapeStyleHelper.kt; the single place
// that turns a shape's `fill` / `stroke` / `strokeLineWidth` properties into a
// concrete paint, so each shape file only describes its geometry — mirroring
// how the Apple side resolves shape styling through
// ColorHelper.resolveShapeStyle.
//
// Fill vs. stroke (matches Apple priority): a resolvable `fill` wins;
// otherwise a resolvable `stroke` is used; otherwise the bare shape renders in
// the foreground style — including the subtle case where a
// present-but-unresolvable `fill` falls through to `stroke` (Apple only enters
// the fill branch when the color resolves).
//
// Color vocabulary: named colors, hex, AND Apple semantic styles ("tint",
// "separator", "fill", "fill.tertiary", "background.secondary", ...) via the
// shared resolveColor - the same vocabulary the foregroundStyle/background
// modifiers accept. resolveColor maps every semantic name to its --aui-* token
// (theme.css, light + dark), so a semantic fill/stroke is theme-correct here
// just as on Apple and Android; only a genuinely unknown color warns and falls
// through to the foreground fill. See Private/Semantic_Color_Mapping_Design.md.
//
// File granularity: Android splits this into ShapeStyleHelper.kt (paint) +
// Views/ShapeView.kt (DrawScope glue). On web a shape is a styled <div> —
// there is no draw pass — so the tiny box/paint glue lives here alongside the
// resolver rather than in a near-empty Views/ShapeView.js.

import { resolveColor } from "../Common/ModifierResolver.js";

// Resolves the paint for a shape element, honoring Apple's
// fill-then-stroke-then-foreground fall-through (see file header).
// Returns { color, strokeWidth }; strokeWidth null means fill the shape
// solidly. The bare-shape color is "currentColor" — the CSS analog of SwiftUI
// filling an unstyled shape with its foreground style (.primary), so the
// foregroundStyle modifier tints it with no extra wiring.
export function resolveShapePaint(properties, logger) {
    if (typeof properties.fill === "string") {
        const color = resolveColor(properties.fill, logger);
        if (color) return { color, strokeWidth: null };
        // resolveColor warned; fall through to stroke, mirroring Apple (the
        // fill branch is only taken when the color resolves).
    }
    if (typeof properties.stroke === "string") {
        const color = resolveColor(properties.stroke, logger);
        if (color) {
            const width = typeof properties.strokeLineWidth === "number" ? properties.strokeLineWidth : 1.0;
            return { color, strokeWidth: width };
        }
    }
    return { color: "currentColor", strokeWidth: null };
}

// Creates the shape's box: a zero-content div that is greedy by default (a
// SwiftUI shape accepts the full proposal; .aui-shape stretches and grows —
// the fillMaxSize analog from Android's ShapeView). An explicit numeric frame
// dimension pins it instead (flex-grow:0), so a frame'd shape keeps its size
// in a stack with free space — see Private/Web_Porting_Notes.md (Shapes) for
// the one-axis-frame caveat.
export function createShapeBox(properties, extraClass) {
    const node = document.createElement("div");
    node.className = extraClass ? `aui-shape ${extraClass}` : "aui-shape";
    const frame = properties.frame;
    if (typeof frame === "object" && frame !== null &&
        (typeof frame.width === "number" || typeof frame.height === "number")) {
        node.style.flexGrow = "0";
    }
    return node;
}

// Applies a resolved paint: fill → background-color, stroke → an inner border
// (box-sizing is border-box throughout, so the stroke renders inside the
// frame — the .strokeBorder look; SwiftUI's .stroke centers the line on the
// path edge, which the DOM box model can't draw without overflow).
export function applyShapePaint(node, paint) {
    if (paint.strokeWidth !== null) {
        node.style.border = `${paint.strokeWidth}px solid ${paint.color}`;
    } else {
        node.style.backgroundColor = paint.color;
    }
}
