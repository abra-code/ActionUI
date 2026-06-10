package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIJson
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.LoggerLevel
import java.io.FileNotFoundException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the pure halves of `WebView.kt`: property validation
 * ([resolveWebViewConfig], [parseUserScripts]), the host-command vocabulary
 * ([parseWebViewCommand]), script-source resolution ([resolveScriptSource]),
 * and the seeded value/state contract. The `android.webkit.WebView` rendering
 * and navigation callbacks are exercised by running the app, the stance the
 * rest of the renderer takes for platform-view code.
 */
class WebViewTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    private fun props(json: String): JsonObject =
        Json.parseToJsonElement(json).jsonObject

    private fun element(json: String): ActionUIElement =
        ActionUIJson.decodeFromString(ActionUIElement.serializer(), json)

    // -----------------------------------------------------------------------
    // Registry / seeding contract
    // -----------------------------------------------------------------------

    @Test
    fun `WebView is registered`() {
        assertSame(WebView, ActionUIRegistry.lookup("WebView"))
    }

    @Test
    fun `initial value is the url property or empty`() {
        val withURL = element(
            """{ "type": "WebView", "id": 1, "properties": { "url": "https://example.com" } }"""
        )
        assertEquals("https://example.com", WebView.initialValue(withURL))

        val htmlOnly = element(
            """{ "type": "WebView", "id": 1, "properties": { "html": "<p>hi</p>" } }"""
        )
        assertEquals("", WebView.initialValue(htmlOnly))
    }

    @Test
    fun `initial states seed the Apple navigation contract`() {
        val states = WebView.initialStates(element("""{ "type": "WebView", "id": 1 }"""))
        assertEquals(false, states["isLoading"])
        assertEquals(0.0, states["estimatedProgress"])
        assertEquals(false, states["canGoBack"])
        assertEquals(false, states["canGoForward"])
        assertNull(states["title"])
    }

    // -----------------------------------------------------------------------
    // resolveWebViewConfig
    // -----------------------------------------------------------------------

    @Test
    fun `config defaults for empty properties`() {
        val config = resolveWebViewConfig(null, null)
        assertNull(config.url)
        assertNull(config.html)
        assertTrue(config.magnificationGestures)
        assertTrue(config.userScripts.isEmpty())
    }

    @Test
    fun `config reads the supported properties`() {
        val logger = CapturingLogger()
        val config = resolveWebViewConfig(
            props(
                """{ "url": "https://example.com", "html": "<p>hi</p>",
                     "baseURL": "https://base.example", "customUserAgent": "MyApp/1.0",
                     "magnificationGestures": false,
                     "navigationActionID": "nav", "valueChangeActionID": "changed" }"""
            ),
            logger
        )
        assertEquals("https://example.com", config.url)
        assertEquals("<p>hi</p>", config.html)
        assertEquals("https://base.example", config.baseURL)
        assertEquals("MyApp/1.0", config.customUserAgent)
        assertFalse(config.magnificationGestures)
        assertEquals("nav", config.navigationActionID)
        assertEquals("changed", config.valueChangeActionID)
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `invalid property types warn and read as absent`() {
        val logger = CapturingLogger()
        val config = resolveWebViewConfig(
            props("""{ "url": 42, "customUserAgent": true, "magnificationGestures": "yes" }"""),
            logger
        )
        assertNull(config.url)
        assertNull(config.customUserAgent)
        assertTrue(config.magnificationGestures)
        assertEquals(3, logger.warnings.size)
    }

    @Test
    fun `Apple-only toggles are ignored without warnings`() {
        val logger = CapturingLogger()
        resolveWebViewConfig(
            props(
                """{ "backForwardNavigationGestures": true, "linkPreviews": false,
                     "limitsNavigationsToAppBoundDomains": true, "upgradeKnownHostsToHTTPS": true }"""
            ),
            logger
        )
        assertTrue("Expected no warnings, got: ${logger.warnings}", logger.warnings.isEmpty())
    }

    // -----------------------------------------------------------------------
    // parseUserScripts
    // -----------------------------------------------------------------------

    @Test
    fun `user scripts parse with injection times`() {
        val logger = CapturingLogger()
        val scripts = parseUserScripts(
            props(
                """{ "userScripts": [
                     { "injectionTime": "documentStart", "source": "window.x = 1;" },
                     { "injectionTime": "documentEnd", "resourceName": "inject.js" },
                     { "filePath": "/tmp/script.js" } ] }"""
            )["userScripts"],
            logger
        )
        assertEquals(3, scripts.size)
        assertEquals(WebViewInjectionTime.DOCUMENT_START, scripts[0].injectionTime)
        assertEquals("window.x = 1;", scripts[0].source)
        assertEquals(WebViewInjectionTime.DOCUMENT_END, scripts[1].injectionTime)
        assertEquals("inject.js", scripts[1].resourceName)
        // injectionTime absent -> documentEnd, no warning (only invalid values warn).
        assertEquals(WebViewInjectionTime.DOCUMENT_END, scripts[2].injectionTime)
        assertEquals("/tmp/script.js", scripts[2].filePath)
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `script without any source is skipped with a warning`() {
        val logger = CapturingLogger()
        val scripts = parseUserScripts(
            props("""{ "userScripts": [ { "injectionTime": "documentStart" } ] }""")["userScripts"],
            logger
        )
        assertTrue(scripts.isEmpty())
        assertEquals(1, logger.warnings.size)
    }

    @Test
    fun `invalid injectionTime warns and defaults to documentEnd`() {
        val logger = CapturingLogger()
        val scripts = parseUserScripts(
            props("""{ "userScripts": [ { "injectionTime": "later", "source": "x" } ] }""")["userScripts"],
            logger
        )
        assertEquals(WebViewInjectionTime.DOCUMENT_END, scripts.single().injectionTime)
        assertEquals(1, logger.warnings.size)
    }

    @Test
    fun `non-array userScripts warns and yields nothing`() {
        val logger = CapturingLogger()
        val scripts = parseUserScripts(props("""{ "userScripts": "nope" }""")["userScripts"], logger)
        assertTrue(scripts.isEmpty())
        assertEquals(1, logger.warnings.size)
    }

    // -----------------------------------------------------------------------
    // parseWebViewCommand
    // -----------------------------------------------------------------------

    @Test
    fun `command vocabulary matches Apple`() {
        assertEquals(WebViewCommand.GO_BACK, parseWebViewCommand("#goBack"))
        assertEquals(WebViewCommand.GO_FORWARD, parseWebViewCommand("#goForward"))
        assertEquals(WebViewCommand.RELOAD, parseWebViewCommand("#reload"))
        assertEquals(WebViewCommand.STOP, parseWebViewCommand("#stop"))
        assertEquals(WebViewCommand.LOAD_URL, parseWebViewCommand("https://example.com"))
    }

    // -----------------------------------------------------------------------
    // resolveScriptSource
    // -----------------------------------------------------------------------

    @Test
    fun `inline source wins`() {
        val script = WebViewUserScript(WebViewInjectionTime.DOCUMENT_END, source = "window.x = 1;")
        assertEquals(
            "window.x = 1;",
            resolveScriptSource(script, { throw FileNotFoundException() }, null)
        )
    }

    @Test
    fun `resourceName resolves through assets, trying a js extension`() {
        val script = WebViewUserScript(WebViewInjectionTime.DOCUMENT_END, resourceName = "inject")
        val resolved = resolveScriptSource(
            script,
            { name ->
                if (name == "inject.js") "window.y = 2;".byteInputStream()
                else throw FileNotFoundException(name)
            },
            null
        )
        assertEquals("window.y = 2;", resolved)
    }

    @Test
    fun `missing asset warns and drops the script`() {
        val logger = CapturingLogger()
        val script = WebViewUserScript(WebViewInjectionTime.DOCUMENT_END, resourceName = "absent.js")
        assertNull(resolveScriptSource(script, { throw FileNotFoundException() }, logger))
        assertEquals(1, logger.warnings.size)
    }

    @Test
    fun `unreadable filePath warns and drops the script`() {
        val logger = CapturingLogger()
        val script = WebViewUserScript(
            WebViewInjectionTime.DOCUMENT_END,
            filePath = "/nonexistent/dir/script.js"
        )
        assertNull(resolveScriptSource(script, { throw FileNotFoundException() }, logger))
        assertEquals(1, logger.warnings.size)
    }
}
