// WebView.js — WebView element.
// Web analog of ActionUI/Views/WebView.swift (a WKWebView / SwiftUI WebKit.WebView)
// and ActionUIAndroid Views/WebView.kt (android.webkit.WebView via AndroidView).
//
// The web's own native analog is the <iframe> - so WebView renders one directly,
// the same "prefer the platform's element over a dependency" stance as VideoPlayer
// (<video>) and AsyncImage (<img>). `url` loads a page; `html` (when no url)
// renders inline via srcdoc.
//
// Value bridge (Apple's, valueType "string"): the value is the current page URL.
// Writing a URL navigates; the command strings "#reload" / "#goBack" /
// "#goForward" / "#stop" mirror WebView.swift's navigation commands.
//
// Observable state (getElementState): isLoading, title, canGoBack, canGoForward,
// estimatedProgress - seeded like Apple/Android.
//
// Divergences from WKWebView (Web_Porting_Notes.md), all consequences of the
// iframe being a sandboxed, cross-origin-restricted frame rather than an in-app
// browser engine:
//   * WK-only knobs have no iframe equivalent and are accepted-and-ignored
//     (validated for type, then no-op): customUserAgent, backForwardNavigationGestures,
//     magnificationGestures, linkPreviews, limitsNavigationsToAppBoundDomains,
//     upgradeKnownHostsToHTTPS, userScripts.
//   * Back/forward, title, and progress observation are SAME-ORIGIN ONLY (the
//     browser blocks reading a cross-origin frame's history/document). For a
//     cross-origin page canGoBack/canGoForward stay false, title stays absent,
//     and estimatedProgress jumps 0 -> 1 on load (no incremental progress).
//   * "#stop" cannot cancel an in-flight iframe load (no API); it warns and is a
//     no-op. "#goBack"/"#goForward" drive the frame's own history same-origin.
//   * Many sites send X-Frame-Options / CSP frame-ancestors and refuse framing
//     entirely - a runtime failure that shows as a blank frame (the browser's
//     policy, not ours), the iframe analog of a page that fails to load.

import { register } from "../Common/ActionUIRegistry.js";

const BOOL_PROPS = [
    "backForwardNavigationGestures", "magnificationGestures", "linkPreviews",
    "limitsNavigationsToAppBoundDomains", "upgradeKnownHostsToHTTPS",
];

