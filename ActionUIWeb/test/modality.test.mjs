// Tests for the shared modality predicates (src/Helpers/Modality.js): the
// size-class / input-modality checks that the Menu, the popover presentation, and
// the animated navigation views branch on. They read window.matchMedia, which the
// headless stub now resolves against setViewportWidth / setReducedMotion (the same
// controller pattern as fireResize), so the compact-width and reduced-motion
// branches are unit-testable here rather than only in a browser.

import { test, before, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { installDom } from "./dom-stub.mjs";

let isCompactWidth, prefersReducedMotion, dom;

before(async () => {
    dom = installDom();
    ({ isCompactWidth, prefersReducedMotion } = await import("../src/Helpers/Modality.js"));
});
beforeEach(() => { dom = installDom(); }); // reset the stub's media state per test

test("isCompactWidth is false at the wide default viewport", () => {
    // The stub defaults to 1024px wide, so a desktop render keeps the anchored path.
    assert.equal(isCompactWidth(), false);
});

test("isCompactWidth is true at and below the 480px breakpoint", () => {
    dom.setViewportWidth(480);
    assert.equal(isCompactWidth(), true, "480 is compact (max-width inclusive)");
    dom.setViewportWidth(390); // an iPhone-class width
    assert.equal(isCompactWidth(), true);
});

test("isCompactWidth is false just above the breakpoint", () => {
    dom.setViewportWidth(481);
    assert.equal(isCompactWidth(), false);
});

test("prefersReducedMotion follows the OS flag", () => {
    assert.equal(prefersReducedMotion(), false, "motion is on by default");
    dom.setReducedMotion(true);
    assert.equal(prefersReducedMotion(), true);
});

test("the two predicates are independent axes", () => {
    // Touch/compact width and reduced-motion are orthogonal: a wide screen can still
    // request reduced motion, and a narrow screen need not.
    dom.setViewportWidth(390);
    assert.equal(isCompactWidth(), true);
    assert.equal(prefersReducedMotion(), false);
});

test("predicates are false when matchMedia is absent (defensive)", () => {
    const saved = global.window;
    global.window = {}; // a window with no matchMedia
    try {
        assert.equal(isCompactWidth(), false);
        assert.equal(prefersReducedMotion(), false);
    } finally {
        global.window = saved;
    }
});
