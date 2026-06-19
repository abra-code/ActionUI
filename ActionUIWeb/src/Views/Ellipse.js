// Ellipse.js — Ellipse element.
// Web analog of ActionUI/Views/Ellipse.swift (and ActionUIAndroid
// Views/Ellipse.kt).
//
// An ellipse inscribed in its frame — exactly what border-radius:50% makes of
// the shape box (.aui-ellipse), so unlike Circle no inner disc is needed.
// Paint and sizing via Helpers/ShapeStyleHelper.js; see
// Private/Web_Porting_Notes.md (Shapes).
//
// Properties: fill (String), stroke (String, fill takes priority),
// strokeLineWidth (Double, default 1.0, used with stroke).

import { register } from "../Common/ActionUIRegistry.js";
import { applyShapePaint, createShapeBox, resolveShapePaint } from "../Helpers/ShapeStyleHelper.js";

register("Ellipse", {
    valueType: "none",

    // Mirrors Ellipse.swift validateProperties (warning text verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        if (validated.fill !== undefined && typeof validated.fill !== "string") {
            logger.log("Ellipse fill must be a String; ignoring", "warning");
            delete validated.fill;
        }
        if (validated.stroke !== undefined && typeof validated.stroke !== "string") {
            logger.log("Ellipse stroke must be a String; ignoring", "warning");
            delete validated.stroke;
        }
        if (validated.strokeLineWidth !== undefined && typeof validated.strokeLineWidth !== "number") {
            logger.log("Ellipse strokeLineWidth must be a CGFloat; ignoring", "warning");
            delete validated.strokeLineWidth;
        }

        return validated;
    },

    buildView: (element, properties, ctx) => {
        const node = createShapeBox(properties, "aui-ellipse");
        applyShapePaint(node, resolveShapePaint(properties, ctx.logger));
        return node;
    },
});
