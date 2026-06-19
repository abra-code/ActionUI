// Tests for src/Common/ModifierResolver.js: resolveColor + applyViewModifiers
// (the build-time CSS application). applyElementProperty is in property-mutation.test.mjs.

import { test } from "node:test";
import assert from "node:assert/strict";
import { makeElement, makeLogger } from "./dom-stub.mjs";
import { resolveColor, applyViewModifiers, markHandlesAction } from "../src/Common/ModifierResolver.js";

test("resolveColor: named -> CSS var, hex pass-through, unknown warns -> null", () => {
    const logger = makeLogger();
    assert.match(resolveColor("red", logger), /var\(--aui-color-red\)/);
    assert.equal(resolveColor("#abc", logger), "#abc");
    assert.equal(resolveColor("#aabbccdd", logger), "#aabbccdd");
    assert.equal(resolveColor(42, logger), null, "non-string -> null");
    assert.equal(resolveColor("chartreuse", logger), null);
    assert.ok(logger.warned("Unknown color"));
});

function applied(properties, element = { id: 1 }) {
    const node = makeElement();
    const dispatched = [];
    const ctx = { logger: makeLogger(), model: { dispatchAction: (...a) => dispatched.push(a) } };
    applyViewModifiers(node, element, properties, ctx);
    return { node, dispatched };
}

test("padding: number, default keyword, and per-edge object", () => {
    assert.equal(applied({ padding: 12 }).node.style.padding, "12px");
    assert.match(applied({ padding: "default" }).node.style.padding, /px$/);
    assert.equal(applied({ padding: { top: 1, bottom: 2, leading: 3, trailing: 4 } }).node.style.padding, "1px 4px 2px 3px");
});

test("opacity / hidden / cornerRadius / colors / help", () => {
    assert.equal(applied({ opacity: 0.5 }).node.style.opacity, "0.5");
    assert.equal(applied({ hidden: true }).node.style.display, "none");
    const cr = applied({ cornerRadius: 6 }).node;
    assert.equal(cr.style.borderRadius, "6px");
    assert.equal(cr.style.overflow, "hidden");
    assert.match(applied({ foregroundColor: "blue" }).node.style.color, /var\(--aui-color-blue\)/);
    assert.match(applied({ background: "green" }).node.style.backgroundColor, /var\(--aui-color-green\)/);
    assert.equal(applied({ help: "tip" }).node.title, "tip");
});

test("font: a text style adds a class; a custom name sets fontFamily", () => {
    assert.ok(applied({ font: "title" }).node.classList.contains("aui-font-title"));
    assert.equal(applied({ font: "Courier New" }).node.style.fontFamily, "Courier New");
});

test("disabled toggles the class and the disabled property", () => {
    const node = applied({ disabled: true }).node;
    assert.ok(node.classList.contains("aui-disabled"));
    assert.equal(node.disabled, true);
});

test("scaleEffect / rotationEffect set the CSS scale / rotate", () => {
    assert.equal(applied({ scaleEffect: 1.25 }).node.style.scale, "1.25");
    assert.equal(applied({ rotationEffect: 45 }).node.style.rotate, "45deg");
});

test("actionID wires a click that dispatches; markHandlesAction opts out", () => {
    const node = makeElement();
    const dispatched = [];
    const ctx = { logger: makeLogger(), model: { dispatchAction: (...a) => dispatched.push(a) } };
    applyViewModifiers(node, { id: 9 }, { actionID: "go" }, ctx);
    node.fire("click");
    assert.deepEqual(dispatched, [["go", 9]], "click dispatches actionID with the element id");

    const handled = makeElement();
    markHandlesAction(handled);
    applyViewModifiers(handled, { id: 9 }, { actionID: "go" }, ctx);
    assert.equal(handled.listenerCount("click"), 0, "a control that handles its own action gets no generic click");
});
