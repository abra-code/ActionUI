// TransitionModifier.js — the `transition` modifier (insert/remove animations).
// Web analog of Apple's resolveTransition (View.swift) / Android's TransitionHelper.kt.
// SwiftUI's `.transition()` defines how a view animates when it is structurally
// inserted/removed at runtime (via insertElement / removeElement, gap #21). On the
// web that entrance is played by ActionUIModel.insertElement: the freshly-mounted
// node is set to a "from" state (offset / scaled / transparent) and then eased to
// its natural state with a CSS transition.
//
// JSON: "transition": "opacity"   (shorthand: opacity | slide | scale | identity), or
//       "transition": { "type": "move", "edge": "bottom" }   (dict), or
//       "transition": ["opacity", { "type": "scale", "scale": 0.8 }]   (array = combined).
// Types: opacity, slide, scale (+ scale factor, anchor), move (+ edge), offset (+ x/y),
//        identity, asymmetric (+ insertion/removal). Mirrors Apple's validateProperties.
//
// Web specifics / divergences:
//   * Only the INSERTION (entrance) is animated. Removal/exit is instant: removeElement
//     drops the node synchronously, with no deferred-removal manager to play an exit, so
//     the `removal` half of an `asymmetric` transition is a documented no-op. (Apple gets
//     exit for free from SwiftUI.) This matches the Android renderer's entrance-only support.
//   * `slide` and `move` slide by the node's own size (translate %), the CSS analog of
//     SwiftUI's edge move. `offset` uses fixed px.
//   * Only runtime inserts animate; the initial page render does not (the entrance is
//     kicked off from insertElement, not at build), matching Apple's "instant at load".
//   * Respects `prefers-reduced-motion: reduce` (skips the animation; the node just appears).

import { prefersReducedMotion } from "./Modality.js";

const VALID_TYPES = new Set(["opacity", "slide", "scale", "move", "offset", "identity", "asymmetric"]);

// Default entrance duration (seconds), matching the animation modifier's time-based default.
const DURATION = 0.35;

// requestAnimationFrame in the browser; a microtask-ish fallback under the headless test stub.
const nextFrame = (fn) =>
    (typeof requestAnimationFrame === "function") ? requestAnimationFrame(fn) : setTimeout(fn, 0);

const moveTransform = (edge) => {
    switch (edge) {
        case "top": return "translateY(-100%)";
        case "leading": return "translateX(-100%)";
        case "trailing": return "translateX(100%)";
        default: return "translateY(100%)"; // bottom (default)
    }
};

const anchorOrigin = (anchor) => {
    switch (anchor) {
        case "leading": return "left center";
        case "trailing": return "right center";
        case "top": return "center top";
        case "bottom": return "center bottom";
        case "topLeading": return "left top";
        case "topTrailing": return "right top";
        case "bottomLeading": return "left bottom";
        case "bottomTrailing": return "right bottom";
        default: return null; // center (CSS default)
    }
};

// Computes the entrance "from" state for a `transition` declaration: a shorthand
// string, a dict, or an array (= combined). Returns { opacity?, transform?,
// transformOrigin? } or null when absent / invalid / a pure identity (nothing to play).
export function transitionFromState(value) {
    if (value == null) return null;
    if (Array.isArray(value)) {
        let opacity, transformOrigin;
        const transforms = [];
        for (const entry of value) {
            const f = transitionFromState(entry);
            if (!f) continue;
            if (f.opacity !== undefined) opacity = f.opacity;
            if (f.transform) transforms.push(f.transform);
            if (f.transformOrigin) transformOrigin = f.transformOrigin;
        }
        if (opacity === undefined && transforms.length === 0) return null;
        return clean({ opacity, transform: transforms.join(" ") || undefined, transformOrigin });
    }
    const cfg = typeof value === "string" ? { type: value } : value;
    if (!cfg || typeof cfg !== "object" || !VALID_TYPES.has(cfg.type)) return null;
    switch (cfg.type) {
        case "identity": return null;
        case "opacity": return { opacity: 0 };
        case "slide": return { transform: "translateX(-100%)" }; // SwiftUI slide enters from leading
        case "scale": {
            const factor = typeof cfg.scale === "number" ? cfg.scale : 0;
            return clean({ transform: `scale(${factor})`, transformOrigin: anchorOrigin(cfg.anchor) });
        }
        case "move": return { transform: moveTransform(cfg.edge) };
        case "offset": return { transform: `translate(${cfg.x ?? 0}px, ${cfg.y ?? 0}px)` };
        case "asymmetric": return transitionFromState(cfg.insertion);
        default: return null;
    }
}

// Drops null / undefined keys so tests can assert exact shapes.
function clean(obj) {
    for (const k of Object.keys(obj)) if (obj[k] == null) delete obj[k];
    return Object.keys(obj).length ? obj : null;
}

// Plays the insertion entrance on a freshly-mounted [node]: snaps it to the
// transition's "from" state (no transition), then on the next frame arms a CSS
// transition and releases it to the natural state so it eases in. A no-op when the
// transition is absent / identity, the node is missing, or reduced-motion is on.
export function playEnterTransition(node, value) {
    if (!node || !node.style) return;
    if (prefersReducedMotion()) return;
    const from = transitionFromState(value);
    if (!from) return;

    const restoreTransition = node.style.transition || "";
    node.style.transition = "none";
    if (from.opacity !== undefined) node.style.opacity = String(from.opacity);
    if (from.transform) node.style.transform = from.transform;
    if (from.transformOrigin) node.style.transformOrigin = from.transformOrigin;

    // Commit the "from" state before arming the transition (a layout read forces reflow).
    void node.offsetWidth;

    nextFrame(() => {
        node.style.transition = `opacity ${DURATION}s ease, transform ${DURATION}s ease`;
        if (from.opacity !== undefined) node.style.opacity = "";
        if (from.transform) node.style.transform = "";
        // Restore the prior transition (e.g. one armed by the animation modifier) after the run.
        setTimeout(() => {
            node.style.transition = restoreTransition;
            if (from.transformOrigin) node.style.transformOrigin = "";
        }, DURATION * 1000 + 50);
    });
}
