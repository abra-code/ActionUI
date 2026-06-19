// ToastHost.js — window-level toast / snackbar.
// Web analog of ActionUI/Common/ToastOverlayView.swift plus the toast half of
// ActionUIModel.swift (presentToast / dismissToast), and ActionUIAndroid's Material
// snackbar. The third member of the Phase 3 presentation layer (Scenes/), after
// DialogHost and ModalHost.
//
// A WindowToast is pure data (message, an auto-dismiss duration, an optional inline
// action) - no ViewModels are allocated, matching WindowToast.swift. Unlike a window
// dialog/modal (a native <dialog> shown with showModal(), Scenes/DialogHost.js,
// Scenes/ModalHost.js), a toast is a plain non-modal positioned <div>: it must NOT
// steal focus or block input. role="status" + aria-live="polite" carry the message to
// VoiceOver / TalkBack (the web analog of Swift's AccessibilityNotification) even
// though the toast is transient and non-focusable.
//
// Only one toast is active per window at a time (Apple's single windowToast slot);
// presenting while one is visible QUEUES the new spec and shows it after the current
// dismisses, coalescing rapid posts into an ordered sequence (presentToast's queue).
// The toast auto-dismisses after `duration` seconds; the optional inline action fires
// its actionID (viewID 0, no context) and then dismisses (ToastOverlayView parity).
//
// Divergences (see Web_Porting_Notes.md, Scenes > Toast):
//   * Placement is a CSS concern, not baked into JS: .aui-toast is top-pinned by
//     default (Apple's transient-banner idiom; the web is a desktop target, like
//     macOS), and a .aui-toast-bottom modifier flips it to the bottom Material
//     placement, added when the renderer is running in an Android browser.
//   * A plain <div> renders in normal flow, so a toast sits BELOW any open
//     <dialog>/modal (those use the browser top layer via showModal()). A toast under
//     an open modal is acceptable.
//   * Queue + auto-dismiss timer live here in a per-window WeakMap, not in
//     ActionUIModel - the web keeps presentation state out of the model (DialogHost /
//     ModalHost keep the active node in the DOM). Swift stores windowToast/toastQueue
//     on WindowModel only for its @Published binding, which the web has no need of.

// Per-window toast state, keyed by the window root node so multiple windows never
// share a queue (the WeakMap entry is collected with the node). The active toast
// itself lives in the DOM; only the pending queue and timer handle live here.
const STATE = new WeakMap(); // host -> { queue: [spec], timerId: number | null }

// Force-completes the exit (remove + promote) if transitionend never fires - a
// backgrounded tab or a zeroed transition can swallow it.
const EXIT_FALLBACK_MS = 400;

const DEFAULT_DURATION_MS = 4000;

function stateFor(host) {
    let state = STATE.get(host);
    if (!state) {
        state = { queue: [], timerId: null };
        STATE.set(host, state);
    }
    return state;
}

// Bottom (Material) placement when running in an Android browser; top (Apple) elsewhere.
function isAndroidBrowser() {
    return typeof navigator !== "undefined" && /Android/i.test(navigator.userAgent || "");
}

// Presents a toast into `host` (the window root). If a toast is already visible the
// new `spec` is queued and shown after the current one dismisses; returns the toast
// node, or null when queued. `spec` = { message, duration, action?: { title, actionID } }.
export function presentToast(host, spec, model, logger) {
    if (!host) return null;
    const state = stateFor(host);

    if (host.querySelector(".aui-toast")) {
        state.queue.push(spec); // single active toast (Apple parity); coalesce the rest
        if (logger) logger.log(`presentToast: queued '${spec.message}' (${state.queue.length} waiting)`, "debug");
        return null;
    }
    return render(host, spec, model, logger);
}

// Dismisses the active toast (if any), then promotes the next queued spec. The
// auto-dismiss timer, the inline action button, and the host-API dismissToast all
// funnel here. Mirrors ActionUIModel.dismissToast.
export function dismissActiveToast(host, model, logger) {
    if (!host) return;
    const toast = host.querySelector(".aui-toast");
    if (toast) beginExit(host, toast, model, logger);
}

function render(host, spec, model, logger) {
    const state = stateFor(host);

    const toast = document.createElement("div");
    toast.className = isAndroidBrowser() ? "aui-toast aui-toast-bottom" : "aui-toast";
    toast.setAttribute("role", "status");       // a transient, non-focusable status banner
    toast.setAttribute("aria-live", "polite");  // announced without moving focus

    const message = document.createElement("span");
    message.className = "aui-toast-message";
    message.textContent = typeof spec.message === "string" ? spec.message : String(spec.message ?? "");
    if (!message.textContent && logger) logger.log("presentToast: empty message", "warning");
    toast.appendChild(message);

    // An inline action needs both a title and an actionID (Swift's `if let actionTitle,
    // let actionID`); Window builds spec.action only when both are present.
    if (spec.action && spec.action.actionID && spec.action.title) {
        const button = document.createElement("button");
        button.className = "aui-toast-action";
        button.textContent = spec.action.title;
        button.addEventListener("click", () => {
            if (toast.dataset.dismissing) return; // tapped mid-exit: ignore
            model.dispatchAction(spec.action.actionID, 0, 0, null); // viewID 0, no context (Apple parity)
            beginExit(host, toast, model, logger);
        });
        toast.appendChild(button);
    }

    host.appendChild(toast);
    // Entrance: commit the hidden state for a frame, then add .is-visible so the CSS
    // transition runs. A single rAF can land in the same paint as the append and skip
    // the animation, so step two frames.
    requestAnimationFrame(() => requestAnimationFrame(() => toast.classList.add("is-visible")));

    // Auto-dismiss. Normalize like Swift's max(0, duration); non-finite -> default.
    const ms = Number.isFinite(spec.duration) ? Math.max(0, spec.duration) * 1000 : DEFAULT_DURATION_MS;
    state.timerId = setTimeout(() => {
        if (!toast.isConnected) return; // window re-presented mid-toast: stale timer
        beginExit(host, toast, model, logger);
    }, ms);

    if (logger) logger.log(`presentToast: '${message.textContent}'`, "debug");
    return toast;
}

// Runs the exit transition, then removes the node and promotes the next queued spec.
// Idempotent (the dataset.dismissing guard) and robust to transitionend never firing
// (the fallback timeout); whichever of the two wins calls finish() exactly once.
function beginExit(host, toast, model, logger) {
    if (toast.dataset.dismissing) return; // already exiting
    toast.dataset.dismissing = "1";

    const state = stateFor(host);
    if (state.timerId != null) {
        clearTimeout(state.timerId);
        state.timerId = null;
    }

    let finished = false;
    const finish = () => {
        if (finished) return;
        finished = true;
        toast.removeEventListener("transitionend", onEnd);
        toast.remove();
        const next = state.queue.shift();
        if (next) render(host, next, model, logger); // promote (Swift's queue.removeFirst)
    };
    // Filter to opacity (present in every variant, including reduced-motion) so the
    // transform sub-transition doesn't fire finish() early.
    const onEnd = (event) => {
        if (event.target === toast && event.propertyName === "opacity") finish();
    };

    toast.addEventListener("transitionend", onEnd);
    toast.classList.remove("is-visible"); // triggers the exit transition
    setTimeout(finish, EXIT_FALLBACK_MS); // fallback if transitionend never fires
}
