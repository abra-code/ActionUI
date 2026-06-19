// Group.js — Group element.
// Web analog of ActionUI/Views/Group.swift and ActionUIAndroid Views/Group.kt.
//
// A transparent passthrough container: it groups its `children` without imposing
// any layout of its own - the children participate in the *parent's* layout
// directly, exactly as SwiftUI's Group (which has no geometry) and Android's
// passthrough Group do. The web realizes this with CSS `display:contents`
// (.aui-group in theme.css): the group box generates no box, so its children flow
// into the enclosing stack/grid as if the Group were not there.
//
// Divergence (documented in Web_Porting_Notes.md): because the box is
// layout-transparent, decoration/geometry modifiers placed on the Group itself
// (background / padding / frame / cornerRadius) are NOT honored - there is no box
// to paint. SwiftUI applies such modifiers to the grouped result; on the web wrap
// the children in a VStack/HStack to decorate them as a unit. This is the same
// box-model tradeoff that shapes the layout engine: a box cannot be both
// layout-transparent and a decoration surface.
//
// Deferral: the data-driven `template` / setElementRows mode is deferred with the
// insertion API, as on the stacks and lazy grids - only `children` renders today.

import { register } from "../Common/ActionUIRegistry.js";
import { ContainerShape } from "../Common/ActionUIInsertion.js";
import { buildFlatChildren } from "../Helpers/InsertionHelper.js";

register("Group", {
    valueType: "none",
    insertableContainers: { children: ContainerShape.FLAT },

    // Group.swift declares no properties; validateProperties passes through.
    validateProperties: (properties) => properties,

    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-group";
        buildFlatChildren(node, element, ctx);
        return node;
    },
});
