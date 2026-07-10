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
import { applyElementProperty } from "./ModifierResolver.js";
import { playEnterTransition } from "../Helpers/TransitionModifier.js";

export class ActionUIModel {
    constructor(windowUUID, logger) {
        this.windowUUID = windowUUID;
        this.logger = logger;
        this.values = new Map();        // viewID -> last known value (fallback when unbound)
        this.bindings = new Map();      // viewID -> { getValue(), setValue(value) }
        this.states = new Map();        // viewID -> { key: value } (fallback when unbound)
        this.stateBindings = new Map(); // viewID -> { getState(key), setState(key, value) }
        this.containerBindings = new Map(); // viewID -> { containerName: binding } (insertion)
        this.propertyOverrides = new Map(); // viewID -> { propertyName: value } (setElementProperty)
        this.refreshes = new Map();     // viewID -> { subtreeIds: Set, onEnd, timeout } (pull-to-refresh)
        this.actionDispatcher = null;   // set by Application
        // Render context for runtime mutations — set once the window is presented.
        this.rootNode = null;           // the window's root DOM node (the id registry)
        this.buildFn = null;            // (element) => HTMLElement, the registry recursion
        this.rootElementId = null;      // guards against removing the root
        // Pull-to-refresh safety net (ms): a refresh whose client never signals
        // completion ends after this delay so the indicator cannot hang. Mirrors
        // Swift's `refreshTimeoutSeconds` / Android's `refreshTimeoutMillis`; a
        // mutable field only so tests can lower it (production never changes it).
        this.refreshTimeoutMs = 60000;
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
        this.endRefreshTargeting(viewID); // a value delivered to a refreshing view (or descendant) ends its pull
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
        if (binding) {
            binding.setState(key, value);
        } else {
            this.logger.log(`setElementState: no element with id ${viewID}`, "warning");
        }
        this.endRefreshTargeting(viewID); // fresh rows/state delivered to a refreshing view (or descendant) ends its pull
    }

    // Runtime property mutation: applies [propertyName]=[value] to the mounted node
    // for [viewID] (web analog of the Swift/Kotlin setElementProperty). Web has no
    // reactive re-render, so this mutates the live node directly via the surgical
    // per-property appliers (ModifierResolver.applyElementProperty) - only the
    // animatable / host-driven *visual* View properties (opacity, hidden,
    // cornerRadius, foregroundStyle, background, disabled, help); an
    // unsupported name warns and is a no-op. Same-node by design, so it does not
    // disturb input focus/scroll and a future `animation` transition can ease it.
    // The override is recorded per id (cleared on removeElement).
    setElementProperty(viewID, propertyName, value) {
        const node = this.findNode(viewID);
        if (!node) {
            this.logger.log(`setElementProperty: no element with id ${viewID}`, "warning");
            return;
        }
        if (applyElementProperty(node, propertyName, value, this.logger)) {
            const overrides = this.propertyOverrides.get(viewID) ?? {};
            overrides[propertyName] = value;
            this.propertyOverrides.set(viewID, overrides);
        }
    }

    // ---- Element selection API (Table / List) ----
    //
    // Programmatic row selection for content-backed Table and List elements.
    // Web analog of ActionUIModel.swift's selection API. On the web the selection
    // rides as the element **value** — the selected row's columns tab-joined ("" =
    // nothing selected; see Views/List.js / Views/Table.js) — and the rows live in
    // the "content" state. So these read the rows, then write the selection through
    // the value binding, which is silent: like Apple, programmatic selection does
    // NOT fire the element's actionID (no selection-changed feedback loop). Read the
    // result back with getElementValue. They apply to Table and the data-driven List
    // modes (itemType / template); a heterogeneous-children List has no row content,
    // so its selection is by child id and these are a no-op there.

    // The [[String]] content rows of a content-backed Table/List, or null when the
    // view is not one (mirrors Swift's `states["content"] as? [[String]]` guard).
    elementContentRows(viewID) {
        const binding = this.stateBindings.get(viewID);
        if (binding) {
            const rows = binding.getState("content");
            if (Array.isArray(rows)) return rows;
        }
        const states = this.states.get(viewID);
        if (states && Array.isArray(states.content)) return states.content;
        return null;
    }

    // Selects a row by its 0-based index in the element's content rows. An index
    // outside 0..<rowCount clears the selection. Returns the selected row's column
    // values, or null (not a Table/List, or the index was out of range).
    selectElementRow(viewID, index) {
        const content = this.elementContentRows(viewID);
        if (content === null) {
            this.logger.log(`selectElementRow: element ${viewID} is not a Table/List (no row content)`, "warning");
            return null;
        }
        if (!Number.isInteger(index) || index < 0 || index >= content.length) {
            this.logger.log(`selectElementRow: index ${index} out of range (0..<${content.length}) for element ${viewID}; clearing selection`, "debug");
            this.clearElementSelection(viewID);
            return null;
        }
        const rowValues = content[index];
        this.setElementValue(viewID, 0, rowValues.join("\t")); // silent: no actionID dispatch
        this.logger.log(`Selected row ${index} for element ${viewID}`, "debug");
        return rowValues;
    }

    // Selects the first row whose column value equals `text` (exact, case-sensitive).
    // `column` < 0 (or null) matches ANY column; otherwise the given 0-based column
    // only. Returns the 0-based matched index, or -1 if no row matched (selection
    // unchanged).
    selectElementRowWithContent(viewID, text, column = -1) {
        const content = this.elementContentRows(viewID);
        if (content === null) {
            this.logger.log(`selectElementRowWithContent: element ${viewID} is not a Table/List (no row content)`, "warning");
            return -1;
        }
        const col = column == null ? -1 : column;
        const index = content.findIndex((row) =>
            col >= 0 ? (col < row.length && row[col] === text) : row.includes(text));
        if (index < 0) {
            this.logger.log(`selectElementRowWithContent: no row matches "${text}"${col >= 0 ? ` in column ${col}` : ""} for element ${viewID}`, "debug");
            return -1;
        }
        this.selectElementRow(viewID, index);
        return index;
    }

