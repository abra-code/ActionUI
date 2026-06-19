// Tests for arrow-key row selection (the listbox/grid keyboard pattern) across the
// selectable row containers: the pure mover (src/Helpers/RowKeyboardNav.js) and its
// four consumers - List data rows, List children rows, NavigationSplitView sidebar,
// and Table. Without this, a focused row's ArrowDown falls through to the scroll
// ancestor (the reported "scroller captures the arrow key"); with it, Down/Up move
// selection+focus to the adjacent row and suppress the scroll. These assert the
// selection moved, focus moved (document.activeElement, via the stub), and that the
// key's default was prevented.

import { test, before, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeLogger } from "./dom-stub.mjs";
import { navigateRowsOnKey } from "../src/Helpers/RowKeyboardNav.js";

let buildElementView, ActionUIModel, ActionUIElement, dom;

before(async () => {
    dom = installDom();
    await import("../src/ActionUI.js");
    ({ buildElementView } = await import("../src/Common/ActionUIRegistry.js"));
    ({ ActionUIModel } = await import("../src/Common/ActionUIModel.js"));
    ({ ActionUIElement } = await import("../src/Common/ActionUIElement.js"));
});
beforeEach(() => { dom = installDom(); }); // reset focus tracking per test

function hasClass(node, cls) {
    const cn = node?.className;
    if (typeof cn === "string" && cn.split(/\s+/).includes(cls)) return true;
    return !!node?.classList?.contains?.(cls);
}
function findByClass(node, cls) {
    if (hasClass(node, cls)) return node;
    for (const child of node?.children ?? []) {
        const hit = findByClass(child, cls);
        if (hit) return hit;
    }
    return null;
}
function findAllByClass(node, cls, out = []) {
    if (hasClass(node, cls)) out.push(node);
    for (const child of node?.children ?? []) findAllByClass(child, cls, out);
    return out;
}
function build(raw, innerClass) {
    const logger = makeLogger();
    const model = new ActionUIModel("", logger);
    model.dispatchAction = () => {};
    const element = ActionUIElement.fromObject(raw, logger);
    const ctx = { model, windowUUID: "", logger, build: (child) => buildElementView(child, ctx) };
    const root = buildElementView(element, ctx);
    return { model, inner: findByClass(root, innerClass) };
}
// Fires a keydown carrying a preventDefault spy (the handlers call it); returns
// whether default was prevented.
function fireKey(node, key) {
    let prevented = false;
    node.fire("keydown", { key, preventDefault() { prevented = true; } });
    return prevented;
}

// ---- the pure mover ----

function fakeEvent(key) {
    return { key, prevented: false, preventDefault() { this.prevented = true; } };
}

test("navigateRowsOnKey: ArrowDown -> next, ArrowUp -> prev, clamped at the edges", () => {
    let moved;
    const run = (key, index, count) => { moved = -1; const ev = fakeEvent(key); const h = navigateRowsOnKey(ev, index, count, (t) => { moved = t; }); return { h, ev }; };
    assert.deepEqual([run("ArrowDown", 0, 3).h, moved], [true, 1]);
    assert.deepEqual([run("ArrowUp", 2, 3).h, moved], [true, 1]);
    run("ArrowDown", 2, 3); assert.equal(moved, -1, "ArrowDown at the last row does not move");
    run("ArrowUp", 0, 3); assert.equal(moved, -1, "ArrowUp at the first row does not move");
});

test("navigateRowsOnKey: Home -> first, End -> last", () => {
    let moved;
    const ev1 = fakeEvent("Home"); navigateRowsOnKey(ev1, 2, 3, (t) => { moved = t; }); assert.equal(moved, 0);
    const ev2 = fakeEvent("End"); navigateRowsOnKey(ev2, 0, 3, (t) => { moved = t; }); assert.equal(moved, 2);
});

test("navigateRowsOnKey: prevents default on a handled key, ignores other keys", () => {
    const down = fakeEvent("ArrowDown");
    assert.equal(navigateRowsOnKey(down, 0, 3, () => {}), true);
    assert.ok(down.prevented, "the scroll-causing default is suppressed");
    const other = fakeEvent("a");
    assert.equal(navigateRowsOnKey(other, 0, 3, () => {}), false);
    assert.equal(other.prevented, false, "a non-navigation key is left alone");
});

