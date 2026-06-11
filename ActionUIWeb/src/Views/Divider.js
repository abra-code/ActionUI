// Divider.js — Divider element.
// Web analog of ActionUI/Views/Divider.swift (PoC subset).
//
// Renders a horizontal rule. SwiftUI's Divider is orientation-sensitive (a
// horizontal rule inside a VStack, a vertical rule inside an HStack); stacks
// tag their root with `data-aui-axis` (see Common/StackAxis.js) so this can be
// resolved later, but axis-aware rendering is not yet ported — see
// Private/Web_Porting_Notes.md.

import { register } from "../Common/ActionUIRegistry.js";

register("Divider", {
    valueType: "none",
    validateProperties: (properties) => properties,
    buildView: () => {
        const node = document.createElement("div");
        node.className = "aui-divider";
        return node;
    },
});
