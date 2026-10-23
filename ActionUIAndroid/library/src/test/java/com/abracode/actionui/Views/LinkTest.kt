package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Unit tests for [Link] - registry resolution, the pure `title`/`url`
 * resolution ([resolveLink], including its missing-URL warn path), and
 * [linkDestination] against the Link URL parity cases every renderer checks
 * (FormatParity/link-url-cases.json, recorded from Foundation on a Mac). The
 * `@Composable` clickable text + `ACTION_VIEW` launch is exercised by the app.
 */
class LinkTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    @Test
    fun `registry resolves Link and it carries no value`() {
        assertSame(Link, ActionUIRegistry.lookup("Link"))
        assertEquals(ActionUIValueType.NONE, Link.valueType)
    }

    @Test
    fun `resolves title and url, defaulting the title to Link`() {
        val config = resolveLink(
            buildJsonObject { put("title", "Visit Site"); put("url", "https://example.com") },
            CapturingLogger()
        )
        assertEquals("Visit Site", config?.title)
        assertEquals("https://example.com", config?.url)
        assertEquals(true, config?.opens)

        val defaulted = resolveLink(buildJsonObject { put("url", "https://example.com") }, CapturingLogger())
        assertEquals("Link", defaulted?.title)
    }

    @Test
    fun `missing or refused url yields null and warns`() {
        val logger = CapturingLogger()
        assertNull(resolveLink(buildJsonObject { put("title", "x") }, logger))
        assertNull(resolveLink(buildJsonObject { put("url", "") }, logger))
        // Not trimmed, as on Apple: the space before the scheme makes it no URL.
        assertNull(resolveLink(buildJsonObject { put("url", " https://example.com") }, logger))
        assertTrue(logger.warnings.all { it.contains("url") })
        assertEquals(3, logger.warnings.size)
    }

    @Test
    fun `a url without a scheme is shown and opens nothing`() {
        val config = resolveLink(buildJsonObject { put("url", "example.com") }, CapturingLogger())
        assertEquals("example.com", config?.url)
        assertFalse(config!!.opens)
    }

    @Test
    fun `every link url case gives its expected destination`() {
        // Unit tests run in the library module's folder.
        val cases = Json.parseToJsonElement(File("../../FormatParity/link-url-cases.json").readText()).jsonObject
        for (element in cases["cases"]!!.jsonArray) {
            val case = element.jsonObject
            val url = case["url"]!!.jsonPrimitive.content
            val expected = case["expected"]!!.jsonPrimitive.content
            assertEquals("'$url'", expected, linkDestination(url).name.lowercase())
        }
    }
}
