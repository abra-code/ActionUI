// ActionUIInsertion.js — vocabulary + pure resolvers for runtime structural
// mutations (insertElement / insertRow / removeElement).
// Web analog of ActionUI/Common/ActionUIInsertion.swift.
//
// Containers declare which of their subview arrays accept runtime insertions via
// the construction's `insertableContainers` map (see ActionUIRegistry.js); the
// model orchestrates, delegating the actual DOM placement to a per-container
// binding the view registers at build time (see Helpers/InsertionHelper.js).
//
// The pure functions here (resolveContainer / resolveFlatIndex / resolveRowIndex
// / collectElementIds) hold no DOM or model state, so they are unit-testable in
// isolation. Errors are thrown as InsertError with messages mirroring the Swift
// InsertError.description cases (em dashes flattened to ASCII).

// Position to insert a new element (or row) within a container's existing array.
// Numeric values match the Node adapter's InsertPosition enum (ActionUINodeJS),
// so JSON / host code written against one runs against the other. before/after
// apply only to flat containers - rows have no addressable identity, so a rows
// container supports only append / prepend / at.
export const InsertPosition = Object.freeze({
    APPEND: 0,  // after the last existing child
    PREPEND: 1, // before the first existing child
    AT: 2,      // at a specific index           (positionParam = index)
    BEFORE: 3,  // before a sibling               (positionParam = sibling viewID; flat only)
    AFTER: 4,   // after a sibling                (positionParam = sibling viewID; flat only)
});

// Whether a container holds a flat array of elements (children / destinations /
// toolbar) or a 2-D array of element rows (Grid's `rows`).
export const ContainerShape = Object.freeze({
    FLAT: "flat",
    ROWS: "rows",
});

// Errors thrown by the insertion API. One class (greppable, `instanceof`-able)
// with named factories per Swift case; the messages match Swift verbatim where
// they were already ASCII, with em dashes flattened to " - ".
export class InsertError extends Error {
    constructor(message) {
        super(message);
        this.name = "InsertError";
    }
    static parentNotFound(parentID) {
        return new InsertError(`No element found with parentID ${parentID}`);
    }
    static notAContainer(type) {
        return new InsertError(`Element type '${type}' does not accept insertions (no insertableContainers declared)`);
    }
    static containerNotMounted(type, container) {
        return new InsertError(`Container '${container}' on element type '${type}' is declared insertable but not supported by the web renderer yet`);
    }
    static unknownContainer(container, valid) {
        return new InsertError(`Unknown container '${container}'. Valid containers: ${valid.join(", ")}`);
    }
    static containerRequired(valid) {
        return new InsertError(`container is required when the element exposes multiple containers: ${valid.join(", ")}`);
    }
    static wrongMethod(container, expectedShape, message) {
        return new InsertError(`Container '${container}' has shape ${expectedShape}; ${message}`);
    }
    static unsupportedPositionForRowContainer(container) {
        return new InsertError(`Row container '${container}' does not support before/after sibling positions; rows have no addressable identity`);
    }
    static positionOutOfBounds(index, count) {
        return new InsertError(`Position ${index} is out of bounds for container of size ${count}`);
    }
    static siblingNotFound(siblingID, container) {
        return new InsertError(`No element with id ${siblingID} found in container '${container}'`);
    }
    static idConflict(ids) {
        return new InsertError(`ID conflict - elements with these IDs are already registered: ${ids.join(", ")}`);
    }
    static invalidJSON(detail) {
        return new InsertError(`Invalid JSON: ${detail}`);
    }
    static missingType() {
        return new InsertError("Element dictionary missing 'type' key");
    }
    static rootRemovalForbidden(rootID) {
        return new InsertError(`Cannot remove root element (id ${rootID})`);
    }
    static viewNotFound(viewID) {
        return new InsertError(`No element found with viewID ${viewID}`);
    }
    static notInRemovableContainer(viewID) {
        return new InsertError(`viewID ${viewID} is not a member of a removable container (single-element slots like content/sidebar/detail are swapped, not removed)`);
    }
}

