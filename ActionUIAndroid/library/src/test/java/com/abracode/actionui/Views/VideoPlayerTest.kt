package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIJson
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the pure half of `VideoPlayer.kt` - property validation
 * ([resolveVideoPlayerConfig]) and the value-bridge seeding. The playback
 * itself (the platform VideoView) is exercised by running the app, the
 * stance the rest of the renderer takes for classic-View interop code.
 */
class VideoPlayerTest {

    private class CapturingLogger : ActionUILogger {
        val messages = mutableListOf<Pair<String, LoggerLevel>>()
        override fun log(message: String, level: LoggerLevel) {
            messages.add(message to level)
        }
    }

    private fun props(json: String): JsonObject =
        Json.parseToJsonElement(json).jsonObject

    private fun element(json: String): ActionUIElement =
        ActionUIJson.decodeFromString(ActionUIElement.serializer(), json)

    @Test
    fun `VideoPlayer is registered with the String value bridge`() {
        assertSame(VideoPlayer, ActionUIRegistry.lookup("VideoPlayer"))
        assertEquals(ActionUIValueType.STRING, VideoPlayer.valueType)
    }

    @Test
    fun `initial value is the url property, empty when absent`() {
        val withURL = element(
            """{ "type": "VideoPlayer", "id": 1, "properties": { "url": "https://example.com/v.mp4" } }"""
        )
        assertEquals("https://example.com/v.mp4", VideoPlayer.initialValue(withURL))

        // Apple seeds "" (a non-optional String value), not nil.
        val withoutURL = element("""{ "type": "VideoPlayer", "id": 1 }""")
        assertEquals("", VideoPlayer.initialValue(withoutURL))
    }

    @Test
    fun `config defaults match Apple's builder`() {
        val config = resolveVideoPlayerConfig(null, null)
        assertNull(config.url)
        assertNull(config.autoplay)
    }

    @Test
    fun `valid properties are read through`() {
        val config = resolveVideoPlayerConfig(
            props("""{ "url": "https://example.com/v.mp4", "autoplay": true }"""),
            null,
        )
        assertEquals("https://example.com/v.mp4", config.url)
        assertEquals(true, config.autoplay)
    }

    @Test
    fun `invalid types warn with Apple's messages and are dropped`() {
        val logger = CapturingLogger()
        val config = resolveVideoPlayerConfig(
            props("""{ "url": 42, "autoplay": "yes" }"""),
            logger,
        )
        assertNull(config.url)
        assertNull(config.autoplay)
        assertEquals(2, logger.messages.size)
        // url is an error on the Apple side, autoplay a warning.
        assertEquals(
            "VideoPlayer url must be a String; ignoring" to LoggerLevel.error,
            logger.messages[0],
        )
        assertEquals(
            "Invalid type for VideoPlayer autoplay: expected Bool, ignoring" to LoggerLevel.warning,
            logger.messages[1],
        )
    }

    @Test
    fun `autoplay false is preserved, not conflated with absent`() {
        val config = resolveVideoPlayerConfig(props("""{ "autoplay": false }"""), null)
        assertEquals(false, config.autoplay)
        assertTrue(resolveVideoPlayerConfig(props("""{ }"""), null).autoplay == null)
    }
}
