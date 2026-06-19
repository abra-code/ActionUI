// LifecycleHooks.js — page-lifecycle action hooks at the window/scene level.
// Web-only (there is no Apple/Android ActionUI equivalent — Apple's lifecycle hooks
// are per-element onAppear/onDisappear; this is the browser's page lifecycle). The
// document root may declare, with the `:web` suffix (resolved by PlatformFilter
// before build, so we read the bare keys here):
//
//   "onForegroundActionID:web" — fires when the page becomes visible again.
//   "onBackgroundActionID:web" — fires when the page becomes hidden (tab switch,
//                                app switch, or close). The reliable "persist now"
//                                point on web.
//   "onTerminateActionID:web"  — fires when the page is being unloaded (pagehide).
//
// Each is dispatched at the window/app level (viewID 0, no context), through the
// same action channel as menu commands, so a host wires them with app.action(id).
//
// Why visibilitychange + pagehide, not `beforeunload`: per the Page Lifecycle API,
// visibilitychange→hidden is the most reliable "this page may be discarded" signal —
// it fires on a mobile app-switch and on tab close, where `beforeunload` does not —
// and `beforeunload` is unreliable and disables the back/forward cache. A host that
// specifically wants an "unsaved changes" confirm prompt can still add its own
// `beforeunload` listener; this provides the save/restore signals.

// Installs the lifecycle listeners declared on [rootProperties] and returns a
// cleanup function that removes them (so re-presenting a window does not stack
// duplicate listeners). A no-op (returns an empty cleanup) when none are declared.
export function installLifecycleHooks(rootProperties, model, logger) {
    const pick = (key) => {
        const value = rootProperties?.[key];
        if (value === undefined || value === null) return null;
        if (typeof value !== "string") {
            logger.log(`Invalid type for ${key}: expected String, ignoring`, "warning");
            return null;
        }
        return value;
    };

    const onForeground = pick("onForegroundActionID");
    const onBackground = pick("onBackgroundActionID");
    const onTerminate = pick("onTerminateActionID");
    if (!onForeground && !onBackground && !onTerminate) return () => {};

    const fire = (actionID) => { if (actionID) model.dispatchAction(actionID, 0, 0, null); };

    const onVisibility = () => {
        if (document.visibilityState === "hidden") fire(onBackground);
        else if (document.visibilityState === "visible") fire(onForeground);
    };
    const onPageHide = () => fire(onTerminate);

    if (onForeground || onBackground) document.addEventListener("visibilitychange", onVisibility);
    if (onTerminate) window.addEventListener("pagehide", onPageHide);

    return () => {
        document.removeEventListener("visibilitychange", onVisibility);
        window.removeEventListener("pagehide", onPageHide);
    };
}
