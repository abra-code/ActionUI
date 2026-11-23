// Core/Common/ActionUIConfiguration.swift
/*
 The host's configuration of ActionUI, for every window: limits, trust settings, the app's resource
 folder, and settings for add-ons. Only host code sets it, never ActionUI JSON, so content cannot
 raise its own limits or trust itself. It is set early, before the first window loads its ActionUI
 JSON, and fixed after that: a later change is refused, so every window and every load in the
 program sees the same settings.

 Set it from Swift with ActionUIConfiguration.set(_:), or from any binding with the same keys in
 JSON (set(json:), which the C adapter and the language bindings call):

 {
   "limits": {
     "maximumJSONSize": 16777216,                 // bytes of ActionUI JSON one load takes (16 MB)
     "loadBudget": { "loads": 256, "seconds": 60 },// LoadableView loads per window in any span
     "maximumNestingDepth": 16,                   // LoadableViews inside LoadableViews
     "maximumDownloadTime": 120                   // seconds one http or https load may take (null: no limit)
   },
   "trust": {
     "trustedOrigins": ["https://ui.example.com"] // servers whose ActionUI JSON is trusted
   },
   "resourceFolder": "/path/to/resources",        // the app's resource folder (null: none)
   "addOns": { "SomeAddOn": { ... } }             // each add-on reads its own section
 }

 Each key is optional: JSON changes only the keys it names and keeps the rest of the current
 configuration (the defaults, or what was set before). A key ActionUI does not know, a value of the
 wrong type or out of range, or a trusted origin that is not an https origin refuses the whole
 change, which then keeps the configuration as it was: a typo must not leave half of a change
 applied.

 Trusted origins: ActionUI JSON from one of these servers is trusted as the app's own, provided
 the content around it is trusted too (a window's root, or a LoadableView in trusted content), so
 less-trusted content cannot name the server and get trusted content inside itself. An origin is a
 scheme, host and port; only https is accepted, with no path, query, fragment or user name. The
 address that counts is the one the ActionUI JSON finally came from, after redirects: a redirect
 from the trusted server to another one gives less-trusted content.

 The host may raise the limits above the defaults: host code is trusted. The trust policy
 (ActionUIModel.trustPolicy) and the logger stay separate setters, since they are code. A policy's
 `byDefault` trust already counts the trusted origins, so a host that only trusts its own server
 needs no policy of its own.

 Read from any thread (images are read off the main thread), so the value is behind a lock.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

public struct ActionUIConfiguration: Sendable, Equatable {
    public struct Limits: Sendable, Equatable {
        /// The largest ActionUI JSON any load takes, in bytes, whoever loads it (16 MB). A file is
        /// refused before it is read, a download once it grows past this.
        public var maximumJSONSize = 16 * 1024 * 1024
        /// How many LoadableView loads one window may make in a span of time; one more is refused,
        /// with "Failed to load view: too many loads in this window". ActionUI JSON that loads
        /// itself through other files can multiply its loads past what the nesting depth stops (7
        /// small files that each list the others made about 2000 loads in 4 seconds). On Apple a
        /// LoadableView loads again each time its own properties change, so a host that changes
        /// them many times a minute raises the count.
        public var loadBudget = ActionUILoadBudget(loads: 256, seconds: 60)
        /// How deep LoadableViews may nest: one with this many LoadableViews around it is refused.
        public var maximumNestingDepth = 16
        /// The longest one http or https load may take, in seconds, however the server sends: a
        /// load of ActionUI JSON (LoadableView) or of an image the renderer loads itself
        /// (AsyncImage; on Apple platforms only less-trusted content's images, since trusted
        /// content's go through SwiftUI's AsyncImage, which has no limit of its own) is given up
        /// after this. The steps of a load (connecting, each read) have shorter time limits of
        /// their own, so this only stops a server that keeps sending slowly. A host whose users
        /// may be on slow networks, or that shows large images, raises it; nil removes it. 120
        /// seconds by default.
        public var maximumDownloadTime: Double? = 120

        public init() {}
    }

    public struct Trust: Sendable, Equatable {
        /// The https origins whose ActionUI JSON is trusted (see the header); empty by default.
        public var trustedOrigins: [URL] = []

        public init() {}
    }

    public var limits = Limits()
    public var trust = Trust()
    /// The folder of the app's resources as the host names it (ActionUIResourceFolder); nil: none,
    /// the platform's own place only.
    public var resourceFolder: String?
    /// Settings for add-ons, each under the add-on's own name, as JSON text. Read with
    /// `addOnSettings(_:)`, set with `setAddOnSettings(_:_:)`.
    public private(set) var addOns: [String: String] = [:]

    public init() {}

    /// The settings stored for the add-on `name`, as Swift-native values (ActionUIJSON.value), or
    /// nil when there are none.
    public func addOnSettings(_ name: String) -> Any? {
        addOns[name].flatMap { try? ActionUIJSON.value(from: $0) }
    }

    /// Stores `value` (Swift-native values that ActionUIJSON can write) as the add-on `name`'s
    /// settings; nil removes them.
    public mutating func setAddOnSettings(_ name: String, _ value: Any?) throws {
        guard let value else {
            addOns[name] = nil
            return
        }
        addOns[name] = try ActionUIJSON.string(from: value)
    }
}

// MARK: - The program's configuration

extension ActionUIConfiguration {
    private static let lock = Lock()
    nonisolated(unsafe) private static var stored = ActionUIConfiguration()
    nonisolated(unsafe) private static var storedIsFixed = false

    /// The configuration in effect.
    public static var current: ActionUIConfiguration {
        lock.withLock { stored }
    }

    /// Whether the configuration is fixed: the first window has loaded its ActionUI JSON.
    public static var isFixed: Bool {
        lock.withLock { storedIsFixed }
    }

    /// Makes `configuration` the one in effect. Throws, keeping the configuration as it was, when
    /// it is fixed already or `configuration` is not valid (see the header).
    public static func set(_ configuration: ActionUIConfiguration) throws {
        try validate(configuration)
        try lock.withLock {
            guard !storedIsFixed else { throw fixedError }
            stored = configuration
        }
    }

    /// Changes the keys `json` names (see the header) in the configuration in effect. Throws,
    /// keeping it as it was, when it is fixed already or `json` is not valid.
    public static func set(json: String) throws {
        let parsed: Any
        do {
            parsed = try ActionUIJSON.value(from: json)
        } catch {
            throw ActionUIError("the configuration is not valid JSON: \(error)")
        }
        try update { try apply(parsed, to: &$0) }
    }

    /// Changes the configuration in effect with `change`, as set(_:) would set the result. `change`
    /// works on a copy, outside the lock, so it may read `current`. When another thread changed the
    /// configuration meanwhile, `change` runs again on the newer value, so neither change is lost.
    /// So `change` must only compute the new configuration: it must not set the configuration
    /// itself (an update inside it would make every attempt stale, and the loop would not end).
    public static func update(_ change: (inout ActionUIConfiguration) throws -> Void) throws {
        while true {
            let (snapshot, wasFixed) = lock.withLock { (stored, storedIsFixed) }
            guard !wasFixed else { throw fixedError }
            var changed = snapshot
            try change(&changed)
            try validate(changed)
            let applied = try lock.withLock { () throws -> Bool in
                guard !storedIsFixed else { throw fixedError }
                guard stored == snapshot else { return false }
                stored = changed
                return true
            }
            if applied { return }
        }
    }

    /// Fixes the configuration: called when a window first loads its ActionUI JSON.
    static func fix() {
        lock.withLock { storedIsFixed = true }
    }

    /// For tests, which load windows and change settings in any order: makes `configuration` the
    /// one in effect whether or not it is fixed, without validating it.
    static func replaceForTesting(_ configuration: ActionUIConfiguration = ActionUIConfiguration()) {
        lock.withLock { stored = configuration }
    }

    /// For tests of the setters: fixes the configuration, or makes it settable again.
    static func setFixedForTesting(_ fixed: Bool) {
        lock.withLock { storedIsFixed = fixed }
    }

    /// For tests: changes the configuration in effect whether or not it is fixed.
    static func updateForTesting(_ change: (inout ActionUIConfiguration) -> Void) {
        var changed = current
        change(&changed)
        replaceForTesting(changed)
    }

    private static var fixedError: ActionUIError {
        ActionUIError("the configuration is fixed once a window has loaded its ActionUI JSON; set it before")
    }

    // MARK: Validation

    static func validate(_ configuration: ActionUIConfiguration) throws {
        let limits = configuration.limits
        guard limits.maximumJSONSize > 0 else { throw ActionUIError("limits.maximumJSONSize must be more than 0") }
        guard limits.loadBudget.loads >= 0 else { throw ActionUIError("limits.loadBudget.loads must not be negative") }
        guard limits.loadBudget.seconds.isFinite, limits.loadBudget.seconds > 0 else {
            throw ActionUIError("limits.loadBudget.seconds must be a number more than 0")
        }
        guard limits.maximumNestingDepth >= 0 else { throw ActionUIError("limits.maximumNestingDepth must not be negative") }
        if let time = limits.maximumDownloadTime, !(time.isFinite && time > 0) {
            throw ActionUIError("limits.maximumDownloadTime must be a number more than 0, or null for no limit")
        }
        for origin in configuration.trust.trustedOrigins {
            if let problem = trustedOriginProblem(origin) {
                throw ActionUIError("trust.trustedOrigins: \(origin.absoluteString) \(problem)")
            }
        }
        if let folder = configuration.resourceFolder, folder.isEmpty {
            throw ActionUIError("resourceFolder must not be empty; null for none")
        }
    }

    /// Why `url` is not a trusted origin, or nil when it is one: https, a host, and nothing but an
    /// optional port after it (a path of "/" at most).
    static func trustedOriginProblem(_ url: URL) -> String? {
        guard url.scheme?.lowercased() == "https" else { return "is not an https address" }
        guard let host = url.host, !host.isEmpty else { return "has no host" }
        guard url.user == nil, url.password == nil else { return "has a user name or password" }
        guard url.path.isEmpty || url.path == "/" else { return "has a path; an origin is the scheme, host and port only" }
        guard url.query == nil, url.fragment == nil else { return "has a query or fragment" }
        return nil
    }

    /// Whether ActionUI JSON from `url` comes from one of `origins` (same scheme, host and port).
    static func isTrustedOrigin(_ url: URL, among origins: [URL]) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        return origins.contains { DefaultTrustPolicy.haveSameOrigin($0, url) }
    }

    // MARK: JSON

    private static let topKeys: Set<String> = ["limits", "trust", "resourceFolder", "addOns"]
    private static let limitKeys: Set<String> = ["maximumJSONSize", "loadBudget", "maximumNestingDepth", "maximumDownloadTime"]
    private static let budgetKeys: Set<String> = ["loads", "seconds"]
    private static let trustKeys: Set<String> = ["trustedOrigins"]

    private static func apply(_ parsed: Any, to configuration: inout ActionUIConfiguration) throws {
        let top = try object(parsed, "the configuration", keys: topKeys)
        if let limits = top["limits"] {
            let limits = try object(limits, "limits", keys: limitKeys)
            if let size = limits["maximumJSONSize"] {
                configuration.limits.maximumJSONSize = try integer(size, "limits.maximumJSONSize")
            }
            if let budget = limits["loadBudget"] {
                let budget = try object(budget, "limits.loadBudget", keys: budgetKeys)
                if let loads = budget["loads"] {
                    configuration.limits.loadBudget.loads = try integer(loads, "limits.loadBudget.loads")
                }
                if let seconds = budget["seconds"] {
                    configuration.limits.loadBudget.seconds = try number(seconds, "limits.loadBudget.seconds")
                }
            }
            if let depth = limits["maximumNestingDepth"] {
                configuration.limits.maximumNestingDepth = try integer(depth, "limits.maximumNestingDepth")
            }
            if let time = limits["maximumDownloadTime"] {
                configuration.limits.maximumDownloadTime = time is ActionUIJSONNull
                    ? nil : try number(time, "limits.maximumDownloadTime")
            }
        }
        if let trust = top["trust"] {
            let trust = try object(trust, "trust", keys: trustKeys)
            if let origins = trust["trustedOrigins"] {
                guard let list = origins as? [Any] else { throw ActionUIError("trust.trustedOrigins must be an array of strings") }
                configuration.trust.trustedOrigins = try list.map { item in
                    guard let text = item as? String, let url = URL(string: text) else {
                        throw ActionUIError("trust.trustedOrigins must be an array of https origins, such as \"https://ui.example.com\"")
                    }
                    return url
                }
            }
        }
        if let folder = top["resourceFolder"] {
            if folder is ActionUIJSONNull {
                configuration.resourceFolder = nil
            } else if let folder = folder as? String {
                configuration.resourceFolder = folder
            } else {
                throw ActionUIError("resourceFolder must be a string or null")
            }
        }
        if let addOns = top["addOns"] {
            guard let sections = addOns as? [String: Any] else { throw ActionUIError("addOns must be an object") }
            for (name, section) in sections {
                if section is ActionUIJSONNull {
                    configuration.addOns[name] = nil
                } else {
                    configuration.addOns[name] = try ActionUIJSON.string(from: section)
                }
            }
        }
    }

    /// The configuration as JSON with every key (see the header), for a binding to read it back;
    /// set(json:) takes it as it is.
    public var json: String {
        var top: [String: Any] = [
            "limits": [
                "maximumJSONSize": limits.maximumJSONSize,
                "loadBudget": ["loads": limits.loadBudget.loads, "seconds": limits.loadBudget.seconds] as [String: Any],
                "maximumNestingDepth": limits.maximumNestingDepth,
                "maximumDownloadTime": limits.maximumDownloadTime.map { $0 as Any } ?? ActionUIJSONNull(),
            ] as [String: Any],
            "trust": ["trustedOrigins": trust.trustedOrigins.map(\.absoluteString)],
            "resourceFolder": resourceFolder.map { $0 as Any } ?? ActionUIJSONNull(),
        ]
        var sections: [String: Any] = [:]
        for (name, text) in addOns {
            sections[name] = (try? ActionUIJSON.value(from: text)) ?? ActionUIJSONNull()
        }
        top["addOns"] = sections
        // Every value here is one ActionUIJSON writes, and the times are finite (validated).
        return (try? ActionUIJSON.string(from: top)) ?? "{}"
    }

    private static func object(_ value: Any, _ name: String, keys: Set<String>) throws -> [String: Any] {
        guard let object = value as? [String: Any] else { throw ActionUIError("\(name) must be an object") }
        if let unknown = object.keys.sorted().first(where: { !keys.contains($0) }) {
            let prefix = name == "the configuration" ? "" : name + "."
            throw ActionUIError("unknown configuration key \(prefix)\(unknown)")
        }
        return object
    }

    private static func integer(_ value: Any, _ name: String) throws -> Int {
        guard !(value is Bool), let int = value as? Int else { throw ActionUIError("\(name) must be a whole number") }
        return int
    }

    private static func number(_ value: Any, _ name: String) throws -> Double {
        if value is Bool { throw ActionUIError("\(name) must be a number") }
        if let int = value as? Int { return Double(int) }
        guard let double = value as? Double else { throw ActionUIError("\(name) must be a number") }
        return double
    }
}
