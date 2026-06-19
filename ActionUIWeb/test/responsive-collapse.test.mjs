// Tests for the adaptive width-class collapse (the responsive part):
// NavigationSplitView's narrow-window single-column mode (src/Views/NavigationSplitView.js)
// and TabView's sidebarAdaptable rail -> top-strip collapse (src/Views/TabView.js).
// Both are driven by a ResizeObserver, which the headless stub never auto-fires;
// the test drives it via the controller's fireResize (see dom-stub.mjs). Pixel
// layout is a browser concern - these assert the data-attributes / classes / inline
// widths the collapse toggles, and the Back deselect behavior.

import { test, before, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeLogger } from "./dom-stub.mjs";

let buildElementView, ActionUIModel, ActionUIElement, dom;

before(async () => {
    dom = installDom();
    await import("../src/ActionUI.js"); // registers every view as a side effect
    ({ buildElementView } = await import("../src/Common/ActionUIRegistry.js"));
    ({ ActionUIModel } = await import("../src/Common/ActionUIModel.js"));
    ({ ActionUIElement } = await import("../src/Common/ActionUIElement.js"));
});
beforeEach(() => { dom = installDom(); }); // reset ResizeObserver instances per test

// Depth-first finders over the stub tree (the renderer sets classes via `.className =`).
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
function findAllByClass(node, cls, out = []) {
    if (hasClass(node, cls)) out.push(node);
    for (const child of node?.children ?? []) findAllByClass(child, cls, out);
    return out;
}

function build(raw) {
    const logger = makeLogger();
    const model = new ActionUIModel("", logger);
    const dispatched = [];
    model.dispatchAction = (id, viewID, idx, context) => dispatched.push({ id, viewID, idx, context });
    const element = ActionUIElement.fromObject(raw, logger);
    const ctx = { model, windowUUID: "", logger, build: (child) => buildElementView(child, ctx) };
    const root = buildElementView(element, ctx);
    return { root, dispatched, logger };
}

const NSV = {
    type: "NavigationSplitView", id: 50, properties: { navigationSplitViewColumnWidth: 200 },
    sidebar: {
        type: "List", id: 51, properties: { actionID: "pick", navigationSplitViewColumnWidth: 200 },
        children: [
            { type: "Label", id: 60, properties: { title: "A", destinationViewId: 70 } },
            { type: "Label", id: 61, properties: { title: "B", destinationViewId: 71 } },
        ],
    },
    detail: { type: "Text", properties: { text: "Pick one" } },
    destinations: [
        { type: "Text", id: 70, properties: { text: "Detail A" } },
        { type: "Text", id: 71, properties: { text: "Detail B" } },
    ],
};
const rowFor = (split, destId) => findAllByClass(split, "aui-nav-split-row").find((r) => r.dataset.auiDestId === String(destId));

test("NavigationSplitView: a narrow width collapses to a single column (sidebar first)", () => {
    const { root } = build(NSV);
    const split = findByClass(root, "aui-nav-split");
    assert.equal(split.dataset.compact, undefined, "expanded by default");
    dom.fireResize(split, 400);
    assert.equal(split.dataset.compact, "true", "compact below the threshold");
    assert.equal(split.dataset.compactPane, "sidebar", "no selection -> the sidebar shows");
});

test("NavigationSplitView: selecting a row in compact flips to the detail pane", () => {
    const { root, dispatched } = build(NSV);
    const split = findByClass(root, "aui-nav-split");
    dom.fireResize(split, 400);
    rowFor(split, 70).fire("click");
    assert.equal(split.dataset.compactPane, "detail", "a selection shows the detail column");
    assert.ok(dispatched.some((d) => d.id === "pick" && d.viewID === 51), "the sidebar actionID fired");
});

test("NavigationSplitView: the compact Back affordance deselects (back to the sidebar)", () => {
    const { root, dispatched } = build(NSV);
    const split = findByClass(root, "aui-nav-split");
    dom.fireResize(split, 400);
    rowFor(split, 70).fire("click");
    const back = findByClass(split, "aui-nav-split-back");
    assert.ok(back, "a Back affordance exists in the selection-driven split");
    back.fire("click");
    assert.equal(split.dataset.compactPane, "sidebar", "Back returns to the sidebar");
    assert.equal(dispatched.filter((d) => d.id === "pick").length, 2, "Back fires the sidebar actionID (now deselected)");
});

test("NavigationSplitView: a wide width restores the expanded columns", () => {
    const { root } = build(NSV);
    const split = findByClass(root, "aui-nav-split");
    dom.fireResize(split, 400);
    assert.equal(split.dataset.compact, "true");
    dom.fireResize(split, 1000);
    assert.equal(split.dataset.compact, undefined, "expanded again above the threshold");
});

test("NavigationSplitView: compact fills the sidebar's rail width, expand restores it", () => {
    const { root } = build(NSV);
    const split = findByClass(root, "aui-nav-split");
    const sidebar = findByClass(split, "aui-nav-split-sidebar");
    assert.equal(sidebar.style.width, "200px", "the declared rail width while expanded");
    dom.fireResize(split, 400);
    assert.equal(sidebar.style.width, "auto", "fills the column while compact");
    dom.fireResize(split, 1000);
    assert.equal(sidebar.style.width, "200px", "the declared rail width restored on expand");
});

const TABVIEW = (style) => ({
    type: "TabView", id: 80, properties: { style },
    children: [
        { type: "Tab", properties: { title: "Home" }, content: { type: "Text", properties: { text: "H" } } },
        { type: "Tab", properties: { title: "Settings" }, content: { type: "Text", properties: { text: "S" } } },
    ],
});

test("TabView sidebarAdaptable: a narrow width collapses the rail to a top strip", () => {
    const { root } = build(TABVIEW("sidebarAdaptable"));
    const tv = findByClass(root, "aui-tabview");
    assert.equal(tv.classList.contains("aui-tabview-compact"), false, "the rail by default");
    dom.fireResize(tv, 400);
    assert.ok(tv.classList.contains("aui-tabview-compact"), "the strip when narrow");
    dom.fireResize(tv, 800);
    assert.equal(tv.classList.contains("aui-tabview-compact"), false, "the rail again when wide");
});

test("TabView automatic (top strip): no rail, so no responsive collapse", () => {
    const { root } = build(TABVIEW("automatic"));
    const tv = findByClass(root, "aui-tabview");
    dom.fireResize(tv, 400);
    assert.equal(tv.classList.contains("aui-tabview-compact"), false, "the top strip is already compact - no observer");
});
