// ActionUIRegistry.js — maps element type strings to view constructions.
// Web analog of ActionUI/Common/ActionUIRegistry.swift (PoC subset).
//
// A view construction is an object:
// {
//   valueType:          "none" | "string" | "boolean" | "int" | "double",
//   validateProperties: (properties, logger) => validatedProperties,
//   buildView:          (element, ctx) => HTMLElement,
//   initialValue:       (element, validatedProperties) => any | undefined,
// }
// ctx = { model, windowUUID, logger, build } where build(childElement) recurses.
//
// Unknown types degrade gracefully: a warning is logged and a placeholder
// element is rendered, mirroring the fail-gracefully design principle.

import { applyViewModifiers } from "./ModifierResolver.js";

const constructions = new Map();

export function register(type, construction) {
    constructions.set(type, construction);
}

export function buildElementView(element, ctx) {
    const construction = constructions.get(element.type);
    if (!construction) {
        ctx.logger.log(`Unknown element type "${element.type}" — rendering placeholder`, "warning");
        const placeholder = document.createElement("div");
        placeholder.className = "aui-unknown";
        placeholder.textContent = `⚠ ${element.type}`;
        return placeholder;
    }

    const properties = construction.validateProperties(element.properties, ctx.logger);
    const node = construction.buildView(element, properties, ctx);
    node.dataset.auiType = element.type;
    if (element.id > 0) {
        node.dataset.auiId = String(element.id);
        const initial = construction.initialValue?.(element, properties);
        if (construction.valueType !== "none" && initial !== undefined) {
            ctx.model.seedValue(element.id, initial);
        }
    }
    applyViewModifiers(node, element, properties, ctx);
    return node;
}
