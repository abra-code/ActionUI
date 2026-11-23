package com.abracode.actionui.Common

import com.abracode.actionui.Helpers.LoadableFormat
import com.abracode.actionui.Helpers.LoadableSource
import com.abracode.actionui.Helpers.descriptionMaxBytes
import com.abracode.actionui.Helpers.loadableNestingRefusal
import com.abracode.actionui.Helpers.remoteOrigin
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.int
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

/**
 * ActionUIConfiguration: the defaults, the JSON keys (each optional, the rest kept), a change
 * refused whole, the configuration fixed by the first window's load, the limits read from it,
 * and trusted origins: trusted only by the address the ActionUI JSON finally came from and only
 * inside trusted content.
 */
class ConfigurationTest {

    @Before
    fun setUp() {
        ActionUIConfiguration.replaceForTesting()
        ActionUIConfiguration.setFixedForTesting(false)
        ActionUIModel.trustPolicy = DefaultTrustPolicy
    }

    @After
    fun tearDown() {
        ActionUIConfiguration.replaceForTesting()
        ActionUIConfiguration.setFixedForTesting(true)
        ActionUIModel.trustPolicy = DefaultTrustPolicy
        ActionUIModel.windowModels.remove("configuration-test")
    }

    private fun refusal(json: String): String? = try {
        ActionUIConfiguration.setJSON(json)
        null
    } catch (e: ActionUIConfiguration.ConfigurationException) {
        e.message
    }

    @Test
    fun `the defaults`() {
        val configuration = ActionUIConfiguration.current
        assertEquals(16 * 1024 * 1024, configuration.limits.maximumJSONSize)
        assertEquals(LoadBudget(256, 60.0), configuration.limits.loadBudget)
        assertEquals(16, configuration.limits.maximumNestingDepth)
        assertEquals(120.0, configuration.limits.maximumDownloadTime)
        assertEquals(emptyList<String>(), configuration.trust.trustedOrigins)
        assertNull(configuration.resourceFolder)
        val json = Json.parseToJsonElement(configuration.json).jsonObject
        assertEquals(setOf("limits", "trust", "resourceFolder", "addOns"), json.keys)
        assertEquals(JsonNull, json["resourceFolder"])
    }

    @Test
    fun `JSON changes only the keys it names`() {
        ActionUIConfiguration.setJSON("""{"limits": {"maximumJSONSize": 67108864, "loadBudget": {"seconds": 30}}}""")
        ActionUIConfiguration.setJSON("""{"trust": {"trustedOrigins": ["https://ui.example.com", "https://cdn.example.com:8443/"]}, "resourceFolder": "/data/ui"}""")
        val configuration = ActionUIConfiguration.current
        assertEquals("a host may raise a limit", 64 * 1024 * 1024, configuration.limits.maximumJSONSize)
        assertEquals("loads kept", LoadBudget(256, 30.0), configuration.limits.loadBudget)
        assertEquals(listOf("https://ui.example.com", "https://cdn.example.com:8443/"), configuration.trust.trustedOrigins)
        assertEquals("/data/ui", configuration.resourceFolder)
        ActionUIConfiguration.setJSON("""{"resourceFolder": null, "addOns": {"Sample": {"level": 2}}}""")
        assertNull(ActionUIConfiguration.current.resourceFolder)
        assertEquals(2, ActionUIConfiguration.current.addOns["Sample"]?.jsonObject?.get("level")?.jsonPrimitive?.int)
        ActionUIConfiguration.setJSON("""{"addOns": {"Sample": null}}""")
        assertTrue("null removes a section", ActionUIConfiguration.current.addOns.isEmpty())
        ActionUIConfiguration.setJSON("""{"limits": {"maximumDownloadTime": 600}}""")
        assertEquals(600.0, ActionUIConfiguration.current.limits.maximumDownloadTime)
        ActionUIConfiguration.setJSON("""{"limits": {"maximumDownloadTime": null}}""")
        assertNull("null removes the time limit", ActionUIConfiguration.current.limits.maximumDownloadTime)
        assertEquals(JsonNull, Json.parseToJsonElement(ActionUIConfiguration.current.json).jsonObject["limits"]?.jsonObject?.get("maximumDownloadTime"))
        // Its own JSON sets the same configuration.
        val changed = ActionUIConfiguration.current
        ActionUIConfiguration.replaceForTesting()
        ActionUIConfiguration.setJSON(changed.json)
        assertEquals(changed, ActionUIConfiguration.current)
    }

