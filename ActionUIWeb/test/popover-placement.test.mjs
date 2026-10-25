// Tests for floating-panel placement (src/Helpers/PopoverPlacement.js) and the
// popover's arrow edge (src/Helpers/PresentationModifier.js): a panel opens below
// its anchor by default, as menus do, also through makeFloatingPanel as Menu,
// MenuBar, the toolbar and context menus open theirs; a popover opens on the side its arrow edge
// names, as on macOS 27 (top above the carrier, leading before it); a panel with
// no room on its side flips to the other one.

import { test, before } from "node:test";
import assert from "node:assert/strict";
import { installDom } from "./dom-stub.mjs";

let placeFloatingPanel, makeFloatingPanel, popoverSide;

before(async () => {
    installDom();
    ({ placeFloatingPanel, makeFloatingPanel } = await import("../src/Helpers/PopoverPlacement.js"));
    ({ popoverSide } = await import("../src/Helpers/PresentationModifier.js"));
});

// Runs `body` in a 1000 x 800 viewport.
function inViewport(body) {
    const saved = globalThis.document.documentElement;
    Object.defineProperty(globalThis.document, "documentElement", {
        value: { clientWidth: 1000, clientHeight: 800 }, configurable: true,
    });
    try {
        body();
    } finally {
        Object.defineProperty(globalThis.document, "documentElement", { value: saved, configurable: true });
    }
}

// An anchor at x 400...500, y 300...340 and a 120 x 60 panel.
function place(side, anchorRect = { left: 400, right: 500, top: 300, bottom: 340 }) {
    const panel = { offsetWidth: 120, offsetHeight: 60, style: {} };
    const anchor = { getBoundingClientRect: () => anchorRect };
    inViewport(() => {
        side === undefined ? placeFloatingPanel(panel, anchor) : placeFloatingPanel(panel, anchor, side);
    });
    return { left: parseFloat(panel.style.left), top: parseFloat(panel.style.top) };
}

test("a panel opens below its anchor by default, as menus do", () => {
    assert.deepEqual(place(undefined), { left: 400, top: 344 });
});

test("a menu's panel, opened with no side given, opens below its anchor", () => {
    const panel = document.createElement("div");
    Object.defineProperty(panel, "offsetWidth", { value: 120 });
    Object.defineProperty(panel, "offsetHeight", { value: 60 });
    const anchor = { getBoundingClientRect: () => ({ left: 400, right: 500, top: 300, bottom: 340 }), contains: () => false };
    const controller = makeFloatingPanel(panel, anchor, { containmentRoots: [anchor] });
    inViewport(() => controller.show());
    controller.close();
    assert.equal(panel.style.top, "344px", "below: 340 + 4");
    assert.equal(panel.style.left, "400px");
});

test("each side places the panel there", () => {
    assert.deepEqual(place("above"), { left: 400, top: 236 }, "above: 300 - 60 - 4");
    assert.deepEqual(place("below"), { left: 400, top: 344 });
    assert.deepEqual(place("leading"), { left: 276, top: 300 }, "leading, to the left: 400 - 120 - 4");
    assert.deepEqual(place("trailing"), { left: 504, top: 300 }, "trailing, to the right");
});

test("a popover opens on the side its arrow edge names, as on macOS", () => {
    assert.equal(popoverSide("top"), "above");
    assert.equal(popoverSide("bottom"), "below");
    assert.equal(popoverSide("leading"), "leading");
    assert.equal(popoverSide("trailing"), "trailing");
    assert.equal(popoverSide(undefined), "above", "SwiftUI's default arrow edge is top");
    assert.equal(popoverSide("sideways"), "above");
});

test("a panel with no room on its side flips to the other one", () => {
    const nearTop = { left: 400, right: 500, top: 10, bottom: 50 };
    assert.equal(place("above", nearTop).top, 54, "no room above: below");
    const nearLeft = { left: 10, right: 110, top: 300, bottom: 340 };
    assert.equal(place("leading", nearLeft).left, 114, "no room to the left: to the right");
});
