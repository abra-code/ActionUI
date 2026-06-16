// ActionUIModel.js — per-window value store, DOM bindings, action routing.
// Web analog of ActionUI/Common/ActionUIModel.swift (PoC subset).
//
// Instead of a virtual DOM, each value-bearing rendered view registers a
// binding record { getValue, setValue } keyed by viewID. Programmatic
// setElementValue calls update the DOM directly through the binding; reads go
// through the binding so they always reflect live UI state.
//
// Element **states** (the Apple ViewModel.states dictionary — named keys like
// DisclosureGroup's "isExpanded", as opposed to the single element value) work
// the same way: a state-bearing view registers a { getState(key),
// setState(key, value) } record, with a per-view key/value map as the fallback
// for unbound keys.
//
// Runtime structural mutations (insertElement / insertRow / removeElement) follow
// the same binding pattern: a container view registers a **container binding**
// per insertable container (see Helpers/InsertionHelper.js), and the model
// orchestrates parse -> id-conflict check -> build -> place, delegating the DOM
// placement to that binding. The built DOM is the effective tree, so there is no
// separate element-graph merge (the Apple/Android dynamicSubviews step): the
// query `[data-aui-id]` *is* the id registry for conflict checks and cascade
// cleanup. See ActionUIInsertion.js for the vocabulary + pure resolvers.

import {
    ContainerShape,
    InsertError,
    InsertPosition,
    collectElementIds,
    resolveContainer,
    resolveFlatIndex,
    resolveRowIndex,
} from "./ActionUIInsertion.js";
import { ActionUIElement } from "./ActionUIElement.js";
import { PlatformFilter } from "./PlatformFilter.js";
import { getInsertableContainers } from "./ActionUIRegistry.js";

export class ActionUIModel {
    constructor(windowUUID, logger) {
        this.windowUUID = windowUUID;
        this.logger = logger;
        this.values = new Map();        // viewID -> last known value (fallback when unbound)
        this.bindings = new Map();      // viewID -> { getValue(), setValue(value) }
        this.states = new Map();        // viewID -> { key: value } (fallback when unbound)
        this.stateBindings = new Map(); // viewID -> { getState(key), setState(key, value) }
        this.containerBindings = new Map(); // viewID -> { containerName: binding } (insertion)
        this.actionDispatcher = null;   // set by Application
        // Render context for runtime mutations — set once the window is presented.
        this.rootNode = null;           // the window's root DOM node (the id registry)
        this.buildFn = null;            // (element) => HTMLElement, the registry recursion
        this.rootElementId = null;      // guards against removing the root
    }

    // Wires the render context the insertion API needs: the root node (queried by
    // data-aui-id as the live id registry) and the build recursion used to render
    // inserted subtrees. Called by Window.present after the tree is built.
    setRenderContext(rootNode, buildFn, rootElementId) {
        this.rootNode = rootNode;
        this.buildFn = buildFn;
        this.rootElementId = rootElementId;
    }

    seedValue(viewID, value) {
        this.values.set(viewID, value);
    }

    bind(viewID, binding) {
        this.bindings.set(viewID, binding);
    }

    seedStates(viewID, states) {
        this.states.set(viewID, { ...states });
    }

    bindState(viewID, binding) {
        this.stateBindings.set(viewID, binding);
    }

    // The current state binding for a view (or undefined). Used by the presentation
    // modifiers (Helpers/PresentationModifier.js) to compose their visibility keys
    // on top of an element's own state binding without clobbering it.
    getStateBinding(viewID) {
        return this.stateBindings.get(viewID);
    }

    getElementValue(viewID, viewPartID = 0) {
        const binding = this.bindings.get(viewID);
        if (binding) return binding.getValue(viewPartID);
        if (this.values.has(viewID)) return this.values.get(viewID);
        this.logger.log(`getElementValue: no element with id ${viewID}`, "warning");
        return null;
    }

    setElementValue(viewID, viewPartID = 0, value) {
        this.values.set(viewID, value);
        const binding = this.bindings.get(viewID);
        if (binding) {
            binding.setValue(value, viewPartID);
        } else {
            this.logger.log(`setElementValue: no element with id ${viewID}`, "warning");
        }
    }