    @Test
    fun `a bad change is refused whole`() {
        val refused = listOf(
            """{"limits": {"maximumJSONSize": 1000}, "trustedOrigins": []}""" to "unknown configuration key trustedOrigins",
            """{"limits": {"maximumJSONSize": 1000, "maxJSONSize": 5}}""" to "unknown configuration key limits.maxJSONSize",
            """{"limits": {"loadBudget": {"loads": 3, "span": 1}}}""" to "unknown configuration key limits.loadBudget.span",
            """{"limits": {"maximumJSONSize": "big"}}""" to "limits.maximumJSONSize must be a whole number",
            """{"limits": {"maximumJSONSize": true}}""" to "limits.maximumJSONSize must be a whole number",
            """{"limits": {"maximumJSONSize": 1.5}}""" to "limits.maximumJSONSize must be a whole number",
            """{"limits": {"maximumJSONSize": 0}}""" to "limits.maximumJSONSize must be more than 0",
            """{"limits": {"loadBudget": {"seconds": 0}}}""" to "limits.loadBudget.seconds must be a number more than 0",
            """{"limits": {"maximumNestingDepth": -1}}""" to "limits.maximumNestingDepth must not be negative",
            """{"limits": {"maximumDownloadTime": 0}}""" to "limits.maximumDownloadTime must be a number more than 0, or null for no limit",
            """{"limits": {"maximumDownloadTime": -5}}""" to "limits.maximumDownloadTime must be a number more than 0, or null for no limit",
            """{"limits": {"maximumDownloadTime": "slow"}}""" to "limits.maximumDownloadTime must be a number",
            """{"limits": {"maximumDownloadTime": true}}""" to "limits.maximumDownloadTime must be a number",
            """{"limits": []}""" to "limits must be an object",
            """{"trust": {"trustedOrigins": "https://ui.example.com"}}""" to "trust.trustedOrigins must be an array of strings",
            """{"trust": {"trustedOrigins": ["http://ui.example.com"]}}""" to "trust.trustedOrigins: http://ui.example.com is not an https address",
            """{"trust": {"trustedOrigins": ["https://ui.example.com/app"]}}""" to "trust.trustedOrigins: https://ui.example.com/app has a path; an origin is the scheme, host and port only",
            """{"trust": {"trustedOrigins": ["https://me@ui.example.com"]}}""" to "trust.trustedOrigins: https://me@ui.example.com has a user name or password",
            """{"trust": {"trustedOrigins": ["https://ui.example.com/?a=1"]}}""" to "trust.trustedOrigins: https://ui.example.com/?a=1 has a query or fragment",
            """{"resourceFolder": ""}""" to "resourceFolder must not be empty; null for none",
            """{"resourceFolder": 3}""" to "resourceFolder must be a string or null",
            """{"addOns": 3}""" to "addOns must be an object",
            "[]" to "the configuration must be an object",
        )
        for ((json, message) in refused) {
            assertEquals(json, message, refusal(json))
            assertEquals("nothing of $json applied", ActionUIConfiguration(), ActionUIConfiguration.current)
        }
        assertTrue(refusal("{limits")!!.startsWith("the configuration is not valid JSON"))
        try {
            ActionUIConfiguration.set(ActionUIConfiguration(trust = ActionUIConfiguration.Trust(listOf("file:///etc"))))
            fail("the value setter validates too")
        } catch (e: ActionUIConfiguration.ConfigurationException) {
            assertEquals(ActionUIConfiguration(), ActionUIConfiguration.current)
        }
    }

    @Test
    fun `the first window's load fixes the configuration`() {
        ActionUIConfiguration.setJSON("""{"limits": {"maximumNestingDepth": 4}}""")
        assertFalse(ActionUIConfiguration.isFixed)
        ActionUIModel.loadDescription(ActionUIElement(id = 1, type = "Text"), windowUUID = "configuration-test")
        assertTrue(ActionUIConfiguration.isFixed)
        val fixed = "the configuration is fixed once a window has loaded its ActionUI JSON; set it before"
        assertEquals(fixed, refusal("""{"limits": {"maximumNestingDepth": 8}}"""))
        for (change in listOf<() -> Unit>(
            { ActionUIConfiguration.set(ActionUIConfiguration()) },
            { ActionUIConfiguration.update { it.copy(resourceFolder = "/data/late") } },
        )) {
            try {
                change()
                fail("a change once fixed")
            } catch (e: ActionUIConfiguration.ConfigurationException) {
                assertEquals(fixed, e.message)
            }
        }
        assertEquals("the setting from before the load stays", 4, ActionUIConfiguration.current.limits.maximumNestingDepth)
    }

    @Test
    fun `a list the host keeps cannot change the configuration later`() {
        val origins = mutableListOf("https://ui.example.com")
        ActionUIConfiguration.set(ActionUIConfiguration(trust = ActionUIConfiguration.Trust(origins)))
        origins += "http://ui.example.com"
        assertEquals(listOf("https://ui.example.com"), ActionUIConfiguration.current.trust.trustedOrigins)
        val later = mutableListOf("https://cdn.example.com")
        ActionUIConfiguration.update { it.copy(trust = ActionUIConfiguration.Trust(later)) }
        later.clear()
        assertEquals(listOf("https://cdn.example.com"), ActionUIConfiguration.current.trust.trustedOrigins)
    }

