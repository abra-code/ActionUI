// EdgeSwipe.js - the left-edge "swipe back" gesture (the iOS interactive-pop idiom).
//
// A touch that STARTS near an element's left edge and travels right far enough,
// dominated by the horizontal axis, reads as "go back": a NavigationStack pops, a
// compact NavigationSplitView returns to its sidebar. Touch-only (there is no mouse
// equivalent); the Back button and Escape stay for every other input. The decision
// is a pure function so the thresholds are unit-testable without synthetic touches.

const EDGE_START = 28;   // px from the element's left edge the swipe must begin within
const MIN_DISTANCE = 64; // px of rightward travel to count as a back

// Pure: is this touch path a left-edge back-swipe? `edgeOffset` is the start point's
// distance from the element's left edge; `dx`/`dy` are the end-minus-start deltas.
// Exported for unit testing.
export function isBackSwipe({ edgeOffset, dx, dy }) {
    if (edgeOffset < 0 || edgeOffset > EDGE_START) return false; // must begin at the left edge
    if (dx < MIN_DISTANCE) return false;                         // enough rightward travel
    if (Math.abs(dy) > Math.abs(dx)) return false;               // horizontal-dominant
    return true;
}

// Wires the gesture on `element`: a left-edge rightward swipe calls onBack(), but
// only when canGoBack() is true (there is somewhere to go back to). Passive
// listeners, so vertical scrolling is never blocked; feature-detected for the
// headless DOM. The element's measured left edge anchors the edge zone, so the
// gesture works whether or not the element sits flush against the viewport.
export function attachEdgeBackSwipe(element, canGoBack, onBack) {
    if (!element || typeof element.addEventListener !== "function") return;
    let startX = null;
    let startY = null;
    element.addEventListener("touchstart", (event) => {
        const touch = event.touches && event.touches[0];
        startX = touch ? touch.clientX : null;
        startY = touch ? touch.clientY : null;
    }, { passive: true });
    element.addEventListener("touchend", (event) => {
        if (startX === null) return;
        const touch = event.changedTouches && event.changedTouches[0];
        if (touch && canGoBack()) {
            const left = typeof element.getBoundingClientRect === "function"
                ? element.getBoundingClientRect().left : 0;
            if (isBackSwipe({ edgeOffset: startX - left, dx: touch.clientX - startX, dy: touch.clientY - startY })) {
                onBack();
            }
        }
        startX = null;
        startY = null;
    }, { passive: true });
}
