// Tests for the `animation` modifier (src/Helpers/AnimationModifier.js).
// Reconstructs the assertions recorded in Private/Commit_Notes_Web_Animation.md.

import { test } from "node:test";
import assert from "node:assert/strict";
import { installDom, makeElement, makeLogger } from "./dom-stub.mjs";
import { resolveAnimation, applyAnimation } from "../src/Helpers/AnimationModifier.js";

const near = (a, b) => Math.abs(a - b) < 1e-9;

test("shorthand curves resolve to default durations", () => {
    const logger = makeLogger();
    const spring = resolveAnimation("spring", logger);
    assert.ok(spring && near(spring.duration, 0.5) && near(spring.delay, 0));
    assert.ok(spring.timing.startsWith("cubic-bezier"));
    assert.ok(near(resolveAnimation("easeOut", logger).duration, 0.35));
    assert.equal(logger.warningCount(), 0);
});

test("absent animation resolves to null", () => {
    const logger = makeLogger();
    assert.equal(resolveAnimation(undefined, logger), null);
    assert.equal(resolveAnimation(null, logger), null);
});

test("an invalid shorthand curve warns and resolves to null", () => {
    const logger = makeLogger();
    assert.equal(resolveAnimation("wobble", logger), null);
    assert.ok(logger.warned("Invalid animation curve 'wobble'"));
});

test("dict form: duration / speed / delay compose (duration / speed)", () => {
    const logger = makeLogger();
    const r = resolveAnimation({ curve: "easeIn", duration: 0.3, delay: 0.1, speed: 2 }, logger);
    assert.ok(near(r.duration, 0.15), "0.3 / speed 2 = 0.15");
    assert.ok(near(r.delay, 0.1));
    assert.equal(logger.warningCount(), 0);
});

test("a missing curve in dict form warns and resolves to null", () => {
    const logger = makeLogger();
    assert.equal(resolveAnimation({ duration: 0.3 }, logger), null);
    assert.ok(logger.warned("(missing)"));
});

test("invalid duration / delay / speed / value each warn and fall back", () => {
    let logger = makeLogger();
    let r = resolveAnimation({ curve: "linear", duration: -1 }, logger);
    assert.ok(near(r.duration, 0.35) && logger.warned("must be positive"));

    logger = makeLogger();
    r = resolveAnimation({ curve: "linear", duration: "x" }, logger);
    assert.ok(near(r.duration, 0.35) && logger.warned("expected positive Double"));

    logger = makeLogger();
    r = resolveAnimation({ curve: "linear", delay: -1 }, logger);
    assert.ok(near(r.delay, 0) && logger.warned("non-negative"));

    logger = makeLogger();
    r = resolveAnimation({ curve: "linear", speed: 0 }, logger);
    assert.ok(near(r.duration, 0.35) && logger.warned("animation.speed"));

    logger = makeLogger();
    r = resolveAnimation({ curve: "linear", value: 5 }, logger);
    assert.ok(r && logger.warned("animation.value"), "non-string value warns but still resolves");
});

test("a wrong top-level type warns and resolves to null", () => {
    const logger = makeLogger();
    assert.equal(resolveAnimation(42, logger), null);
    assert.ok(logger.warned("expected String or object"));
});

test("applyAnimation arms the transition longhands incl. scale + rotate", () => {
    installDom();
    const logger = makeLogger();
    const n = makeElement();
    applyAnimation(n, { animation: "bouncy" }, logger);
    assert.equal(n.style.transitionDuration, "0.5s");
    assert.ok(n.style.transitionTimingFunction.startsWith("cubic-bezier"));
    assert.equal(n.style.transitionDelay, "0s");
    assert.ok(n.style.transitionProperty.includes("scale"));
    assert.ok(n.style.transitionProperty.includes("rotate"));
});

test("applyAnimation is a no-op when no animation is declared", () => {
    installDom();
    const n = makeElement();
    applyAnimation(n, { padding: 8 }, makeLogger());
    assert.equal(n.style.transitionProperty, undefined);
});

test("applyAnimation respects prefers-reduced-motion (arms nothing)", () => {
    const dom = installDom();
    dom.setReducedMotion(true);
    const n = makeElement();
    applyAnimation(n, { animation: "bouncy" }, makeLogger());
    assert.equal(n.style.transitionProperty, undefined);
});
