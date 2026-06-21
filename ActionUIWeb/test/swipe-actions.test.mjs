// Tests for the `swipeActions` View modifier (src/Helpers/SwipeActionsModifier.js),
// the web side of Apple's `.swipeActions` / Android's swipe-to-reveal.
//
// swipeActions is a TOP-LEVEL subview key holding real Button elements (not a property
// descriptor array), mirroring SwiftUI's `.swipeActions(edge:allowsFullSwipe:)`. So these
// exercise: the pure settle decision (the threshold math, no layout needed - the pure/DOM
// test split), the wrapping DOM build (edge panels behind a translating content layer), and
// an action tap dispatching that Button's own actionID. The pointer gesture itself is
// verified by running the app (it needs real layout/pointer events).

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeElement, makeLogger } from "./dom-stub.mjs";
import { wrapWithSwipeActions, swipeSettleTarget, swipeEdge, swipeIsStacked } from "../src/Helpers/SwipeActionsModifier.js";
import { ActionUIElement } from "../src/Common/ActionUIElement.js";

before(async () => {
    installDom();
    await import("../src/ActionUI.js"); // registers views; SymbolIcon helpers load
});

// Parses an element so its swipeActions subviews are real ActionUIElement subtrees, then
// wraps it with a dispatch spy. Returns the wrapper, its panels, and the dispatched calls.
function wired(raw) {
    installDom();
    const logger = makeLogger();
    const element = ActionUIElement.fromObject({ type: "Text", id: 7, ...raw }, logger);
    const node = makeElement("div");
    node.dataset.auiId = "7";
    const dispatched = [];
    const ctx = { logger, model: { dispatchAction: (...args) => dispatched.push(args) } };
    const wrapped = wrapWithSwipeActions(node, element, element.properties, ctx);
    const panels = (wrapped.children ?? []).filter(
        (c) => typeof c.className === "string" && c.className.includes("aui-swipe-actions"),
    );
    const leadingPanel = panels.find((p) => p.className.includes("leading"));
    const trailingPanel = panels.find((p) => p.className.includes("trailing"));
    return { wrapped, node, leadingPanel, trailingPanel, dispatched };
}

const GEOM = { leadingWidth: 80, trailingWidth: 160, rowWidth: 400, leadingFull: true, trailingFull: true };

test("swipeEdge defaults to trailing; honors a declared leading", () => {
    assert.equal(swipeEdge({ properties: { edge: "leading" } }), "leading");
    assert.equal(swipeEdge({ properties: { edge: "trailing" } }), "trailing");
    assert.equal(swipeEdge({ properties: {} }), "trailing");
    assert.equal(swipeEdge({}), "trailing");
});

test("settle: a small drag snaps closed", () => {
    assert.deepEqual(swipeSettleTarget(20, GEOM), { target: 0, fire: null });   // < leadingWidth/2
    assert.deepEqual(swipeSettleTarget(-50, GEOM), { target: 0, fire: null });  // < trailingWidth/2
});

test("settle: past half the edge width reveals (opens) that edge", () => {
    assert.deepEqual(swipeSettleTarget(60, GEOM), { target: 80, fire: null });    // leading reveal
    assert.deepEqual(swipeSettleTarget(-120, GEOM), { target: -160, fire: null }); // trailing reveal
});

test("settle: a full swipe (past half the row) fires that edge's first button and closes", () => {
    assert.deepEqual(swipeSettleTarget(250, GEOM), { target: 0, fire: "leadingFirst" });
    assert.deepEqual(swipeSettleTarget(-250, GEOM), { target: 0, fire: "trailingFirst" });
});

test("settle: allowsFullSwipe=false reveals instead of firing on a full swipe", () => {
    const g = { ...GEOM, trailingFull: false };
    assert.deepEqual(swipeSettleTarget(-250, g), { target: -160, fire: null });
});

test("no swipeActions subview is a no-op (returns the node unchanged)", () => {
    const { wrapped, node } = wired({});
    assert.equal(wrapped, node, "same node, no wrapper");
});

test("builds leading + trailing panels with one button each per edge", () => {
    const { wrapped, leadingPanel, trailingPanel, node } = wired({
        swipeActions: [
            { type: "Button", id: 2, properties: { title: "Flag", systemImage: "flag", tint: "orange", edge: "leading", actionID: "row.flag" } },
            { type: "Button", id: 3, properties: { title: "Archive", systemImage: "archivebox", edge: "trailing", actionID: "row.archive" } },
            { type: "Button", id: 4, properties: { title: "Delete", role: "destructive", edge: "trailing", actionID: "row.delete" } },
        ],
    });
    assert.notEqual(wrapped, node, "node is wrapped");
    assert.ok(wrapped.className.includes("aui-swipe-row"));
    assert.equal(leadingPanel.children.length, 1, "one leading action");
    assert.equal(trailingPanel.children.length, 2, "two trailing actions");
});

test("swipeIsStacked: a tall row stacks (icon over label); a short row goes inline", () => {
    assert.equal(swipeIsStacked(64), true);
    assert.equal(swipeIsStacked(40), false);
});

test("a destructive action publishes red; an explicit tint publishes that color (--aui-swipe-color)", () => {
    const { leadingPanel, trailingPanel } = wired({
        swipeActions: [
            { type: "Button", id: 2, properties: { title: "Flag", tint: "orange", edge: "leading", actionID: "row.flag" } },
            { type: "Button", id: 4, properties: { title: "Delete", role: "destructive", edge: "trailing", actionID: "row.delete" } },
        ],
    });
    // The action color is published as a custom property; CSS paints the pill or the circle with it.
    assert.match(leadingPanel.children[0].style.getPropertyValue("--aui-swipe-color"), /orange/i);
    assert.match(trailingPanel.children[0].style.getPropertyValue("--aui-swipe-color"), /aui-color-red/);
    // The icon lives in a glyph wrapper (the circle in stacked mode); the title is a sibling.
    const btn = trailingPanel.children[0];
    assert.ok(btn.children.some((c) => typeof c.className === "string" && c.className.includes("aui-swipe-action-glyph")));
});

test("tapping a revealed action dispatches that Button's own actionID (viewID = the Button id)", () => {
    const { trailingPanel, dispatched } = wired({
        swipeActions: [
            { type: "Button", id: 4, properties: { title: "Delete", role: "destructive", edge: "trailing", actionID: "row.delete" } },
        ],
    });
    trailingPanel.children[0].fire("click", { stopPropagation() {} });
    assert.deepEqual(dispatched, [["row.delete", 4]]);
});
