// LoadableView.js — LoadableView element.
// Web analog of ActionUI/Views/LoadableView.swift (and ActionUIAndroid
// Views/LoadableView.kt).
//
// A "dynamic include": fetches a sub-document (a JSON UI description) from a source
// and renders it inline as a nested ActionUIView, so an author can split a UI
// across files. Exactly one source — `url`, `filePath`, or `name` (Apple's
// priority) — and the active source is also the element's String value, so a host
// can swap it with setString(id) to load a different document.
//
// Web specifics. The browser has no app bundle or synchronous filesystem, so every
// source kind resolves to a `fetch` relative to the host page (see
// Helpers/LoadableSource.js): a spinner shows while in flight, then the parsed
// sub-tree replaces it (or an error/deferred message on failure). The loaded JSON
// goes through the same PlatformFilter.WEB normalization and ActionUIElement parse
// the window root uses; building it through ctx.build registers every loaded id's
// value/state binding into the current window model, so the value/state/rows API
// reaches the loaded controls by id (no separate "merge" step — that is implicit on
// the web, where the registry binds as it builds). Ids must be unique within the
// combined tree (Apple/Android document the same).
//
//   viewDidLoadActionID  fires once after a new source loads successfully (keyed to
//                        the source, so a re-render for the same source does not
//                        re-fire — Apple/Android dedup).
//
// Nesting: a loaded document may hold LoadableViews of its own, up to
// the configuration's maximumNestingDepth levels; a document that loads itself, directly or through
// another, is refused at the repeat, so a self-including document cannot fetch
// without end.
//
// Deferred vs. Apple: `.plist` sources warn-and-skip (no web property-list parser —
// the Android stance); use a JSON description.

import { register, buildElementView } from "../Common/ActionUIRegistry.js";
import { HOST_ORIGIN, LESS_TRUSTED, TRUSTED, resolvedOrigin } from "../Common/TrustPolicy.js";
import { jsonRefusal, readJSONText } from "../Helpers/JSONLimits.js";
import { currentConfiguration } from "../Common/Configuration.js";
import { ActionUIElement } from "../Common/ActionUIElement.js";
import { collectElementIds } from "../Common/ActionUIInsertion.js";
import { PlatformFilter } from "../Common/PlatformFilter.js";
import { resolveLoadableSource, classifyLoadableSource } from "../Helpers/LoadableSource.js";
import { pageBaseURL } from "../Helpers/URLPolicy.js";

// How many LoadableViews may be nested inside one another (the configuration's maximumNestingDepth).
function maximumNestingDepth() {
    return currentConfiguration().limits.maximumNestingDepth;
}

// The resolved address each LoadableView node shows, for the nesting checks.
const loadedAddressOf = new WeakMap();

// Why a document loaded at `address` into `node` must not be shown, or null when it may be: too
// deep, or the same address as a LoadableView it sits in. Read when the fetch completes, by which
// time the node is in its parent's tree.
function nestingRefusal(node, address) {
    const limit = maximumNestingDepth();
    let depth = 0;
    for (let ancestor = node.parentNode; ancestor; ancestor = ancestor.parentNode) {
        const ancestorAddress = loadedAddressOf.get(ancestor);
        if (ancestorAddress === undefined) continue;
        depth += 1;
        if (ancestorAddress === address) return "it includes itself";
        if (depth >= limit) return `LoadableViews are nested more than ${limit} deep`;
    }
    return null;
}

// The absolute address a fetch of `fetchURL` goes to, as the browser resolves it.
function resolvedAddress(fetchURL) {
    try { return new URL(fetchURL, pageBaseURL()).href; } catch { return fetchURL; }
}

