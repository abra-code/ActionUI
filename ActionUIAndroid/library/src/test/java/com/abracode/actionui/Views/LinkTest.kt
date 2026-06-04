package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [Link] - registry resolution and the pure `title`/`url`
 * resolution ([resolveLink], including its missing-URL warn path). The
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

        val defaulted = resolveLink(buildJsonObject { put("url", "https://example.com") }, CapturingLogger())
        assertEquals("Link", defaulted?.title)
    }

    @Test
    fun `missing or blank url yields null and warns`() {
        val logger = CapturingLogger()
        assertNull(resolveLink(buildJsonObject { put("title", "x") }, logger))
        assertNull(resolveLink(buildJsonObject { put("url", "   ") }, logger))
        assertTrue(logger.warnings.all { it.contains("url") })
        assertEquals(2, logger.warnings.size)
    }
}
