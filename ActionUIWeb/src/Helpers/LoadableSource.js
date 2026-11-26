// LoadableSource.js — classify a LoadableView source string.
// Web analog of ActionUIAndroid Helpers/LoadableSource.kt (the pure
// resolve/classify functions), adapted to produce a browser fetch URL.
//
// A LoadableView's source can arrive three ways (Apple's `url` > `filePath` >
// `name` priority); the string is then classified by the same heuristics on every
// platform — an http(s) prefix is a remote URL, a `file://` prefix or any string
// containing `/` is a path, and anything else is a bundle/resource name. The
// serialized format is read from the trailing extension (`.plist` → "plist", else
// "json").
//
// On the web there is no app bundle or synchronous filesystem: every kind resolves
// to a `fetch(url)` relative to the host page. So classify carries a `fetchURL` —
// the remote URL as-is, the path (with any `file://` stripped), or the bundle name
// with `.json` appended when it has no extension — alongside the `kind` (kept for
// parity/diagnostics) and `format`.

import { pageBaseURL } from "./URLPolicy.js";

// The effective source string: the runtime [value] when set and non-blank, else
// the first present and non-blank of url > filePath > name. Null when none.
export function resolveLoadableSource(value, properties) {
    if (typeof value === "string" && value.trim() !== "") return value;
    for (const key of ["url", "filePath", "name"]) {
        const candidate = properties?.[key];
        if (typeof candidate === "string" && candidate.trim() !== "") return candidate;
    }
    return null;
}

// Classifies a source into { kind, fetchURL, format }. A blank/absent source is
// { kind: "none" }. kind ∈ "none"|"remote"|"filePath"|"bundle".
export function classifyLoadableSource(source) {
    const trimmed = typeof source === "string" ? source.trim() : "";
    if (trimmed === "") return { kind: "none", fetchURL: "", format: "json" };

    const lower = trimmed.toLowerCase();
    if (lower.startsWith("http://") || lower.startsWith("https://")) {
        return { kind: "remote", fetchURL: trimmed, format: formatOf(trimmed) };
    }
    // A path or name is fetched from the page's own server. "//host/path" is a path on other
    // platforms, but a browser fetches it (and spellings such as "\\host/path",
    // "file:////host/path" or "https:host/path") from another server; JSON that means a
    // remote address names its scheme.
    let local;
    if (lower.startsWith("file://")) {
        const path = trimmed.slice("file://".length);
        local = { kind: "filePath", fetchURL: path, format: formatOf(path) };
    } else if (trimmed.includes("/")) {
        local = { kind: "filePath", fetchURL: trimmed, format: formatOf(trimmed) };
    } else {
        // Bundle/resource name - on the web, fetched relative to the page; append
        // `.json` when the name carries no extension (Android appends it too).
        const fetchURL = trimmed.includes(".") ? trimmed : `${trimmed}.json`;
        local = { kind: "bundle", fetchURL, format: formatOf(fetchURL) };
    }
    return isPageServerAddress(local.fetchURL) ? local : { kind: "none", fetchURL: "", format: "json" };
}

// False when the browser would fetch `path` from a server other than the page's own. A path the
// URL parser rejects counts as the page's: the fetch fails on its own, as before.
function isPageServerAddress(path) {
    const base = pageBaseURL();
    try {
        const page = new URL(base);
        const target = new URL(path, base);
        return target.protocol === page.protocol && target.host === page.host;
    } catch {
        return true;
    }
}

// The serialized format from a source's trailing extension; defaults to "json".
function formatOf(source) {
    const ext = source.includes(".") ? source.slice(source.lastIndexOf(".") + 1).toLowerCase() : "";
    return ext === "plist" ? "plist" : "json";
}
