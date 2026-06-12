// GroupBox.js — GroupBox element.
// Web analog of ActionUI/Views/GroupBox.swift (and ActionUIAndroid Views/GroupBox.kt).
//
// A titled, visually grouped container: a bordered rounded box with an optional
// `title` label above the content column — the default SwiftUI GroupBoxStyle
// shape (Android renders the same as an OutlinedCard). The template/
// setElementRows data-driven mode is deferred with the insertion API (see
// Web_Porting_Notes.md) — only `children` renders.
//
// Properties: title (String shown above the content; absent/non-string omits it).

import { register } from "../Common/ActionUIRegistry.js";
import { StackAxis } from "../Common/StackAxis.js";

register("GroupBox", {
    valueType: "none",

    // Mirrors GroupBox.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.title !== undefined && typeof validated.title !== "string") {
            logger.log("GroupBox 'title' must be String; setting to nil", "warning");
            delete validated.title;
        }
        return validated;
    },

    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-stack aui-vstack aui-groupbox";
        node.dataset.auiAxis = StackAxis.Vertical;

        if (typeof properties.title === "string") {
            const title = document.createElement("span");
            title.className = "aui-groupbox-title";
            title.textContent = properties.title;
            node.appendChild(title);
        }
        for (const child of element.children()) {
            node.appendChild(ctx.build(child));
        }
        return node;
    },
});
