// Tests for ActionUIElement parsing (src/Common/ActionUIElement.js).

import { test } from "node:test";
import assert from "node:assert/strict";
import { makeLogger } from "./dom-stub.mjs";
import { ActionUIElement } from "../src/Common/ActionUIElement.js";

test("fromObject parses type, properties, and a positive id", () => {
    const logger = makeLogger();
    const el = ActionUIElement.fromObject({ type: "Text", id: 7, properties: { text: "hi" } }, logger);
    assert.equal(el.type, "Text");
    assert.equal(el.id, 7);
    assert.equal(el.properties.text, "hi");
});

test("fromObject assigns a negative id when none is given", () => {
    const el = ActionUIElement.fromObject({ type: "Text" }, makeLogger());
    assert.ok(el.id < 0, "auto id is negative (not host-addressable)");
    assert.deepEqual(el.properties, {}, "missing properties default to {}");
});

test("fromObject rejects non-objects and missing type", () => {
    const logger = makeLogger();
    assert.equal(ActionUIElement.fromObject(null, logger), null);
    assert.equal(ActionUIElement.fromObject([1], logger), null);
    assert.equal(ActionUIElement.fromObject({ properties: {} }, logger), null, "missing type");
});

test("fromObject parses flat children, single content, and Grid rows", () => {
    const raw = {
        type: "NavigationSplitView",
        content: { type: "Text" },
        children: [{ type: "A" }, { type: "B" }],
        rows: [[{ type: "C" }, { type: "D" }]],
    };
    const el = ActionUIElement.fromObject(raw, makeLogger());
    assert.equal(el.subviews.children.length, 2);
    assert.equal(el.subviews.children[0].type, "A");
    assert.equal(el.subviews.content.type, "Text");
    assert.equal(el.subviews.rows[0].length, 2);
    assert.equal(el.subviews.rows[0][1].type, "D");
});

test("fromJSONString parses valid JSON and rejects malformed", () => {
    const logger = makeLogger();
    const el = ActionUIElement.fromJSONString('{"type":"Text"}', logger);
    assert.equal(el.type, "Text");
    assert.equal(ActionUIElement.fromJSONString("{bad", logger), null);
});

test("accessors expose named subviews", () => {
    const el = ActionUIElement.fromObject({ type: "VStack", children: [{ type: "X" }] }, makeLogger());
    assert.equal(el.children().length, 1);
    assert.equal(el.children()[0].type, "X");
});

test("fromObject replaces an id of 0 or below, with a warning", () => {
    const logger = makeLogger();
    const el = ActionUIElement.fromObject({ type: "VStack", id: 1, children: [
        { type: "Button", id: 0 }, { type: "Text", id: -9 }, { type: "Text", id: 3 }] }, logger);
    const [zero, negative, positive] = el.children();
    assert.ok(zero.id < 0, "0 becomes a generated id");
    assert.equal(negative.id, zero.id - 1, "a negative id from JSON is not kept: the next generated id replaces it");
    assert.equal(positive.id, 3, "a positive id is kept");
    assert.ok(logger.warned("Ignoring id 0 on Button: an id must be a positive integer"));
    assert.ok(logger.warned("Ignoring id -9 on Text: an id must be a positive integer"));
});

test("fromObject names a non-number id by its kind only, and takes null for no id", () => {
    const logger = makeLogger();
    const el = ActionUIElement.fromObject({ type: "VStack", children: [
        { type: "Text", id: "secret" }, { type: "Text", id: 1.5 }, { type: "Text", id: 10n }, { type: "Text", id: null }] }, logger);
    assert.ok(el.children().every((child) => child.id < 0));
    const warnings = logger.messages.filter((m) => m.level === "warning").map((m) => m.message);
    assert.deepEqual(warnings, [
        "Ignoring an id of type string on Text: an id must be a positive integer",
        "Ignoring id 1.5 on Text: an id must be a positive integer",
        "Ignoring an id of type bigint on Text: an id must be a positive integer"]);
});

test("fromObject logs a duplicate id within one ActionUI JSON, but not across loads or in a template", () => {
    const logger = makeLogger();
    ActionUIElement.fromObject({ type: "VStack", id: 1, children: [
        { type: "Text", id: 2 }, { type: "HStack", children: [{ type: "Button", id: 2 }] }] }, logger);
    const errors = () => logger.messages.filter((m) => m.level === "error").map((m) => m.message);
    assert.deepEqual(errors(), ["Duplicate id 2: its elements share one state"]);
    // Another load may use the same ids: each fromObject call is one ActionUI JSON.
    ActionUIElement.fromObject({ type: "Text", id: 2 }, logger);
    // A template's elements are a row's blueprint, not live elements.
    ActionUIElement.fromObject({ type: "List", id: 5, template: { type: "Text", id: 5 } }, logger);
    assert.equal(errors().length, 1);
});
