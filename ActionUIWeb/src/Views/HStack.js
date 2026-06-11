// HStack.js — HStack element.
// Web analog of ActionUI/Views/HStack.swift (PoC subset).
//
// Properties: spacing (Number → CSS gap), alignment (top|center|bottom →
// cross-axis align-items). Layout mapping: HStack → flexbox row.

import { register } from "../Common/ActionUIRegistry.js";
import { ROW_ALIGN, DEFAULT_SPACING, StackAxis } from "../Common/StackAxis.js";
import { validateStackProperties } from "./VStack.js";

register("HStack", {
    valueType: "none",
    validateProperties: validateStackProperties,
    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-stack aui-hstack";
        node.dataset.auiAxis = StackAxis.Horizontal;
        node.style.gap = `${properties.spacing ?? DEFAULT_SPACING}px`;
        // SwiftUI HStack default alignment is .center.
        node.style.alignItems = ROW_ALIGN[properties.alignment] ?? "center";
        for (const child of element.children()) {
            node.appendChild(ctx.build(child));
        }
        return node;
    },
});
