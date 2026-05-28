// Common/PlatformFilter.swift
import Foundation

/*
 PlatformFilter resolves `<key>:<platform>` key-suffix overrides against an active
 platform set, producing a "platform-normalized" JSON tree with no suffixed keys
 remaining.

 Walks a generic JSON tree (typically `[String: Any]` / `[Any]` / leaf primitives
 as produced by `JSONSerialization`). For each `[String: Any]`, groups keys by
 base name, picks the highest-specificity variant whose suffix is in the active
 set, drops variants targeting other known platforms, and recurses into nested
 objects and arrays.

 Any key whose suffix is not in `allPlatforms` is treated the same as a non-
 matching platform — the key is dropped and the configured logger (if any) is
 invoked with a one-line warning naming the key and suffix. This makes the
 filter forward-compatible: JSON authored for a future platform token will
 quietly disappear on today's builds until the token is added to `allPlatforms`,
 at which point the same JSON starts working without edits. It also surfaces
 typos (e.g., `tint:Android` with capital A) instead of silently passing them
 through.

 Mirror image of `PlatformFilter.kt` in ActionUIAndroid. Both filters must agree
 on the `allPlatforms` set so that a JSON file's "known platform tokens" don't
 depend on which platform is reading it. See Stage 0 §Design notes in
 Private/Android_Development_Plan.md.

 Not wired into the parsing pipeline yet — written ahead of integration for
 review and cross-platform parity.
*/
public struct PlatformFilter {

    /// Platform tokens that match the current runtime. On iOS this would be
    /// `["ios", "apple"]`; on Android (Kotlin port) it is `["android"]`.
    public let active: Set<String>

    /// Optional logger; receives one warning per unknown-suffix key encountered.
    /// Pass `nil` to silence (e.g., in tests). `.warning` level is used.
    public let logger: (any ActionUILogger)?

    /// - Parameters:
    ///   - active: Platform tokens active for this runtime context. Most
    ///     callers should pass `PlatformFilter.runtimeActiveSet`.
    ///   - logger: Receives unknown-suffix warnings. `nil` silences them.
    public init(active: Set<String>, logger: (any ActionUILogger)? = nil) {
        self.active = active
        self.logger = logger
    }

    /// Recursively filters a JSON tree. Inputs are typically `[String: Any]`,
    /// `[Any]`, `String`, `NSNumber`, or `NSNull` as produced by
    /// `JSONSerialization.jsonObject(with:)`.
    public func filter(_ value: Any) -> Any {
        switch value {
        case let dict as [String: Any]: return filterObject(dict)
        case let array as [Any]:        return array.map(filter)
        default:                        return value
        }
    }

    private func filterObject(_ obj: [String: Any]) -> [String: Any] {
        // base name -> (winning value, rank)
        var winners: [String: (value: Any, rank: Int)] = [:]

        for (key, value) in obj {
            let (base, suffix) = splitKey(key)
            let rank: Int
            if let suffix = suffix {
                if active.contains(suffix) {
                    rank = specificity(suffix)
                } else if PlatformFilter.allPlatforms.contains(suffix) {
                    continue   // known-but-inactive platform — silent drop
                } else {
                    logger?.log(
                        "Unknown platform suffix in key '\(key)' (suffix='\(suffix)'). "
                        + "Known platforms: "
                        + PlatformFilter.allPlatforms.sorted().joined(separator: ", ")
                        + ". Key dropped.",
                        .warning
                    )
                    continue
                }
            } else {
                rank = 0
            }
            if let existing = winners[base], existing.rank >= rank { continue }
            winners[base] = (filter(value), rank)
        }

        return winners.mapValues { $0.value }
    }

    /// Splits a key into `(base, suffix-or-nil)`. A key without `:` returns
    /// `(key, nil)`. A key with `:` always returns the split, regardless of
    /// whether the suffix is a known platform — the caller decides what to do
    /// with unknown suffixes.
    private func splitKey(_ key: String) -> (String, String?) {
        guard let colon = key.lastIndex(of: ":") else { return (key, nil) }
        let base = String(key[..<colon])
        let suffix = String(key[key.index(after: colon)...])
        return (base, suffix)
    }

    private func specificity(_ platform: String) -> Int {
        platform == "apple" ? 1 : 2
    }

    // MARK: - Token table

    /// Every recognized platform token across Apple, Android, and (reserved)
    /// cross-platform targets. Must match `PlatformFilter.Companion.ALL_PLATFORMS`
    /// in the Kotlin port — both filters must agree on which suffixes are
    /// platform tokens vs unknown/typos.
    public static let allPlatforms: Set<String> = [
        "ios", "macos", "tvos", "watchos", "visionos", "apple",
        "android", "androidtv", "wear",
        "desktop", "web"
    ]

    // MARK: - Runtime-active set

    /// Active platform tokens for the current Swift runtime, computed from
    /// compile-time platform flags. Callers construct their own
    /// `PlatformFilter` instance with this set and their logger.
    public static let runtimeActiveSet: Set<String> = {
        #if os(iOS)
            return ["ios", "apple"]
        #elseif os(macOS)
            return ["macos", "apple"]
        #elseif os(tvOS)
            return ["tvos", "apple"]
        #elseif os(watchOS)
            return ["watchos", "apple"]
        #elseif os(visionOS)
            return ["visionos", "apple"]
        #else
            return []
        #endif
    }()
}