    @Test
    fun `the limits come from the configuration`() {
        ActionUIConfiguration.setJSON("""{"limits": {"maximumJSONSize": 3000, "maximumNestingDepth": 2, "loadBudget": {"loads": 1}}}""")
        assertEquals(3000, descriptionMaxBytes)
        assertNull(loadableNestingRefusal("c", listOf("a")))
        assertEquals("LoadableViews are nested more than 2 deep", loadableNestingRefusal("c", listOf("a", "b")))
        val window = WindowModel(windowUUID = "budget", logger = ConsoleLogger())
        assertTrue(window.spendLoad(0))
        assertFalse(window.spendLoad(1))
    }

    @Test
    fun `a trusted origin is trusted only by its exact origin and inside trusted content`() {
        val origins = listOf("https://ui.example.com")
        fun trust(address: String, parent: JSONContentOrigin? = null) =
            classifyOrigin(LoadableSource.Remote(address, LoadableFormat.JSON), parent, null, emptyList(), origins)?.trust
        assertEquals(JSONContentOrigin.Trust.TRUSTED, trust("https://ui.example.com/app/main.json"))
        assertEquals("case and the default port", JSONContentOrigin.Trust.TRUSTED, trust("https://UI.Example.com:443/main.json"))
        assertEquals("plain http", JSONContentOrigin.Trust.LESS_TRUSTED, trust("http://ui.example.com/main.json"))
        assertEquals("another port", JSONContentOrigin.Trust.LESS_TRUSTED, trust("https://ui.example.com:8443/main.json"))
        assertEquals("a subdomain", JSONContentOrigin.Trust.LESS_TRUSTED, trust("https://evil.ui.example.com/main.json"))
        assertEquals(JSONContentOrigin.Trust.LESS_TRUSTED, trust("https://ui.example.com.evil.net/main.json"))
        val remote = JSONContentOrigin(JSONContentOrigin.Source.Remote("https://other.net/a.json"), JSONContentOrigin.Trust.LESS_TRUSTED, null)
        assertEquals("named by less-trusted content", JSONContentOrigin.Trust.LESS_TRUSTED, trust("https://ui.example.com/main.json", remote))
        assertEquals(JSONContentOrigin.Trust.TRUSTED, trust("https://ui.example.com/main.json", JSONContentOrigin.HOST))
        assertEquals("no trusted origins by default", JSONContentOrigin.Trust.LESS_TRUSTED,
            classifyOrigin(LoadableSource.Remote("https://ui.example.com/a.json", LoadableFormat.JSON), null, null, emptyList())?.trust)
    }

    @Test
    fun `a remote load is judged by where it finally came from`() {
        ActionUIConfiguration.setJSON("""{"trust": {"trustedOrigins": ["https://ui.example.com"]}}""")
        val source = LoadableSource.Remote("https://ui.example.com/root.json", LoadableFormat.JSON)
        val redirected = remoteOrigin(source, "https://cdn.other.net/root.json", null, null)
        assertEquals("redirected off the trusted server", JSONContentOrigin.Trust.LESS_TRUSTED, redirected?.trust)
        assertEquals(JSONContentOrigin.Source.Remote("https://cdn.other.net/root.json"), redirected?.source)
        val direct = remoteOrigin(source, "https://ui.example.com/root.json", null, null)
        assertEquals(JSONContentOrigin.Trust.TRUSTED, direct?.trust)
        assertEquals("no final address reported: the requested one", JSONContentOrigin.Trust.TRUSTED, remoteOrigin(source, null, null, null)?.trust)
        // A trust policy sees the trusted origin as its default.
        val defaults = mutableListOf<JSONContentOrigin.Trust>()
        ActionUIModel.trustPolicy = object : ActionUITrustPolicy {
            override fun trust(source: JSONContentOrigin.Source, parent: JSONContentOrigin?, byDefault: JSONContentOrigin.Trust): JSONContentOrigin.Trust {
                defaults += byDefault
                return JSONContentOrigin.Trust.LESS_TRUSTED
            }
        }
        assertEquals("the policy has the last word", JSONContentOrigin.Trust.LESS_TRUSTED, remoteOrigin(source, null, null, null)?.trust)
        assertEquals(listOf(JSONContentOrigin.Trust.TRUSTED), defaults)
    }

    @Test
    fun `the resource folder counts as the app's resources`() {
        val folder = java.nio.file.Files.createTempDirectory("actionui-configuration").toFile()
        try {
            val file = java.io.File(folder, "a.json").apply { writeText("{}") }
            assertFalse(DefaultTrustPolicy.isInAppResources(file.path))
            ActionUIConfiguration.setJSON(JsonObject(mapOf("resourceFolder" to JsonPrimitive(folder.path))).toString())
            assertTrue(DefaultTrustPolicy.isInAppResources(file.path))
            assertEquals(JSONContentOrigin.Trust.TRUSTED,
                resolvedOrigin(LoadableSource.FilePath(file.path, LoadableFormat.JSON), null, null)?.trust)
        } finally {
            folder.deleteRecursively()
        }
    }
}
