// ZStack.js — ZStack element.
// Web analog of ActionUI/Views/ZStack.swift (PoC subset).
//
// Layout mapping: ZStack → single-cell CSS grid; children share one grid cell
// and stack on the z-axis in document order (later children paint on top).

import { register } from "../Common/ActionUIRegistry.js";
import { ContainerShape } from "../Common/ActionUIInsertion.js";
import { buildFlatChildren } from "../Helpers/InsertionHelper.js";

// SwiftUI ZStack alignments → CSS `place-self` (block/vertical + inline/horizontal).
const Z_ALIGN = {
    topLeading: "start start", top: "start center", topTrailing: "start end",
    leading: "center start", center: "center center", trailing: "center end",
    bottomLeading: "end start", bottom: "end center", bottomTrailing: "end end",
};
const Z_VALID = Object.keys(Z_ALIGN);

register("ZStack", {
    valueType: "none",
    insertableContainers: { children: ContainerShape.FLAT },

    // Mirrors ZStack.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (typeof validated.alignment === "string") {
            if (!Z_VALID.includes(validated.alignment)) {
                logger.log(
                    "ZStack alignment must be one of 'topLeading', 'top', 'topTrailing', 'leading', " +
                    "'center', 'trailing', 'bottomLeading', 'bottom', 'bottomTrailing'; ignoring",
                    "warning",
                );
                delete validated.alignment;
            }
        } else if (validated.alignment !== undefined) {
            logger.log("Invalid type for alignment: expected String; ignoring", "warning");
            delete validated.alignment;
        }
        return validated;
    },

    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-zstack";
        // The alignment, as the grid's place-items (the children's place-self is auto in
        // theme.css), not an inline place-self per child, so a child that fills can stretch over
        // it, as in SwiftUI, and inserted children get it too. Not a custom property: a ZStack
        // child would read its own value instead of its parent's. Default: center.
        node.style.placeItems = Z_ALIGN[properties.alignment] ?? "center center";
        buildFlatChildren(node, element, ctx);
        return node;
    },
});