// Resolves which insertable container to use given the parent's declared
// containers and the requested name (or null), validating the shape matches the
// caller's method (flat for insertElement, rows for insertRow). Mirrors Swift's
// ActionUIModel.resolveContainer.
export function resolveContainer(containers, requested, expectedShape) {
    if (requested != null) {
        const shape = containers[requested];
        if (shape === undefined) {
            throw InsertError.unknownContainer(requested, Object.keys(containers).sort());
        }
        if (shape !== expectedShape) {
            const methodName = expectedShape === ContainerShape.FLAT ? "insertElement" : "insertRow";
            const altMethod = expectedShape === ContainerShape.FLAT ? "insertRow" : "insertElement";
            throw InsertError.wrongMethod(requested, shape,
                `${methodName} requires a ${expectedShape} container - use ${altMethod} for this container.`);
        }
        return requested;
    }
    // Auto-derive: the unique container matching the expected shape.
    const matching = Object.keys(containers).filter((key) => containers[key] === expectedShape);
    if (matching.length === 1) return matching[0];
    throw InsertError.containerRequired(matching.sort());
}

// Resolves a flat-container insertion index from a position + the current child
// ids (in document order). Mirrors Swift's resolveFlatIndex.
export function resolveFlatIndex(childIds, position, positionParam, container) {
    switch (position) {
        case InsertPosition.APPEND:
            return childIds.length;
        case InsertPosition.PREPEND:
            return 0;
        case InsertPosition.AT: {
            const i = positionParam;
            if (!Number.isInteger(i) || i < 0 || i > childIds.length) {
                throw InsertError.positionOutOfBounds(i, childIds.length);
            }
            return i;
        }
        case InsertPosition.BEFORE: {
            const idx = childIds.indexOf(positionParam);
            if (idx < 0) throw InsertError.siblingNotFound(positionParam, container);
            return idx;
        }
        case InsertPosition.AFTER: {
            const idx = childIds.indexOf(positionParam);
            if (idx < 0) throw InsertError.siblingNotFound(positionParam, container);
            return idx + 1;
        }
        default:
            throw InsertError.positionOutOfBounds(position, childIds.length);
    }
}

// Resolves a rows-container insertion index. before/after are rejected (rows
// have no synthetic identity). Mirrors Swift's resolveRowIndex.
export function resolveRowIndex(rowCount, position, positionParam, container) {
    switch (position) {
        case InsertPosition.APPEND:
            return rowCount;
        case InsertPosition.PREPEND:
            return 0;
        case InsertPosition.AT: {
            const i = positionParam;
            if (!Number.isInteger(i) || i < 0 || i > rowCount) {
                throw InsertError.positionOutOfBounds(i, rowCount);
            }
            return i;
        }
        default:
            throw InsertError.unsupportedPositionForRowContainer(container);
    }
}

// Collects the positive (host-addressable) ids declared anywhere in a freshly
// parsed element subtree - used for the insert-time id-conflict check. Negative
// (auto-assigned) ids never collide, so they are skipped. Duck-types element
// nodes (id/type/subviews) to avoid an import cycle with ActionUIElement.
export function collectElementIds(element, acc = new Set()) {
    if (!element || typeof element !== "object") return acc;
    if (Number.isInteger(element.id) && element.id > 0) acc.add(element.id);
    const subviews = element.subviews;
    if (subviews && typeof subviews === "object") {
        for (const value of Object.values(subviews)) {
            if (Array.isArray(value)) {
                for (const item of value) {
                    if (Array.isArray(item)) {
                        for (const cell of item) collectElementIds(cell, acc);
                    } else {
                        collectElementIds(item, acc);
                    }
                }
            } else {
                collectElementIds(value, acc);
            }
        }
    }
    return acc;
}
