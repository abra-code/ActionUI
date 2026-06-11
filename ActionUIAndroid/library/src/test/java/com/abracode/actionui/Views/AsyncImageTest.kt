package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIJson
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.LoggerLevel
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
 * Unit tests for the pure half of `AsyncImage.kt` - property validation
 * ([resolveAsyncImageConfig]) and the value-bridge seeding. The fetch/decode
 * and phase rendering are exercised by running the app, the stance the rest
 * of the renderer takes for IO-backed Compose code.
 */
class AsyncImageTest {

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

    @Test
    fun `AsyncImage is registered`() {
        assertSame(AsyncImage, ActionUIRegistry.lookup("AsyncImage"))
    }

    @Test
    fun `initial value is the url property`() {
        val withURL = element(
            """{ "type": "AsyncImage", "id": 1, "properties": { "url": "https://example.com/a.png" } }"""
        )
        assertEquals("https://example.com/a.png", AsyncImage.initialValue(withURL))

        val withoutURL = element("""{ "type": "AsyncImage", "id": 1 }""")
        assertNull(AsyncImage.initialValue(withoutURL))
    }

    @Test
    fun `config defaults match Apple's builder`() {
        val config = resolveAsyncImageConfig(null, null)
        assertNull(config.url)
        assertEquals("photo", config.placeholder)
        assertTrue(config.resizable)
        assertFalse(config.contentModeFill)
    }

    @Test
    fun `config reads all properties`() {
        val logger = CapturingLogger()
        val config = resolveAsyncImageConfig(
            props(
                """{ "url": "https://example.com/a.png", "placeholder": "photo.circle",
                     "resizable": false, "contentMode": "fill" }"""
            ),
            logger
        )
        assertEquals("https://example.com/a.png", config.url)
        assertEquals("photo.circle", config.placeholder)
        assertFalse(config.resizable)
        assertTrue(config.contentModeFill)
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `any string url is accepted without validation warnings`() {
        // Apple allows even an unloadable url string; failure is a runtime
        // phase (placeholder), not a validation error.
        val logger = CapturingLogger()
        val config = resolveAsyncImageConfig(props("""{ "url": "invalid-url" }"""), logger)
        assertEquals("invalid-url", config.url)
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `invalid property types warn and fall back to defaults`() {
        val logger = CapturingLogger()
        val config = resolveAsyncImageConfig(
            props("""{ "url": 42, "placeholder": 7, "resizable": "yes", "contentMode": true }"""),
            logger
        )
        assertNull(config.url)
        assertEquals("photo", config.placeholder)
        assertTrue(config.resizable)
        assertFalse(config.contentModeFill)
        assertEquals(4, logger.warnings.size)
    }

    @Test
    fun `unknown contentMode warns and defaults to fit`() {
        val logger = CapturingLogger()
        val config = resolveAsyncImageConfig(props("""{ "contentMode": "stretch" }"""), logger)
        assertFalse(config.contentModeFill)
        assertEquals(1, logger.warnings.size)
    }

    // -----------------------------------------------------------------------
    // ByteBudgetLruCache (the in-memory image cache)
    // -----------------------------------------------------------------------

    /** A cache of strings where each entry costs its length in bytes. */
    private fun cache(budget: Long) = ByteBudgetLruCache<String>(budget) { it.length.toLong() }

    @Test
    fun `cache stores and retrieves under budget`() {
        val c = cache(budget = 10)
        c.put("a", "12345")
        assertEquals("12345", c.get("a"))
        assertEquals(1, c.size)
    }

    @Test
    fun `exceeding the budget evicts the least recently used entry`() {
        val c = cache(budget = 10)
        c.put("a", "12345")
        c.put("b", "12345")
        c.put("c", "1") // 11 bytes total: "a" is eldest, evicted
        assertNull(c.get("a"))
        assertEquals("12345", c.get("b"))
        assertEquals("1", c.get("c"))
    }

    @Test
    fun `a get refreshes recency so the other entry is evicted`() {
        val c = cache(budget = 10)
        c.put("a", "12345")
        c.put("b", "12345")
        c.get("a") // "b" becomes eldest
        c.put("c", "1")
        assertEquals("12345", c.get("a"))
        assertNull(c.get("b"))
    }

    @Test
    fun `replacing a key updates the byte accounting`() {
        val c = cache(budget = 10)
        c.put("a", "12345678")
        c.put("a", "12") // 8 bytes released, 2 used
        c.put("b", "12345678") // fits only if the replacement freed the budget
        assertEquals("12", c.get("a"))
        assertEquals("12345678", c.get("b"))
        assertEquals(2, c.size)
    }

    @Test
    fun `an entry larger than the whole budget is never cached`() {
        val c = cache(budget = 4)
        c.put("a", "12345")
        assertNull(c.get("a"))
        assertEquals(0, c.size)
    }
}