register("LoadableView", {
    // The active source (url/filePath/name); settable to swap the document.
    valueType: "string",

    // Mirrors LoadableView.swift validateProperties (warnings verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        for (const key of ["url", "filePath", "name"]) {
            if (validated[key] !== undefined && typeof validated[key] !== "string") {
                logger.log(`LoadableView ${key} must be a String; ignoring`, "warning");
                delete validated[key];
            }
        }

        // Exactly one source; prioritize url > filePath > name (Apple).
        const sources = ["url", "filePath", "name"].filter((k) => validated[k] !== undefined);
        if (sources.length === 0) {
            logger.log("LoadableView requires one of 'url', 'filePath', or 'name'; displaying error", "error");
        } else if (sources.length > 1) {
            logger.log("LoadableView has multiple sources; prioritizing 'url' > 'filePath' > 'name'", "warning");
            if (validated.url !== undefined) { delete validated.filePath; delete validated.name; }
            else if (validated.filePath !== undefined) { delete validated.name; }
        }

        return validated;
    },

    // The authored source seeds the value bridge (url > filePath > name).
    initialValue: (element, properties) => resolveLoadableSource(null, properties) ?? "",

    buildView: (element, properties, ctx) => {
        const node = document.createElement("div");
        node.className = "aui-loadable";

        let currentSource = resolveLoadableSource(null, properties) ?? "";
        let loadToken = 0;          // guards against out-of-order async loads
        let lastLoadedSource = null; // viewDidLoadActionID dedup (per source)
        let ownIDs = new Set();      // the ids the shown content (and LoadableViews in it) brought in

        const renderMessage = (text, cls) => {
            const div = document.createElement("div");
            div.className = cls;
            div.textContent = text;
            node.replaceChildren(div);
        };

        const load = (source) => {
            const token = ++loadToken;
            currentSource = source;
            // Every path below replaces the shown content, so the ids the previous content
            // brought in are no longer this view's, whether or not the new content loads.
            for (const id of ownIDs) ctx.model.origins.delete(id);
            ownIDs = new Set();
            const classified = classifyLoadableSource(source);

            if (classified.kind === "none") {
                loadedAddressOf.delete(node);
                renderMessage("No valid source provided", "aui-loadable-error");
                return;
            }
            if (classified.format === "plist") {
                ctx.logger.log(`LoadableView: '.plist' sources are not supported on the web (no property-list parser); use a JSON description. Source: ${source}`, "warning");
                renderMessage("Property-list (.plist) sources are not supported on the web; use JSON", "aui-loadable-deferred");
                return;
            }

            // The window's load budget, whatever the source: a document that reloads itself
            // through its value, or a chain of them, cannot spin the page.
            if (!ctx.model.loadBudget.spend()) {
                const budget = ctx.model.loadBudget.budget;
                ctx.logger.log(`Not loading a LoadableView in window ${ctx.windowUUID}: ${budget.loads} loads in ${budget.seconds} s already`, "error");
                renderMessage(`Failed to load view: too many loads in this window`, "aui-loadable-error");
                return;
            }

            const address = resolvedAddress(classified.fetchURL);
            renderMessage("Loading…", "aui-loadable-loading");
            // Where the content comes from, decided once fetched, by the address it finally came
            // from (after redirects); no more trusted than the content around this view.
            let origin = null;
            fetch(classified.fetchURL)
                .then((response) => {
                    if (!response.ok) throw new Error(`HTTP ${response.status}`);
                    origin = resolvedOrigin(classified, ctx.origin ?? HOST_ORIGIN, element.id, ctx.logger, response.url || null);
                    return readJSONText(response);
                })
                .then((text) => {
                    if (token !== loadToken) return; // superseded by a newer load
                    const refusal = nestingRefusal(node, address);
                    if (refusal !== null) {
                        loadedAddressOf.delete(node);
                        ctx.logger.log(`LoadableView: not showing '${source}': ${refusal}`, "error");
                        renderMessage(`Failed to load view: ${source}`, "aui-loadable-error");
                        return;
                    }
                    const tooBig = jsonRefusal(text);
                    if (tooBig !== null) {
                        loadedAddressOf.delete(node);
                        ctx.logger.log(`LoadableView: not showing '${source}': ${tooBig}`, "error");
                        renderMessage(`Failed to load view: ${tooBig}`, "aui-loadable-error");
                        return;
                    }
                    loadedAddressOf.set(node, address);
                    const raw = JSON.parse(text);
                    const normalized = PlatformFilter.WEB.withLogger(ctx.logger).filter(raw);
                    const loaded = ActionUIElement.fromObject(normalized, ctx.logger);
                    if (!loaded) {
                        renderMessage("Failed to parse description", "aui-loadable-error");
                        return;
                    }
                    // Less-trusted content may not share an id with a trusted element already
                    // in the window: it would bind to that element's value and state.
                    if (origin.trust === LESS_TRUSTED) {
                        const taken = [...collectElementIds(loaded)].filter((id) => ctx.model.origins.get(id)?.trust === TRUSTED).sort((a, b) => a - b);
                        if (taken.length > 0) {
                            const list = taken.join(", ");
                            ctx.logger.log(`Not loading a less-trusted sub-view for parent ${element.id}: ${taken.length === 1 ? `id ${list} is` : `ids ${list} are`} already in the window`, "error");
                            renderMessage(`Failed to load view: id conflict: ${list} already in the window`, "aui-loadable-error");
                            return;
                        }
                    }
                    // Build through the registry on a context carrying the content's origin -
                    // this registers every loaded id's value/state binding into the window
                    // model, and records each one's origin and that this view brought it in.
                    const inner = { ...ctx, origin, loadedIDSets: [...(ctx.loadedIDSets ?? []), ownIDs] };
                    inner.build = (el) => buildElementView(el, inner);
                    node.replaceChildren(inner.build(loaded));
                    // Fire viewDidLoadActionID once per successfully loaded source.
                    if (typeof properties.viewDidLoadActionID === "string" && lastLoadedSource !== source) {
                        lastLoadedSource = source;
                        ctx.model.dispatchAction(properties.viewDidLoadActionID, element.id, 0, null);
                    }
                })
                .catch((error) => {
                    if (token !== loadToken) return;
                    ctx.logger.log(`LoadableView: failed to load '${source}': ${error.message}`, "error");
                    renderMessage(`Failed to load view: ${source}`, "aui-loadable-error");
                });
        };

        // Value bridge: the source string; setting it reloads the document.
        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => currentSource,
                setValue: (value) => { load(String(value ?? "")); },
            });
        }

        load(currentSource);
        return node;
    },
});
