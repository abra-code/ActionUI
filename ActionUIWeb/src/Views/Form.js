// Form.js — Form element.
// Web analog of ActionUI/Views/Form.swift (and ActionUIAndroid Views/Form.kt).
//
// A grouped form layout: a leading-aligned column of controls (typically
// Sections, TextFields, Toggles, Pickers). Like the Android port, it does not
// scroll on its own — SwiftUI's Form brings its own scroller, but here the
// scrolling belongs to an enclosing ScrollView (the same stance the renderer
// takes elsewhere), and macOS grouped/inset styling is not replicated; a small
// default row spacing approximates the visual grouping. See
// Web_Porting_Notes.md. Form.swift declares no properties of its own
// (validateProperties passes through).

import { register } from "../Common/ActionUIRegistry.js";
import { StackAxis } from "../Common/StackAxis.js";

register("Form", {
    valueType: "none",

    // Mirrors Form.swift validateProperties (a pass-through).
    validateProperties: (properties) => properties,

    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        // Reuses the vstack flex column (so Divider orientation comes for
        // free); .aui-form adds the leading alignment and row spacing.
        node.className = "aui-stack aui-vstack aui-form";
        node.dataset.auiAxis = StackAxis.Vertical;
        for (const child of element.children()) {
            node.appendChild(ctx.build(child));
        }
        return node;
    },
});
