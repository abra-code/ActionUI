package com.abracode.actionui.Common

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull
import java.net.URI
import java.net.URISyntaxException

/**
 * The host's configuration of ActionUI, for every window: limits, trust settings, the app's
 * resource folder, and settings for add-ons, with the same keys as on Apple and Linux. Only
 * host code sets it, never ActionUI JSON, so content cannot raise its own limits or trust
 * itself. It is set early, before the first window loads its ActionUI JSON, and fixed after
 * that: a later change is refused, so every window and every load sees the same settings.
 *
 * Set it with [set] (a value), [update] (a change to the current value) or [setJSON] (the
 * keys as JSON):
 *
 * ```
 * {
 *   "limits": {
 *     "maximumJSONSize": 16777216,                  // bytes of ActionUI JSON one load takes (16 MB)
 *     "loadBudget": { "loads": 256, "seconds": 60 },// LoadableView loads per window in any span
 *     "maximumNestingDepth": 16,                    // LoadableViews inside LoadableViews
 *     "maximumDownloadTime": 120                    // seconds one http or https load may take (null: no limit)
 *   },
 *   "trust": { "trustedOrigins": ["https://ui.example.com"] },  // servers whose JSON is trusted
 *   "resourceFolder": "/data/user/0/com.example/files/ui",      // a folder of the app's own (null: none)
 *   "addOns": { "SomeAddOn": { } }                               // each add-on reads its own section
 * }
 * ```
 *
 * Each key is optional: JSON changes only the keys it names and keeps the rest. A key ActionUI
 * does not know, a value of the wrong type or out of range, or a trusted origin that is not an
 * https origin refuses the whole change ([ConfigurationException]), which then keeps the
 * configuration as it was.
 *
 * Trusted origins: ActionUI JSON from one of these servers is trusted as the app's own,
 * provided the content around it is trusted too (a window's root, or a LoadableView in trusted
 * content), so less-trusted content cannot name the server and get trusted content inside
 * itself. An origin is a scheme, host and port; only https is accepted, with no path, query,
 * fragment or user name. The address that counts is the one the ActionUI JSON finally came
 * from, after redirects.
 *
 * The app's assets are always its resources; [resourceFolder] adds a folder of files (unpacked
 * into the app's files folder, say) whose ActionUI JSON is trusted the same way. The host may
 * raise the limits above the defaults: host code is trusted. The trust policy
 * ([ActionUIModel.trustPolicy]) stays a separate setter, since it is code; its `byDefault`
 * trust already counts the trusted origins.
 */
