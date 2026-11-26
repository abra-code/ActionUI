// URLPolicy.js - which addresses ActionUI JSON may open in a new tab or show in a frame.
//
// ActionUI JSON names addresses in Link url, WebView url, Map openInMapsURL and ShareLink item. The
// browser reads such a string with its own URL parser (it drops tabs and line breaks, trims
// spaces, resolves relative addresses against the page), so the checks here parse the same way
// and test the resulting scheme, never the raw text.
//
// - isOpenedURL: a link the visitor clicks. Anything but javascript:, vbscript: and data:, which
//   would run script in the host page or replace it (Apple has no app for them either).
// - isFramedURL: a page shown inside a WebView frame. Only http and https, or the page's own
//   scheme and host (a relative address on a page an app serves from a custom scheme);
//   javascript: would run in the host page's origin, file: would show any local file, and other
//   schemes (data:, blob:, about:) have no counterpart in the WebView contract.

const NOT_OPENED_PROTOCOLS = new Set(["javascript:", "vbscript:", "data:"]);
const FRAMED_PROTOCOLS = new Set(["http:", "https:"]);

// The scheme of text as the browser reads it ("https:"), or null when it is no address.
function protocolOf(text) {
    if (typeof text !== "string") return null;
    try {
        return new URL(text, pageBaseURL()).protocol.toLowerCase();
    } catch {
        return null;
    }
}

// The base that relative addresses resolve against: the page's own base when there is a page.
export function pageBaseURL() {
    const base = globalThis.document?.baseURI ?? globalThis.location?.href;
    return typeof base === "string" && base.length > 0 ? base : "http://localhost/";
}

export function isOpenedURL(text) {
    const protocol = protocolOf(text);
    return protocol !== null && !NOT_OPENED_PROTOCOLS.has(protocol);
}

export function isFramedURL(text) {
    const protocol = protocolOf(text);
    if (protocol === null || NOT_OPENED_PROTOCOLS.has(protocol)) return false;
    if (FRAMED_PROTOCOLS.has(protocol)) return true;
    if (protocol === "file:") return false;
    try {
        const base = pageBaseURL();
        const target = new URL(text, base);
        const page = new URL(base);
        return target.protocol === page.protocol && target.host === page.host;
    } catch {
        return false;
    }
}

// The iframe sandbox for a WebView. Inline html gets an opaque origin of its own (no
// allow-same-origin), as on Apple, where it cannot reach the app. Neither may navigate the host
// page itself (no allow-top-navigation). Pop-ups open as tabs that keep the frame's sandbox (no
// allow-popups-to-escape-sandbox), so a page cannot reach an unsandboxed window through one.
export const WEBVIEW_HTML_SANDBOX = "allow-scripts allow-forms allow-popups";
// A page on another server keeps its own origin, so sites that need their cookies still work; the
// browser's same-origin rule keeps it from the host page.
export const WEBVIEW_URL_SANDBOX = `${WEBVIEW_HTML_SANDBOX} allow-same-origin`;

// The sandbox for a WebView showing `text`. Only an http or https page on another origin keeps
// its own; anything else gets the opaque origin of inline html, since a page on the host page's
// origin with allow-scripts and allow-same-origin together could remove its own sandbox and reach
// the host page. The page's origin is read from location as well as from the base, which a
// <base href> may point at another server. An opaque origin ("null" for file: and custom schemes,
// which a browser may still treat as one origin) cannot be compared, so it counts as the page's.
export function webViewSandboxFor(text) {
    try {
        const base = pageBaseURL();
        const target = new URL(text, base);
        const pageOrigins = [new URL(base).origin, globalThis.location?.origin];
        if (FRAMED_PROTOCOLS.has(target.protocol) && !pageOrigins.includes(target.origin)) return WEBVIEW_URL_SANDBOX;
    } catch {
        // Not an address: navigate refuses it before the sandbox matters.
    }
    return WEBVIEW_HTML_SANDBOX;
}
