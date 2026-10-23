// HStack.js — HStack element.
// Web analog of ActionUI/Views/HStack.swift (PoC subset).
//
// Properties: spacing (Number → CSS gap), alignment (top|center|bottom →
// cross-axis align-items). Layout mapping: HStack → flexbox row.

import { register } from "../Common/ActionUIRegistry.js";
import { ROW_ALIGN, StackAxis } from "../Common/StackAxis.js";
import { ContainerShape } from "../Common/ActionUIInsertion.js";
import { buildFlatChildren } from "../Helpers/InsertionHelper.js";

// Mirrors HStack.swift validateProperties (warning text included verbatim).
function validateProperties(properties, logger) {
    const validated = { ...properties };
    if (validated.spacing !== undefined && typeof validated.spacing !== "number") {
        logger.log("HStack spacing must be a number; ignoring", "warning");
        delete validated.spacing;
    }
    const valid = ["top", "center", "bottom", "firstTextBaseline", "lastTextBaseline"];
    if (typeof validated.alignment === "string") {
        if (!valid.includes(validated.alignment)) {
            logger.log(`HStack alignment '${validated.alignment}' invalid; ignoring`, "warning");
            delete validated.alignment;
        }
    } else if (validated.alignment !== undefined) {
        logger.log("HStack alignment must be a String; ignoring", "warning");
        delete validated.alignment;
    }
    return validated;
}

register("HStack", {
    valueType: "none",
    insertableContainers: { children: ContainerShape.FLAT },
    validateProperties,
    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-stack aui-hstack";
        node.dataset.auiAxis = StackAxis.Horizontal;
        // No spacing given: SwiftUI's default, 8 between views and none next to a Spacer (the
        // aui-default-spacing rules in theme.css: a gap of 8 that a Spacer's margins cancel).
        if (typeof properties.spacing === "number") {
            node.style.gap = `${properties.spacing}px`;
        } else {
            node.classList.add("aui-default-spacing");
        }
        // SwiftUI HStack default alignment is .center.
        node.style.alignItems = ROW_ALIGN[properties.alignment] ?? "center";
        buildFlatChildren(node, element, ctx);
        return node;
    },
});