    // Clears the current selection of a Table/List (no-op if nothing is selected).
    clearElementSelection(viewID) {
        const content = this.elementContentRows(viewID);
        if (content === null) {
            this.logger.log(`clearElementSelection: element ${viewID} is not a Table/List`, "warning");
            return;
        }
        if (this.getElementValue(viewID) === "") return; // already cleared
        this.setElementValue(viewID, 0, ""); // silent
        this.logger.log(`Cleared selection for element ${viewID}`, "debug");
    }

    // User interaction entry point called by view implementations.
    // Mirrors the Swift action callback signature:
    // (actionID, windowUUID, viewID, viewPartID, context)
    dispatchAction(actionID, viewID, viewPartID = 0, context = null) {
        if (!actionID) return;
        this.actionDispatcher?.(actionID, this.windowUUID, viewID, viewPartID, context);
    }

    // ---- Pull-to-refresh ----
    //
    // Web analog of Swift's `ActionUIModel.runRefresh` + Android's `beginRefresh`.
    // The scrollable view (List / ScrollView, see Helpers/PullToRefreshHelper.js)
    // owns the indicator DOM and the pull gesture; the model owns the *lifecycle*.
    // On a pull, the view calls beginRefresh with an `onEnd` that retracts its
    // indicator; the model captures the view's subtree and fires the actionID. The
    // refresh ends — onEnd runs — when the client delivers data to this view or
    // anything inside it (any setElementValue/setElementState, which both call
    // endRefreshTargeting) or the safety timeout elapses. No dedicated "done" API,
    // matching Apple/Android: the client's natural response retracts the indicator.

    // Ids of the subtree rooted at viewID (itself + every mounted descendant), or
    // null if the view is not mounted. The DOM is the element tree on the web, so
    // this reads it directly (mirrors Swift/Android `WindowModel.subtreeIDs`). The
    // subtree is what makes ScrollView work: its content's id, not the container's
    // own, is the one a client mutates.
    subtreeIds(viewID) {
        const node = this.findNode(viewID);
        if (!node) return null;
        return new Set(this.collectMountedIds(viewID, node));
    }

    // Starts a refresh for viewID: captures its subtree, arms the safety timeout,
    // then fires the actionID. The timeout and action fire AFTER the record is
    // stored so a client that responds synchronously from its handler (calling
    // setElementValue/Rows inline) finds the in-flight record and ends it, rather
    // than the signal being missed. `onEnd` retracts the view's indicator.
    beginRefresh(viewID, actionID, onEnd) {
        this.endRefresh(viewID); // restart cleanly if one is somehow already in flight
        const subtreeIds = this.subtreeIds(viewID) ?? new Set([viewID]);
        const timeout = setTimeout(() => this.endRefreshTargeting(viewID), this.refreshTimeoutMs);
        if (timeout && typeof timeout.unref === "function") timeout.unref(); // do not keep Node alive (tests)
        this.refreshes.set(viewID, { subtreeIds, onEnd, timeout });
        this.dispatchAction(actionID, viewID, 0, null);
    }

    // Ends any in-flight refresh whose captured subtree includes viewID. Called from
    // the element-mutation APIs (setElementValue / setElementState) so the client's
    // natural response to a refresh retracts the indicator; the safety timeout calls
    // it with the refreshing view's own id. Idempotent.
    endRefreshTargeting(viewID) {
        if (this.refreshes.size === 0) return;
        const ending = [];
        for (const [refreshID, record] of this.refreshes) {
            if (record.subtreeIds.has(viewID)) ending.push(refreshID);
        }
        for (const refreshID of ending) this.endRefresh(refreshID);
    }

    // Ends the refresh rooted at refreshID: clears its timeout and runs its onEnd
    // (retracting the indicator). A no-op when none is in flight, so it is safe to
    // call from every mutation, the timeout, element cleanup, and dispose.
    endRefresh(refreshID) {
        const record = this.refreshes.get(refreshID);
        if (!record) return;
        this.refreshes.delete(refreshID);
        clearTimeout(record.timeout);
        record.onEnd?.();
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
        // The `transition` modifier: a freshly-inserted node plays its entrance (TransitionModifier.js).
        // Removal/exit is instant - the diff drops the node (documented divergence from Apple).
        if (node && element.properties?.transition != null) {
            playEnterTransition(node, element.properties.transition);
        }
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
        this.endRefresh(id); // clears any in-flight refresh timer rooted at this id
        this.values.delete(id);
        this.bindings.delete(id);
        this.states.delete(id);
        this.stateBindings.delete(id);
        this.containerBindings.delete(id);
        this.propertyOverrides.delete(id);
    }

    // Drops every binding/value/state/override and the render context, leaving the
    // model inert. Used when a window is closed (Window.dismiss / Application.
    // closeWindow): the model holds no DOM listeners itself (those live on the nodes
    // it built, removed with the root), so clearing its maps is the full teardown.
    dispose() {
        for (const record of this.refreshes.values()) clearTimeout(record.timeout);
        this.refreshes.clear();
        this.values.clear();
        this.bindings.clear();
        this.states.clear();
        this.stateBindings.clear();
        this.containerBindings.clear();
        this.propertyOverrides.clear();
        this.actionDispatcher = null;
        this.rootNode = null;
        this.buildFn = null;
        this.rootElementId = null;
    }
}
