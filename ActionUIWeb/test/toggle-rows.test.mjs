// Tests for a Toggle whose state is row data: inside a data-driven template (List,
// LazyVStack) and as a Table column type. They pin the string-to-Boolean rule, the
// write of a user toggle into the rows, the action's viewID / viewPartID / context,
// that the action fires after the write, that a rows change by the host fires
// nothing, that the state is kept across a re-render, and that toggling does not
// move the selection (while a click elsewhere in the row does).

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeLogger } from "./dom-stub.mjs";

let buildElementView, ActionUIModel, ActionUIElement, getConstruction;
let rowBool, singleColumnIndex, substituteElement, IS_ON_COLUMN_KEY;

before(async () => {
    installDom();
    await import("../src/ActionUI.js"); // registers every view as a side effect
    ({ buildElementView, getConstruction } = await import("../src/Common/ActionUIRegistry.js"));
    ({ ActionUIModel } = await import("../src/Common/ActionUIModel.js"));
    ({ ActionUIElement } = await import("../src/Common/ActionUIElement.js"));
    ({ rowBool, singleColumnIndex, substituteElement, IS_ON_COLUMN_KEY } =
        await import("../src/Helpers/TemplateHelper.js"));
});

const PACK_ROWS = [
    ["true", "Xcode and Swift builds", "xcode", "false"],
    ["false", "Node", "node", "false"],
    ["false", "Locked", "locked", "true"],
];

const PACK_LIST = {
    type: "List", id: 600,
    properties: { actionID: "packs.selection.changed" },
    template: {
        type: "Toggle",
        properties: { style: "checkbox", isOn: "$1", title: "$2", disabled: "$4", actionID: "packs.toggled" },
    },
};

const PACK_TABLE = {
    type: "Table", id: 600,
    properties: {
        columns: ["", "Pack"],
        columnTypes: [
            { viewType: "Toggle", style: "checkbox", actionID: "packs.toggled", disabledColumn: 4 },
            { viewType: "Text" },
        ],
        actionID: "packs.selection.changed",
    },
};

const validateProperties = (type, properties, logger) =>
    getConstruction(type).validateProperties(properties, logger);

function findAll(node, pred, out = []) {
    if (pred(node)) out.push(node);
    for (const child of node?.children ?? []) findAll(child, pred, out);
    return out;
}
const inputs = (root) => findAll(root, (n) => n.tagName === "INPUT");
const hasClass = (node, cls) => typeof node.className === "string" && node.className.split(/\s+/).includes(cls);

// Builds `raw`, loads PACK_ROWS, and records every dispatch together with the rows
// as the handler would read them at that moment.
function build(raw, rows = PACK_ROWS) {
    const logger = makeLogger();
    const model = new ActionUIModel("", logger);
    const dispatched = [];
    model.dispatchAction = (id, viewID, viewPartID, context) =>
        dispatched.push({ id, viewID, viewPartID, context, rows: model.getElementState(raw.id, "content") });
    const element = ActionUIElement.fromObject(raw, logger);
    const ctx = { model, windowUUID: "", logger, build: (child) => buildElementView(child, ctx) };
    const root = buildElementView(element, ctx);
    model.setElementState(raw.id, "content", rows);
    return { model, dispatched, root, logger, rows: () => model.getElementState(raw.id, "content") };
}

// What a user click on a checkbox does: the state flips, then "change" fires.
function userToggle(input) {
    input.checked = !input.checked;
    input.fire("change");
}

// ---- The shared rules ----

test("rowBool reads the documented words in any letter case", () => {
    for (const text of ["true", "TRUE", "True", "1"]) assert.equal(rowBool(text), true, text);
    for (const text of ["false", "FALSE", "False", "0", ""]) assert.equal(rowBool(text), false, text);
    for (const text of ["yes", "no", "on", " true", "2", "mixed", "$4"]) assert.equal(rowBool(text), null, text);
});

test("singleColumnIndex: only a whole reference names a column", () => {
    assert.equal(singleColumnIndex("$1"), 0);
    assert.equal(singleColumnIndex("$12"), 11);
    for (const value of ["$0", "$1 ", "x$1", "$1$2", "true", true, undefined]) {
        assert.equal(singleColumnIndex(value), null, String(value));
    }
});

test("substituteElement reads isOn / disabled / hidden from the row on any element", () => {
    const logger = makeLogger();
    const toggle = ActionUIElement.fromObject(PACK_LIST.template, logger);
    const locked = substituteElement(toggle, PACK_ROWS[2], logger).properties;
    assert.equal(locked.isOn, false);
    assert.equal(locked.disabled, true);
    assert.equal(locked.title, "Locked");
    assert.equal(locked[IS_ON_COLUMN_KEY], 0);

    const text = ActionUIElement.fromObject(
        { type: "Text", properties: { text: "$1", hidden: "$2", disabled: "$3" } }, logger);
    const shown = substituteElement(text, ["Alpha", "1", "TRUE"], logger).properties;
    assert.equal(shown.hidden, true);
    assert.equal(shown.disabled, true);
    assert.equal(shown.text, "Alpha", "a non-Boolean property stays text");
    assert.equal(logger.warningCount(), 0);
});

