// LabeledContent.js — LabeledContent element.
// Web analog of ActionUI/Views/LabeledContent.swift (and ActionUIAndroid
// Views/LabeledContent.kt).
//
// Pairs a `title` label with content. Outside a Form it is an HStack with SwiftUI's default
// spacing, as on macOS 27 (measured): the title hugs its text, the `children` follow it, and an
// empty title still takes the gap of 8 before them. In a Form the title flexes and the content
// goes to the trailing edge (theme.css).
//
// Properties: title (String for the leading label, defaults to "").

import { register } from "../Common/ActionUIRegistry.js";
import { StackAxis } from "../Common/StackAxis.js";

register("LabeledContent", {
    valueType: "none",

    // Mirrors LabeledContent.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.title !== undefined && typeof validated.title !== "string") {
            logger.log("LabeledContent 'title' must be String; setting to nil", "warning");
            delete validated.title;
        }
        return validated;
    },

    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-stack aui-hstack aui-default-spacing aui-labeled-content";
        node.dataset.auiAxis = StackAxis.Horizontal;

        // Kept when empty, as SwiftUI keeps the gap after an empty title. Its extent is then
        // known (0 by 0), so the row's own follows from its children's (markExpansion).
        const title = document.createElement("span");
        title.className = "aui-labeled-content-title";
        title.textContent = properties.title ?? "";
        if (title.textContent === "") {
            title.auiExtent = { w: { kind: "fixed", value: 0 }, h: { kind: "fixed", value: 0 } };
        }
        node.appendChild(title);

        for (const child of element.children()) {
            node.appendChild(ctx.build(child));
        }
        return node;
    },
});
