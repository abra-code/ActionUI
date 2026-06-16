package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [resolveScrollContentBackgroundMode] - the pure parse of the
 * `scrollContentBackground` base property. The `@Composable`
 * [applyScrollContentBackground] (which reads `MaterialTheme`) is exercised by
 * running the app; here we only cover the value -> mode mapping and its
 * warn-and-default paths, the stance the rest of the renderer's pure resolvers take.
 */
class ScrollContentBackgroundTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    private fun props(value: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit): JsonObject =
        buildJsonObject(value)

    @Test
    fun `absent property defaults to automatic without warning`() {
        val logger = CapturingLogger()
        assertEquals(
            ScrollContentBackgroundMode.AUTOMATIC,
            resolveScrollContentBackgroundMode(null, logger),
        )
        assertEquals(
            ScrollContentBackgroundMode.AUTOMATIC,
            resolveScrollContentBackgroundMode(props { put("other", "x") }, logger),
        )
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `the three valid values map without warning`() {
        val logger = CapturingLogger()
        assertEquals(
            ScrollContentBackgroundMode.VISIBLE,
            resolveScrollContentBackgroundMode(props { put("scrollContentBackground", "visible") }, logger),
        )
        assertEquals(
            ScrollContentBackgroundMode.HIDDEN,
            resolveScrollContentBackgroundMode(props { put("scrollContentBackground", "hidden") }, logger),
        )
        assertEquals(
            ScrollContentBackgroundMode.AUTOMATIC,
            resolveScrollContentBackgroundMode(props { put("scrollContentBackground", "automatic") }, logger),
        )
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `unknown string warns and falls back to automatic`() {
        val logger = CapturingLogger()
        assertEquals(
            ScrollContentBackgroundMode.AUTOMATIC,
            resolveScrollContentBackgroundMode(props { put("scrollContentBackground", "translucent") }, logger),
        )
        assertFalse(logger.warnings.isEmpty())
        assertTrue(logger.warnings.any { it.contains("translucent") })
    }

    @Test
    fun `a non-string value warns and falls back to automatic`() {
        val logger = CapturingLogger()
        assertEquals(
            ScrollContentBackgroundMode.AUTOMATIC,
            resolveScrollContentBackgroundMode(props { put("scrollContentBackground", true) }, logger),
        )
        assertEquals(
            ScrollContentBackgroundMode.AUTOMATIC,
            resolveScrollContentBackgroundMode(props { put("scrollContentBackground", 3) }, logger),
        )
        assertEquals(
            ScrollContentBackgroundMode.AUTOMATIC,
            resolveScrollContentBackgroundMode(
                props { putJsonArray("scrollContentBackground") { add("visible") } },
                logger,
            ),
        )
        assertEquals(3, logger.warnings.size)
        assertTrue(logger.warnings.all { it.contains("expected String") })
    }
}
