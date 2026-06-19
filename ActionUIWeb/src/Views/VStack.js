// VStack.js — VStack element.
// Web analog of ActionUI/Views/VStack.swift (PoC subset).
//
// Properties: spacing (Number → CSS gap), alignment (leading|center|trailing →
// cross-axis align-items). Layout mapping: VStack → flexbox column.

import { register } from "../Common/ActionUIRegistry.js";
import { COLUMN_ALIGN, DEFAULT_SPACING, StackAxis } from "../Common/StackAxis.js";
import { ContainerShape } from "../Common/ActionUIInsertion.js";
import { buildFlatChildren } from "../Helpers/InsertionHelper.js";

// Mirrors VStack.swift validateProperties (warning text included verbatim).
function validateProperties(properties, logger) {
    const validated = { ...properties };
    if (validated.spacing !== undefined && typeof validated.spacing !== "number") {
        logger.log("VStack spacing must be numeric; ignoring", "warning");
        delete validated.spacing;
    }
    if (typeof validated.alignment === "string") {
        if (!["leading", "center", "trailing"].includes(validated.alignment)) {
            logger.log(`VStack alignment '${validated.alignment}' invalid; defaulting to nil`, "warning");
            delete validated.alignment;
        }
    } else if (validated.alignment !== undefined) {
        logger.log("VStack alignment must be 'leading', 'center', or 'trailing'; ignoring", "warning");
        delete validated.alignment;
    }
    return validated;
}

register("VStack", {
    valueType: "none",
    insertableContainers: { children: ContainerShape.FLAT },
    validateProperties,
    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-stack aui-vstack";
        node.dataset.auiAxis = StackAxis.Vertical;
        node.style.gap = `${properties.spacing ?? DEFAULT_SPACING}px`;
        // SwiftUI VStack default alignment is .center.
        node.style.alignItems = COLUMN_ALIGN[properties.alignment] ?? "center";
        buildFlatChildren(node, element, ctx);
        return node;
    },
});
