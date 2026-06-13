// Rectangle.js — Rectangle element.
// Web analog of ActionUI/Views/Rectangle.swift (and ActionUIAndroid
// Views/Rectangle.kt).
//
// A stateless shape filling its frame: a zero-content div painted by the
// shared Helpers/ShapeStyleHelper.js (fill → background, stroke → inner
// border, bare → currentColor, Apple's fill-then-stroke-then-foreground
// priority). Greedy without a frame, pinned with one — sizing and the stroke
// divergence are documented in Private/Web_Porting_Notes.md (Shapes).
//
// Properties: fill (String), stroke (String, fill takes priority),
// strokeLineWidth (Double, default 1.0, used with stroke).

import { register } from "../Common/ActionUIRegistry.js";
import { applyShapePaint, createShapeBox, resolveShapePaint } from "../Helpers/ShapeStyleHelper.js";

register("Rectangle", {
    valueType: "none",

    // Mirrors Rectangle.swift validateProperties (warning text verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        if (validated.fill !== undefined && typeof validated.fill !== "string") {
            logger.log("Rectangle fill must be a String; ignoring", "warning");
            delete validated.fill;
        }
        if (validated.stroke !== undefined && typeof validated.stroke !== "string") {
            logger.log("Rectangle stroke must be a String; ignoring", "warning");
            delete validated.stroke;
        }
        if (validated.strokeLineWidth !== undefined && typeof validated.strokeLineWidth !== "number") {
            logger.log("Rectangle strokeLineWidth must be a CGFloat; ignoring", "warning");
            delete validated.strokeLineWidth;
        }

        return validated;
    },

    buildView: (element, properties, ctx) => {
        const node = createShapeBox(properties);
        applyShapePaint(node, resolveShapePaint(properties, ctx.logger));
        return node;
    },
});
