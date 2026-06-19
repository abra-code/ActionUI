// EmptyView.js — EmptyView element.
// Web analog of ActionUI/Views/EmptyView.swift (SwiftUI.EmptyView) and
// ActionUIAndroid Views/EmptyView.kt (a no-op).
//
// Renders nothing. The node is an empty, layout-collapsed box (display:none via
// .aui-empty) so it occupies no space and draws nothing, matching SwiftUI's
// EmptyView and the Android no-op. It is still registered (and carries its
// data-aui-id when given one) so a cross-platform document resolves the type and
// a host can address it, but it has no value and no children.
//
// Note: like Apple, baseline View modifiers (padding/background/frame/...) apply
// to nothing here - the element is deliberately invisible. There is no divergence
// worth a Web_Porting_Notes entry; this is the trivial member of the group-A
// batch (EmptyView / Group / Link / ShareLink / ContentUnavailableView).

import { register } from "../Common/ActionUIRegistry.js";

register("EmptyView", {
    valueType: "none",

    // EmptyView.swift validates nothing (no properties); pass through.
    validateProperties: (properties) => properties,

    buildView: () => {
        const node = document.createElement("div");
        node.className = "aui-empty";
        return node;
    },
});
