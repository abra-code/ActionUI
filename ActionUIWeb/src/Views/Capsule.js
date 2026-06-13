// Capsule.js — Capsule element.
// Web analog of ActionUI/Views/Capsule.swift (and ActionUIAndroid
// Views/Capsule.kt).
//
// A rounded rectangle whose corner radius is half the shorter side — the
// classic CSS pill (.aui-capsule's oversized border-radius clamps to exactly
// that). `style` "continuous" sets `corner-shape: squircle` for the
// continuous end caps, the same progressive enhancement as RoundedRectangle's
// cornerStyle. Paint and sizing via Helpers/ShapeStyleHelper.js; see
// Private/Web_Porting_Notes.md (Shapes).
//
// Properties: style ("circular" default | "continuous"), fill (String),
// stroke (String, fill takes priority), strokeLineWidth (Double, default 1.0,
// used with stroke).

import { register } from "../Common/ActionUIRegistry.js";
import { applyShapePaint, createShapeBox, resolveShapePaint } from "../Helpers/ShapeStyleHelper.js";

register("Capsule", {
    valueType: "none",

    // Mirrors Capsule.swift validateProperties (warning text verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        if (typeof validated.style === "string") {
            if (validated.style !== "circular" && validated.style !== "continuous") {
                logger.log("Capsule style must be 'circular' or 'continuous'; ignoring", "warning");
                delete validated.style;
            }
        } else if (validated.style !== undefined) {
            logger.log("Capsule style must be a String; ignoring", "warning");
            delete validated.style;
        }
        if (validated.fill !== undefined && typeof validated.fill !== "string") {
            logger.log("Capsule fill must be a String; ignoring", "warning");
            delete validated.fill;
        }
        if (validated.stroke !== undefined && typeof validated.stroke !== "string") {
            logger.log("Capsule stroke must be a String; ignoring", "warning");
            delete validated.stroke;
        }
        if (validated.strokeLineWidth !== undefined && typeof validated.strokeLineWidth !== "number") {
            logger.log("Capsule strokeLineWidth must be a CGFloat; ignoring", "warning");
            delete validated.strokeLineWidth;
        }

        return validated;
    },

    buildView: (element, properties, ctx) => {
        const node = createShapeBox(properties, "aui-capsule");
        if (properties.style === "continuous") {
            node.style.setProperty("corner-shape", "squircle");
        }
        applyShapePaint(node, resolveShapePaint(properties, ctx.logger));
        return node;
    },
});
