// RoundedRectangle.js — RoundedRectangle element.
// Web analog of ActionUI/Views/RoundedRectangle.swift (and ActionUIAndroid
// Views/RoundedRectangle.kt).
//
// Rectangle with rounded corners: the shared shape box plus an inline
// border-radius from `cornerRadius` (default 0, like Swift's `?? 0`).
// `cornerStyle` "continuous" (the squircle) sets the CSS `corner-shape:
// squircle` — a progressive enhancement: browsers that support it render the
// continuous curve, others keep circular arcs (the Android downgrade, minus
// the warning since here it is the same declaration either way). Paint and
// sizing via Helpers/ShapeStyleHelper.js; see Private/Web_Porting_Notes.md
// (Shapes).
//
// Properties: cornerRadius (Double, default 0), cornerStyle ("circular"
// default | "continuous"), fill (String), stroke (String, fill takes
// priority), strokeLineWidth (Double, default 1.0, used with stroke).

import { register } from "../Common/ActionUIRegistry.js";
import { applyShapePaint, createShapeBox, resolveShapePaint } from "../Helpers/ShapeStyleHelper.js";

register("RoundedRectangle", {
    valueType: "none",

    // Mirrors RoundedRectangle.swift validateProperties (warning text verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        if (validated.cornerRadius !== undefined && typeof validated.cornerRadius !== "number") {
            logger.log("RoundedRectangle cornerRadius must be a CGFloat; defaulting to 0", "warning");
            delete validated.cornerRadius;
        }
        if (typeof validated.cornerStyle === "string") {
            if (validated.cornerStyle !== "circular" && validated.cornerStyle !== "continuous") {
                logger.log("RoundedRectangle cornerStyle must be 'circular' or 'continuous'; ignoring", "warning");
                delete validated.cornerStyle;
            }
        } else if (validated.cornerStyle !== undefined) {
            logger.log("RoundedRectangle cornerStyle must be a String; ignoring", "warning");
            delete validated.cornerStyle;
        }
        if (validated.fill !== undefined && typeof validated.fill !== "string") {
            logger.log("RoundedRectangle fill must be a String; ignoring", "warning");
            delete validated.fill;
        }
        if (validated.stroke !== undefined && typeof validated.stroke !== "string") {
            logger.log("RoundedRectangle stroke must be a String; ignoring", "warning");
            delete validated.stroke;
        }
        if (validated.strokeLineWidth !== undefined && typeof validated.strokeLineWidth !== "number") {
            logger.log("RoundedRectangle strokeLineWidth must be a CGFloat; ignoring", "warning");
            delete validated.strokeLineWidth;
        }

        return validated;
    },

    buildView: (element, properties, ctx) => {
        const node = createShapeBox(properties);
        const cornerRadius = typeof properties.cornerRadius === "number" ? properties.cornerRadius : 0;
        node.style.borderRadius = `${cornerRadius}px`;
        if (properties.cornerStyle === "continuous") {
            node.style.setProperty("corner-shape", "squircle");
        }
        applyShapePaint(node, resolveShapePaint(properties, ctx.logger));
        return node;
    },
});
