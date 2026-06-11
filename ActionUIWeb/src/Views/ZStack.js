// ZStack.js — ZStack element.
// Web analog of ActionUI/Views/ZStack.swift (PoC subset).
//
// Layout mapping: ZStack → single-cell CSS grid; children share one grid cell
// and stack on the z-axis in document order (later children paint on top).

import { register } from "../Common/ActionUIRegistry.js";

register("ZStack", {
    valueType: "none",
    validateProperties: (properties) => properties,
    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-zstack";
        for (const child of element.children()) {
            node.appendChild(ctx.build(child));
        }
        return node;
    },
});
