// LazyHStack.js — LazyHStack element.
// Web analog of ActionUI/Views/LazyHStack.swift (and ActionUIAndroid Views/LazyHStack.kt).
//
// Same flexbox-row layout as HStack; on web it renders eagerly — the "lazy"
// virtualization is a Phase 4 concern (not done yet), so LazyHStack and HStack
// look identical. It reuses the `.aui-hstack` class (Divider orientation +
// flex-direction) plus an `.aui-lazyhstack` marker. Like LazyVStack the default
// spacing is 0 (Swift `spacing ?? 0.0`), and its alignment vocabulary is the
// VerticalAlignment subset top|center|bottom — without HStack's baseline cases.
// Template/data-driven mode is deferred with the insertion API.
//
// Properties: spacing (Number → CSS gap, default 0), alignment
// (top|center|bottom → cross-axis align-items, default center).

import { register } from "../Common/ActionUIRegistry.js";
import { ROW_ALIGN, StackAxis } from "../Common/StackAxis.js";
import { ContainerShape } from "../Common/ActionUIInsertion.js";
import { buildFlatChildren } from "../Helpers/InsertionHelper.js";

// Mirrors LazyHStack.swift validateProperties (warning text included verbatim).
function validateProperties(properties, logger) {
    const validated = { ...properties };
    if (validated.spacing !== undefined && typeof validated.spacing !== "number") {
        logger.log("LazyHStack spacing must be numeric; ignoring", "warning");
        delete validated.spacing;
    }
    if (typeof validated.alignment === "string") {
        if (!["top", "center", "bottom"].includes(validated.alignment)) {
            logger.log(`LazyHStack alignment '${validated.alignment}' invalid; defaulting to nil`, "warning");
            delete validated.alignment;
        }
    } else if (validated.alignment !== undefined) {
        logger.log("LazyHStack alignment must be 'top', 'center', or 'bottom'; ignoring", "warning");
        delete validated.alignment;
    }
    return validated;
}

register("LazyHStack", {
    valueType: "none",
    insertableContainers: { children: ContainerShape.FLAT },
    validateProperties,
    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-stack aui-hstack aui-lazyhstack";
        node.dataset.auiAxis = StackAxis.Horizontal;
        node.style.gap = `${properties.spacing ?? 0}px`;
        // SwiftUI LazyHStack default alignment is .center.
        node.style.alignItems = ROW_ALIGN[properties.alignment] ?? "center";
        buildFlatChildren(node, element, ctx);
        return node;
    },
});
