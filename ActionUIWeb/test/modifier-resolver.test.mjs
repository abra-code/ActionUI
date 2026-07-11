// Tests for src/Common/ModifierResolver.js: resolveColor + applyViewModifiers
// (the build-time CSS application). applyElementProperty is in property-mutation.test.mjs.

import { test } from "node:test";
import assert from "node:assert/strict";
import { makeElement, makeLogger } from "./dom-stub.mjs";
import { resolveColor, applyViewModifiers, markHandlesAction } from "../src/Common/ModifierResolver.js";

test("resolveColor: named -> CSS var, hex pass-through, unknown warns -> null", () => {
    const logger = makeLogger();
    assert.match(resolveColor("red", logger), /var\(--aui-color-red\)/);
    assert.equal(resolveColor("#abc", logger), "#abc");
    assert.equal(resolveColor("#aabbccdd", logger), "#aabbccdd");
    assert.equal(resolveColor(42, logger), null, "non-string -> null");
    assert.equal(resolveColor("chartreuse", logger), null);
    assert.ok(logger.warned("Unknown color"));
});

test("resolveColor: SwiftUI <color>.opacity(<fraction>) -> color-mix toward transparent", () => {
    const logger = makeLogger();
    assert.equal(resolveColor("gray.opacity(0.15)", logger),
        "color-mix(in srgb, var(--aui-color-gray) 15%, transparent)");
    assert.equal(resolveColor("#ff0000.opacity(0.5)", logger),
        "color-mix(in srgb, #ff0000 50%, transparent)");
    assert.equal(resolveColor("black.opacity(1)", logger),
        "color-mix(in srgb, #000000 100%, transparent)");
    assert.equal(logger.warningCount(), 0, "a valid base color does not warn");
    // an unknown base still surfaces the real problem
    assert.equal(resolveColor("bogus.opacity(0.3)", logger), null);
    assert.ok(logger.warned("Unknown color"));
});

test("resolveColor: Apple semantic styles -> --aui-* tokens (the full set)", () => {
    const logger = makeLogger();
    // Hierarchical content levels.
    assert.equal(resolveColor("primary", logger), "var(--aui-color-primary)");
    assert.equal(resolveColor("secondary", logger), "var(--aui-color-secondary)");
    assert.equal(resolveColor("tertiary", logger), "var(--aui-tertiary)");
    assert.equal(resolveColor("quaternary", logger), "var(--aui-quaternary)");
    assert.equal(resolveColor("quinary", logger), "var(--aui-quinary)");
    // foreground.* (and the bare foreground).
    assert.equal(resolveColor("foreground", logger), "var(--aui-foreground)");
    assert.equal(resolveColor("foreground.secondary", logger), "var(--aui-foreground-secondary)");
    assert.equal(resolveColor("foreground.tertiary", logger), "var(--aui-foreground-tertiary)");
    assert.equal(resolveColor("foreground.quaternary", logger), "var(--aui-foreground-quaternary)");
    // Opaque layered surfaces.
    assert.equal(resolveColor("background", logger), "var(--aui-background)");
    assert.equal(resolveColor("background.secondary", logger), "var(--aui-background-secondary)");
    assert.equal(resolveColor("background.tertiary", logger), "var(--aui-background-tertiary)");
    assert.equal(resolveColor("background.quaternary", logger), "var(--aui-background-quaternary)");
    assert.equal(resolveColor("windowBackground", logger), "var(--aui-window-background)");
    // Translucent fills.
    assert.equal(resolveColor("fill", logger), "var(--aui-fill)");
    assert.equal(resolveColor("fill.secondary", logger), "var(--aui-fill-secondary)");
    assert.equal(resolveColor("fill.tertiary", logger), "var(--aui-fill-tertiary)");
    assert.equal(resolveColor("fill.quaternary", logger), "var(--aui-fill-quaternary)");
    // Discrete roles.
    assert.equal(resolveColor("separator", logger), "var(--aui-separator)");
    assert.equal(resolveColor("tint", logger), "var(--aui-tint)");
    assert.equal(resolveColor("link", logger), "var(--aui-link)");
    assert.equal(resolveColor("placeholder", logger), "var(--aui-placeholder)");
    assert.equal(resolveColor("selection", logger), "var(--aui-selection)");
    assert.equal(logger.warningCount(), 0, "every documented semantic style resolves with no warning");
});

test("resolveColor: .opacity(f) works on a semantic base via color-mix", () => {
    const logger = makeLogger();
    // The base resolves to a var() token, then color-mix fades it - the path
    // rgba()/hex math cannot take (CSS color-mix handles the var()).
    assert.equal(resolveColor("secondary.opacity(0.5)", logger),
        "color-mix(in srgb, var(--aui-color-secondary) 50%, transparent)");
    assert.equal(resolveColor("fill.tertiary.opacity(0.25)", logger),
        "color-mix(in srgb, var(--aui-fill-tertiary) 25%, transparent)");
    assert.equal(resolveColor("tint.opacity(0.8)", logger),
        "color-mix(in srgb, var(--aui-tint) 80%, transparent)");
    assert.equal(logger.warningCount(), 0, "a valid semantic base does not warn");
});

function applied(properties, element = { id: 1 }) {
    const node = makeElement();
    const dispatched = [];
    const ctx = { logger: makeLogger(), model: { dispatchAction: (...a) => dispatched.push(a) } };
    applyViewModifiers(node, element, properties, ctx);
    return { node, dispatched };
}

