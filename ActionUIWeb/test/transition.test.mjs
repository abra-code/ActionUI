// Tests for the `transition` modifier (src/Helpers/TransitionModifier.js): the
// pure entrance "from"-state mapping (shorthand / dict / array = combined) and the
// DOM-bound playEnterTransition (snaps the node to the from-state synchronously,
// respects reduced-motion). Web animates the INSERTION only; removal/exit is instant.

import { test } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeElement } from "./dom-stub.mjs";
import { transitionFromState, playEnterTransition } from "../src/Helpers/TransitionModifier.js";

// --- pure: transitionFromState ---

test("opacity shorthand fades from transparent", () => {
    assert.deepEqual(transitionFromState("opacity"), { opacity: 0 });
});

test("slide shorthand enters from the leading edge", () => {
    assert.deepEqual(transitionFromState("slide"), { transform: "translateX(-100%)" });
});

test("scale shorthand starts collapsed", () => {
    assert.deepEqual(transitionFromState("scale"), { transform: "scale(0)" });
});

test("identity has no entrance", () => {
    assert.equal(transitionFromState("identity"), null);
});

test("an unknown shorthand has no entrance", () => {
    assert.equal(transitionFromState("explode"), null);
});

test("null / undefined declarations have no entrance", () => {
    assert.equal(transitionFromState(null), null);
    assert.equal(transitionFromState(undefined), null);
});

test("move dict slides from the named edge", () => {
    assert.deepEqual(transitionFromState({ type: "move", edge: "bottom" }), { transform: "translateY(100%)" });
    assert.deepEqual(transitionFromState({ type: "move", edge: "top" }), { transform: "translateY(-100%)" });
    assert.deepEqual(transitionFromState({ type: "move", edge: "trailing" }), { transform: "translateX(100%)" });
});

test("scale dict carries factor and anchor origin", () => {
    assert.deepEqual(
        transitionFromState({ type: "scale", scale: 0.5, anchor: "topLeading" }),
        { transform: "scale(0.5)", transformOrigin: "left top" },
    );
});

test("offset dict translates by fixed px", () => {
    assert.deepEqual(transitionFromState({ type: "offset", x: 0, y: 20 }), { transform: "translate(0px, 20px)" });
});

test("a dict with a missing or invalid type has no entrance", () => {
    assert.equal(transitionFromState({ edge: "top" }), null);
    assert.equal(transitionFromState({ type: "warp" }), null);
});

test("asymmetric uses its insertion half", () => {
    assert.deepEqual(
        transitionFromState({ type: "asymmetric", insertion: "opacity", removal: { type: "move", edge: "bottom" } }),
        { opacity: 0 },
    );
    assert.equal(
        transitionFromState({ type: "asymmetric", insertion: "identity", removal: "opacity" }),
        null,
    );
});

test("an array combines opacity and transform from its entries", () => {
    assert.deepEqual(
        transitionFromState(["opacity", { type: "scale", scale: 0.8 }]),
        { opacity: 0, transform: "scale(0.8)" },
    );
});

test("an array skips identity / invalid entries", () => {
    assert.deepEqual(transitionFromState(["identity", "opacity"]), { opacity: 0 });
    assert.equal(transitionFromState(["explode", "warp"]), null);
});

// --- DOM: playEnterTransition ---

test("playEnterTransition snaps the node to the from-state synchronously", () => {
    installDom();
    const node = makeElement();
    playEnterTransition(node, "opacity");
    assert.equal(node.style.transition, "none", "the from-state is committed with no transition");
    assert.equal(node.style.opacity, "0", "the node starts transparent");
});

test("playEnterTransition sets the from-transform for a move", () => {
    installDom();
    const node = makeElement();
    playEnterTransition(node, { type: "move", edge: "bottom" });
    assert.equal(node.style.transform, "translateY(100%)");
});

test("playEnterTransition respects reduced-motion", () => {
    const dom = installDom();
    dom.setReducedMotion(true);
    const node = makeElement();
    playEnterTransition(node, "opacity");
    assert.equal(node.style.opacity ?? "", "", "reduced motion leaves the node at its natural state");
});

test("playEnterTransition is a no-op for identity / missing node", () => {
    installDom();
    const node = makeElement();
    playEnterTransition(node, "identity");
    assert.equal(node.style.opacity ?? "", "");
    assert.doesNotThrow(() => playEnterTransition(null, "opacity"));
});