test("substituteElement: other text is off, with a warning; a literal Boolean is kept", () => {
    const logger = makeLogger();
    const toggle = ActionUIElement.fromObject(PACK_LIST.template, logger);
    const odd = substituteElement(toggle, ["perhaps not", "Title", "id", "false"], logger).properties;
    assert.equal(odd.isOn, false);
    assert.ok(logger.warned("perhaps not"));

    const literal = ActionUIElement.fromObject({ type: "Toggle", properties: { isOn: true, title: "$1" } }, logger);
    const properties = substituteElement(literal, ["Alpha"], logger).properties;
    assert.equal(properties.isOn, true);
    assert.equal(properties[IS_ON_COLUMN_KEY], undefined, "a literal names no column");
});

test("outside a template a string isOn is still invalid", () => {
    assert.equal(validateProperties("Toggle", { isOn: "true" }, makeLogger()).isOn, undefined);
});

// ---- List template ----

test("List template: the toggles show what the rows say", () => {
    const { root } = build(PACK_LIST);
    assert.deepEqual(inputs(root).map((box) => box.checked), [true, false, false]);
    // The disabled modifier marks the Toggle (and, in a browser, its input).
    const toggles = findAll(root, (n) => hasClass(n, "aui-toggle"));
    assert.deepEqual(toggles.map((toggle) => toggle.classList.contains("aui-disabled")), [false, false, true]);
});

test("List template: a user toggle writes the row, then fires with the row index and the new Boolean", () => {
    const { root, dispatched, rows } = build(PACK_LIST);
    userToggle(inputs(root)[1]);
    assert.deepEqual(rows()[1], ["true", "Node", "node", "false"]);
    assert.deepEqual(rows()[0], PACK_ROWS[0], "other rows are untouched");
    assert.equal(dispatched.length, 1);
    const [fired] = dispatched;
    assert.deepEqual([fired.id, fired.viewID, fired.viewPartID, fired.context], ["packs.toggled", 600, 1, true]);
    assert.equal(fired.rows[1][0], "true", "the action fires after the write");
    assert.equal(PACK_ROWS[1][0], "false", "the host's own array is not written into");
});

test("List template: the row node stays in place and the state survives a re-render", () => {
    const { root, model, rows } = build(PACK_LIST);
    const box = inputs(root)[1];
    userToggle(box);
    assert.equal(inputs(root)[1], box, "the toggled row was not rebuilt");
    // The host sends the rows back as it read them: nothing to rebuild, still on.
    model.setElementState(600, "content", rows().map((row) => [...row]));
    assert.equal(inputs(root)[1], box);
    // A full rebuild draws the state from the rows.
    model.setElementState(600, "content", [["false", "New", "new", "false"], ...rows()]);
    assert.deepEqual(inputs(root).map((b) => b.checked), [false, true, true, false]);
});

test("List template: toggling does not select the row; a click elsewhere does and does not toggle", () => {
    const { root, model, dispatched } = build({
        ...PACK_LIST,
        template: {
            type: "HStack",
            children: [PACK_LIST.template, { type: "Text", properties: { text: "$3" } }],
        },
    });
    const toggles = findAll(root, (n) => hasClass(n, "aui-toggle"));
    const visual = findAll(toggles[1], (n) => hasClass(n, "aui-toggle-visual"))[0];
    visual.fire("click");                       // the drawn box: the label, not the input
    inputs(root)[1].fire("click");
    inputs(root)[1].fire("keydown", { key: " " });
    assert.equal(model.getElementValue(600), "", "nothing was selected");
    assert.equal(dispatched.length, 0);

    const text = findAll(root, (n) => n.textContent === "node")[0];
    text.fire("click");
    assert.equal(model.getElementValue(600), PACK_ROWS[1].join("\t"));
    assert.deepEqual(dispatched.map((d) => d.id), ["packs.selection.changed"]);
    assert.equal(inputs(root)[1].checked, false, "selecting did not toggle");
});

test("List template: a selection on the toggled row follows it and fires nothing", () => {
    const { root, model, dispatched } = build(PACK_LIST);
    model.selectElementRow(600, 1);
    userToggle(inputs(root)[1]);
    assert.equal(model.getElementValue(600), ["true", "Node", "node", "false"].join("\t"));
    assert.deepEqual(dispatched.map((d) => d.id), ["packs.toggled"]);
});

test("List template: rows changes by the host fire nothing", () => {
    const { model, root, dispatched } = build(PACK_LIST);
    model.setElementState(600, "content", [["true", "A", "a", "false"]]);
    model.setElementState(600, "content", [["true", "A", "a", "false"], ["false", "B", "b", "false"]]);
    assert.deepEqual(inputs(root).map((box) => box.checked), [true, false]);
    model.setElementState(600, "content", []);
    assert.equal(dispatched.length, 0);
});

