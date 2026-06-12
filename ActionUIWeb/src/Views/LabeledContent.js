// LabeledContent.js — LabeledContent element.
// Web analog of ActionUI/Views/LabeledContent.swift (and ActionUIAndroid
// Views/LabeledContent.kt).
//
// Pairs a `title` label with content: the title leads, the `children` are
// pushed to the trailing edge (the SwiftUI label-left / content-right layout,
// which stays visible in any container — unlike a control's built-in,
// often-hidden label). The row stretches to the available width like the
// Android weighted Row; an empty/absent title renders content only.
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
        node.className = "aui-stack aui-hstack aui-labeled-content";
        node.dataset.auiAxis = StackAxis.Horizontal;

        // The title flexes (flex:1 in theme.css), pushing the children to the
        // trailing edge; kept even when empty so content stays trailing.
        const title = document.createElement("span");
        title.className = "aui-labeled-content-title";
        title.textContent = properties.title ?? "";
        node.appendChild(title);

        for (const child of element.children()) {
            node.appendChild(ctx.build(child));
        }
        return node;
    },
});
