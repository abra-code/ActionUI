// Link.js — Link element.
// Web analog of ActionUI/Views/Link.swift (SwiftUI.Link, opens externally) and
// ActionUIAndroid Views/Link.kt (Intent(ACTION_VIEW)).
//
// The web is hyperlinks - so a Link is the platform's own <a> element, the most
// native mapping there is (where Apple opens the default browser and Android
// fires ACTION_VIEW). A missing/invalid url renders nothing (the Swift/Android
// EmptyView fallback, with the same warning text).
//
// Properties (Link.swift): title (String, defaults to "Link"), url (String).
//
// Divergences (Web_Porting_Notes.md):
//   * The link opens in a new tab (target="_blank", rel="noopener noreferrer") -
//     the web analog of Apple/Android "open externally", so a tap does not
//     navigate the whole ActionUI host page away.
//   * URL validity is "a non-empty String" rather than re-parsing: the browser
//     resolves the href itself (relative hrefs are valid too), where Swift's
//     URL(string:) is already permissive. Type validation stays verbatim.

import { register } from "../Common/ActionUIRegistry.js";

register("Link", {
    valueType: "none",

    // Mirrors Link.swift validateProperties (warning text included verbatim).
    validateProperties: (properties, logger) => {
        const validated = { ...properties };
        if (validated.title !== undefined && typeof validated.title !== "string") {
            logger.log(`Invalid type for Link title: expected String, got ${typeof validated.title}, ignoring`, "warning");
            delete validated.title;
        }
        if (validated.url !== undefined && typeof validated.url !== "string") {
            logger.log(`Invalid type for Link url: expected String, got ${typeof validated.url}, ignoring`, "warning");
            delete validated.url;
        }
        return validated;
    },

    buildView: (element, properties, ctx) => {
        const url = typeof properties.url === "string" ? properties.url.trim() : "";
        if (url.length === 0) {
            // Apple/Android return EmptyView for a missing/invalid URL.
            ctx.logger.log("Link missing valid URL, returning EmptyView", "warning");
            const empty = document.createElement("div");
            empty.className = "aui-empty";
            return empty;
        }

        const node = document.createElement("a");
        node.className = "aui-link";
        node.href = url;
        node.target = "_blank";
        node.rel = "noopener noreferrer";
        node.textContent = typeof properties.title === "string" ? properties.title : "Link";
        return node;
    },
});
