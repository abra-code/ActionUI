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
