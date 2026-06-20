// Modality.js - input-modality and size-class predicates shared across views.
//
// Two Web-Platform media checks that several views branch on, factored here so
// there is one source of truth - and one place the headless test DOM can drive
// (the dom-stub's controllable matchMedia: setViewportWidth / setReducedMotion):
//   * isCompactWidth()       - the phone-width size class (Apple's compact
//     horizontal size class) where a Menu / popover presents as a bottom sheet
//     and a split collapses to one column. 480px is the breakpoint the
//     bottom-sheet theme rules key off, so JS and CSS agree on "compact".
//   * prefersReducedMotion() - the user asked the OS to minimize animation, so the
//     WAAPI navigation / cross-fade transitions skip their motion (the end state
//     is applied instantly) and the implicit `animation` transition is not armed.
//
// Both are feature-detected (no window / no matchMedia -> false), so a headless
// DOM defaults to the wide, motion-on path unless a test opts in. This is the
// shared owner the per-view copies (Menu, PresentationModifier, the animated
// navigation views) referred to when they noted "factor this out".

// The compact horizontal size class. Mirrors the 480px the compact-overlays theme
// block uses; keep the two in sync if either moves.
const COMPACT_MAX_WIDTH = 480;

function mediaMatches(query) {
    return typeof window !== "undefined" && typeof window.matchMedia === "function"
        && window.matchMedia(query).matches;
}

export function isCompactWidth() {
    return mediaMatches(`(max-width: ${COMPACT_MAX_WIDTH}px)`);
}

export function prefersReducedMotion() {
    return mediaMatches("(prefers-reduced-motion: reduce)");
}
