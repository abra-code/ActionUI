// Tests for toolbar placement bucketing (resolveToolbar) plus the chrome wrap
// (wrapWithToolbar): the secondaryAction overflow menu and the navigation-title
// size modes (toolbarTitleDisplayMode). src/Helpers/ToolbarHelper.js.

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeElement, makeLogger } from "./dom-stub.mjs";
import { ActionUIElement } from "../src/Common/ActionUIElement.js";
import { resolveToolbar, wrapWithToolbar } from "../src/Helpers/ToolbarHelper.js";

before(() => { installDom(); }); // wrapWithToolbar builds DOM via document.createElement

function withToolbar(items, properties = {}) {
    return ActionUIElement.fromObject({ type: "VStack", toolbar: items, properties }, makeLogger());
}
const item = (placement, title) => ({
    type: "ToolbarItem", properties: { placement }, content: { type: "Button", properties: { title } },
});

// Depth-first search of the stub element tree for the first node carrying a class.
// The renderer sets classes both ways (`.className =` assignment and
// classList.add), so check both.
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
// A ctx for wrapWithToolbar: a no-op model + a build that returns a fresh node.
const makeCtx = (logger) => ({ logger, model: { dispatchAction() {} }, build: () => makeElement("div") });

test("placements map to leading / principal / trailing / overflow / bottom buckets", () => {
    const el = withToolbar([
        item("navigation", "Back"),
        item("principal", "Title"),
        item("primaryAction", "Add"),
        item("secondaryAction", "Archive"),
        item("bottomBar", "Status"),
    ]);
    const b = resolveToolbar(el, makeLogger());
    assert.equal(b.leading.length, 1, "navigation -> leading");
    assert.equal(b.principal.length, 1, "principal -> principal");
    assert.equal(b.trailing.length, 1, "primaryAction -> trailing (default)");
    assert.equal(b.overflow.length, 1, "secondaryAction -> overflow");
    assert.equal(b.bottom.length, 1, "bottomBar -> bottom");
});

test("an unsupported placement (keyboard) is dropped with a warning", () => {
    const logger = makeLogger();
    const b = resolveToolbar(withToolbar([item("keyboard", "X")]), logger);
    assert.equal(b.leading.length + b.principal.length + b.trailing.length + b.overflow.length + b.bottom.length, 0);
    assert.ok(logger.warned("not supported on the web"));
});

test("ToolbarItemGroup contributes all its children to one slot", () => {
    const group = {
        type: "ToolbarItemGroup",
        properties: { placement: "primaryAction" },
        children: [{ type: "Button", properties: { title: "A" } }, { type: "Button", properties: { title: "B" } }],
    };
    const b = resolveToolbar(withToolbar([group]), makeLogger());
    assert.equal(b.trailing.length, 2, "both group children land in trailing");
});

test("secondaryAction items render as an overflow ('...') menu in the trailing slot", () => {
    const logger = makeLogger();
    const el = withToolbar([item("secondaryAction", "Archive"), item("secondaryAction", "Move")]);
    const host = wrapWithToolbar(makeElement("div"), el, el.properties, makeCtx(logger));
    const trailing = findByClass(host, "aui-toolbar-trailing");
    const overflow = findByClass(trailing, "aui-toolbar-overflow");
    assert.ok(overflow, "an overflow menu is appended to the trailing slot");
    const trigger = findByClass(overflow, "aui-toolbar-overflow-trigger");
    assert.ok(trigger, "the overflow has a '...' trigger");
    const items = findByClass(overflow, "aui-toolbar-overflow-items");
    assert.equal(items.children.length, 2, "both secondary actions are items in the panel");
});

test("a large title mode renders the title on its own large row, not inline", () => {
    const logger = makeLogger();
    const el = withToolbar([], { navigationTitle: "Library", toolbarTitleDisplayMode: "large" });
    const host = wrapWithToolbar(makeElement("div"), el, el.properties, makeCtx(logger));
    assert.equal(host.dataset.auiTitleMode, "large");
    assert.ok(findByClass(host, "aui-toolbar-largetitle"), "a large-title row is rendered");
    assert.equal(findByClass(host, "aui-toolbar-title"), null, "no compact inline title in the bar");
});

test("an inline/automatic title stays compact in the principal slot", () => {
    const logger = makeLogger();
    const el = withToolbar([], { navigationTitle: "Documents", toolbarTitleDisplayMode: "inline" });
    const host = wrapWithToolbar(makeElement("div"), el, el.properties, makeCtx(logger));
    assert.equal(host.dataset.auiTitleMode, "inline");
    assert.ok(findByClass(host, "aui-toolbar-title"), "the compact inline title is rendered");
    assert.equal(findByClass(host, "aui-toolbar-largetitle"), null, "no large-title row");
});

test("an invalid toolbarTitleDisplayMode warns and falls back to automatic", () => {
    const logger = makeLogger();
    const el = withToolbar([], { navigationTitle: "X", toolbarTitleDisplayMode: "huge" });
    const host = wrapWithToolbar(makeElement("div"), el, el.properties, makeCtx(logger));
    assert.equal(host.dataset.auiTitleMode, "automatic");
    assert.ok(logger.warned("Invalid toolbarTitleDisplayMode"));
});
