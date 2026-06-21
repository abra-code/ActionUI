// SwipeActionsModifier.js - the `swipeActions` View modifier.
// Web analog of Apple's `.swipeActions` (View.swift applyModifiers) and Android's
// swipe-to-reveal (Helpers/SwipeActionsHelper.kt). Honored on List rows.
//
// Why a subview slot, not a property array:
// SwiftUI's `.swipeActions(edge:allowsFullSwipe:)` is a ViewBuilder of Buttons. ActionUI
// models it like `contextMenu`: `swipeActions` is an ARRAY subview of real `Button`
// elements, each carrying its own title / systemImage / role / tint / actionID plus an
// optional `edge` ("leading"/"trailing", default trailing) and `allowsFullSwipe` (default
// true). Real Button subtrees let a designer reuse the Button surface (role colors the
// action, tint sets its background), not a bespoke descriptor array.
//
// Gesture is the platform idiom, not a port. Apple reveals the buttons on a horizontal
// swipe of a List row; the web idiom is the same swipe-to-reveal, on Pointer Events (mouse
// drag + touch). This is a WRAPPING modifier (like overlay/background decorations): it
// returns a wrapper holding the edge action panels behind an opaque, translating content
// layer that carries the original row node. The data-aui-id stays on the inner node, so
// host addressing is unaffected. Tapping a revealed Button fires its actionID and closes
// the row; a full swipe of an `allowsFullSwipe` edge fires that edge's first Button.

import { selectLabelIcon, labelIcon } from "./SymbolIcon.js";
import { resolveColor } from "../Common/ModifierResolver.js";

const FULL_SWIPE_FRACTION = 0.5;  // drag past this fraction of the row width fires the first button
const DRAG_SLOP = 6;              // px before a press is treated as a swipe (not a click)
const STACK_MIN_HEIGHT = 50;      // row >= this -> stacked (icon circle + label below), else inline pill

// Pure layout choice by row height, mirroring iOS: a tall row stacks the icon circle over the
// label; a short row puts icon + label inline in a pill. Factored out so it is unit-testable
// without layout (the pure/DOM test split).
export function swipeIsStacked(rowHeightPx) {
    return rowHeightPx >= STACK_MIN_HEIGHT;
}

/** The button's declared swipe edge, defaulting to trailing (SwiftUI's default). */
export function swipeEdge(button) {
    return button?.properties?.edge === "leading" ? "leading" : "trailing";
}

/** allowsFullSwipe for an edge: the first button declaring it (the full-swipe target), default true. */
function edgeAllowsFullSwipe(buttons) {
    for (const b of buttons) {
        const v = b?.properties?.allowsFullSwipe;
        if (typeof v === "boolean") return v;
    }
    return true;
}

// Pure settle decision: given the released drag offset and the row geometry, returns the
// offset to animate to and which button (if any) a full swipe fires. Positive offset =
// leading revealed (swiped right); negative = trailing (swiped left). Factored out of the
// DOM so the threshold logic is unit-testable without layout (the pure/DOM test split).
export function swipeSettleTarget(offset, geom) {
    const { leadingWidth, trailingWidth, rowWidth, leadingFull, trailingFull } = geom;
    if (offset > 0) { // leading side
        if (leadingFull && rowWidth > 0 && offset > rowWidth * FULL_SWIPE_FRACTION) {
            return { target: 0, fire: "leadingFirst" };
        }
        if (offset > leadingWidth * 0.5) return { target: leadingWidth, fire: null };
        return { target: 0, fire: null };
    }
    if (offset < 0) { // trailing side
        if (trailingFull && rowWidth > 0 && -offset > rowWidth * FULL_SWIPE_FRACTION) {
            return { target: 0, fire: "trailingFirst" };
        }
        if (-offset > trailingWidth * 0.5) return { target: -trailingWidth, fire: null };
        return { target: 0, fire: null };
    }
    return { target: 0, fire: null };
}

