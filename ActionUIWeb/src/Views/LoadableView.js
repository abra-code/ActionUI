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
// Deferred vs. Apple: `.plist` sources warn-and-skip (no web property-list parser —
// the Android stance); use a JSON description.

import { register } from "../Common/ActionUIRegistry.js";
import { ActionUIElement } from "../Common/ActionUIElement.js";
import { PlatformFilter } from "../Common/PlatformFilter.js";
import { resolveLoadableSource, classifyLoadableSource } from "../Helpers/LoadableSource.js";

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

        const renderMessage = (text, cls) => {
            const div = document.createElement("div");
            div.className = cls;
            div.textContent = text;
            node.replaceChildren(div);
        };

        const load = (source) => {
            const token = ++loadToken;
            currentSource = source;
            const classified = classifyLoadableSource(source);

            if (classified.kind === "none") {
                renderMessage("No valid source provided", "aui-loadable-error");
                return;
            }
            if (classified.format === "plist") {
                ctx.logger.log(`LoadableView: '.plist' sources are not supported on the web (no property-list parser); use a JSON description. Source: ${source}`, "warning");
                renderMessage("Property-list (.plist) sources are not supported on the web; use JSON", "aui-loadable-deferred");
                return;
            }

            renderMessage("Loading…", "aui-loadable-loading");
            fetch(classified.fetchURL)
                .then((response) => {
                    if (!response.ok) throw new Error(`HTTP ${response.status}`);
                    return response.text();
                })
                .then((text) => {
                    if (token !== loadToken) return; // superseded by a newer load
                    const raw = JSON.parse(text);
                    const normalized = PlatformFilter.WEB.withLogger(ctx.logger).filter(raw);
                    const loaded = ActionUIElement.fromObject(normalized, ctx.logger);
                    if (!loaded) {
                        renderMessage("Failed to parse description", "aui-loadable-error");
                        return;
                    }
                    // Build through the registry on the current ctx — this registers
                    // every loaded id's value/state binding into the window model.
                    node.replaceChildren(ctx.build(loaded));
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
