// VStack.js — VStack element.
// Web analog of ActionUI/Views/VStack.swift (PoC subset).
//
// Properties: spacing (Number → CSS gap), alignment (leading|center|trailing →
// cross-axis align-items). Layout mapping: VStack → flexbox column.

import { register } from "../Common/ActionUIRegistry.js";
import { COLUMN_ALIGN, DEFAULT_SPACING, StackAxis } from "../Common/StackAxis.js";

function validateStackProperties(properties, logger) {
    const validated = { ...properties };
    if (validated.spacing !== undefined && typeof validated.spacing !== "number") {
        logger.log(`Stack spacing must be a number, got ${JSON.stringify(validated.spacing)}`, "warning");
        delete validated.spacing;
    }
    return validated;
}

register("VStack", {
    valueType: "none",
    validateProperties: validateStackProperties,
    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-stack aui-vstack";
        node.dataset.auiAxis = StackAxis.Vertical;
        node.style.gap = `${properties.spacing ?? DEFAULT_SPACING}px`;
        // SwiftUI VStack default alignment is .center.
        node.style.alignItems = COLUMN_ALIGN[properties.alignment] ?? "center";
        for (const child of element.children()) {
            node.appendChild(ctx.build(child));
        }
        return node;
    },
});

export { validateStackProperties };