test("navigateRowsOnKey: an empty list is a no-op", () => {
    assert.equal(navigateRowsOnKey(fakeEvent("ArrowDown"), 0, 0, () => {}), false);
});

// ---- List (data-driven rows) ----

test("List data rows: ArrowDown moves selection+focus to the next row", () => {
    const { model, inner } = build(
        { type: "List", id: 300, properties: { actionID: "pick" }, template: { type: "Text", properties: { text: "$1" } } },
        "aui-list");
    model.setElementState(300, "content", [["a"], ["b"], ["c"]]);
    const rows = findAllByClass(inner, "aui-list-row");
    fireKey(rows[0], "Enter"); // select row 0 (also exercises the Enter branch)
    assert.ok(rows[0].classList.contains("aui-list-row-selected"));
    const prevented = fireKey(rows[0], "ArrowDown");
    assert.ok(prevented, "ArrowDown is consumed (no parent scroll)");
    assert.ok(rows[1].classList.contains("aui-list-row-selected"), "selection moved to row 1");
    assert.ok(!rows[0].classList.contains("aui-list-row-selected"), "row 0 deselected");
    assert.equal(dom.document.activeElement, rows[1], "focus moved to row 1");
});

// ---- List (heterogeneous children rows) ----

test("List children rows: ArrowDown moves selection+focus to the next row", () => {
    const { inner } = build(
        { type: "List", id: 301, properties: { actionID: "pick" }, children: [
            { type: "Text", id: 90, properties: { text: "A" } },
            { type: "Text", id: 91, properties: { text: "B" } },
        ] }, "aui-list");
    const rows = findAllByClass(inner, "aui-list-row");
    rows[0].fire("click"); // select row 0 (children rows select by id)
    fireKey(rows[0], "ArrowDown");
    assert.ok(rows[1].classList.contains("aui-list-row-selected"), "selection moved to row 1");
    assert.equal(dom.document.activeElement, rows[1], "focus moved to row 1");
});

// ---- NavigationSplitView sidebar ----

test("NavigationSplitView sidebar: ArrowDown moves the destination selection+focus", () => {
    const { model, inner } = build({
        type: "NavigationSplitView", id: 302, properties: {},
        sidebar: { type: "List", id: 303, properties: { actionID: "pick" }, children: [
            { type: "Label", id: 70, properties: { title: "A", destinationViewId: 80 } },
            { type: "Label", id: 71, properties: { title: "B", destinationViewId: 81 } },
        ] },
        detail: { type: "Text", properties: { text: "d" } },
        destinations: [
            { type: "Text", id: 80, properties: { text: "A" } },
            { type: "Text", id: 81, properties: { text: "B" } },
        ],
    }, "aui-nav-split");
    const rows = findAllByClass(inner, "aui-nav-split-row").filter((r) => r.dataset.auiDestId);
    rows[0].fire("click");
    assert.equal(model.getElementState(302, "selectedDestination"), 80);
    fireKey(rows[0], "ArrowDown");
    assert.equal(model.getElementState(302, "selectedDestination"), 81, "selection moved to the next destination");
    assert.equal(dom.document.activeElement, rows[1], "focus moved to the next sidebar row");
});

// ---- Table ----

test("Table: ArrowDown moves the row selection+focus (rows are now focusable)", () => {
    const { model, inner } = build(
        { type: "Table", id: 304, properties: { columns: ["A", "B"], widths: [80, 80], actionID: "pick" } },
        "aui-table-scroll");
    model.setElementState(304, "content", [["a", "1"], ["b", "2"], ["c", "3"]]);
    const table = inner.children.find((c) => c.tagName === "TABLE");
    const tbody = table.children.find((c) => c.tagName === "TBODY");
    tbody.children[0].fire("click");
    assert.ok(tbody.children[0].classList.contains("aui-table-row-selected"));
    const prevented = fireKey(tbody.children[0], "ArrowDown");
    assert.ok(prevented, "ArrowDown is consumed (no scroll-wrapper scroll)");
    assert.ok(tbody.children[1].classList.contains("aui-table-row-selected"), "selection moved to row 1");
    assert.equal(dom.document.activeElement, tbody.children[1], "focus moved to row 1");
});