// Wraps `node` in a swipe-to-reveal container when the element declares a non-empty
// `swipeActions` subview array; otherwise returns `node` unchanged (a no-op, like the
// other wrapping modifiers). Called from ActionUIRegistry.buildElement.
export function wrapWithSwipeActions(node, element, properties, ctx) {
    const all = element.subviews?.swipeActions;
    if (!Array.isArray(all) || all.length === 0) return node;
    const leading = all.filter((b) => swipeEdge(b) === "leading");
    const trailing = all.filter((b) => swipeEdge(b) === "trailing");
    if (leading.length === 0 && trailing.length === 0) return node;

    const wrapper = document.createElement("div");
    wrapper.className = "aui-swipe-row";

    const content = document.createElement("div");
    content.className = "aui-swipe-content";
    content.appendChild(node);

    // Pick inline vs stacked from the actual row height (iOS adapts the same way). The actions
    // are hidden until a swipe, so measuring lazily on the first drag is in time; a proactive
    // rAF pass sets it earlier when available. Guarded for the headless test DOM.
    const applyLayout = () => {
        const h = content.offsetHeight || 0;
        wrapper.classList.toggle("aui-swipe-stacked", swipeIsStacked(h));
    };
    if (typeof requestAnimationFrame === "function") requestAnimationFrame(applyLayout);

    // currentOffset is the live transform; close() and the action taps animate it back.
    let currentOffset = 0;
    const setOffset = (x) => { currentOffset = x; content.style.transform = `translateX(${x}px)`; };
    const animateTo = (x) => { content.style.transition = "transform 0.2s ease"; setOffset(x); };
    const close = () => animateTo(0);

    const leadingPanel = buildPanel(leading, "leading", ctx, close);
    const trailingPanel = buildPanel(trailing, "trailing", ctx, close);
    if (leadingPanel) wrapper.appendChild(leadingPanel);
    if (trailingPanel) wrapper.appendChild(trailingPanel);
    wrapper.appendChild(content);

    const leadingFull = edgeAllowsFullSwipe(leading);
    const trailingFull = edgeAllowsFullSwipe(trailing);
    const fire = (button) => {
        if (button && typeof button.properties?.actionID === "string") {
            ctx.model.dispatchAction(button.properties.actionID, button.id);
        }
    };

    // Pointer drag: translate the content layer, then settle on release. Pointer Events
    // cover mouse + touch; `touch-action: pan-y` (CSS) lets vertical list scroll through
    // while we own the horizontal axis.
    let startX = 0, baseOffset = 0, dragging = false, draggedThisGesture = false;
    let leadW = 0, trailW = 0, rowW = 0;

    content.addEventListener("pointerdown", (event) => {
        if (event.pointerType === "mouse" && event.button !== 0) return;
        startX = event.clientX;
        baseOffset = currentOffset;
        dragging = false;
        // Set inline/stacked from the row height first, then measure (the layout changes the
        // panel widths), all before the actions are revealed by the drag.
        applyLayout();
        leadW = leadingPanel ? leadingPanel.offsetWidth : 0;
        trailW = trailingPanel ? trailingPanel.offsetWidth : 0;
        rowW = wrapper.offsetWidth;
        content.setPointerCapture?.(event.pointerId);
    });

    content.addEventListener("pointermove", (event) => {
        if (event.pointerType === "mouse" && (event.buttons & 1) === 0) return;
        const dx = event.clientX - startX;
        if (!dragging && Math.abs(dx) < DRAG_SLOP) return;
        dragging = true;
        draggedThisGesture = true;
        content.style.transition = "none";
        const min = trailingPanel ? -rowW : 0;
        const max = leadingPanel ? rowW : 0;
        setOffset(Math.max(min, Math.min(max, baseOffset + dx)));
    });

    const onUp = (event) => {
        content.releasePointerCapture?.(event.pointerId);
        if (!dragging) return; // a tap, not a swipe - leave the row as-is
        dragging = false;
        const { target, fire: which } = swipeSettleTarget(currentOffset, {
            leadingWidth: leadW, trailingWidth: trailW, rowWidth: rowW, leadingFull, trailingFull,
        });
        if (which === "leadingFirst") fire(leading[0]);
        else if (which === "trailingFirst") fire(trailing[0]);
        animateTo(target);
    };
    content.addEventListener("pointerup", onUp);
    content.addEventListener("pointercancel", onUp);

    // Swallow the click that follows a drag, so a horizontal swipe never also triggers the
    // row's own click handler (selection / a Label actionID). Capture phase, before it reaches them.
    content.addEventListener("click", (event) => {
        if (draggedThisGesture) {
            event.stopPropagation();
            event.preventDefault();
            draggedThisGesture = false;
        }
    }, true);

    return wrapper;
}

function buildPanel(buttons, edge, ctx, close) {
    if (buttons.length === 0) return null;
    const panel = document.createElement("div");
    panel.className = `aui-swipe-actions aui-swipe-actions-${edge}`;
    for (const button of buttons) panel.appendChild(buildSwipeButton(button, ctx, close));
    return panel;
}

function buildSwipeButton(button, ctx, close) {
    const props = button.properties ?? {};
    const el = document.createElement("button");
    el.type = "button";
    el.className = "aui-swipe-action";

    // The action color (role:destructive -> red; explicit tint -> that color; else neutral gray)
    // is published as a custom property so one DOM structure serves both layouts: the CSS paints
    // the whole pill with it (inline mode) or just the icon circle with it (stacked mode).
    const color = props.role === "destructive"
        ? "var(--aui-color-red)"
        : (typeof props.tint === "string" ? (resolveColor(props.tint, ctx.logger) ?? "var(--aui-color-gray)") : "var(--aui-color-gray)");
    el.style.setProperty("--aui-swipe-color", color);

    // icon (in its glyph wrapper) + optional title; CSS arranges them inline or stacked.
    const glyph = document.createElement("span");
    glyph.className = "aui-swipe-action-glyph";
    const icon = labelIcon(selectLabelIcon(props, "assetImage", "Swipe action", ctx.logger), props, "Swipe action", ctx.logger);
    if (icon) glyph.appendChild(icon);
    el.appendChild(glyph);

    if (typeof props.title === "string" && props.title.length > 0) {
        const title = document.createElement("span");
        title.className = "aui-swipe-action-title";
        title.textContent = props.title;
        el.appendChild(title);
    }

    el.addEventListener("click", (event) => {
        event.stopPropagation();
        if (typeof props.actionID === "string") ctx.model.dispatchAction(props.actionID, button.id);
        close();
    });
    return el;
}
