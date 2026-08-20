// Tests for src/Common/ModifierResolver.js: resolveColor + applyViewModifiers
// (the build-time CSS application). applyElementProperty is in property-mutation.test.mjs.

import { test } from "node:test";
import assert from "node:assert/strict";
import { makeElement, makeLogger } from "./dom-stub.mjs";
import { resolveColor, applyViewModifiers, markHandlesAction, applyElementProperty } from "../src/Common/ModifierResolver.js";

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
    const hid = applied({ hidden: true }).node;
    assert.equal(hid.style.visibility, "hidden", "hidden is visibility:hidden, not display:none");
    assert.ok(!hid.style.display, "hidden never collapses the box - the space is reserved (Apple parity)");
    const cr = applied({ cornerRadius: 6 }).node;
    assert.equal(cr.style.borderRadius, "6px");
    assert.equal(cr.style.overflow, "hidden");
    assert.match(applied({ foregroundStyle: "blue" }).node.style.color, /var\(--aui-color-blue\)/);
    assert.match(applied({ background: "green" }).node.style.backgroundColor, /var\(--aui-color-green\)/);
    assert.equal(applied({ help: "tip" }).node.title, "tip");
});

// The `hidden` contract, pinned in one place because it is a cross-platform one and
// the web was the host that broke it: SwiftUI `.hidden()` (and Android's
// Modifier.hiddenSubtree()) keep the element LAID OUT while making it invisible,
// non-interactive and inaudible to assistive tech. `visibility: hidden` is all four;
// `display: none`, which this used to be, collapses the box and so laid identical JSON
// out differently here than on the other two hosts. Private/Missing_Features.md #30.
test("hidden reserves its layout space (SwiftUI .hidden() parity)", () => {
    const on = applied({ hidden: true }).node;
    assert.equal(on.style.visibility, "hidden");
    assert.ok(!on.style.display, "the box is never collapsed");

    // A sized hidden element keeps its frame, which is the space it reserves.
    const sized = applied({ hidden: true, frame: { width: 48, height: 32 } }).node;
    assert.equal(sized.style.visibility, "hidden");
    assert.equal(sized.style.width, "48px");
    assert.equal(sized.style.height, "32px");

    // Authoring hidden:false (or omitting it) touches nothing.
    assert.ok(!applied({ hidden: false }).node.style.visibility);
    assert.ok(!applied({}).node.style.visibility);
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
    assert.deepEqual(dispatched, [["go", 9, 0, null]], "click dispatches actionID with the element id");

    const handled = makeElement();
    markHandlesAction(handled);
    applyViewModifiers(handled, { id: 9 }, { actionID: "go" }, ctx);
    assert.equal(handled.listenerCount("click"), 0, "a control that handles its own action gets no generic click");
});

// --- a container actionID inside a template row -------------
//
// The whole point of a container actionID is the rich tappable cell: an avatar, a name
// and a status line under ONE target, instead of a small glyph Button inside the cell.
// That only works if the dispatch says WHICH row was tapped.

test("actionID inside a template row dispatches the owning container id and row index", () => {
    const node = makeElement();
    const dispatched = [];
    const ctx = {
        logger: makeLogger(),
        model: { dispatchAction: (...a) => dispatched.push(a) },
        templateContext: { parentID: 100, rowIndex: 4 },
    };
    // TemplateHelper forces every cloned instance's id to 0, so element.id carries no
    // row identity and never can - the context is the only source of it.
    applyViewModifiers(node, { id: 0 }, { actionID: "row.open" }, ctx);
    node.fire("click");
    assert.deepEqual(dispatched, [["row.open", 100, 4, null]],
        "dispatches (owning container id, row index), matching Views/Button.js");
});

test("row 0 dispatches the owning container id, not the cell's own", () => {
    // JS-specific hazard, and the reason this row gets its own test: 0 is falsy, so the
    // natural shorthand (`templateContext?.rowIndex ? ... : ...`, or `parentID || id`)
    // collapses "row zero" into "no template" and sends the FIRST cell - the one every
    // manual check taps first - to the wrong handler.
    const node = makeElement();
    const dispatched = [];
    const ctx = {
        logger: makeLogger(),
        model: { dispatchAction: (...a) => dispatched.push(a) },
        templateContext: { parentID: 100, rowIndex: 0 },
    };
    applyViewModifiers(node, { id: 0 }, { actionID: "row.open" }, ctx);
    node.fire("click");
    assert.deepEqual(dispatched, [["row.open", 100, 0, null]],
        "row 0 is a real row: the context decides, not the index's truthiness");
});

