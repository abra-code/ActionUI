// Section.js — Section element.
// Web analog of ActionUI/Views/Section.swift (and ActionUIAndroid Views/Section.kt).
//
// A named group of rows within a Form or other container: an optional `header`
// label above a leading-aligned column of `children`. The header is styled like
// a list-section label (small, secondary), matching the Android titleSmall/
// onSurfaceVariant rendering; SwiftUI's footer is not modeled by this element
// on any platform. The template/setElementRows data-driven mode is deferred
// with the insertion API (see Web_Porting_Notes.md) — only `children` renders.
//
// Properties: header (String → the section label; absent/non-string omits it).

import { register } from "../Common/ActionUIRegistry.js";
import { StackAxis } from "../Common/StackAxis.js";
import { ContainerShape } from "../Common/ActionUIInsertion.js";
import { buildFlatChildren } from "../Helpers/InsertionHelper.js";

register("Section", {
    valueType: "none",
    insertableContainers: { children: ContainerShape.FLAT },

    // Mirrors Section.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.header !== undefined && typeof validated.header !== "string") {
            logger.log("Section header must be a String; ignoring", "warning");
            delete validated.header;
        }
        return validated;
    },

    buildView: (element, properties, ctx) => {
        const node = document.createElement("section");
        node.className = "aui-stack aui-vstack aui-section";
        node.dataset.auiAxis = StackAxis.Vertical;

        if (typeof properties.header === "string") {
            const header = document.createElement("span");
            header.className = "aui-section-header";
            header.textContent = properties.header;
            node.appendChild(header);
        }
        // The optional header is not a tracked child, so insertions land after it.
        buildFlatChildren(node, element, ctx);
        return node;
    },
});
