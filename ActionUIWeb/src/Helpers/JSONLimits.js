// The limits every document is held to, from the host, a page-relative file or another server,
// as on the other platforms: no larger than 16 MB, no deeper than 512 levels of JSON nesting, and
// a window's LoadableViews load at most 256 documents a minute (a document that reloads itself
// through its value, or a chain of them, cannot spin the page).

export const MAX_DOCUMENT_BYTES = 16 * 1024 * 1024;
export const MAX_DOCUMENT_DEPTH = 512;
export const LOAD_BUDGET = Object.freeze({ loads: 256, seconds: 60 });

// Whether `text` is longer than `limit` bytes in UTF-8, counted without encoding it.
export function utf8LongerThan(text, limit) {
    if (text.length > limit) return true;
    let bytes = 0;
    for (let i = 0; i < text.length; i++) {
        const code = text.charCodeAt(i);
        if (code < 0x80) bytes += 1;
        else if (code < 0x800) bytes += 2;
        else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) { bytes += 4; i++; }
        else bytes += 3;
        if (bytes > limit) return true;
    }
    return false;
}

// Whether the JSON `text` nests arrays and objects deeper than `depth`, brackets inside strings
// not counted. A parser would recurse that deep (the element decoder does).
export function nestsDeeperThan(text, depth) {
    let level = 0;
    let inString = false;
    for (let i = 0; i < text.length; i++) {
        const c = text[i];
        if (inString) {
            if (c === "\\") i++;
            else if (c === "\"") inString = false;
        } else if (c === "\"") {
            inString = true;
        } else if (c === "{" || c === "[") {
            if (++level > depth) return true;
        } else if (c === "}" || c === "]") {
            level--;
        }
    }
    return false;
}

// Why the document `text` is not decoded, or null when it may be.
export function jsonRefusal(text) {
    if (typeof text !== "string") return null;
    if (utf8LongerThan(text, MAX_DOCUMENT_BYTES)) return "Larger than 16 MB";
    if (nestsDeeperThan(text, MAX_DOCUMENT_DEPTH)) return `Nested deeper than ${MAX_DOCUMENT_DEPTH} levels`;
    return null;
}

// The body of `response` as text, read up to the document cap: a larger body is refused (an
// Error) without reading the rest, as reading more only costs memory.
export async function readJSONText(response) {
    const declared = Number(response.headers?.get?.("content-length"));
    if (Number.isFinite(declared) && declared > MAX_DOCUMENT_BYTES) throw new Error("Larger than 16 MB");
    const reader = response.body?.getReader?.();
    if (!reader) {
        const text = await response.text();
        if (utf8LongerThan(text, MAX_DOCUMENT_BYTES)) throw new Error("Larger than 16 MB");
        return text;
    }
    const chunks = [];
    let size = 0;
    for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > MAX_DOCUMENT_BYTES) {
            reader.cancel?.().catch?.(() => {});
            throw new Error("Larger than 16 MB");
        }
        chunks.push(value);
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
        bytes.set(chunk, offset);
        offset += chunk.byteLength;
    }
    return new TextDecoder().decode(bytes);
}

// A window's load budget: at most LOAD_BUDGET.loads loads in any LOAD_BUDGET.seconds.
export class LoadBudget {
    constructor(budget = LOAD_BUDGET, now = () => (globalThis.performance?.now?.() ?? Date.now())) {
        this.budget = budget;
        this.now = now;
        this.recent = [];
    }

    // True, counting the load, when one more is within the budget.
    spend() {
        const now = this.now();
        const windowMs = this.budget.seconds * 1000;
        this.recent = this.recent.filter((time) => now - time < windowMs);
        if (this.recent.length >= this.budget.loads) return false;
        this.recent.push(now);
        return true;
    }
}
