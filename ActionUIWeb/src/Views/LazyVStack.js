// LazyVStack.js — LazyVStack element.
// Web analog of ActionUI/Views/LazyVStack.swift (and ActionUIAndroid Views/LazyVStack.kt).
//
// Same flexbox-column layout as VStack; on web it renders eagerly — the "lazy"
// virtualization (only realizing on-screen cells) is a Phase 4 concern and not
// done yet, so visually LazyVStack and VStack are identical. It reuses the
// `.aui-vstack` class (so Divider orientation and flex-direction come for free)
// plus an `.aui-lazyvstack` marker. One divergence from VStack: the default
// spacing is 0, mirroring the Swift `spacing ?? 0.0` (VStack approximates
// SwiftUI's adaptive default with 8). Template/data-driven mode is deferred with
// the insertion API (see Web_Porting_Notes.md), as on the other stacks.
//
// Properties: spacing (Number → CSS gap, default 0), alignment
// (leading|center|trailing → cross-axis align-items, default center).

import { register } from "../Common/ActionUIRegistry.js";
import { COLUMN_ALIGN, StackAxis } from "../Common/StackAxis.js";

// Mirrors LazyVStack.swift validateProperties (warning text included verbatim).
function validateProperties(properties, logger) {
    const validated = { ...properties };
    if (validated.spacing !== undefined && typeof validated.spacing !== "number") {
        logger.log("LazyVStack spacing must be numeric; ignoring", "warning");
        delete validated.spacing;
    }
    if (typeof validated.alignment === "string") {
        if (!["leading", "center", "trailing"].includes(validated.alignment)) {
            logger.log(`LazyVStack alignment '${validated.alignment}' invalid; defaulting to nil`, "warning");
            delete validated.alignment;
        }
    } else if (validated.alignment !== undefined) {
        logger.log("LazyVStack alignment must be 'leading', 'center', or 'trailing'; ignoring", "warning");
        delete validated.alignment;
    }
    return validated;
}

register("LazyVStack", {
    valueType: "none",
    validateProperties,
    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-stack aui-vstack aui-lazyvstack";
        node.dataset.auiAxis = StackAxis.Vertical;
        node.style.gap = `${properties.spacing ?? 0}px`;
        // SwiftUI LazyVStack default alignment is .center.
        node.style.alignItems = COLUMN_ALIGN[properties.alignment] ?? "center";
        for (const child of element.children()) {
            node.appendChild(ctx.build(child));
        }
        return node;
    },
});
