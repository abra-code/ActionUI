// PopoverPlacement.js — shared top-layer floating-panel placement.
// The Popover-API mechanism Menu pioneered, factored out so the element-level
// `.popover` modifier (Helpers/PresentationModifier.js) and Menu both share one
// implementation. Web analog of the placement/anchoring half of Apple's
// PopoverHelper.swift (SwiftUI does this inside `.popover`; the web has to anchor
// a top-layer element to the carrier itself).
//
// A floating panel renders in the browser top layer (the Popover API), so it
// overlays content and escapes every ancestor overflow/clip (e.g. the
// NavigationSplitView pane's overflow:scroll), the way a SwiftUI popover/menu
// escapes its window. We drive it as a "manual" popover with our own open/close
// and dismissal, NOT the declarative popovertarget invoker with auto
// light-dismiss: that keeps open/close, positioning, and dismissal uniform across
// engines (Safari's declarative-invoker and toggle-event timing diverge from
// Blink/Gecko) while still getting the top layer. When the Popover API is
// unavailable the panel degrades to a fixed, class-toggled element positioned the
// same way (no top layer, so an overflow ancestor of the host can clip it).

export const SUPPORTS_POPOVER = typeof HTMLElement !== "undefined"
    && Object.prototype.hasOwnProperty.call(HTMLElement.prototype, "popover");

const GAP = 4; // px between the anchor and the panel

// Positions `panel` (already sized by the browser) relative to `anchor` for the
// given arrowEdge. arrowEdge names the edge of the anchor the panel's arrow points
// from, i.e. the side the panel sits on: "top" => panel below (the Menu default),
// "bottom" => above, "leading" => to the right (LTR), "trailing" => to the left.
// The panel flips to the opposite side when it would overflow and there is room,
// then is clamped on-screen - the way SwiftUI menus/popovers flip and clamp.
export function placeFloatingPanel(panel, anchor, arrowEdge = "top") {
    const rect = anchor.getBoundingClientRect();
    const vw = document.documentElement.clientWidth;
    const vh = document.documentElement.clientHeight;
    const pw = panel.offsetWidth;
    const ph = panel.offsetHeight;

    let left;
    let top;
    if (arrowEdge === "leading" || arrowEdge === "trailing") {
        // Horizontal: beside the anchor, top edges aligned (clamped vertically).
        top = Math.max(GAP, Math.min(rect.top, vh - ph - GAP));
        if (arrowEdge === "leading") {
            left = rect.right + GAP;                               // to the right
            if (left + pw > vw - GAP && rect.left - pw - GAP >= GAP) left = rect.left - pw - GAP;
        } else {
            left = rect.left - pw - GAP;                           // to the left
            if (left < GAP && rect.right + pw + GAP <= vw - GAP) left = rect.right + GAP;
        }
        left = Math.max(GAP, Math.min(left, vw - pw - GAP));
    } else {
        // Vertical: left edge aligned to the anchor (clamped horizontally).
        left = Math.max(GAP, Math.min(rect.left, vw - pw - GAP));
        if (arrowEdge === "bottom") {
            top = rect.top - ph - GAP;                             // above
            if (top < GAP && rect.bottom + ph + GAP <= vh - GAP) top = rect.bottom + GAP;
        } else {
            top = rect.bottom + GAP;                               // below (default)
            if (top + ph > vh - GAP && rect.top - ph - GAP >= GAP) top = rect.top - ph - GAP;
        }
        top = Math.max(GAP, Math.min(top, vh - ph - GAP));
    }
    panel.style.left = `${left}px`;
    panel.style.top = `${top}px`;
}

// A floating-panel controller. Promotes `panel` to the top layer (or a fallback
// class), anchors it to `anchor`, keeps it placed while open (scroll/resize), and
// dismisses on an outside pointerdown or Escape. The caller wires the trigger(s)
// and reads/sets visibility through the returned controller - positioning runs
// synchronously right after show (not from the async `toggle` event, whose timing
// differs in Safari). This is event-driven floating-element placement (what any
// menu/popover needs; a native <select> does the same internally), not the JS
// measure/relayout layout loop the layout engine avoids - the browser still sizes
// the panel.
//
// Options:
//   arrowEdge          placement side (see placeFloatingPanel); default "top".
//   containmentRoots   nodes whose subtree counts as "inside" for outside-click
//                      dismissal (the panel itself is always inside); default [anchor].
//   fallbackOpenClass  class toggled on the panel when the Popover API is absent.
//   onAutoDismiss      called when an outside-click/Escape closes the panel (not a
//                      programmatic close()), so the caller can sync its own state.
export function makeFloatingPanel(panel, anchor, options = {}) {
    const {
        arrowEdge = "top",
        containmentRoots = [anchor],
        fallbackOpenClass = "is-open",
        onAutoDismiss = null,
    } = options;

    if (SUPPORTS_POPOVER) panel.setAttribute("popover", "manual"); // top layer; we own dismissal

    const place = () => placeFloatingPanel(panel, anchor, arrowEdge);
    let open = false;

    const isInside = (target) => panel.contains(target)
        || containmentRoots.some((root) => root && root.contains(target));
    const onPointerDown = (event) => { if (!isInside(event.target)) autoClose(); };
    const onKeyDown = (event) => { if (event.key === "Escape") autoClose(); };

    function bindGlobal() {
        window.addEventListener("scroll", place, true); // capture: follow a scrolling ancestor
        window.addEventListener("resize", place);
        document.addEventListener("pointerdown", onPointerDown, true);
        document.addEventListener("keydown", onKeyDown);
    }
    function unbindGlobal() {
        window.removeEventListener("scroll", place, true);
        window.removeEventListener("resize", place);
        document.removeEventListener("pointerdown", onPointerDown, true);
        document.removeEventListener("keydown", onKeyDown);
    }

    function show() {
        if (open) return;
        open = true;
        if (SUPPORTS_POPOVER) panel.showPopover();
        else panel.classList.add(fallbackOpenClass);
        place();
        bindGlobal();
    }
    function close() {
        if (!open) return;
        open = false;
        if (SUPPORTS_POPOVER) { if (panel.matches(":popover-open")) panel.hidePopover(); }
        else panel.classList.remove(fallbackOpenClass);
        unbindGlobal();
    }
    function autoClose() {
        if (!open) return;
        close();
        if (onAutoDismiss) onAutoDismiss();
    }

    return { show, close, get open() { return open; } };
}
