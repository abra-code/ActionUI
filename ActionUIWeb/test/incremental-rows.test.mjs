// Tests for Tier 2 incremental rows: the common-prefix diff (src/Helpers/RowDiff.js)
// and its two consumers - the template repeater (Helpers/TemplateHelper.renderTemplateRows,
// used by the Lazy stacks/grids) and List's selectable data rows (Views/List.js
// buildDataRows). The rows API re-sends the whole array on append, so the diff must
// keep the unchanged prefix nodes in place (and, for List, the selection) and build
// only the new tail. These assert DOM/node identity and the row count the diff
// produces; pixel layout is a browser concern the headless stub does not model.

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeLogger } from "./dom-stub.mjs";
import { rowsEqual, commonRowPrefix } from "../src/Helpers/RowDiff.js";

let buildElementView, ActionUIModel, ActionUIElement;

before(async () => {
    installDom();
    await import("../src/ActionUI.js"); // registers every view as a side effect
    ({ buildElementView } = await import("../src/Common/ActionUIRegistry.js"));
    ({ ActionUIModel } = await import("../src/Common/ActionUIModel.js"));
    ({ ActionUIElement } = await import("../src/Common/ActionUIElement.js"));
});

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

// Builds an element to its DOM through the full registry path; returns the model
// (with dispatchAction stubbed to a recorder) and the located inner node.
function build(raw, innerClass) {
    const logger = makeLogger();
    const model = new ActionUIModel("", logger);
    const dispatched = [];
    model.dispatchAction = (id, viewID, idx, context) => dispatched.push({ id, viewID, idx, context });
    const element = ActionUIElement.fromObject(raw, logger);
    const ctx = { model, windowUUID: "", logger, build: (child) => buildElementView(child, ctx) };
    const root = buildElementView(element, ctx);
    return { model, dispatched, inner: findByClass(root, innerClass) };
}

const TEXT_TEMPLATE = { type: "Text", properties: { text: "$1" } };

// ---- RowDiff (pure) ----

test("commonRowPrefix: an append keeps the whole old prefix", () => {
    assert.equal(commonRowPrefix([["a"], ["b"]], [["a"], ["b"], ["c"]]), 2);
});
test("commonRowPrefix: a mid-list edit stops at the first change", () => {
    assert.equal(commonRowPrefix([["a"], ["b"], ["c"]], [["a"], ["x"], ["c"]]), 1);
});
test("commonRowPrefix: a truncation keeps the surviving prefix", () => {
    assert.equal(commonRowPrefix([["a"], ["b"], ["c"]], [["a"]]), 1);
});
test("rowsEqual: shallow per-column compare", () => {
    assert.ok(rowsEqual(["a", "b"], ["a", "b"]));
    assert.ok(!rowsEqual(["a"], ["a", "b"]));
    assert.ok(!rowsEqual(["a", "b"], ["a", "c"]));
});

// ---- LazyVStack template repeater ----

test("LazyVStack template: append builds only the new tail (prefix reused)", () => {
    const { model, inner } = build(
        { type: "LazyVStack", id: 200, properties: {}, template: TEXT_TEMPLATE }, "aui-lazyvstack");
    model.setElementState(200, "content", [["a"], ["b"]]);
    assert.equal(inner.children.length, 2);
    const firstBefore = inner.children[0];
    model.setElementState(200, "content", [["a"], ["b"], ["c"]]);
    assert.equal(inner.children.length, 3);
    assert.equal(inner.children[0], firstBefore, "the unchanged prefix instance was not rebuilt");
});

test("LazyVStack template: truncation drops the tail", () => {
    const { model, inner } = build(
        { type: "LazyVStack", id: 201, properties: {}, template: TEXT_TEMPLATE }, "aui-lazyvstack");
    model.setElementState(201, "content", [["a"], ["b"], ["c"]]);
    model.setElementState(201, "content", [["a"]]);
    assert.equal(inner.children.length, 1);
});