    getElementState(viewID, key) {
        const binding = this.stateBindings.get(viewID);
        if (binding) {
            const value = binding.getState(key);
            if (value !== undefined) return value;
        }
        const states = this.states.get(viewID);
        if (states && key in states) return states[key];
        this.logger.log(`getElementState: no state "${key}" on element ${viewID}`, "warning");
        return null;
    }

    setElementState(viewID, key, value) {
        const states = this.states.get(viewID) ?? {};
        states[key] = value;
        this.states.set(viewID, states);
        const binding = this.stateBindings.get(viewID);
        if (!binding) {
            this.logger.log(`setElementState: no element with id ${viewID}`, "warning");
            return;
        }
        binding.setState(key, value);
    }

    // User interaction entry point called by view implementations.
    // Mirrors the Swift action callback signature:
    // (actionID, windowUUID, viewID, viewPartID, context)
    dispatchAction(actionID, viewID, viewPartID = 0, context = null) {
        if (!actionID) return;
        this.actionDispatcher?.(actionID, this.windowUUID, viewID, viewPartID, context);
    }

    // ---- Runtime structural mutations (insertElement / insertRow / removeElement) ----

    // A container view registers one binding per insertable container at build
    // time. The binding shape (FLAT / ROWS) dictates which methods the model
    // calls; see Helpers/InsertionHelper.js for the two factory shapes.
    bindContainer(viewID, container, binding) {
        const map = this.containerBindings.get(viewID) ?? {};
        map[container] = binding;
        this.containerBindings.set(viewID, map);
    }

    // Inserts a new element into a flat container of `parentID`. `raw` is an
    // element object (or a JSON string of one). `container` may be null to
    // auto-derive the unique flat container. Returns the inserted element's id.
    insertElement(parentID, raw, container = null, position = InsertPosition.APPEND, positionParam = 0) {
        const { name, binding } = this.resolveParentContainer(parentID, ContainerShape.FLAT, container);
        const element = this.parseElementObject(raw);
        this.assertNoIdConflict(collectElementIds(element));
        const index = resolveFlatIndex(binding.childIds(), position, positionParam, name);
        // Most containers render a child as a built node placed in the DOM. The
        // interpretive containers (TabView tabs, Menu items) instead read the
        // element to synthesize their own structure (a tab strip + panel, a menu
        // item), so the model skips the default build and hands them the element;
        // they build what they need through their own closed-over render context.
        const node = binding.interpretive ? null : this.buildFn(element);
        binding.insert(node, element.id, index, element);
        this.logger.log(`insertElement: id ${element.id} into ${parentID}.${name} at index ${index}`, "info");
        return element.id;
    }

    // Inserts a row of cells into a rows-shaped container (Grid). `rawCells` is an
    // array of cell objects (or a JSON string of one). Rows have no addressable
    // identity, so before/after positions are rejected. Returns the cell ids.
    insertRow(parentID, rawCells, container = null, position = InsertPosition.APPEND, positionParam = 0) {
        const { name, binding } = this.resolveParentContainer(parentID, ContainerShape.ROWS, container);
        const cells = this.parseCellsArray(rawCells);
        const ids = new Set();
        for (const cell of cells) collectElementIds(cell, ids);
        this.assertNoIdConflict(ids);
        const index = resolveRowIndex(binding.rowCount(), position, positionParam, name);
        const cellNodes = cells.map((cell) => this.buildFn(cell));
        binding.insertRow(cellNodes, index);
        this.logger.log(`insertRow: ${cells.length} cells into ${parentID}.${name} at row ${index}`, "info");
        return cells.map((cell) => cell.id);
    }

    // Removes an element (and all its descendants) by viewID. Refuses to remove
    // the window root. Only members of a flat/rows container are removable -
    // single-element slots (content/sidebar/detail) are swapped, not removed.
    removeElement(viewID) {
        if (viewID === this.rootElementId) throw InsertError.rootRemovalForbidden(viewID);
        const node = this.findNode(viewID);
        if (!node) throw InsertError.viewNotFound(viewID);
        const owner = this.findOwningContainer(viewID, node);
        if (!owner) throw InsertError.notInRemovableContainer(viewID);

        const ids = this.collectMountedIds(viewID, node);
        if (owner.binding.shape === ContainerShape.ROWS) {
            owner.binding.removeCell(viewID, node);
        } else {
            owner.binding.remove(viewID);
        }
        for (const id of ids) this.cleanupElement(id);
        this.logger.log(`removeElement: id ${viewID} (cleaned ${ids.length} bound ids)`, "info");
    }

