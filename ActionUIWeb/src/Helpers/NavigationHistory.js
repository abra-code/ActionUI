// NavigationHistory.js — opt-in browser back/forward for the navigation
// containers (NavigationStack, NavigationSplitView).
//
// The browser history is a single global resource (window.history) per browsing
// context, so ONE module-level coordinator owns it rather than each nav element
// poking history independently (which would fight over entries). A nav element
// that opts in - the `browserHistory` property, authored `browserHistory:web` so
// Apple/Android drop the key - registers a { capture, restore } pair and gets
// back a handle it calls when its own navigation changes. Elements that do not
// opt in never touch history (the back button keeps its default page behavior),
// which is why this is opt-in: hijacking Back is invasive in an embedded page.
//
// Model (deliberately simple and predictable):
//   * The active history entry carries a snapshot of EVERY participant's nav
//     state, keyed by element id, under a namespaced `__aui_nav` key so it
//     coexists with any history.state a host already keeps.
//   * USER navigation (a link tap, a sidebar selection) calls commit("push") ->
//     history.pushState, so the browser Back button returns to the prior state.
//   * PROGRAMMATIC navigation (a host setState / structural sync) calls
//     commit("replace") -> history.replaceState: it updates the current entry
//     without growing history, so a startup selection becomes the baseline rather
//     than a spurious entry. The trade-off - a purely programmatic navigation is
//     not itself a distinct Back target - is documented in Web_Porting_Notes.
//   * popstate restores each participant from the entry's snapshot; a restore
//     does NOT re-commit and does NOT fire selection actionIDs (it is a
//     reconciliation, like setState).
//   * The in-app Back affordances route through history.back() when enabled, so
//     in-app and browser Back agree (each element decides that, not this module).
//
// URL is intentionally left unchanged (state-only history): the buttons work
// with no server route handling and no build step - consistent with the
// dependency-free, no-build-step project rule. Hash/path URL sync could layer on
// later as a host concern.

const AUI_KEY = "__aui_nav";
const participants = new Map(); // String(id) -> { capture, restore }
let installed = false;

function entryState() {
    return (history.state && typeof history.state === "object") ? history.state : {};
}

function snapshot() {
    const snap = {};
    for (const [id, p] of participants) snap[id] = p.capture();
    return snap;
}

// Writes the full snapshot into the current ("replaceState") or a new
// ("pushState") history entry, preserving any non-ActionUI history.state.
function write(method) {
    const next = { ...entryState(), [AUI_KEY]: snapshot() };
    history[method](next, "");
}

function install() {
    if (installed) return;
    installed = true;
    window.addEventListener("popstate", (event) => {
        const snap = event.state && event.state[AUI_KEY];
        if (!snap || typeof snap !== "object") return; // not ours / pre-ActionUI entry
        for (const [id, p] of participants) {
            if (Object.prototype.hasOwnProperty.call(snap, id)) p.restore(snap[id]);
        }
    });
}

// Register an opt-in navigation container.
//   handlers.capture()        -> this element's serializable nav state.
//   handlers.restore(state)   <- apply a state from a history entry (no commit).
// Returns a handle:
//   commit(mode)  "push" (user nav, a new Back target) | "replace" (programmatic
//                 sync of the current entry). Default "push".
//   release()     stop participating (e.g. the element was removed).
export function registerNavigationHistory(id, handlers) {
    install();
    participants.set(String(id), handlers);
    // Fold the newcomer's current state into the active entry (not a new entry),
    // so a later Back to here restores it.
    write("replaceState");
    return {
        commit: (mode = "push") => write(mode === "replace" ? "replaceState" : "pushState"),
        release: () => participants.delete(String(id)),
    };
}