test("a marked descendant serves the click; the enclosing container does not also fire", () => {
    const container = makeElement();
    const dispatched = [];
    const ctx = { logger: makeLogger(), model: { dispatchAction: (...a) => dispatched.push(a) } };
    applyViewModifiers(container, { id: 7 }, { actionID: "cell.open" }, ctx);

    // Stand in for a Button: it marks itself and wires its own dispatch, as Button.js does.
    const button = makeElement("button");
    markHandlesAction(button);
    button.addEventListener("click", () => dispatched.push(["button.delete", 8, 0, null]));
    container.appendChild(button);

    button.fire("click"); // bubbles to the container, as in a browser
    assert.deepEqual(dispatched, [["button.delete", 8, 0, null]],
        "only the button's action fires - the container stands down");
});

test("a click on plain content inside the container still fires the container action", () => {
    const container = makeElement();
    const dispatched = [];
    const ctx = { logger: makeLogger(), model: { dispatchAction: (...a) => dispatched.push(a) } };
    applyViewModifiers(container, { id: 7 }, { actionID: "cell.open" }, ctx);

    const label = makeElement("span"); // a Text: no action of its own, not marked
    container.appendChild(label);

    label.fire("click");
    assert.deepEqual(dispatched, [["cell.open", 7, 0, null]],
        "unmarked content is part of the cell's tap target");
});

test("a tappable container inside another tappable container: only the inner one fires", () => {
    // Web is the only host that has to arrange this: SwiftUI resolves a tap to the innermost
    // gesture and Compose's inner clickable consumes the press, but a DOM click bubbles, so
    // without a guard BOTH containers dispatch. An avatar block with its own action inside a
    // tappable row is the ordinary shape that hits it.
    const outer = makeElement();
    const inner = makeElement();
    const dispatched = [];
    const ctx = { logger: makeLogger(), model: { dispatchAction: (...a) => dispatched.push(a) } };
    applyViewModifiers(outer, { id: 7 }, { actionID: "row.open" }, ctx);
    applyViewModifiers(inner, { id: 8 }, { actionID: "avatar.open" }, ctx);
    outer.appendChild(inner);

    inner.fire("click");
    assert.deepEqual(dispatched, [["avatar.open", 8, 0, null]],
        "the inner container serves the click; the outer one stands down");
});

test("a tappable container stops the click reaching an enclosing List row's selection", () => {
    // List rows guard with their own selector of native control tags, which a container
    // (a plain div) never matches - so without stopPropagation one click both fired the
    // cell action and selected the row, running two handlers for one gesture.
    const row = makeElement();
    const seen = [];
    row.addEventListener("click", () => seen.push("row.select"));

    const cell = makeElement();
    const ctx = { logger: makeLogger(), model: { dispatchAction: (id) => seen.push(id) } };
    applyViewModifiers(cell, { id: 7 }, { actionID: "cell.open" }, ctx);
    row.appendChild(cell);

    cell.fire("click");
    assert.deepEqual(seen, ["cell.open"], "the row's own click handler must not also run");
});

test("a blank actionID wires no tap target at all", () => {
    // Apple and Android refuse a blank action rather than dispatch an unroutable empty id;
    // web used to accept it and dispatch "". All three now agree.
    const node = makeElement();
    const dispatched = [];
    const ctx = { logger: makeLogger(), model: { dispatchAction: (...a) => dispatched.push(a) } };
    applyViewModifiers(node, { id: 7 }, { actionID: "   " }, ctx);
    assert.equal(node.listenerCount("click"), 0, "no listener is wired for a blank actionID");
    node.fire("click");
    assert.deepEqual(dispatched, [], "and nothing dispatches");
});

test("an element with NO actionID is left completely alone", () => {
    // The property that keeps this from changing hit-testing for every existing document:
    // no listener, nothing marking the node as an action handler (which would make a
    // genuinely tappable ancestor stand down for no reason), and no button semantics
    // announced to a screen reader for a plain layout box.
    const node = makeElement();
    const ctx = { logger: makeLogger(), model: { dispatchAction: () => {} } };
    applyViewModifiers(node, { id: 7 }, { padding: 8 }, ctx);
    assert.equal(node.listenerCount("click"), 0, "no click listener");
    assert.equal(node.dataset.auiHandlesAction, undefined, "not marked as handling an action");
    assert.equal(node.role, undefined, "no button role");
    assert.equal(node.tabIndex, undefined, "not in the tab order");
});