data class ActionUIConfiguration(
    val limits: Limits = Limits(),
    val trust: Trust = Trust(),
    val resourceFolder: String? = null,
    /** Settings for add-ons, each under the add-on's own name. */
    val addOns: Map<String, JsonElement> = emptyMap(),
) {
    data class Limits(
        /** The largest ActionUI JSON any load takes, in UTF-8 bytes, whoever loads it (16 MB). */
        val maximumJSONSize: Int = 16 * 1024 * 1024,
        /** How many LoadableView loads one window may make in a span of time; one more is refused. */
        val loadBudget: LoadBudget = LoadBudget(loads = 256, seconds = 60.0),
        /** How deep LoadableViews may nest: one with this many LoadableViews around it is refused. */
        val maximumNestingDepth: Int = 16,
        /**
         * The longest one http or https load may take, in seconds, however the server sends: a load of
         * ActionUI JSON or of an image by the renderer's own loader (LoadableView, AsyncImage) is given up
         * after this. The connect and read timeouts cover each step, so this only stops a server that keeps
         * sending slowly. A host whose users may be on slow networks, or that shows large images, raises it;
         * null removes it. 120 seconds by default.
         */
        val maximumDownloadTime: Double? = 120.0,
    )

    data class Trust(
        /** The https origins whose ActionUI JSON is trusted (see the class comment); none by default. */
        val trustedOrigins: List<String> = emptyList(),
    )

    /** [resourceFolder] as a list, for the checks that take several folders. */
    internal val resourceFolders: List<String> get() = listOfNotNull(resourceFolder)

    /** The configuration as JSON with every key, for a host to read it back; [setJSON] takes it as it is. */
    val json: String
        get() = JsonObject(
            mapOf(
                "limits" to JsonObject(
                    mapOf(
                        "maximumJSONSize" to JsonPrimitive(limits.maximumJSONSize),
                        "loadBudget" to JsonObject(
                            mapOf(
                                "loads" to JsonPrimitive(limits.loadBudget.loads),
                                "seconds" to JsonPrimitive(limits.loadBudget.seconds),
                            )
                        ),
                        "maximumNestingDepth" to JsonPrimitive(limits.maximumNestingDepth),
                        "maximumDownloadTime" to (limits.maximumDownloadTime?.let { JsonPrimitive(it) } ?: JsonNull),
                    )
                ),
                "trust" to JsonObject(mapOf("trustedOrigins" to JsonArray(trust.trustedOrigins.map { JsonPrimitive(it) }))),
                "resourceFolder" to (resourceFolder?.let { JsonPrimitive(it) } ?: JsonNull),
                "addOns" to JsonObject(addOns),
            )
        ).toString()

    /** Why a change to the configuration was refused; the configuration is as it was. */
    class ConfigurationException(message: String) : IllegalArgumentException(message)

    companion object {
        private val lock = Any()
        @Volatile private var stored = ActionUIConfiguration()
        @Volatile private var storedIsFixed = false

        /** The configuration in effect. */
        @JvmStatic val current: ActionUIConfiguration get() = stored

        /** Whether the configuration is fixed: the first window has loaded its ActionUI JSON. */
        @JvmStatic val isFixed: Boolean get() = storedIsFixed

        private const val FIXED = "the configuration is fixed once a window has loaded its ActionUI JSON; set it before"

        /** Makes [configuration] the one in effect; [ConfigurationException], changing nothing, when fixed or not valid. */
        @JvmStatic
        fun set(configuration: ActionUIConfiguration) {
            // A copy, so a list or map the host keeps cannot change the configuration later.
            val copied = configuration.copied()
            validate(copied)
            synchronized(lock) {
                if (storedIsFixed) throw ConfigurationException(FIXED)
                stored = copied
            }
        }

        /** Changes the configuration in effect with [change], as [set] would set the result. */
        @JvmStatic
        fun update(change: (ActionUIConfiguration) -> ActionUIConfiguration) {
            synchronized(lock) {
                if (storedIsFixed) throw ConfigurationException(FIXED)
                val changed = change(stored).copied()
                validate(changed)
                stored = changed
            }
        }

        /** Changes the keys [json] names (see the class comment); [ConfigurationException], changing nothing, when fixed or not valid. */
        @JvmStatic
        fun setJSON(json: String) {
            val parsed = try {
                Json.parseToJsonElement(json)
            } catch (e: Exception) {
                throw ConfigurationException("the configuration is not valid JSON: ${e.message}")
            }
            update { apply(parsed, it) }
        }

        /** Fixes the configuration: called when a window first loads its ActionUI JSON. */
        internal fun fix() {
            // Under the lock, so an update in progress either finishes before or is refused.
            synchronized(lock) { storedIsFixed = true }
        }

        /** For tests, which load windows and change settings in any order: [configuration] in effect, unvalidated. */
        internal fun replaceForTesting(configuration: ActionUIConfiguration = ActionUIConfiguration()) {
            synchronized(lock) { stored = configuration }
        }

        /** For tests of the setters: fixes the configuration, or makes it settable again. */
        internal fun setFixedForTesting(fixed: Boolean) {
            synchronized(lock) { storedIsFixed = fixed }
        }

        /** This configuration with its own copies of the lists and maps in it. */
        private fun ActionUIConfiguration.copied(): ActionUIConfiguration =
            copy(trust = trust.copy(trustedOrigins = trust.trustedOrigins.toList()), addOns = addOns.toMap())

        internal fun validate(configuration: ActionUIConfiguration) {
            val limits = configuration.limits
            if (limits.maximumJSONSize <= 0) throw ConfigurationException("limits.maximumJSONSize must be more than 0")
            if (limits.loadBudget.loads < 0) throw ConfigurationException("limits.loadBudget.loads must not be negative")
            if (!limits.loadBudget.seconds.isFinite() || limits.loadBudget.seconds <= 0) {
                throw ConfigurationException("limits.loadBudget.seconds must be a number more than 0")
            }
            if (limits.maximumNestingDepth < 0) throw ConfigurationException("limits.maximumNestingDepth must not be negative")
            limits.maximumDownloadTime?.let { time ->
                if (!time.isFinite() || time <= 0) {
                    throw ConfigurationException("limits.maximumDownloadTime must be a number more than 0, or null for no limit")
                }
            }
            for (origin in configuration.trust.trustedOrigins) {
                trustedOriginProblem(origin)?.let { throw ConfigurationException("trust.trustedOrigins: $origin $it") }
            }
            if (configuration.resourceFolder?.isEmpty() == true) {
                throw ConfigurationException("resourceFolder must not be empty; null for none")
            }
        }

        /** Why [address] is not a trusted origin, or null when it is one: https, a host, and at most a port after it. */
        internal fun trustedOriginProblem(address: String): String? {
            val uri = try { URI(address) } catch (e: URISyntaxException) { return "is not an https address" }
            if (uri.scheme?.lowercase() != "https") return "is not an https address"
            if (uri.host.isNullOrEmpty()) return "has no host"
            if (uri.rawUserInfo != null) return "has a user name or password"
            val path = uri.rawPath ?: ""
            if (path.isNotEmpty() && path != "/") return "has a path; an origin is the scheme, host and port only"
            if (uri.rawQuery != null || uri.rawFragment != null) return "has a query or fragment"
            return null
        }

        /** Whether ActionUI JSON from [url] comes from one of [origins] (same scheme, host and port), https only. */
        internal fun isTrustedOrigin(url: String, origins: List<String>): Boolean {
            if (DefaultTrustPolicy.schemeOf(url) != "https") return false
            return origins.any { DefaultTrustPolicy.haveSameOrigin(it, url) }
        }

        private val topKeys = setOf("limits", "trust", "resourceFolder", "addOns")
        private val limitKeys = setOf("maximumJSONSize", "loadBudget", "maximumNestingDepth", "maximumDownloadTime")
        private val budgetKeys = setOf("loads", "seconds")
        private val trustKeys = setOf("trustedOrigins")

        private fun apply(parsed: JsonElement, configuration: ActionUIConfiguration): ActionUIConfiguration {
            val top = objectOf(parsed, "the configuration", topKeys)
            var limits = configuration.limits
            top["limits"]?.let { value ->
                val section = objectOf(value, "limits", limitKeys)
                section["maximumJSONSize"]?.let { limits = limits.copy(maximumJSONSize = integer(it, "limits.maximumJSONSize")) }
                section["loadBudget"]?.let { budgetValue ->
                    val budget = objectOf(budgetValue, "limits.loadBudget", budgetKeys)
                    var loadBudget = limits.loadBudget
                    budget["loads"]?.let { loadBudget = loadBudget.copy(loads = integer(it, "limits.loadBudget.loads")) }
                    budget["seconds"]?.let { loadBudget = loadBudget.copy(seconds = number(it, "limits.loadBudget.seconds")) }
                    limits = limits.copy(loadBudget = loadBudget)
                }
                section["maximumNestingDepth"]?.let { limits = limits.copy(maximumNestingDepth = integer(it, "limits.maximumNestingDepth")) }
                section["maximumDownloadTime"]?.let {
                    limits = limits.copy(maximumDownloadTime = if (it is JsonNull) null else number(it, "limits.maximumDownloadTime"))
                }
            }
            var trust = configuration.trust
            top["trust"]?.let { value ->
                val section = objectOf(value, "trust", trustKeys)
                section["trustedOrigins"]?.let { origins ->
                    val list = origins as? JsonArray ?: throw ConfigurationException("trust.trustedOrigins must be an array of strings")
                    trust = trust.copy(trustedOrigins = list.map { item ->
                        (item as? JsonPrimitive)?.takeIf { it.isString }?.content
                            ?: throw ConfigurationException("trust.trustedOrigins must be an array of https origins, such as \"https://ui.example.com\"")
                    })
                }
            }
            var folder = configuration.resourceFolder
            top["resourceFolder"]?.let { value ->
                folder = when {
                    value is JsonNull -> null
                    value is JsonPrimitive && value.isString -> value.content
                    else -> throw ConfigurationException("resourceFolder must be a string or null")
                }
            }
            var addOns = configuration.addOns
            top["addOns"]?.let { value ->
                val sections = value as? JsonObject ?: throw ConfigurationException("addOns must be an object")
                val changed = addOns.toMutableMap()
                for ((name, section) in sections) {
                    if (section is JsonNull) changed.remove(name) else changed[name] = section
                }
                addOns = changed
            }
            return ActionUIConfiguration(limits, trust, folder, addOns)
        }

        private fun objectOf(value: JsonElement, name: String, keys: Set<String>): JsonObject {
            val obj = value as? JsonObject ?: throw ConfigurationException("$name must be an object")
            obj.keys.sorted().firstOrNull { it !in keys }?.let { unknown ->
                val prefix = if (name == "the configuration") "" else "$name."
                throw ConfigurationException("unknown configuration key $prefix$unknown")
            }
            return obj
        }

        private fun integer(value: JsonElement, name: String): Int {
            val primitive = value as? JsonPrimitive
            if (primitive == null || primitive.isString || primitive.booleanOrNull != null) {
                throw ConfigurationException("$name must be a whole number")
            }
            val long = primitive.longOrNull ?: throw ConfigurationException("$name must be a whole number")
            if (long < Int.MIN_VALUE || long > Int.MAX_VALUE) throw ConfigurationException("$name is out of range")
            return long.toInt()
        }

        private fun number(value: JsonElement, name: String): Double {
            val primitive = value as? JsonPrimitive
            if (primitive == null || primitive.isString || primitive.booleanOrNull != null) {
                throw ConfigurationException("$name must be a number")
            }
            return primitive.doubleOrNull ?: throw ConfigurationException("$name must be a number")
        }
    }
}
