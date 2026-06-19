// AsyncImage.js — AsyncImage element.
// Web analog of ActionUI/Views/AsyncImage.swift (SwiftUI AsyncImage) and
// ActionUIAndroid Views/AsyncImage.kt.
//
// The web is AsyncImage's native habitat: an <img src> already fetches off the
// main thread, rides the browser HTTP cache, and reports load/error events - so
// there is no bespoke fetch / decode / LRU cache (the work the Android port had
// to write by hand against HttpURLConnection). This element is an <img> with
// SwiftUI's AsyncImagePhase shape layered on top: a placeholder SF Symbol shows
// while loading (.empty) and on failure (.failure); the image shows on .success.
//
// Properties (AsyncImage.swift):
//   url          String. Any string is accepted; an unloadable one is a runtime
//                load failure (the placeholder), never a validation error - the
//                Apple/Android stance. A non-string is dropped with a warning.
//   placeholder  SF Symbol name shown while loading / on failure. Default "photo".
//   resizable    Bool, default true. true -> the image fills its frame and
//                contentMode picks object-fit; false -> intrinsic size.
//   contentMode  "fit" | "fill", default "fit" -> object-fit contain / cover.
// Baseline View modifiers (frame, cornerRadius, padding, opacity, ...) are
// applied by the registry after buildView, so frame sizing + corner clipping
// come for free; like SwiftUI, a resizable AsyncImage wants a frame.
//
// Value bridge (Apple's): the runtime value is the URL string. A host setString
// swaps the source and restarts the load (placeholder shows again until it
// lands), matching Apple/Android where the load is keyed on the resolved URL.

import { register } from "../Common/ActionUIRegistry.js";
import { systemSymbolGlyph } from "../Helpers/SymbolIcon.js";

const CONTENT_MODES = ["fit", "fill"];
const DEFAULT_PLACEHOLDER = "photo";

register("AsyncImage", {
    valueType: "string",

    validateProperties: (properties, logger) => {
        const validated = { ...properties };

        // Any string url is allowed (load failure is a runtime phase, not a
        // validation error); only a wrong type is dropped. Mirrors Apple.
        if (validated.url !== undefined && typeof validated.url !== "string") {
            logger.log(`Invalid type for AsyncImage url: expected String, ignoring`, "warning");
            delete validated.url;
        }
        if (validated.placeholder !== undefined && typeof validated.placeholder !== "string") {
            logger.log(`Invalid type for AsyncImage placeholder: expected String, ignoring`, "warning");
            delete validated.placeholder;
        }
        if (validated.resizable !== undefined && typeof validated.resizable !== "boolean") {
            logger.log(`Invalid type for AsyncImage resizable: expected Bool, ignoring`, "warning");
            delete validated.resizable;
        }
        if (validated.contentMode !== undefined) {
            if (typeof validated.contentMode !== "string" || !CONTENT_MODES.includes(validated.contentMode)) {
                logger.log(`Invalid AsyncImage contentMode '${JSON.stringify(validated.contentMode)}', ignoring`, "warning");
                delete validated.contentMode;
            }
        }
        return validated;
    },

    // The static value is the url; a host setString overrides it (Apple
    // initialValue: model.value first, then the "url" property).
    initialValue: (element, properties) => properties.url,

    buildView: (element, properties, ctx) => {
        const node = document.createElement("span");
        node.className = "aui-async-image";

        const config = {
            placeholder: typeof properties.placeholder === "string" ? properties.placeholder : DEFAULT_PLACEHOLDER,
            resizable: properties.resizable !== false, // default true
            contentMode: properties.contentMode === "fill" ? "fill" : "fit",
        };

        render(node, properties.url, config, ctx);

        if (element.id > 0) {
            ctx.model.bind(element.id, {
                getValue: () => node.dataset.auiUrl ?? "",
                setValue: (value) => render(node, value, config, ctx),
            });
        }
        return node;
    },
});

// Renders `url` into `node` as the AsyncImagePhase shape: a placeholder glyph
// (shown while loading and on failure) plus, when there is a URL, an <img> that
// reveals itself on load and falls back to the placeholder on error.
function render(node, url, config, ctx) {
    node.replaceChildren();
    node.dataset.auiUrl = typeof url === "string" ? url : "";

    const placeholder = makePlaceholder(config.placeholder, ctx);

    if (typeof url !== "string" || url.length === 0) {
        ctx.logger.log(`AsyncImage missing valid url, using placeholder '${config.placeholder}'`, "warning");
        node.appendChild(placeholder);
        return;
    }

    // Phase .empty: the placeholder is visible until the image loads.
    node.appendChild(placeholder);

    const img = document.createElement("img");
    img.alt = "";
    if (config.resizable) {
        img.style.objectFit = config.contentMode === "fill" ? "cover" : "contain";
        img.style.width = "100%";
        img.style.height = "100%";
    }
    img.hidden = true; // revealed on a successful load (phase .success)
    img.addEventListener("load", () => {
        placeholder.remove();
        img.hidden = false;
    });
    img.addEventListener("error", () => {
        // Phase .failure: keep the placeholder, drop the broken <img>.
        ctx.logger.log(`AsyncImage failed to load '${url}', using placeholder '${config.placeholder}'`, "warning");
        img.remove();
    });
    img.src = url; // assigning src begins the async fetch
    node.appendChild(img);
}

function makePlaceholder(name, ctx) {
    return systemSymbolGlyph(name, { imageScale: "large" }, ctx.logger, (n) =>
        `AsyncImage placeholder '${n}' has no SF->Material mapping; nothing shown while ` +
        `loading/failed. Use a mapped SF Symbol name for the placeholder.`);
}
