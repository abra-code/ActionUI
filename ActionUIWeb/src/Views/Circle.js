// Circle.js — Circle element.
// Web analog of ActionUI/Views/Circle.swift (and ActionUIAndroid
// Views/Circle.kt).
//
// A circle inscribed in its frame: SwiftUI's Circle stays circular in a
// non-square box (diameter = min(width, height), centered), where a plain
// border-radius:50% div would degenerate to an ellipse — the same fidelity
// point that made Android draw its own geometry instead of reusing Compose's
// CircleShape. The box (.aui-circle) is a CSS size container centering an
// inner disc sized min(100cqw, 100cqh) with aspect-ratio 1, so the inscribed
// geometry is pure CSS; the paint applies to the disc. Paint and sizing via
// Helpers/ShapeStyleHelper.js; see Private/Web_Porting_Notes.md (Shapes).
//
// Properties: fill (String), stroke (String, fill takes priority),
// strokeLineWidth (Double, default 1.0, used with stroke).

import { register } from "../Common/ActionUIRegistry.js";
import { applyShapePaint, createShapeBox, resolveShapePaint } from "../Helpers/ShapeStyleHelper.js";

register("Circle", {
    valueType: "none",

    // Mirrors Circle.swift validateProperties (warning text verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        if (validated.fill !== undefined && typeof validated.fill !== "string") {
            logger.log("Circle fill must be a String; ignoring", "warning");
            delete validated.fill;
        }
        if (validated.stroke !== undefined && typeof validated.stroke !== "string") {
            logger.log("Circle stroke must be a String; ignoring", "warning");
            delete validated.stroke;
        }
        if (validated.strokeLineWidth !== undefined && typeof validated.strokeLineWidth !== "number") {
            logger.log("Circle strokeLineWidth must be a CGFloat; ignoring", "warning");
            delete validated.strokeLineWidth;
        }

        return validated;
    },

    buildView: (element, properties, ctx) => {
        const node = createShapeBox(properties, "aui-circle");
        const disc = document.createElement("div");
        disc.className = "aui-circle-disc";
        applyShapePaint(disc, resolveShapePaint(properties, ctx.logger));
        node.appendChild(disc);
        return node;
    },
});
