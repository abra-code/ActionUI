// InsertionHelper.js — container bindings for the runtime insertion API.
// No Apple/Android analog (the web has no virtual DOM): on the web a container
// view exposes, at build time, *how* to place and remove a child in its own DOM,
// the same way a value-bearing view exposes get/setValue. The model
// (ActionUIModel.insertElement / insertRow / removeElement) builds the new
// subtree and resolves the index, then hands placement to one of these bindings.
//
// Two shapes mirror ActionUIInsertion.ContainerShape:
//   FLAT  — an ordered list of child element nodes (stacks, Form, Section, List).
//   ROWS  — a 2-D grid of cells laid out by explicit grid-row/column (Grid).

import { ContainerShape } from "../Common/ActionUIInsertion.js";

// A flat-container binding over `mount`, whose tracked children are direct DOM
// children placed in order. `initialSlots` are the children already built by the
// view ([{ id, dom }] - `dom` is the node actually in `mount`, e.g. a List row
// wrapper). Options:
//   wrap(childNode, id) -> domNode  wraps a built child before insertion (List).
//   prepare(childNode)              mutates the built child in place (ZStack's
//                                   per-child place-self).
// The binding is the source of truth for child order, so before/after-sibling
// and at-index positions resolve against `childIds()` and insertions land at the
// right DOM offset even when the mount also holds non-child nodes (a Section
// header, a GroupBox title): we always insertBefore a *tracked* slot, and append
// past the last tracked slot lands at the end of the mount.
export function flatContainerBinding(mount, initialSlots, options = {}) {
    const slots = [...initialSlots]; // [{ id, dom }] in document order
    return {
        shape: ContainerShape.FLAT,
        childIds() {
            return slots.map((slot) => slot.id);
        },
        insert(childNode, id, index) {
            if (options.prepare) options.prepare(childNode);
            const dom = options.wrap ? options.wrap(childNode, id) : childNode;
            const ref = slots[index]?.dom ?? null; // null => append to end of mount
            mount.insertBefore(dom, ref);
            slots.splice(index, 0, { id, dom });
        },
        remove(id) {
            const i = slots.findIndex((slot) => slot.id === id);
            if (i < 0) return false;
            slots[i].dom.remove();
            slots.splice(i, 1);
            return true;
        },
    };
}

// Builds a flat container's children directly into `mount`, then registers its
// binding - the one-liner for the simple direct-child containers (the stacks,
// the lazy grids, Form, GroupBox, Section). `options` are passed through to
// flatContainerBinding (e.g. ZStack's `prepare`). The `container` name defaults
// to "children".
export function buildFlatChildren(mount, element, ctx, options = {}) {
    const slots = [];
    for (const child of element.children()) {
        const childNode = ctx.build(child);
        if (options.prepare) options.prepare(childNode);
        mount.appendChild(childNode);
        slots.push({ id: child.id, dom: childNode });
    }
    if (element.id > 0) {
        ctx.model.bindContainer(element.id, options.container ?? "children",
            flatContainerBinding(mount, slots, options));
    }
}

// An interpretive flat-container binding: the container synthesizes its own
// structure from the inserted *element* (a TabView tab -> strip button + panel, a
// Menu child -> an item), rather than placing a pre-built node, so the model skips
// the default build (binding.interpretive) and passes the element to `insert`. The
// view supplies the placement and removal it needs; this only tracks child-id
// order so childIds()/before-after positioning and removal resolve.
//   insertChild(element, id, index)  builds + places the view's structure for the
//                                    child at `index` (tagging its primary node
//                                    data-aui-id=id so removeElement can find it).
//   removeChild(id)                  tears that structure down.
export function interpretiveFlatBinding(insertChild, removeChild, initialIds = []) {
    const ids = [...initialIds];
    return {
        shape: ContainerShape.FLAT,
        interpretive: true,
        childIds() {
            return [...ids];
        },
        insert(_node, id, index, element) {
            insertChild(element, id, index);
            ids.splice(index, 0, id);
        },
        remove(id) {
            const i = ids.indexOf(id);
            if (i < 0) return false;
            removeChild(id);
            ids.splice(i, 1);
            return true;
        },
    };
}

// A rows-container binding over a Grid `node` (display:grid). Cells are placed by
// explicit grid-row/grid-column so columns line up across uneven rows (CSS
// auto-placement would backfill short rows into the gaps); inserting/removing a
// cell therefore reflows the explicit coordinates. `initialRows` is [[cellNode]]
// in row-major order. Only whole-row insertion is supported (insertRow); single
// cells are addressable for removal (a Grid row has no synthetic id), mirroring
// the Swift note - removing a cell removes only that cell.
export function gridRowsBinding(node, initialRows) {
    const rows = initialRows.map((row) => [...row]); // [[cellNode]]
    const reflow = () => {
        rows.forEach((row, r) => {
            row.forEach((cell, c) => {
                cell.style.gridRow = String(r + 1);
                cell.style.gridColumn = String(c + 1);
            });
        });
    };
    return {
        shape: ContainerShape.ROWS,
        rowCount() {
            return rows.length;
        },
        insertRow(cellNodes, index) {
            cellNodes.forEach((cell) => node.appendChild(cell)); // reflow sets coordinates
            rows.splice(index, 0, [...cellNodes]);
            reflow();
        },
        ownsCell(cellNode) {
            return rows.some((row) => row.includes(cellNode));
        },
        removeCell(_id, cellNode) {
            for (const row of rows) {
                const c = row.indexOf(cellNode);
                if (c >= 0) {
                    row.splice(c, 1);
                    cellNode.remove();
                    reflow();
                    return true;
                }
            }
            return false;
        },
    };
}
