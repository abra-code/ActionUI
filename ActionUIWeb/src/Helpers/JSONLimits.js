// The limits all ActionUI JSON is held to, from the host, a page-relative file or another
// server, as on the other platforms: no larger than the configuration's maximumJSONSize (16 MB by
// default), no deeper than 512 levels of JSON nesting, fetched within the configuration's
// maximumDownloadTime (120 seconds by default), and a window's LoadableViews load at most the
// configuration's load budget (256 a minute by default), so JSON that reloads itself through its
// value, or a chain of it, cannot spin the page. See Common/Configuration.js.

import { currentConfiguration } from "../Common/Configuration.js";

export const MAX_DOCUMENT_DEPTH = 512;

// The largest ActionUI JSON a load takes, in UTF-8 bytes (the configuration's).
export function maximumJSONSize() {
    return currentConfiguration().limits.maximumJSONSize;
}

// The refusal for ActionUI JSON larger than the cap, in whole megabytes as the other platforms say it.
function tooLarge() {
    return `Larger than ${Math.floor(maximumJSONSize() / (1024 * 1024))} MB`;
}

// The configuration's load budget: { loads, seconds }.
export function loadBudget() {
    return currentConfiguration().limits.loadBudget;
}

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

// Why the JSON `text` is not decoded, or null when it may be.
export function jsonRefusal(text) {
    if (typeof text !== "string") return null;
    if (utf8LongerThan(text, maximumJSONSize())) return tooLarge();
    if (nestsDeeperThan(text, MAX_DOCUMENT_DEPTH)) return `Nested deeper than ${MAX_DOCUMENT_DEPTH} levels`;
    return null;
}

// The longest one fetch of ActionUI JSON may take, in seconds (the configuration's), or null: no limit.
export function maximumDownloadTime() {
    return currentConfiguration().limits.maximumDownloadTime;
}

// The longest delay a browser timer takes, in milliseconds: a longer one fires at once.
const LONGEST_TIMER_MS = 2147483647;

// The error for a load given up after `seconds`, as the other platforms say it.
function tookTooLong(seconds) {
    return new Error(`loading it took longer than ${seconds} seconds`);
}

// fetch(url), given up after the configuration's maximumDownloadTime, however slowly the server
// sends: the browser's own fetch has no time limit. The signal also ends the reading of the body
// (readJSONText). A load given up rejects with "loading it took longer than N seconds".
export async function fetchWithTimeLimit(url) {
    const seconds = maximumDownloadTime();
    if (seconds === null || typeof AbortSignal?.timeout !== "function") return fetch(url);
    const signal = AbortSignal.timeout(Math.min(Math.max(1, Math.ceil(seconds * 1000)), LONGEST_TIMER_MS));
    try {
        const response = await fetch(url, { signal });
        timeLimitOf.set(response, seconds);
        return response;
    } catch (error) {
        if (error?.name === "TimeoutError") throw tookTooLong(seconds);
        throw error;
    }
}

// The time limit each response of fetchWithTimeLimit was fetched with, for the error its reading
// gives when the limit ends it.
const timeLimitOf = new WeakMap();

// The body of `response` as text, read up to the size cap: a larger body is refused (an
// Error) without reading the rest, as reading more only costs memory.
export async function readJSONText(response) {
    try {
        return await readCappedText(response);
    } catch (error) {
        if (error?.name === "TimeoutError" && timeLimitOf.has(response)) throw tookTooLong(timeLimitOf.get(response));
        throw error;
    }
}

async function readCappedText(response) {
    const limit = maximumJSONSize();
    const declared = Number(response.headers?.get?.("content-length"));
    if (Number.isFinite(declared) && declared > limit) throw new Error(tooLarge());
    const reader = response.body?.getReader?.();
    if (!reader) {
        const text = await response.text();
        if (utf8LongerThan(text, limit)) throw new Error(tooLarge());
        return text;
    }
    const chunks = [];
    let size = 0;
    for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        size += value.byteLength;
        if (size > limit) {
            reader.cancel?.().catch?.(() => {});
            throw new Error(tooLarge());
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

// A window's load budget: at most `loads` loads in any `seconds`, the configuration's unless a
// budget is given (tests).
export class LoadBudget {
    constructor(budget = null, now = () => (globalThis.performance?.now?.() ?? Date.now())) {
        this.fixedBudget = budget;
        this.now = now;
        this.recent = [];
    }

    // The budget in effect: { loads, seconds }.
    get budget() {
        return this.fixedBudget ?? loadBudget();
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