test("padding: number, default keyword, and per-edge object", () => {
    assert.equal(applied({ padding: 12 }).node.style.padding, "12px");
    assert.match(applied({ padding: "default" }).node.style.padding, /px$/);
    assert.equal(applied({ padding: { top: 1, bottom: 2, leading: 3, trailing: 4 } }).node.style.padding, "1px 4px 2px 3px");
});

test("opacity / hidden / cornerRadius / colors / help", () => {
    assert.equal(applied({ opacity: 0.5 }).node.style.opacity, "0.5");
    assert.equal(applied({ hidden: true }).node.style.display, "none");
    const cr = applied({ cornerRadius: 6 }).node;
    assert.equal(cr.style.borderRadius, "6px");
    assert.equal(cr.style.overflow, "hidden");
    assert.match(applied({ foregroundStyle: "blue" }).node.style.color, /var\(--aui-color-blue\)/);
    assert.match(applied({ background: "green" }).node.style.backgroundColor, /var\(--aui-color-green\)/);
    assert.equal(applied({ help: "tip" }).node.title, "tip");
});

test("font: a text style adds a class; a custom name sets fontFamily", () => {
    assert.ok(applied({ font: "title" }).node.classList.contains("aui-font-title"));
    assert.equal(applied({ font: "Courier New" }).node.style.fontFamily, "Courier New");
});

test("disabled toggles the class and the disabled property", () => {
    const node = applied({ disabled: true }).node;
    assert.ok(node.classList.contains("aui-disabled"));
    assert.equal(node.disabled, true);
});

test("scaleEffect / rotationEffect set the CSS scale / rotate", () => {
    assert.equal(applied({ scaleEffect: 1.25 }).node.style.scale, "1.25");
    assert.equal(applied({ rotationEffect: 45 }).node.style.rotate, "45deg");
});

test("frame: fixed width/height set inline px sizes", () => {
    const { node } = applied({ frame: { width: 180, height: 52 } });
    assert.equal(node.style.width, "180px");
    assert.equal(node.style.height, "52px");
});

test("frame: maxWidth infinity -> aui-fill-width (SwiftUI .frame(maxWidth: .infinity))", () => {
    // The parent stack's CSS resolves this class per axis - flex:1 1 0 (share the
    // remainder) along an HStack main axis, align-self:stretch across a VStack
    // cross axis. The CSS contract is pinned in stack-fill.test.mjs.
    const node = applied({ frame: { maxWidth: "infinity" } }).node;
    assert.ok(node.classList.contains("aui-fill-width"), "maxWidth infinity tags the node fill-width");
    assert.ok(!node.classList.contains("aui-fill-height"));
});

test("frame: maxHeight infinity -> aui-fill-height", () => {
    const node = applied({ frame: { maxHeight: "infinity" } }).node;
    assert.ok(node.classList.contains("aui-fill-height"), "maxHeight infinity tags the node fill-height");
    assert.ok(!node.classList.contains("aui-fill-width"));
});

test("frame: a finite maxWidth GROWS to the cap via the CAP class (alignment-respecting)", () => {
    // SwiftUI .frame(maxWidth: N) grows the view UP TO N, positioned by the parent.
    // So a bare finite maxWidth both caps AND tags the axis-aware CAP class (flex
    // along an HStack main axis, width:100% across a VStack cross axis so the
    // parent still centers it) - NOT the fill class, which would stretch/anchor it.
    const { node } = applied({ frame: { maxWidth: 300 } });
    assert.equal(node.style.maxWidth, "min(300px, 100%)");
    assert.ok(node.classList.contains("aui-cap-width"), "a finite maxWidth grows to its cap");
    assert.ok(!node.classList.contains("aui-fill-width"), "finite cap is not the infinity fill (would stretch)");
});

test("frame: a finite maxWidth does NOT grow when the width is already pinned", () => {
    // An explicit width / idealWidth on the same axis pins it; the cap then only bounds.
    const pinned = applied({ frame: { idealWidth: 200, maxWidth: 300 } }).node;
    assert.ok(!pinned.classList.contains("aui-cap-width"), "a pinned width is not overridden by grow-to-cap");
    assert.ok(!pinned.classList.contains("aui-fill-width"));
});

test("frame: minWidth sets a hard floor", () => {
    assert.equal(applied({ frame: { minWidth: 120 } }).node.style.minWidth, "120px");
});

test("FILLS: a sized frame and a background land on the SAME node (background fills the frame)", () => {
    // The cross-platform FILLS contract on Web: the renderer is single-node, so a
    // frame's size and the background color sit on one element - the fill covers
    // the framed box with no content-hugging wrapper, mirroring the reordered
    // Apple pipeline (frame before background) and the Android sizing/decoration split.
    const { node } = applied({ frame: { width: 180, height: 52 }, background: "green" });
    assert.equal(node.style.width, "180px");
    assert.equal(node.style.height, "52px");
    assert.match(node.style.backgroundColor, /var\(--aui-color-green\)/);
});

test("actionID wires a click that dispatches; markHandlesAction opts out", () => {
    const node = makeElement();
    const dispatched = [];
    const ctx = { logger: makeLogger(), model: { dispatchAction: (...a) => dispatched.push(a) } };
    applyViewModifiers(node, { id: 9 }, { actionID: "go" }, ctx);
    node.fire("click");
    assert.deepEqual(dispatched, [["go", 9]], "click dispatches actionID with the element id");

    const handled = makeElement();
    markHandlesAction(handled);
    applyViewModifiers(handled, { id: 9 }, { actionID: "go" }, ctx);
    assert.equal(handled.listenerCount("click"), 0, "a control that handles its own action gets no generic click");
});
