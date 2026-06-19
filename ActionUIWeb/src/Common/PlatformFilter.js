// PlatformFilter.js — resolve `<key>:<platform>` key-suffix overrides.
// Web analog of ActionUI/Common/PlatformFilter.swift + PlatformFilter.kt.
//
// Walks a generic JSON tree (objects / arrays / leaf primitives, as produced by
// JSON.parse). For each object, groups keys by base name, picks the
// highest-specificity variant whose suffix is in the active set, drops variants
// targeting other known platforms, and recurses into nested objects and arrays.
// The output is a "platform-normalized" JSON tree with no suffixed keys left.
//
// Any key whose suffix is not in ALL_PLATFORMS is treated the same as a
// non-matching platform — the key is dropped and the logger (if any) is invoked
// with a one-line warning. This makes the filter forward-compatible: JSON
// authored for a future platform token quietly disappears until the token is
// added to ALL_PLATFORMS, at which point the same JSON starts working without
// edits. It also surfaces typos (e.g. `tint:Web` with capital W).
//
// Mirror image of the Swift/Kotlin filters. All three must agree on
// ALL_PLATFORMS so a JSON file's "known platform tokens" don't depend on which
// platform reads it. (`web` is already present in the Swift `allPlatforms` and
// Kotlin `ALL_PLATFORMS` sets — no edits needed there.)

export class PlatformFilter {
    // active: Set<string> of platform tokens matching this runtime.
    // logger: receives one warning per unknown-suffix key; null silences.
    constructor(active, logger = null) {
        this.active = active instanceof Set ? active : new Set(active);
        this.logger = logger;
    }

    withLogger(logger) {
        return new PlatformFilter(this.active, logger);
    }

    filter(value) {
        if (Array.isArray(value)) return value.map((v) => this.filter(v));
        if (value !== null && typeof value === "object") return this.filterObject(value);
        return value;
    }

    filterObject(obj) {
        // base name -> { value, rank }
        const winners = new Map();

        for (const [key, value] of Object.entries(obj)) {
            const [base, suffix] = splitKey(key);
            let rank;
            if (suffix === null) {
                rank = 0;
            } else if (this.active.has(suffix)) {
                rank = specificity(suffix);
            } else if (PlatformFilter.ALL_PLATFORMS.has(suffix)) {
                continue; // known-but-inactive platform — silent drop
            } else {
                this.logger?.log(
                    `Unknown platform suffix in key '${key}' (suffix='${suffix}'). ` +
                    `Known platforms: ${[...PlatformFilter.ALL_PLATFORMS].sort().join(", ")}. ` +
                    `Key dropped.`,
                    "warning",
                );
                continue;
            }
            const existing = winners.get(base);
            if (existing && existing.rank >= rank) continue;
            winners.set(base, { value: this.filter(value), rank });
        }

        const out = {};
        for (const [base, { value }] of winners) out[base] = value;
        return out;
    }
}

// Splits a key into [base, suffix-or-null]. A key without ':' returns
// [key, null]. A key with ':' always returns the split, regardless of whether
// the suffix is a known platform — the caller decides what to do with it.
function splitKey(key) {
    const colon = key.lastIndexOf(":");
    if (colon < 0) return [key, null];
    return [key.slice(0, colon), key.slice(colon + 1)];
}

function specificity(platform) {
    return platform === "apple" ? 1 : 2;
}

// Every recognized platform token across Apple, Android, and (reserved)
// cross-platform targets. Must match the Swift `allPlatforms` and Kotlin
// `ALL_PLATFORMS` sets.
PlatformFilter.ALL_PLATFORMS = new Set([
    "ios", "macos", "tvos", "watchos", "visionos", "apple",
    "android", "androidtv", "wear",
    "desktop", "web",
]);

// Active set for the browser runtime. ("desktop" is reserved and intentionally
// not auto-active, mirroring how Swift's macOS set is ["macos","apple"] without
// "desktop".)
PlatformFilter.WEB = new PlatformFilter(new Set(["web"]));
