// GroupBox.js - GroupBox element.
// Web analog of ActionUI/Views/GroupBox.swift (and ActionUIAndroid Views/GroupBox.kt).
//
// A titled, visually grouped container: an optional `title` label above a rounded
// card holding the content column - the default SwiftUI GroupBoxStyle shape
// (Android renders the same as an OutlinedCard). The template/
// setElementRows data-driven mode is deferred with the insertion API -
// only `children` renders.
//
// Properties: title (String shown above the content; absent/non-string omits it).

import { register } from "../Common/ActionUIRegistry.js";
import { StackAxis } from "../Common/StackAxis.js";
import { ContainerShape } from "../Common/ActionUIInsertion.js";
import { buildFlatChildren } from "../Helpers/InsertionHelper.js";
import { markExpansion } from "../Common/ModifierResolver.js";

register("GroupBox", {
    valueType: "none",
    insertableContainers: { children: ContainerShape.FLAT },

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
        // The title above a card holding the children, as macOS draws a GroupBox (measured on
        // macOS 27): the content is inset 5 points on every side, centered, spaced as a stack
        // given no spacing (8, none next to a Spacer), and the box is as large as its children
        // unless one of them fills.
        const node = document.createElement("div");
        node.className = "aui-stack aui-vstack aui-groupbox";
        node.dataset.auiAxis = StackAxis.Vertical;

        if (typeof properties.title === "string") {
            const title = document.createElement("span");
            title.className = "aui-groupbox-title";
            title.textContent = properties.title;
            node.appendChild(title);
        }
        const card = document.createElement("div");
        card.className = "aui-stack aui-vstack aui-default-spacing aui-groupbox-card";
        card.dataset.auiAxis = StackAxis.Vertical;
        // Insertions land in the card.
        buildFlatChildren(card, element, ctx);
        // The card expands where its children do; the GroupBox then expands where the card does
        // (buildElementView marks the GroupBox itself).
        markExpansion(card, { w: 10, h: 10 }); // the card's padding, 5 on each side
        node.appendChild(card);
        return node;
    },
});
