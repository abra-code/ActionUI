// Tests for the safe-area modifiers (src/Helpers/SafeAreaModifier.js) - the web side of
// SwiftUI's .ignoresSafeArea / .safeAreaInset. Covers the negative-env() ignoresSafeArea margins
// and the safeAreaInset wrapper (an edge bar padded by env() + the content).

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeElement, makeLogger } from "./dom-stub.mjs";
import { applyIgnoresSafeArea, wrapWithSafeAreaInset } from "../src/Helpers/SafeAreaModifier.js";
import { ActionUIElement } from "../src/Common/ActionUIElement.js";

before(async () => {
    installDom();
    await import("../src/ActionUI.js");
});

test("ignoresSafeArea: true sets negative env() margins on all edges", () => {
    installDom();
    const node = makeElement("div");
    applyIgnoresSafeArea(node, { ignoresSafeArea: true });
    assert.match(node.style["margin-top"], /-1 \* env\(safe-area-inset-top\)/);
    assert.match(node.style["margin-bottom"], /env\(safe-area-inset-bottom\)/);
    assert.match(node.style["margin-left"], /env\(safe-area-inset-left\)/);
});

test("ignoresSafeArea: an object narrows to the given edges", () => {
    installDom();
    const node = makeElement("div");
    applyIgnoresSafeArea(node, { ignoresSafeArea: { edges: "bottom" } });
    assert.match(node.style["margin-bottom"], /env\(safe-area-inset-bottom\)/);
    assert.equal(node.style["margin-top"] ?? "", "");
});

test("ignoresSafeArea: absent or false is a no-op", () => {
    installDom();
    const node = makeElement("div");
    applyIgnoresSafeArea(node, {});
    applyIgnoresSafeArea(node, { ignoresSafeArea: false });
    assert.equal(node.style["margin-bottom"] ?? "", "");
});

function wired(raw) {
    installDom();
    const logger = makeLogger();
    const element = ActionUIElement.fromObject({ type: "ScrollView", id: 1, ...raw }, logger);
    const node = makeElement("div");
    node.dataset.auiId = "1";
    const built = [];
    const ctx = { logger, build: (el) => { built.push(el); const m = makeElement("div"); m.dataset.auiId = String(el.id); return m; } };
    const wrapped = wrapWithSafeAreaInset(node, element, element.properties, ctx);
    return { node, wrapped, built };
}

test("safeAreaInset: wraps with a content layer + an edge bar padded by env()", () => {
    const { node, wrapped } = wired({
        safeAreaInset: { type: "Text", id: 2, properties: { safeAreaEdge: "bottom", text: "Bar" } },
    });
    assert.notEqual(wrapped, node, "node is wrapped");
    assert.ok(wrapped.className.includes("aui-safe-area-inset"));
    assert.equal(wrapped.style.flexDirection, "column", "vertical edge -> column");
    const bar = wrapped.children.find((c) => typeof c.className === "string" && c.className.includes("aui-safe-area-bar"));
    assert.ok(bar, "bar present");
    assert.match(bar.style["padding-bottom"], /env\(safe-area-inset-bottom\)/);
    // bottom edge -> bar after the content
    assert.ok(wrapped.children.at(-1).className.includes("aui-safe-area-bar"));
});

test("safeAreaInset: a leading edge lays out as a row with the bar first", () => {
    const { wrapped } = wired({
        safeAreaInset: { type: "Text", id: 2, properties: { safeAreaEdge: "leading", text: "Rail" } },
    });
    assert.equal(wrapped.style.flexDirection, "row");
    assert.ok(wrapped.children[0].className.includes("aui-safe-area-bar"), "leading -> bar first");
});

test("safeAreaInset: no subview is a no-op (returns the node)", () => {
    const { node, wrapped } = wired({});
    assert.equal(wrapped, node);
});
