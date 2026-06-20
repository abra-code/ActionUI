// Tests for the left-edge swipe-back decision (src/Helpers/EdgeSwipe.js). The DOM
// wiring (touchstart/touchend on the NavigationStack / compact split) is not
// exercised headlessly - there are no synthetic touches in the stub - but the pure
// threshold decision, which is where the gesture is right or wrong, is pinned here.

import { test } from "node:test";
import assert from "node:assert/strict";
import { isBackSwipe } from "../src/Helpers/EdgeSwipe.js";

test("a clear left-edge rightward swipe is a back", () => {
    assert.equal(isBackSwipe({ edgeOffset: 8, dx: 120, dy: 10 }), true);
});

test("a swipe that starts away from the left edge is not a back", () => {
    // Started 200px in (e.g. a mid-content horizontal pan) - not an edge gesture.
    assert.equal(isBackSwipe({ edgeOffset: 200, dx: 120, dy: 10 }), false);
});

test("a short rightward nudge from the edge is not a back", () => {
    assert.equal(isBackSwipe({ edgeOffset: 5, dx: 30, dy: 5 }), false);
});

test("a leftward swipe from the edge is not a back", () => {
    assert.equal(isBackSwipe({ edgeOffset: 5, dx: -120, dy: 10 }), false);
});

test("a mostly-vertical drag from the edge is not a back (it is a scroll)", () => {
    assert.equal(isBackSwipe({ edgeOffset: 5, dx: 70, dy: 140 }), false);
});

test("the edge zone is inclusive at its boundary and exclusive just past it", () => {
    assert.equal(isBackSwipe({ edgeOffset: 28, dx: 100, dy: 0 }), true, "28px is still the edge");
    assert.equal(isBackSwipe({ edgeOffset: 29, dx: 100, dy: 0 }), false, "29px is past the edge");
});

test("the distance threshold is inclusive at 64px", () => {
    assert.equal(isBackSwipe({ edgeOffset: 0, dx: 64, dy: 0 }), true);
    assert.equal(isBackSwipe({ edgeOffset: 0, dx: 63, dy: 0 }), false);
});
