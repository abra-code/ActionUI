// Where content came from, how far it is trusted, and what it may do. Mirrors the Swift
// JSONContentOrigin / ActionUITrustPolicy / DefaultTrustPolicy; origins and capabilities are plain
// objects with the keys the C adapter's JSON uses.
//
// ActionUI JSON the host passes in, or JSON from the page's own origin (a filePath or name, which
// is always fetched from the page's server, or a URL on the page's origin), is trusted; one a
// LoadableView loads from another origin is less trusted, and so is anything inside it. The
// origin rides on the render context (ctx.origin), so elements with no id and template rows are
// judged by the JSON they are in; the model records it per id for the host
// (Window.getElementOrigin).
//
//   origin:     { source: "host" | "resource" | "remote", path?, url?, trust: "trusted" | "lessTrusted", parentID? }
//   capability: { capability: "openLink", url } | { capability: "webView", url } (url null: inline html)
//               | { capability: "webViewBaseURL", url } | { capability: "windowTitle" }
//               | { capability: "presentModal" } | { capability: "load", source } | { capability: "action", actionID }
//               | { capability: "playMedia", url } (a VideoPlayer's address, resolved against the page)

import { pageBaseURL } from "../Helpers/URLPolicy.js";
import { isTrustedOrigin } from "./Configuration.js";

export const TRUSTED = "trusted";
export const LESS_TRUSTED = "lessTrusted";

// The host's own content.
export const HOST_ORIGIN = Object.freeze({ source: "host", trust: TRUSTED });

// The schemes less-trusted content may open, and those its WebView may show.
export const LINK_SCHEMES = new Set(["http:", "https:", "mailto:"]);
export const WEBVIEW_SCHEMES = new Set(["http:", "https:"]);
// The schemes a less-trusted VideoPlayer may play.
export const MEDIA_SCHEMES = new Set(["http:", "https:"]);

// The scheme of `address` with its colon, lower-cased ("https:"); "" when it has none or it
// does not parse.
export function schemeOf(address) {
    const match = /^([A-Za-z][A-Za-z0-9+.-]*):/.exec(String(address ?? "").trim());
    return match ? `${match[1].toLowerCase()}:` : "";
}

// Whether two absolute addresses have the same origin (scheme, host and port).
export function haveSameOrigin(first, second) {
    try {
        const a = new URL(first);
        const b = new URL(second);
        return a.origin !== "null" && a.origin === b.origin;
    } catch {
        return false;
    }
}

// Whether the absolute address `address` is on the page's server: the scheme and host (with its
// port) of `base`.
function isOnPageServer(address, base) {
    try {
        const target = new URL(address);
        const page = new URL(base);
        return target.protocol === page.protocol && target.host === page.host;
    } catch {
        return false;
    }
}

// What content of `origin` may do when the host does not say: trusted content anything;
// less-trusted content may open only web and mail links, show only web addresses in a WebView
// and play only web addresses in a VideoPlayer, give its inline html a base address only of its
// own JSON's origin, and neither title the screen nor present its own sheets, covers and
// popovers. The Swift table, less what the web
// has no counterpart for (local files, script files, menu commands).
export function allowsByDefault(capability, origin) {
    if (origin?.trust === TRUSTED) return true;
    switch (capability?.capability) {
        case "openLink":
            return LINK_SCHEMES.has(schemeOf(capability.url));
        case "webView":
            return capability.url == null || WEBVIEW_SCHEMES.has(schemeOf(capability.url));
        case "webViewBaseURL":
            return origin?.source === "remote" && haveSameOrigin(capability.url, origin.url);
        case "playMedia":
            return MEDIA_SCHEMES.has(schemeOf(capability.url));
        case "windowTitle":
        case "presentModal":
            return false;
        default:
            return true;
    }
}

// ActionUI's own policy: trust as classified, and the default refusals.
export const DefaultTrustPolicy = Object.freeze({
    trust: (source, parent, byDefault) => byDefault,
    allows: (capability, origin) => allowsByDefault(capability, origin),
});

let policy = DefaultTrustPolicy;