test("a Toggle whose isOn is not one column is display-only", () => {
    const { root, dispatched, rows } = build({
        ...PACK_LIST,
        template: { type: "Toggle", properties: { isOn: "$1$4", title: "$2", actionID: "packs.toggled" } },
    }, [["", "Node", "node", "true"]]);
    const box = inputs(root)[0];
    assert.equal(box.checked, true, "'' + 'true' reads as on");
    userToggle(box);
    assert.equal(box.checked, true, "the click is undone");
    assert.deepEqual(rows(), [["", "Node", "node", "true"]]);
    assert.equal(dispatched.length, 0);
});

test("List itemType Toggle is refused", () => {
    const logger = makeLogger();
    assert.equal(validateProperties("List", { itemType: { viewType: "Toggle" } }, logger).itemType.viewType, "Text");
    assert.ok(logger.warned("use a template with a Toggle"));
});

// ---- LazyVStack template (the plain repeater) ----

test("LazyVStack template: a user toggle writes the row and fires with the row index", () => {
    const { root, dispatched, rows } = build({ ...PACK_LIST, type: "LazyVStack", properties: {} });
    userToggle(inputs(root)[0]);
    assert.equal(rows()[0][0], "false");
    assert.deepEqual([dispatched[0].viewID, dispatched[0].viewPartID, dispatched[0].context], [600, 0, false]);
});

// ---- Table column ----

test("Table: a Toggle column is valid; a bad style and disabledColumn are dropped", () => {
    const good = validateProperties("Table", PACK_TABLE.properties, makeLogger()).columnTypes[0];
    assert.deepEqual(good, { viewType: "Toggle", style: "checkbox", actionID: "packs.toggled", disabledColumn: 4 });
    const logger = makeLogger();
    const bad = validateProperties("Table", {
        columns: ["On"], columnTypes: [{ viewType: "Toggle", style: "radio", disabledColumn: 0 }],
    }, logger).columnTypes[0];
    assert.deepEqual(bad, { viewType: "Toggle" });
    assert.equal(logger.warningCount(), 2);
});

test("Table: the cells show what the rows say, with no title", () => {
    const { root } = build(PACK_TABLE);
    const boxes = inputs(root);
    assert.deepEqual(boxes.map((box) => box.checked), [true, false, false]);
    assert.deepEqual(boxes.map((box) => box.disabled), [false, false, true]);
    assert.equal(findAll(root, (n) => hasClass(n, "aui-toggle-title")).length, 0);
});

test("Table: a user toggle writes the cell, then fires with the column and the row index", () => {
    const { root, dispatched, rows } = build(PACK_TABLE);
    userToggle(inputs(root)[1]);
    assert.deepEqual(rows()[1], ["true", "Node", "node", "false"]);
    assert.equal(dispatched.length, 1);
    const [fired] = dispatched;
    assert.deepEqual([fired.id, fired.viewID, fired.viewPartID, fired.context], ["packs.toggled", 600, 0, 1]);
    assert.equal(fired.rows[1][0], "true", "the action fires after the write");
});

test("Table: toggling does not select the row and keeps a selection where it was", () => {
    const { root, model, dispatched } = build(PACK_TABLE);
    const label = findAll(root, (n) => hasClass(n, "aui-table-toggle"))[1];
    label.fire("click");
    label.fire("keydown", { key: " " });
    assert.equal(model.getElementValue(600), "", "nothing was selected");
    assert.equal(dispatched.length, 0);

    // The control: a click on the row's plain cell does select it, and toggles nothing.
    findAll(root, (n) => n.tagName === "TD" && n.textContent === "Node")[0].fire("click");
    assert.equal(model.getElementValue(600), PACK_ROWS[1].join("\t"));
    assert.deepEqual(dispatched.map((d) => d.id), ["packs.selection.changed"]);
    assert.equal(inputs(root)[1].checked, false, "selecting did not toggle");

    userToggle(inputs(root)[1]);
    assert.equal(model.getElementValue(600), ["true", "Node", "node", "false"].join("\t"), "the selection stays on its row");
    assert.deepEqual(dispatched.map((d) => d.id), ["packs.selection.changed", "packs.toggled"]);
});

test("Table: rows changes by the host fire nothing", () => {
    const { model, root, dispatched } = build(PACK_TABLE);
    model.setElementState(600, "content", [["false", "A", "a", "false"]]);
    assert.deepEqual(inputs(root).map((box) => box.checked), [false]);
    model.setElementState(600, "content", []);
    assert.equal(dispatched.length, 0);
});

test("List template: a double-click on a row toggled since it was built still fires", () => {
    const { root, dispatched } = build({
        ...PACK_LIST,
        properties: { ...PACK_LIST.properties, doubleClickActionID: "packs.opened" },
    });
    userToggle(inputs(root)[1]);
    const rowNode = findAll(root, (n) => hasClass(n, "aui-list-row"))[1];
    rowNode.fire("click");      // a double-click arrives as click (selects), then dblclick
    rowNode.fire("dblclick");
    assert.deepEqual(dispatched.map((d) => [d.id, d.context]),
        [["packs.toggled", true], ["packs.selection.changed", null], ["packs.opened", 1]]);
});