    // -- insertion internals --

    // Finds a mounted element node by id. querySelector only searches
    // descendants, so the root node (which can be an addressable container) is
    // matched explicitly.
    findNode(viewID) {
        if (!this.rootNode) return null;
        if (Number(this.rootNode.dataset.auiId) === viewID) return this.rootNode;
        return this.rootNode.querySelector(`[data-aui-id="${viewID}"]`);
    }

    // Locates the parent's declared container of the expected shape and its live
    // binding. Throws the appropriate InsertError when the parent is missing, not
    // a container, or the container is declared but not mounted on the web yet.
    resolveParentContainer(parentID, expectedShape, requestedContainer) {
        const parentNode = this.findNode(parentID);
        if (!parentNode) throw InsertError.parentNotFound(parentID);
        const type = parentNode.dataset.auiType;
        const containers = getInsertableContainers(type);
        if (!containers) throw InsertError.notAContainer(type);
        const name = resolveContainer(containers, requestedContainer, expectedShape);
        const binding = this.containerBindings.get(parentID)?.[name];
        if (!binding) throw InsertError.containerNotMounted(type, name);
        return { name, binding };
    }

    // Parses a single element from an object or JSON string, through the same
    // PlatformFilter + ActionUIElement.fromObject the window root uses.
    parseElementObject(raw) {
        const obj = this.coerceJSON(raw);
        if (typeof obj !== "object" || obj === null || Array.isArray(obj)) {
            throw InsertError.missingType();
        }
        const normalized = PlatformFilter.WEB.withLogger(this.logger).filter(obj);
        const element = ActionUIElement.fromObject(normalized, this.logger);
        if (!element) throw InsertError.missingType();
        return element;
    }

    // Parses an array of cells from an array or a JSON string of an array.
    parseCellsArray(raw) {
        const arr = this.coerceJSON(raw);
        if (!Array.isArray(arr)) throw InsertError.invalidJSON("Expected an array of cell objects");
        return arr.map((cell) => {
            const normalized = PlatformFilter.WEB.withLogger(this.logger).filter(cell);
            const element = ActionUIElement.fromObject(normalized, this.logger);
            if (!element) throw InsertError.missingType();
            return element;
        });
    }

    coerceJSON(raw) {
        if (typeof raw !== "string") return raw;
        try {
            return JSON.parse(raw);
        } catch (error) {
            throw InsertError.invalidJSON(error.message);
        }
    }

    // Throws idConflict if any of `ids` is already mounted in the live tree.
    assertNoIdConflict(ids) {
        const conflicts = [];
        for (const id of ids) {
            if (this.findNode(id)) conflicts.push(id);
        }
        if (conflicts.length > 0) throw InsertError.idConflict(conflicts.sort((a, b) => a - b));
    }

    // Finds the container binding that holds `viewID` as a direct member. Flat
    // containers match by child id; rows containers match by cell node identity.
    findOwningContainer(viewID, node) {
        for (const [parentID, map] of this.containerBindings) {
            for (const binding of Object.values(map)) {
                if (binding.shape === ContainerShape.ROWS) {
                    if (binding.ownsCell(node)) return { parentID, binding };
                } else if (binding.childIds().includes(viewID)) {
                    return { parentID, binding };
                }
            }
        }
        return null;
    }

    // The host-addressable ids within a subtree (the node itself + every
    // descendant carrying a data-aui-id) - the set to purge from the model maps.
    collectMountedIds(viewID, node) {
        const ids = [viewID];
        node.querySelectorAll("[data-aui-id]").forEach((el) => {
            const id = Number(el.dataset.auiId);
            if (Number.isInteger(id)) ids.push(id);
        });
        return ids;
    }

    // Drops every binding/value/state record for a removed element id.
    cleanupElement(id) {
        this.values.delete(id);
        this.bindings.delete(id);
        this.states.delete(id);
        this.stateBindings.delete(id);
        this.containerBindings.delete(id);
    }
}
