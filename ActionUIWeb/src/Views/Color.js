// Color.js — Color element (SwiftUI's `Color` used as a View).
// Web analog of ActionUI/Views/Color.swift and ActionUIAndroid Views/Color.kt.
//
// SwiftUI's `Color` is itself a View: a greedy block that fills the proposed space - the
// canonical way to use a solid color as a view (a colored divider, a tinted background block),
// simpler than a Rectangle().fill(). It reuses the shape box (Helpers/ShapeStyleHelper.js):
// greedy without a frame (`.aui-shape`), pinned with one. Give it a `frame` to size it
// (e.g. height 2 for a divider). Baseline View properties are inherited via ModifierResolver.
//
// Property: color (String) - a named color ("red"), an Apple semantic style
// ("primary"/"secondary"/"fill.tertiary"/"tint"/...), a hex string ("#RRGGBB" / "#RRGGBBAA"),
// or "<color>.opacity(<fraction>)". Resolved through the shared resolveColor (semantic names
// map to adaptive --aui-* tokens; it warns on a genuinely unknown color); a missing/unresolvable
// color renders transparent.

import { register } from "../Common/ActionUIRegistry.js";
import { resolveColor } from "../Common/ModifierResolver.js";
import { createShapeBox } from "../Helpers/ShapeStyleHelper.js";

register("Color", {
    valueType: "none",

    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.color !== undefined && typeof validated.color !== "string") {
            logger.log("Color color must be a String; ignoring", "warning");
            delete validated.color;
        }
        return validated;
    },

    buildView: (element, properties, ctx) => {
        const node = createShapeBox(properties, "aui-color");
        const colorStr = properties.color;
        if (typeof colorStr === "string" && colorStr.length > 0) {
            const css = resolveColor(colorStr, ctx.logger); // warns on an unknown color
            if (css) node.style.background = css;
        } else {
            ctx.logger.log("Color view requires a 'color' string; rendering transparent", "warning");
        }
        return node;
    },
});
