// Tests for `hidden` on the web renderer: the whole element hides, as on Apple, Android and
// Linux - the view-valued background/overlay wrapper and the safe-area inset bar around the
// node too, not only the node - both when the document says so and when a host sets it at
// run time. The searchable field and toolbar chrome outside those wrappers are not hidden.

import { test, before, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeLogger } from "./dom-stub.mjs";

let buildElementView, ActionUIModel, ActionUIElement, applyElementProperty;

before(async () => {
    installDom();
    await import("../src/ActionUI.js"); // registers every view
    ({ buildElementView } = await import("../src/Common/ActionUIRegistry.js"));
    ({ ActionUIModel } = await import("../src/Common/ActionUIModel.js"));
    ({ ActionUIElement } = await import("../src/Common/ActionUIElement.js"));
    ({ applyElementProperty } = await import("../src/Common/ModifierResolver.js"));
});
beforeEach(() => { installDom(); });

function build(raw) {
    const logger = makeLogger();
    const model = new ActionUIModel("", logger);
    model.dispatchAction = () => {};
    const element = ActionUIElement.fromObject(raw, logger);
    const ctx = { model, windowUUID: "", logger, build: (child) => buildElementView(child, ctx) };
    const root = buildElementView(element, ctx);
    model.rootNode = root;
    return { root, model };
}

function findByDataId(node, id) {
    if (node?.dataset?.auiId === String(id)) return node;
    for (const child of node?.children ?? []) {
        const found = findByDataId(child, id);
        if (found) return found;
    }
    return null;
}

const decorated = (hidden) => ({
    type: "VStack", id: 1, properties: { hidden, background: "blue" },
    background: { type: "Color", id: 2, properties: { color: "red" } },
    overlay: { type: "Color", id: 3, properties: { color: "green" } },
    children: [{ type: "Text", id: 4, properties: { text: "content" } }],
});

test("a hidden element's decoration wrapper is hidden too", () => {
    const { root } = build(decorated(true));
    const node = findByDataId(root, 1);
    assert.notEqual(root, node, "the overlay and background wrap the node");
    assert.equal(node.style.visibility, "hidden");
    assert.equal(root.style.visibility, "hidden", "the wrapper holding the background and overlay layers");
});

test("a visible element's wrapper is not hidden", () => {
    const { root } = build(decorated(false));
    assert.equal(root.style.visibility ?? "", "");
});

test("hiding and showing at run time reaches the wrapper", () => {
    // What ActionUIModel.setElementProperty does with the node it finds by id (the stub DOM
    // has no querySelector, so the node is handed over directly).
    const { root } = build(decorated(false));
    const node = findByDataId(root, 1);
    applyElementProperty(node, "hidden", true, makeLogger());
    assert.equal(root.style.visibility, "hidden");
    assert.equal(node.style.visibility, "hidden");
    applyElementProperty(node, "hidden", false, makeLogger());
    assert.equal(root.style.visibility, "");
    assert.equal(findByDataId(root, 1).style.visibility, "");
});

test("a hidden element's safe-area inset bar is hidden too", () => {
    const { root } = build({
        type: "ScrollView", id: 1, properties: { hidden: true },
        safeAreaInset: { type: "Text", id: 2, properties: { safeAreaEdge: "bottom", text: "Bar" } },
        children: [{ type: "Text", id: 3, properties: { text: "content" } }],
    });
    assert.ok(String(root.className).includes("aui-safe-area-inset"));
    assert.equal(root.style.visibility, "hidden");
});

test("an element without wrappers hides only itself", () => {
    const { root } = build({ type: "Text", id: 1, properties: { hidden: true, text: "x" } });
    assert.equal(root.style.visibility, "hidden");
    assert.equal(root.auiHiddenRoot, undefined);
});
