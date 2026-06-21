// Tests for the :web stackedCards opt-in (src/Views/Table.js): on a phone the rows
// render as label:value cards instead of a horizontal table. The CSS does the visual
// transform; these pin the hooks it needs - the .aui-table-stackable class on the
// scroll wrapper and each cell's data-label (its column name) - plus the validation.
// The pixel transform is a browser/CSS concern, not under the headless suite.

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeLogger } from "./dom-stub.mjs";

let buildElementView, getConstruction, ActionUIModel, ActionUIElement;

before(async () => {
    installDom();
    await import("../src/ActionUI.js");
    ({ buildElementView, getConstruction } = await import("../src/Common/ActionUIRegistry.js"));
    ({ ActionUIModel } = await import("../src/Common/ActionUIModel.js"));
    ({ ActionUIElement } = await import("../src/Common/ActionUIElement.js"));
});

function buildTable(properties) {
    const logger = makeLogger();
    const model = new ActionUIModel("", logger);
    const element = ActionUIElement.fromObject({ type: "Table", id: 100, properties }, logger);
    const ctx = { model, windowUUID: "", logger, build: (child) => buildElementView(child, ctx) };
    const scroll = buildElementView(element, ctx);
    return { scroll, model };
}

const hasClass = (node, cls) =>
    (typeof node.className === "string" && node.className.split(/\s+/).includes(cls))
    || !!node.classList?.contains?.(cls);

function firstRowCells(scroll) {
    const table = scroll.children.find((c) => c.tagName === "TABLE");
    const tbody = table.children.find((c) => c.tagName === "TBODY");
    const tr = tbody.children[0];
    return tr ? tr.children : [];
}

test("stackedCards adds the stackable class to the scroll wrapper", () => {
    const { scroll } = buildTable({ columns: ["Name", "Kind"], stackedCards: true });
    assert.ok(hasClass(scroll, "aui-table-stackable"));
});

test("a plain table is not stackable", () => {
    const { scroll } = buildTable({ columns: ["Name", "Kind"] });
    assert.equal(hasClass(scroll, "aui-table-stackable"), false);
});

test("each cell carries its column name as data-label when stacked", () => {
    const { scroll, model } = buildTable({ columns: ["Name", "Kind"], stackedCards: true });
    model.setElementState(100, "content", [["Report", "doc"]]);
    const cells = firstRowCells(scroll);
    assert.equal(cells.length, 2);
    assert.equal(cells[0].dataset.label, "Name");
    assert.equal(cells[1].dataset.label, "Kind");
});

test("cells carry no data-label without stackedCards", () => {
    const { scroll, model } = buildTable({ columns: ["Name", "Kind"] });
    model.setElementState(100, "content", [["Report", "doc"]]);
    assert.equal(firstRowCells(scroll)[0].dataset.label, undefined);
});

test("validation drops a non-boolean stackedCards with a warning", () => {
    const logger = makeLogger();
    const out = getConstruction("Table").validateProperties({ columns: ["A"], stackedCards: "yes" }, logger);
    assert.equal(out.stackedCards, undefined);
    assert.ok(logger.warned("stackedCards must be a boolean"));
});
