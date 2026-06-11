// Spacer.js — Spacer element.
// Web analog of ActionUI/Views/Spacer.swift (PoC subset).
//
// Flexible empty space that pushes siblings apart. Maps to a flex-grow:1
// filler (the `.aui-spacer` rule in theme.css). Property: minLength (Number) →
// min-width/min-height floor. A stack-less Spacer is inert, matching SwiftUI.

import { register } from "../Common/ActionUIRegistry.js";

register("Spacer", {
    valueType: "none",

    // Mirrors Spacer.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.minLength !== undefined && typeof validated.minLength !== "number") {
            logger.log("Spacer minLength must be a CGFloat; ignoring", "warning");
            delete validated.minLength;
        }
        return validated;
    },

    buildView: (element, properties) => {
        const node = document.createElement("div");
        node.className = "aui-spacer";
        if (typeof properties.minLength === "number") {
            node.style.minWidth = `${properties.minLength}px`;
            node.style.minHeight = `${properties.minLength}px`;
        }
        return node;
    },
});