test("a tappable container is reachable by keyboard and announced as a button", () => {
    // A bare div with a click listener is invisible to a screen reader and unreachable by
    // keyboard. Without this the whole-cell pattern would be better for a mouse and worse
    // for everyone else, which is the opposite of why it is recommended over a small
    // leading-glyph Button.
    const node = makeElement();
    const dispatched = [];
    const ctx = { logger: makeLogger(), model: { dispatchAction: (...a) => dispatched.push(a) } };
    applyViewModifiers(node, { id: 7 }, { actionID: "cell.open" }, ctx);

    assert.equal(node.role, "button", "announced as a button");
    assert.equal(node.tabIndex, 0, "reachable by Tab");

    node.fire("keydown", { key: "Enter" });
    assert.deepEqual(dispatched, [["cell.open", 7, 0, null]], "Enter activates it");

    node.fire("keydown", { key: " " });
    assert.equal(dispatched.length, 2, "Space activates it too");

    node.fire("keydown", { key: "a" });
    assert.equal(dispatched.length, 2, "other keys do not");
});

test("a disabled tappable container is inert to the KEYBOARD, not only to the mouse", () => {
    // The mouse is covered by CSS - `.aui-disabled { pointer-events: none }` - and that is
    // the whole defense a <div role="button"> gets, because `disabled` is not a real
    // attribute on a div. pointer-events does nothing to focus or keydown, so a disabled
    // cell stayed keyboard-activatable while looking inert: "disabled is honored on all
    // three hosts" was true for a pointer and false for Enter/Space.
    const node = makeElement();
    const dispatched = [];
    const ctx = { logger: makeLogger(), model: { dispatchAction: (...a) => dispatched.push(a) } };
    applyViewModifiers(node, { id: 7 }, { actionID: "cell.open", disabled: true }, ctx);

    assert.equal(node.tabIndex, -1, "kept out of the tab order");
    node.fire("keydown", { key: "Enter" });
    node.fire("keydown", { key: " " });
    node.fire("click");
    assert.deepEqual(dispatched, [], "neither key nor click dispatches");
});

test("a container disabled by an ANCESTOR is inert too", () => {
    // The other half: Apple needs two separate routes for this (resolve() for the
    // container's own `disabled`, \.isEnabled for an inherited one), so the web must not
    // answer only the first. The class is on the ancestor, never on this node.
    const outer = makeElement();
    outer.classList.add("aui-disabled");
    const node = makeElement();
    const dispatched = [];
    const ctx = { logger: makeLogger(), model: { dispatchAction: (...a) => dispatched.push(a) } };
    applyViewModifiers(node, { id: 7 }, { actionID: "cell.open" }, ctx);
    outer.appendChild(node);

    node.fire("keydown", { key: "Enter" });
    node.fire("click");
    assert.deepEqual(dispatched, [], "an inherited disable suppresses the cell action");
});

test("re-enabling through setElementProperty restores the cell action", () => {
    // The guard is asked at EVENT time rather than wire time precisely so a host can flip
    // `disabled` later; a wire-time-only check would leave the cell permanently dead.
    const node = makeElement();
    const dispatched = [];
    const ctx = { logger: makeLogger(), model: { dispatchAction: (...a) => dispatched.push(a) } };
    applyViewModifiers(node, { id: 7 }, { actionID: "cell.open", disabled: true }, ctx);
    node.fire("click");
    assert.deepEqual(dispatched, [], "inert while disabled");

    applyElementProperty(node, "disabled", false, makeLogger());
    node.fire("click");
    assert.deepEqual(dispatched, [["cell.open", 7, 0, null]], "live again once re-enabled");
});

test("a marked ancestor ABOVE the container does not suppress the container's action", () => {
    const outer = makeElement();
    markHandlesAction(outer); // e.g. a List row that handles its own selection
    const container = makeElement();
    const dispatched = [];
    const ctx = { logger: makeLogger(), model: { dispatchAction: (...a) => dispatched.push(a) } };
    applyViewModifiers(container, { id: 7 }, { actionID: "cell.open" }, ctx);
    outer.appendChild(container);

    container.fire("click");
    assert.deepEqual(dispatched, [["cell.open", 7, 0, null]],
        "the walk stops at the container - what is above it answers for itself");
});

test("onAppearActionID fires once after mount, with id + null context, guarded per node", async () => {
    const dispatched = [];
    const ctx = { logger: makeLogger(), model: { dispatchAction: (...a) => dispatched.push(a) } };
    const node = makeElement();
    applyViewModifiers(node, { id: 5 }, { onAppearActionID: "init" }, ctx);
    assert.deepEqual(dispatched, [], "does not fire synchronously during build (waits for mount)");

    await Promise.resolve(); // flush the microtask
    assert.deepEqual(dispatched, [["init", 5, 0, null]], "fires once with (actionID, id, viewPartID 0, null context)");

    // Re-applying to the same node (a rebuild) must not re-fire: it is guarded per node.
    applyViewModifiers(node, { id: 5 }, { onAppearActionID: "init" }, ctx);
    await Promise.resolve();
    assert.equal(dispatched.length, 1, "guarded per node: no second fire on the same node");
});
