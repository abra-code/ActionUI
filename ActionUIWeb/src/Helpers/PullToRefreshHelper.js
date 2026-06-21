// PullToRefreshHelper.js - the pull-to-refresh gesture + indicator for scrollable
// views (List / ScrollView). The web side of the cross-platform feature whose
// Apple parity is the `.refreshable` modifier and whose Android parity is the
// Material3 `PullToRefreshBox` (see Helpers/PullToRefreshHelper.kt).
//
// Same JSON contract as Apple/Android: an optional `onRefreshActionID` string on
// List / ScrollView enables it; absence is a no-op (the view renders unchanged).
//
// There is no per-element native pull-to-refresh on the web - the browser's only
// pull-to-refresh is the document reloading on overscroll - so this is a custom
// touch gesture (the mobile idiom; touch-only, like the EdgeSwipe back gesture).
// A downward drag that STARTS at the top of the scroll viewport reveals a spinner;
// releasing past a threshold fires the actionID through ActionUIModel.beginRefresh.
// The model holds the indicator up until the client delivers fresh data to this
// view or anything inside it (any setElementValue/setElementState - see
// ActionUIModel.endRefreshTargeting) or a safety timeout elapses, then runs the
// `onEnd` below to retract it. No dedicated "done" API, matching Apple/Android.
//
// The threshold/resistance math is pure (exported) so it is unit-testable without
// synthetic touches, exactly as EdgeSwipe.js factors `isBackSwipe`.

// Travel (px) the finger must drag down past the top to arm a refresh on release.
export const PULL_THRESHOLD = 64;
// Resting height (px) the indicator holds at while the refresh runs.
export const INDICATOR_HEIGHT = 36;
// Rubber-band: the indicator follows the finger at half speed, capped, so the pull
// feels elastic rather than 1:1 and cannot grow without bound.
const PULL_RESISTANCE = 0.5;
const PULL_MAX = 96;

// Pure: the indicator height to show for a raw downward drag of `dy` px (0 for a
// non-downward drag). Exported for unit testing.
export function resistedPull(dy) {
    if (dy <= 0) return 0;
    return Math.min(dy * PULL_RESISTANCE, PULL_MAX);
}

// Pure: has the finger dragged down far enough to arm a refresh on release?
// Exported for unit testing.
export function isRefreshPull(dy) {
    return dy >= PULL_THRESHOLD;
}

// Wraps a scrollable element's node in a pull-to-refresh container when the element
// carries an `onRefreshActionID`, otherwise returns `scrollNode` unchanged (zero
// layout change for the common, non-refresh case). Called from the build pipeline
// for the views that opt in (List / ScrollView, gated by `construction.refreshable`
// in ActionUIRegistry.buildElementView); `scrollNode` is the element's own node,
// which keeps its `data-aui-id` so host addressing is unaffected by the wrap.
export function wrapWithPullToRefresh(scrollNode, element, properties, ctx) {
    const actionID = properties.onRefreshActionID;
    if (typeof actionID !== "string" || actionID === "") return scrollNode;
    const viewID = element.id;

    const wrapper = document.createElement("div");
    wrapper.className = "aui-refresh";

    // The indicator: a flex row above the content whose height grows with the pull
    // (a CSS spin on the glyph runs while refreshing). Height 0 at rest, so nothing
    // shows until pulled; growing it pushes the content down via the flex column.
    const spinner = document.createElement("div");
    spinner.className = "aui-refresh-spinner";
    spinner.setAttribute("aria-hidden", "true");
    const glyph = document.createElement("div");
    glyph.className = "aui-refresh-glyph";
    spinner.appendChild(glyph);

    wrapper.appendChild(spinner);
    wrapper.appendChild(scrollNode);

    let startY = null;   // touch start Y while a pull is being tracked (null = not tracking)
    let pulling = false; // the finger is actively pulling down at the top
    let refreshing = false;

    const setIndicatorHeight = (px) => { spinner.style.height = `${Math.max(0, px)}px`; };

    // Retracts the indicator (run by the model when the refresh ends).
    const onEnd = () => {
        refreshing = false;
        wrapper.classList.remove("is-refreshing");
        wrapper.classList.remove("is-armed");
        setIndicatorHeight(0);
    };

    scrollNode.addEventListener("touchstart", (event) => {
        if (refreshing) return;
        // Only the top of the viewport starts a pull; below the top this is a scroll.
        if (scrollNode.scrollTop > 0) { startY = null; return; }
        const touch = event.touches && event.touches[0];
        startY = touch ? touch.clientY : null;
        pulling = false;
        wrapper.classList.add("is-dragging"); // suppress the settle transition while tracking the finger
    }, { passive: true });

    scrollNode.addEventListener("touchmove", (event) => {
        if (startY === null || refreshing) return;
        const touch = event.touches && event.touches[0];
        if (!touch) return;
        const dy = touch.clientY - startY;
        if (dy <= 0) { // dragged back up past the start - cancel the pull, let scrolling resume
            if (pulling) { pulling = false; setIndicatorHeight(0); wrapper.classList.remove("is-armed"); }
            return;
        }
        pulling = true;
        // Pulling down at the top: own the gesture so the page does not scroll/overscroll.
        if (event.cancelable && typeof event.preventDefault === "function") event.preventDefault();
        setIndicatorHeight(resistedPull(dy));
        wrapper.classList.toggle("is-armed", isRefreshPull(dy));
    }, { passive: false });

    scrollNode.addEventListener("touchend", (event) => {
        wrapper.classList.remove("is-dragging");
        if (startY === null || refreshing) { startY = null; return; }
        const touch = event.changedTouches && event.changedTouches[0];
        const dy = touch ? touch.clientY - startY : 0;
        startY = null;
        const wasPulling = pulling;
        pulling = false;
        wrapper.classList.remove("is-armed");
        if (wasPulling && isRefreshPull(dy)) {
            refreshing = true;
            wrapper.classList.add("is-refreshing");
            setIndicatorHeight(INDICATOR_HEIGHT); // hold the indicator while the client fetches
            ctx.model.beginRefresh(viewID, actionID, onEnd);
        } else {
            setIndicatorHeight(0); // snap back: not pulled far enough
        }
    }, { passive: true });

    return wrapper;
}
