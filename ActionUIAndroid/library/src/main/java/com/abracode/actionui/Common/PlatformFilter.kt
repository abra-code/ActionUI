package com.abracode.actionui.Common

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * Resolves `<key>:<platform>` key-suffix overrides against an active platform set.
 *
 * For each JsonObject, groups keys by base name, picks the highest-specificity
 * variant whose suffix is in the active set, drops variants targeting other
 * platforms, and recurses into nested objects and arrays. The output is a
 * "platform-normalized" JSON tree with no suffixed keys remaining.
 *
 * Any key whose `<suffix>` is not in [ALL_PLATFORMS] is treated the same as a
 * non-matching platform - the key is dropped and the configured [logger] is
 * invoked with a one-line warning at [LoggerLevel.warning]. This makes the
 * filter forward-compatible: JSON authored for a future platform token will
 * quietly disappear on today's builds until the token is added to
 * [ALL_PLATFORMS], at which point the same JSON starts working without edits.
 *
 * Mirror image of `PlatformFilter.swift` in ActionUI. Both filters must agree
 * on [ALL_PLATFORMS] so that a JSON file's "known platform tokens" don't
 * depend on which platform is reading it. See Stage 0 section Design notes in
 * Private/Android_Development_Plan.md.
 *
 * @param active Platform tokens active for this runtime (e.g., `{"android"}`).
 * @param logger Receives unknown-suffix warnings. `null` silences them.
 */
class PlatformFilter(
    val active: Set<String>,
    val logger: ActionUILogger? = null
) {

    /**
     * Returns a copy of this filter with the given logger attached. Useful when
     * starting from [Android] (no logger) and wanting warnings to flow through
     * the caller's existing logger.
     */
    fun withLogger(logger: ActionUILogger): PlatformFilter =
        PlatformFilter(active, logger)

    fun filter(element: JsonElement): JsonElement = when (element) {
        is JsonObject -> filterObject(element)
        is JsonArray  -> JsonArray(element.map(::filter))
        else          -> element
    }

    private fun filterObject(obj: JsonObject): JsonObject {
        val winners = mutableMapOf<String, Pair<JsonElement, Int>>()

        for ((key, value) in obj) {
            val (base, suffix) = splitKey(key)
            val rank = when {
                suffix == null              -> 0
                suffix in active            -> specificity(suffix)
                suffix in ALL_PLATFORMS     -> continue
                else                        -> {
                    logger?.log(
                        "Unknown platform suffix in key '$key' " +
                        "(suffix='$suffix'). Known platforms: " +
                        "${ALL_PLATFORMS.sorted().joinToString()}. Key dropped.",
                        LoggerLevel.warning
                    )
                    continue
                }
            }
            val existing = winners[base]
            if (existing == null || rank > existing.second) {
                winners[base] = filter(value) to rank
            }
        }

        return JsonObject(winners.mapValues { it.value.first })
    }

    /**
     * Splits a key into (base, suffix-or-null). A key without `:` returns
     * (key, null). A key with `:` always returns the split, regardless of
     * whether the suffix is a known platform - the caller decides what to do
     * with unknown suffixes.
     */
    private fun splitKey(key: String): Pair<String, String?> {
        val idx = key.lastIndexOf(':')
        if (idx < 0) return key to null
        return key.substring(0, idx) to key.substring(idx + 1)
    }

    private fun specificity(platform: String): Int = when (platform) {
        "apple" -> 1
        else    -> 2
    }

    companion object {
        /**
         * Every recognized platform token across Apple, Android, and (reserved)
         * cross-platform targets. Must match `PlatformFilter.allPlatforms` in
         * the Swift port - both filters must agree on which suffixes are
         * platform tokens vs unknown/typos.
         */
        val ALL_PLATFORMS: Set<String> = setOf(
            "ios", "macos", "tvos", "watchos", "visionos", "apple",
            "android", "androidtv", "wear",
            "desktop", "web"
        )

        /**
         * Active set for the Android runtime. Logger is `null`; attach one via
         * [withLogger] when wiring into a renderer.
         */
        val Android: PlatformFilter = PlatformFilter(setOf("android"))
    }
}