register("WebView", {
    valueType: "string",

    // Mirrors WebView.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        if (validated.url !== undefined && typeof validated.url !== "string") {
            logger.log("WebView url must be a String; ignoring", "warning");
            delete validated.url;
        }
        if (validated.html !== undefined && typeof validated.html !== "string") {
            logger.log("WebView html must be a String; ignoring", "warning");
            delete validated.html;
        }
        if (validated.baseURL !== undefined && typeof validated.baseURL !== "string") {
            logger.log("WebView baseURL must be a String; ignoring", "warning");
            delete validated.baseURL;
        }
        if (validated.customUserAgent !== undefined && typeof validated.customUserAgent !== "string") {
            logger.log("WebView customUserAgent must be a String; ignoring", "warning");
            delete validated.customUserAgent;
        }
        for (const key of BOOL_PROPS) {
            if (validated[key] !== undefined && typeof validated[key] !== "boolean") {
                logger.log(`WebView ${key} must be a Bool; ignoring`, "warning");
                delete validated[key];
            }
        }
        if (validated.navigationActionID !== undefined && typeof validated.navigationActionID !== "string") {
            logger.log("WebView navigationActionID must be a String; ignoring", "warning");
            delete validated.navigationActionID;
        }

        // userScripts: validate the array-of-dicts shape (Swift parity) even though
        // an iframe cannot inject them - so a cross-platform document still warns
        // on a malformed value rather than silently mis-shaping it.
        if (validated.userScripts !== undefined) {
            if (Array.isArray(validated.userScripts)) {
                const valid = [];
                validated.userScripts.forEach((script, i) => {
                    const ok = script && typeof script === "object" &&
                        (typeof script.source === "string" || typeof script.filePath === "string" || typeof script.resourceName === "string");
                    if (!ok) {
                        logger.log(`WebView userScripts[${i}] missing 'source', 'filePath', or 'resourceName'; skipping`, "warning");
                        return;
                    }
                    const entry = { ...script };
                    if (typeof entry.injectionTime === "string" && !["documentStart", "documentEnd"].includes(entry.injectionTime)) {
                        logger.log(`WebView userScripts[${i}] injectionTime '${entry.injectionTime}' invalid; defaulting to 'documentEnd'`, "warning");
                        entry.injectionTime = "documentEnd";
                    }
                    valid.push(entry);
                });
                validated.userScripts = valid.length > 0 ? valid : undefined;
            } else {
                logger.log("WebView userScripts must be an array of dictionaries; ignoring", "warning");
                delete validated.userScripts;
            }
        }

        return validated;
    },

    // The value is the URL (default the `url` property, Apple parity).
    initialValue: (element, properties) => properties.url ?? "",

    initialStates: () => ({
        isLoading: false,
        estimatedProgress: 0.0,
        canGoBack: false,
        canGoForward: false,
    }),

    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-webview";

        const frame = document.createElement("iframe");
        frame.className = "aui-webview-frame";
        frame.setAttribute("referrerpolicy", "no-referrer");
        node.appendChild(frame);

        // Live observable state (same-origin only where noted in the header).
        const state = { isLoading: false, estimatedProgress: 0.0, canGoBack: false, canGoForward: false, title: undefined };
        let currentURL = typeof properties.url === "string" ? properties.url : "";

        frame.addEventListener("load", () => {
            state.isLoading = false;
            state.estimatedProgress = 1.0;
            try { state.title = frame.contentDocument?.title || undefined; } catch { /* cross-origin */ }
            if (typeof properties.navigationActionID === "string") {
                ctx.model.dispatchAction(properties.navigationActionID, element.id, 0, null);
            }
            if (typeof properties.valueChangeActionID === "string" && currentURL) {
                ctx.model.dispatchAction(properties.valueChangeActionID, element.id, 0, null);
            }
        });

        // Initial content: a url wins over inline html (Apple's precedence).
        if (currentURL) {
            navigate(frame, currentURL, state, ctx.logger);
        } else if (typeof properties.html === "string") {
            frame.srcdoc = withBase(properties.html, properties.baseURL);
        }

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => currentURL,
                setValue: (value) => {
                    const command = String(value ?? "");
                    if (command.length === 0 || command === currentURL && !command.startsWith("#")) return;
                    const next = navigate(frame, command, state, ctx.logger);
                    if (next !== null) currentURL = next;
                },
            });
            ctx.model.bindState(element.id, {
                getState: (key) => state[key],
                setState: () => { /* WebView states are observe-only; host writes go through the value */ },
            });
        }
        return node;
    },
});

// Applies a navigation command to the frame. Returns the new current URL, or null
// when the command was a non-URL action (reload/back/forward/stop) that leaves the
// tracked URL unchanged. Mirrors WebView.swift's handleCommand.
function navigate(frame, command, state, logger) {
    switch (command) {
        case "#reload":
            // Re-assigning src reloads the frame (cross-origin safe).
            frame.src = frame.src; // eslint-disable-line no-self-assign
            return null;
        case "#goBack":
            historyGo(frame, -1, logger);
            return null;
        case "#goForward":
            historyGo(frame, 1, logger);
            return null;
        case "#stop":
            // No API to cancel an in-flight iframe load (see header).
            logger.log("WebView '#stop' is not supported on the iframe backing; ignoring", "warning");
            return null;
        default:
            state.isLoading = true;
            state.estimatedProgress = 0.0;
            frame.src = command;
            return command;
    }
}

// Drives the frame's own history; cross-origin frames throw (caught + warned).
function historyGo(frame, delta, logger) {
    try {
        frame.contentWindow.history.go(delta);
    } catch {
        logger.log("WebView back/forward is only available for a same-origin page; ignoring", "warning");
    }
}

// Injects a <base href> into inline html so relative links resolve, the srcdoc
// analog of WKWebView's baseURL. A no-op when baseURL is absent.
function withBase(html, baseURL) {
    if (typeof baseURL !== "string" || baseURL.length === 0) return html;
    const baseTag = `<base href="${baseURL.replace(/"/g, "&quot;")}">`;
    if (/<head[^>]*>/i.test(html)) return html.replace(/<head[^>]*>/i, (m) => m + baseTag);
    return baseTag + html;
}
