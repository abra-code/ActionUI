// Tests for the ActionUIModel host bridges: value, state, and row selection.
// (setElementProperty is covered in property-mutation.test.mjs.)

import { test } from "node:test";
import assert from "node:assert/strict";
import { makeLogger } from "./dom-stub.mjs";
import { ActionUIModel } from "../src/Common/ActionUIModel.js";

const model = (logger = makeLogger()) => new ActionUIModel("", logger);

// ---------------- value bridge ----------------

test("value bridge: seeded fallback, then a registered binding", () => {
    const m = model();
    m.seedValue(1, "seed");
    assert.equal(m.getElementValue(1), "seed", "reads the seeded fallback when unbound");

    let stored = "init";
    m.bind(2, { getValue: () => stored, setValue: (v) => { stored = v; } });
    m.setElementValue(2, 0, "new");
    assert.equal(stored, "new", "set routes through the binding");
    assert.equal(m.getElementValue(2), "new", "get routes through the binding");
});

test("value bridge: unknown id warns and returns null", () => {
    const logger = makeLogger();
    assert.equal(model(logger).getElementValue(999), null);
    assert.ok(logger.warned("no element with id 999"));
});

// ---------------- state bridge ----------------

test("state bridge: seeded states + a registered state binding", () => {
    const m = model();
    m.seedStates(1, { isExpanded: false });
    assert.equal(m.getElementState(1, "isExpanded"), false, "reads the seeded fallback");

    const states = {};
    m.bindState(2, { getState: (k) => states[k], setState: (k, v) => { states[k] = v; } });
    m.setElementState(2, "isExpanded", true);
    assert.equal(states.isExpanded, true);
    assert.equal(m.getElementState(2, "isExpanded"), true);
});

// ---------------- selection bridge ----------------

function withRows(m, viewID, rows) {
    // Selection reads rows from the "content" state and writes the selection as the
    // element value; seed both fallback maps so no binding wiring is needed.
    m.seedStates(viewID, { content: rows });
    m.seedValue(viewID, "");
}

test("selectElementRow returns the row and writes the tab-joined selection", () => {
    const m = model();
    withRows(m, 5, [["Ada", "person"], ["Alan", "person"]]);
    const row = m.selectElementRow(5, 1);
    assert.deepEqual(row, ["Alan", "person"]);
    assert.equal(m.getElementValue(5), "Alan\tperson", "selection stored as the element value");
});

test("selectElementRow out of range clears and returns null", () => {
    const m = model();
    withRows(m, 5, [["a"]]);
    m.selectElementRow(5, 0);
    assert.equal(m.selectElementRow(5, 9), null);
    assert.equal(m.getElementValue(5), "", "out-of-range index clears the selection");
});

test("selectElementRowWithContent matches by column / any column", () => {
    const m = model();
    withRows(m, 5, [["Ada", "x"], ["Alan", "y"], ["Grace", "y"]]);
    assert.equal(m.selectElementRowWithContent(5, "Alan"), 1, "any-column match");
    assert.equal(m.selectElementRowWithContent(5, "y", 1), 1, "first match in column 1");
    assert.equal(m.selectElementRowWithContent(5, "missing"), -1, "no match -> -1");
});

test("selection on a non-content element warns and is a no-op", () => {
    const logger = makeLogger();
    const m = model(logger);
    m.seedValue(5, "x"); // no "content" state -> not a Table/List
    assert.equal(m.selectElementRow(5, 0), null);
    assert.ok(logger.warned("not a Table/List"));
});

test("clearElementSelection empties the value", () => {
    const m = model();
    withRows(m, 5, [["a"]]);
    m.selectElementRow(5, 0);
    m.clearElementSelection(5);
    assert.equal(m.getElementValue(5), "");
});
