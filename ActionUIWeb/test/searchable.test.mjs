// Tests for the `searchable` property modifier (src/Helpers/SearchableModifier.js).
// Reconstructs the assertions recorded in Private/Commit_Notes_Web_Searchable.md.

import { test } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeElement, makeLogger } from "./dom-stub.mjs";
import { wrapWithSearchable } from "../src/Helpers/SearchableModifier.js";

function setup() {
    const dom = installDom();
    const logger = makeLogger();
    const dispatched = [];
    const ctx = { logger, model: { dispatchAction: (...args) => dispatched.push(args) } };
    return { dom, logger, dispatched, ctx };
}

const searchInput = (dom) => dom.findCreated((e) => e.type === "search");

test("valid searchable wraps the body and dispatches the query as context", () => {
    const { dom, logger, dispatched, ctx } = setup();
    const body = makeElement("div");
    const out = wrapWithSearchable(body, { id: 47 }, { searchable: { actionID: "demo.search", prompt: "Find" } }, ctx);

    assert.notEqual(out, body, "returns a new wrapper node");
    assert.equal(out.className, "aui-searchable");
    assert.ok(out.children.includes(body), "wrapper contains the body node");

    const input = searchInput(dom);
    assert.ok(input, "a type=search input is created");
    assert.equal(input.placeholder, "Find");

    input.value = "ad";
    input.fire("input");
    assert.deepEqual(dispatched, [["demo.search", 47, 0, "ad"]], "input dispatches actionID with the query as context, viewID 0 viewPartID");
    assert.equal(logger.warningCount(), 0);
});

test("prompt is optional", () => {
    const { dom, ctx } = setup();
    wrapWithSearchable(makeElement("div"), { id: 1 }, { searchable: { actionID: "x" } }, ctx);
    assert.equal(searchInput(dom).placeholder, "", "no placeholder when prompt omitted");
});

test("absent searchable returns the body unchanged with no warning", () => {
    const { logger, ctx } = setup();
    const body = makeElement("div");
    const out = wrapWithSearchable(body, { id: 1 }, { navigationTitle: "x" }, ctx);
    assert.equal(out, body);
    assert.equal(logger.warningCount(), 0);
});

test("missing actionID is dropped with a warning", () => {
    const { logger, ctx } = setup();
    const body = makeElement("div");
    const out = wrapWithSearchable(body, { id: 1 }, { searchable: { prompt: "Find" } }, ctx);
    assert.equal(out, body);
    assert.ok(logger.warned("non-empty String 'actionID'"));
});

test("empty actionID is dropped with a warning", () => {
    const { logger, ctx } = setup();
    const out = wrapWithSearchable(makeElement("div"), { id: 1 }, { searchable: { actionID: "" } }, ctx);
    assert.ok(out.className !== "aui-searchable");
    assert.ok(logger.warned("non-empty String 'actionID'"));
});

test("a non-object searchable is dropped with a warning", () => {
    const { logger, ctx } = setup();
    const out = wrapWithSearchable(makeElement("div"), { id: 1 }, { searchable: "demo.search" }, ctx);
    assert.ok(out.className !== "aui-searchable");
    assert.ok(logger.warned("expected dictionary"));
});

test("a non-string prompt is stripped but the modifier is kept", () => {
    const { dom, logger, ctx } = setup();
    const body = makeElement("div");
    const out = wrapWithSearchable(body, { id: 1 }, { searchable: { actionID: "x", prompt: 42 } }, ctx);
    assert.notEqual(out, body, "still wraps");
    assert.equal(searchInput(dom).placeholder, "", "prompt dropped");
    assert.ok(logger.warned("searchable.prompt"));
});
