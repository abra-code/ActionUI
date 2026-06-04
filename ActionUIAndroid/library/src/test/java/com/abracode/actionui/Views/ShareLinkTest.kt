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
 * Unit tests for [ShareLink] - registry resolution, the pure `item`/`subject`/
 * `message` resolution ([resolveShareConfig], with its missing-item warn path),
 * and the [shareText] message-prepend rule. The `@Composable` `ACTION_SEND`
 * chooser launch is exercised by the app.
 */
class ShareLinkTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    @Test
    fun `registry resolves ShareLink and it carries no value`() {
        assertSame(ShareLink, ActionUIRegistry.lookup("ShareLink"))
        assertEquals(ActionUIValueType.NONE, ShareLink.valueType)
    }

    @Test
    fun `resolves item, subject, and message`() {
        val config = resolveShareConfig(
            buildJsonObject {
                put("item", "https://example.com")
                put("subject", "Check this out")
                put("message", "Look!")
            },
            CapturingLogger()
        )
        assertEquals("https://example.com", config?.item)
        assertEquals("Check this out", config?.subject)
        assertEquals("Look!", config?.message)
    }

    @Test
    fun `missing item yields null and warns`() {
        val logger = CapturingLogger()
        assertNull(resolveShareConfig(buildJsonObject { put("subject", "x") }, logger))
        assertTrue(logger.warnings.any { it.contains("item") })
    }

    @Test
    fun `shareText prepends a non-empty message to the item`() {
        assertEquals(
            "https://example.com",
            shareText(ShareConfig("https://example.com", subject = null, message = null))
        )
        assertEquals(
            "Look! https://example.com",
            shareText(ShareConfig("https://example.com", subject = null, message = "Look!"))
        )
    }
}