test("LazyVStack template: a mid-list edit rebuilds from the change, keeps the prefix", () => {
    const { model, inner } = build(
        { type: "LazyVStack", id: 202, properties: {}, template: TEXT_TEMPLATE }, "aui-lazyvstack");
    model.setElementState(202, "content", [["a"], ["b"], ["c"]]);
    const firstBefore = inner.children[0];
    const secondBefore = inner.children[1];
    model.setElementState(202, "content", [["a"], ["x"], ["c"]]);
    assert.equal(inner.children.length, 3);
    assert.equal(inner.children[0], firstBefore, "row 0 unchanged -> reused");
    assert.notEqual(inner.children[1], secondBefore, "row 1 changed -> rebuilt");
});

// ---- List selectable data rows ----

function buildList(id) {
    return build({ type: "List", id, properties: { actionID: "pick" }, template: TEXT_TEMPLATE }, "aui-list");
}

test("List data rows: append preserves the prefix node identity and the selection", () => {
    const { model, inner } = buildList(210);
    model.setElementState(210, "content", [["a"], ["b"]]);
    const row0 = inner.children[0];
    row0.fire("click"); // selects "a" (stub node has no closest(), so the guard passes)
    assert.ok(row0.classList.contains("aui-list-row-selected"), "row 0 is selected after the click");
    model.setElementState(210, "content", [["a"], ["b"], ["c"]]);
    assert.equal(inner.children.length, 3);
    assert.equal(inner.children[0], row0, "the prefix row node was reused");
    assert.ok(row0.classList.contains("aui-list-row-selected"), "the selection survived the append");
});

test("List data rows: a truncation that drops the selected row clears the selection", () => {
    const { model, inner } = buildList(211);
    model.setElementState(211, "content", [["a"], ["b"], ["c"]]);
    inner.children[2].fire("click"); // selects "c"
    assert.ok(inner.children[2].classList.contains("aui-list-row-selected"));
    model.setElementState(211, "content", [["a"]]); // "c" is gone
    assert.equal(inner.children.length, 1);
    assert.ok(!inner.children[0].classList.contains("aui-list-row-selected"), "selection cleared (its row is gone)");
});

// ---- Table data rows (<tbody>) ----

// Table builds a <table> inside the .aui-table-scroll wrapper; the data rows are
// <tr> in <tbody>. Selection is index-based (selectedIndex) and the click handler
// takes no event arg, so a bare fire("click") selects the row.
function buildTable(id) {
    const logger = makeLogger();
    const model = new ActionUIModel("", logger);
    model.dispatchAction = () => {};
    const raw = { type: "Table", id, properties: { columns: ["A", "B"], widths: [80, 80], actionID: "pick" } };
    const element = ActionUIElement.fromObject(raw, logger);
    const ctx = { model, windowUUID: "", logger, build: (child) => buildElementView(child, ctx) };
    const root = buildElementView(element, ctx);
    const table = findByClass(root, "aui-table-scroll").children.find((c) => c.tagName === "TABLE");
    const tbody = table.children.find((c) => c.tagName === "TBODY");
    return { model, tbody };
}

test("Table data rows: append preserves the prefix <tr> identity and the selection", () => {
    const { model, tbody } = buildTable(220);
    model.setElementState(220, "content", [["a", "1"], ["b", "2"]]);
    const row0 = tbody.children[0];
    row0.fire("click"); // selects index 0
    assert.ok(row0.classList.contains("aui-table-row-selected"), "row 0 selected after the click");
    model.setElementState(220, "content", [["a", "1"], ["b", "2"], ["c", "3"]]);
    assert.equal(tbody.children.length, 3);
    assert.equal(tbody.children[0], row0, "the prefix <tr> was reused");
    assert.ok(row0.classList.contains("aui-table-row-selected"), "the selection survived the append");
});

test("Table data rows: a truncation that drops the selected row clears the selection", () => {
    const { model, tbody } = buildTable(221);
    model.setElementState(221, "content", [["a", "1"], ["b", "2"], ["c", "3"]]);
    tbody.children[2].fire("click"); // selects index 2
    assert.ok(tbody.children[2].classList.contains("aui-table-row-selected"));
    model.setElementState(221, "content", [["a", "1"]]); // index 2 is gone
    assert.equal(tbody.children.length, 1);
    assert.ok(!tbody.children[0].classList.contains("aui-table-row-selected"), "selection cleared (its row is gone)");
});
