// ActionUIRegistry.js — maps element type strings to view constructions.
// Web analog of ActionUI/Common/ActionUIRegistry.swift (PoC subset).
//
// A view construction is an object:
// {
//   valueType:           "none" | "string" | "boolean" | "int" | "double",
//   validateProperties:  (properties, logger) => validatedProperties,
//   buildView:           (element, ctx) => HTMLElement,
//   initialValue:        (element, validatedProperties) => any | undefined,
//   initialStates:       (element, validatedProperties) => { key: value } | undefined,
//   insertableContainers:{ <containerName>: ContainerShape } | undefined,
// }
// ctx = { model, windowUUID, logger, build } where build(childElement) recurses.
//
// `insertableContainers` is the web analog of Swift's
// ActionUIViewConstruction.insertableContainers - it declares which subview
// arrays accept runtime insertions (insertElement / insertRow) and their shape.
// A view that declares one also registers a matching container binding at build
// time (Helpers/InsertionHelper.js); the model reads the declaration via
// getInsertableContainers to resolve/validate the target container.
//
// Unknown types degrade gracefully: a warning is logged and a placeholder
// element is rendered, mirroring the fail-gracefully design principle.

import { applyViewModifiers } from "./ModifierResolver.js";
import { wrapWithToolbar } from "../Helpers/ToolbarHelper.js";

const constructions = new Map();

export function register(type, construction) {
    constructions.set(type, construction);
}

// The container declarations for a type, or null when it accepts no insertions.
// Mirrors ActionUIRegistry.getInsertableContainers(forElementType:).
export function getInsertableContainers(type) {
    return constructions.get(type)?.insertableContainers ?? null;
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
        const states = construction.initialStates?.(element, properties);
        if (states !== undefined) {
            ctx.model.seedStates(element.id, states);
        }
    }
    applyViewModifiers(node, element, properties, ctx);
    // A `toolbar` / `navigationTitle` wraps the node in screen chrome (a top bar
    // + optional bottom bar). The data-aui-id stays on the inner node, so host
    // addressing (value/state/scroll) is unaffected by the wrap.
    return wrapWithToolbar(node, element, properties, ctx);
}
