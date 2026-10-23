// Link.js — Link element.
// Web analog of ActionUI/Views/Link.swift (SwiftUI.Link, opens externally) and
// ActionUIAndroid Views/Link.kt (Intent(ACTION_VIEW)).
//
// The web is hyperlinks - so a Link is the platform's own <a> element, the most
// native mapping there is (where Apple opens the default browser and Android
// fires ACTION_VIEW). The url is read as Apple's URL(string:) reads it
// (linkDestination): a missing or refused url renders nothing (the Swift/Android
// EmptyView fallback, with the same warning text); a url without a scheme
// ("example.com", "docs/page") renders a link that opens nothing, as on Apple,
// where the system has nothing to open it with.
//
// Properties (Link.swift): title (String, defaults to "Link"), url (String).
//
// Divergences:
//   * The link opens in a new tab (target="_blank", rel="noopener noreferrer") -
//     the web analog of Apple/Android "open externally", so a tap does not
//     navigate the whole ActionUI host page away.
//   * javascript:, vbscript: and data: urls open nothing either: Apple has no
//     app for them, and in a page they would run script or replace the page.

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
        const url = typeof properties.url === "string" ? properties.url : null;
        const destination = url === null ? "none" : linkDestination(url);
        if (destination === "none") {
            // Apple/Android return EmptyView for a missing/invalid URL.
            ctx.logger.log("Link missing valid URL, returning EmptyView", "warning");
            const empty = document.createElement("div");
            empty.className = "aui-empty";
            return empty;
        }

        const node = document.createElement("a");
        node.className = "aui-link";
        node.textContent = typeof properties.title === "string" ? properties.title : "Link";
        if (destination === "absolute" && !NOT_OPENED_SCHEMES.test(url)) {
            node.href = url;
            node.target = "_blank";
            node.rel = "noopener noreferrer";
        } else {
            // Shown and focusable, as Apple's link is; without an href it opens nothing.
            node.setAttribute("role", "link");
            node.tabIndex = 0;
            node.addEventListener("click", () => {
                if (reportedUnopenedURLs.has(url)) return;
                reportedUnopenedURLs.add(url);
                ctx.logger.log(`Link URL "${url}" opens nothing`, "warning");
            });
        }
        return node;
    },
});

// Schemes a page never opens from a Link (Apple has no app for them either).
const NOT_OPENED_SCHEMES = /^(javascript|vbscript|data):/i;

// URLs tapped that open nothing, each logged once.
const reportedUnopenedURLs = new Set();

// The destination of text as Apple's URL(string:) reads it (Link.destination in Core): "none"
// when empty, when the text before a first ":" is no scheme (" https://...", "1abc:x"), or when
// the host or port after "//" is invalid (a space, "<", a bad "%" escape, an unclosed "[", a port
// that is not digits); every other character is percent-encoded there, so accepted. Otherwise
// "absolute" with a scheme, "relative" without. FormatParity/link-url-cases.json, recorded from
// Foundation, holds the cases every platform checks.
export function linkDestination(text) {
    if (text.length === 0) return "none";
    let rest = text;
    let hasScheme = false;
    const end = text.search(/[:/?#]/);
    if (end >= 0 && text[end] === ":") {
        const prefix = text.slice(0, end);
        if (/^([A-Za-z][A-Za-z0-9+.-]*)?$/.test(prefix)) {
            // An empty prefix (":foo") is accepted with an empty scheme.
            hasScheme = prefix.length > 0;
            rest = text.slice(end + 1);
        } else if (!/[@[\]]/.test(prefix)) {
            // Foundation reads a prefix with "@", "[" or "]" as a relative path ("a@b:x").
            return "none";
        }
    }
    if (rest.startsWith("//")) {
        const authority = rest.slice(2).match(/^[^/?#]*/)[0];
        if (!isHostAndPort(authority.slice(authority.lastIndexOf("@") + 1))) return "none";
    }
    return hasScheme ? "absolute" : "relative";
}

function isHostAndPort(text) {
    if (text.startsWith("[")) {
        const close = text.indexOf("]");
        // Inside "[...]", up to a "%" (the zone, "[::1%en0]", which takes anything), only ASCII
        // letters, digits and "-._~!$&'()*+,;=:" ("[::1]", "[v1.x]").
        return close >= 0 && /^[A-Za-z0-9\-._~!$&'()*+,;=:]*(%|$)/.test(text.slice(1, close))
            && /^(:[0-9]*)?$/.test(text.slice(close + 1));
    }
    const colon = text.indexOf(":");
    if (colon >= 0 && !/^[0-9]*$/.test(text.slice(colon + 1))) return false;
    return isHost(colon < 0 ? text : text.slice(0, colon));
}

// No space, control character or character a host refuses, "%" only as an escape. A non-ASCII
// character is part of an international domain name, refused only as a space (U+3000).
function isHost(text) {
    return /^(?:[^\x00-\x20\x7f"<>[\\\]^`{|}%\p{Zs}\p{Zl}\p{Zp}]|%[0-9A-Fa-f]{2})*$/u.test(text);
}
