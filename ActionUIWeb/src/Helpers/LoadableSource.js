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
    if (lower.startsWith("file://")) {
        const path = trimmed.slice("file://".length);
        return { kind: "filePath", fetchURL: path, format: formatOf(path) };
    }
    if (trimmed.includes("/")) {
        return { kind: "filePath", fetchURL: trimmed, format: formatOf(trimmed) };
    }
    // Bundle/resource name — on the web, fetched relative to the page; append
    // `.json` when the name carries no extension (Android appends it too).
    const fetchURL = trimmed.includes(".") ? trimmed : `${trimmed}.json`;
    return { kind: "bundle", fetchURL, format: formatOf(fetchURL) };
}

// The serialized format from a source's trailing extension; defaults to "json".
function formatOf(source) {
    const ext = source.includes(".") ? source.slice(source.lastIndexOf(".") + 1).toLowerCase() : "";
    return ext === "plist" ? "plist" : "json";
}