// Sets the host's trust policy, for all windows: { trust(source, parent, byDefault), allows(capability, origin) },
// either left out to keep ActionUI's own. trust gets the source ({ source, path or url }), the
// parent's origin (null for a window's root) and ActionUI's own decision, and returns "trusted" or
// "lessTrusted" (anything else counts as less trusted). No argument restores ActionUI's own policy.
// Set it before loading content. A method that throws counts as less trusted, or as a refusal.
export function setTrustPolicy(hostPolicy) {
    if (hostPolicy != null && typeof hostPolicy !== "object") {
        throw new TypeError("setTrustPolicy takes { trust, allows } or nothing");
    }
    for (const name of ["trust", "allows"]) {
        if (hostPolicy?.[name] != null && typeof hostPolicy[name] !== "function") {
            throw new TypeError(`setTrustPolicy: ${name} must be a function`);
        }
    }
    // Bound, so a policy object's methods keep their `this` (a class instance).
    const method = (name) => (hostPolicy[name] == null ? DefaultTrustPolicy[name] : hostPolicy[name].bind(hostPolicy));
    policy = hostPolicy == null ? DefaultTrustPolicy : { trust: method("trust"), allows: method("allows") };
}

// Whether content of `origin` may do `capability`, by the policy; a policy that throws refuses.
export function allows(capability, origin, logger) {
    try {
        return policy.allows(capability, origin ?? HOST_ORIGIN) === true;
    } catch (error) {
        logger?.log(`The trust policy's allows threw: ${error.message}`, "error");
        return false;
    }
}

// The source a LoadableView's classified source `classified` ({ kind, fetchURL }) names, as its
// content would be classified before it is fetched: { source: "resource", path } for the page's own
// server, else { source: "remote", url }; null for no source. For the load capability.
export function loadSource(classified) {
    if (!classified || classified.kind === "none") return null;
    const base = pageBaseURL();
    let address;
    try {
        address = new URL(classified.fetchURL, base).href;
    } catch {
        address = classified.fetchURL;
    }
    const own = classified.kind !== "remote" || haveSameOrigin(address, base);
    return own ? { source: "resource", path: address } : { source: "remote", url: address };
}

// The origin of content a LoadableView loads from the classified source `classified`
// ({ kind, fetchURL }) inside content of origin `parent`, into the LoadableView `parentID`: a
// path or name (always on the page's server) or a URL on the page's origin is a resource; another
// origin is remote, less trusted unless it is one of the configuration's trusted origins; no more
// trusted than `parent`. Then the host's policy has the last word. Null for no source.
//
// `finalURL`, once fetched: the address the ActionUI JSON finally came from (the Response's url,
// after redirects), which decides, so a page-relative path or a trusted server that redirects
// to another origin gives remote, less-trusted content.
export function resolvedOrigin(classified, parent, parentID, logger, finalURL = null) {
    if (!classified || classified.kind === "none") return null;
    const base = pageBaseURL();
    let address;
    try {
        address = new URL(finalURL || classified.fetchURL, base).href;
    } catch {
        address = finalURL || classified.fetchURL;
    }
    // A redirect can take even a page-relative path to another origin: once fetched, the final
    // address alone decides. It is the page's own when it has the page's scheme and host, as a
    // path or name is classified (Helpers/LoadableSource.js), so a page served from a custom
    // scheme (an opaque origin) keeps its own files as resources.
    const own = finalURL
        ? isOnPageServer(address, base)
        : classified.kind !== "remote" || haveSameOrigin(address, base);
    const source = own ? { source: "resource", path: address } : { source: "remote", url: address };
    const ownTrust = own || isTrustedOrigin(address) ? TRUSTED : LESS_TRUSTED;
    const byDefault = ownTrust === TRUSTED && (parent?.trust ?? TRUSTED) === TRUSTED ? TRUSTED : LESS_TRUSTED;
    let trust;
    try {
        trust = policy.trust(source, parent ?? null, byDefault) === TRUSTED ? TRUSTED : LESS_TRUSTED;
    } catch (error) {
        logger?.log(`The trust policy's trust threw: ${error.message}`, "error");
        trust = LESS_TRUSTED;
    }
    const origin = { ...source, trust };
    if (parentID != null && parentID > 0) origin.parentID = parentID;
    return Object.freeze(origin);
}
