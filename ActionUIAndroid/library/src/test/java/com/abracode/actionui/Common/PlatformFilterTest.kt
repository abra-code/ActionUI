package com.abracode.actionui.Common

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlatformFilterTest {

    /**
     * Test logger that records messages by level. Mirrors the Swift
     * `CapturingLogger` helper in `PlatformFilterTests.swift`.
     */
    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        val infos    = mutableListOf<String>()
        var errors   = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            when (level) {
                LoggerLevel.warning                                            -> warnings.add(message)
                LoggerLevel.info, LoggerLevel.debug, LoggerLevel.verbose        -> infos.add(message)
                LoggerLevel.error                                              -> errors.add(message)
            }
        }
    }

    // Silent filters — most tests don't care about warnings.
    // Tests that assert warnings use a CapturingLogger constructed inline.
    private val android = PlatformFilter(setOf("android"))
    private val ios     = PlatformFilter(setOf("ios", "apple"))
    private val macos   = PlatformFilter(setOf("macos", "apple"))

    private fun parse(json: String): JsonElement = Json.parseToJsonElement(json)

    private fun filterJson(filter: PlatformFilter, json: String): String =
        Json.encodeToString(JsonElement.serializer(), filter.filter(parse(json)))

    @Test
    fun `unsuffixed keys pass through unchanged`() {
        val input = """{"type":"Text","properties":{"text":"hello"}}"""
        assertEquals(input, filterJson(android, input))
    }

    @Test
    fun `matching suffix is renamed to base`() {
        val input = """{"tint:android":"primary"}"""
        assertEquals("""{"tint":"primary"}""", filterJson(android, input))
    }

    @Test
    fun `non-matching suffix is dropped`() {
        val input = """{"tint:ios":"blue"}"""
        assertEquals("""{}""", filterJson(android, input))
    }

    @Test
    fun `unsuffixed default is overridden by matching suffix`() {
        val input = """{"tint":"gray","tint:android":"primary"}"""
        assertEquals("""{"tint":"primary"}""", filterJson(android, input))
    }

    @Test
    fun `unsuffixed default survives when no suffix matches`() {
        val input = """{"tint":"gray","tint:ios":"blue"}"""
        assertEquals("""{"tint":"gray"}""", filterJson(android, input))
    }

    @Test
    fun `specific platform wins over apple umbrella on iOS`() {
        val input = """{"tint:apple":"systemGray","tint:ios":"systemBlue"}"""
        assertEquals("""{"tint":"systemBlue"}""", filterJson(ios, input))
    }

    @Test
    fun `apple umbrella matches on macOS`() {
        val input = """{"tint:apple":"systemGray","tint:android":"primary"}"""
        assertEquals("""{"tint":"systemGray"}""", filterJson(macos, input))
    }

    @Test
    fun `apple umbrella does not match on Android`() {
        val input = """{"tint:apple":"systemGray","tint:android":"primary"}"""
        assertEquals("""{"tint":"primary"}""", filterJson(android, input))
    }

    @Test
    fun `type-level platform switch picks the matching variant`() {
        val input = """{"type:ios":"Button","type:android":"FilledTonalButton"}"""
        assertEquals("""{"type":"FilledTonalButton"}""", filterJson(android, input))
    }

    @Test
    fun `element with only non-matching type variants ends up with no type`() {
        val input = """{"type:ios":"Picker","properties":{"title":"x"}}"""
        val result = filterJson(android, input)
        assertFalse("Expected no type key", result.contains("\"type\""))
        assertTrue("Expected properties to survive", result.contains("\"properties\""))
    }

    @Test
    fun `unknown suffix is dropped with a warning (forward-compat)`() {
        // "format" is not in ALL_PLATFORMS; treated as if it targets an unknown platform.
        val logger = CapturingLogger()
        val filter = PlatformFilter(setOf("android"), logger)
        val result = filter.filter(parse("""{"time:format":"HH:mm"}"""))
        assertEquals("""{}""", Json.encodeToString(JsonElement.serializer(), result))
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("Unknown platform suffix"))
        assertTrue(logger.warnings[0].contains("'time:format'"))
        assertTrue(logger.warnings[0].contains("suffix='format'"))
    }

    @Test
    fun `typo in platform token logs warning and drops key`() {
        // Capital 'A' — common typo. Should not silently pass through.
        val logger = CapturingLogger()
        val filter = PlatformFilter(setOf("android"), logger)
        val result = filter.filter(parse("""{"tint:Android":"primary","tint":"gray"}"""))
        // The typo'd variant is dropped; the unsuffixed default survives.
        assertEquals("""{"tint":"gray"}""", Json.encodeToString(JsonElement.serializer(), result))
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("'tint:Android'"))
    }

    @Test
    fun `filter recurses into nested objects`() {
        val input = """{"properties":{"tint:android":"primary","tint:ios":"blue"}}"""
        assertEquals("""{"properties":{"tint":"primary"}}""", filterJson(android, input))
    }

    @Test
    fun `filter recurses into arrays`() {
        val input = """{"children":[{"type":"Text"},{"type:ios":"Button"}]}"""
        // Both array elements survive (filter does not drop typeless objects);
        // the second one ends up with no type, which the renderer skips.
        val expected = """{"children":[{"type":"Text"},{}]}"""
        assertEquals(expected, filterJson(android, input))
    }

    @Test
    fun `multiple suffixed variants resolve to highest specificity match`() {
        // On iOS, both ios and apple are in active set; ios should win (rank 2 vs 1).
        val input = """{"x:apple":"umbrella","x:ios":"specific"}"""
        assertEquals("""{"x":"specific"}""", filterJson(ios, input))
    }

    @Test
    fun `tvos token resolves on the apple umbrella when only apple variant exists`() {
        val tvos = PlatformFilter(setOf("tvos", "apple"))
        val input = """{"label:apple":"AppleLabel"}"""
        assertEquals("""{"label":"AppleLabel"}""", filterJson(tvos, input))
    }

    @Test
    fun `empty string after colon is treated as unknown suffix and dropped with warning`() {
        // "x:" — empty after colon is not a known platform token.
        val logger = CapturingLogger()
        val filter = PlatformFilter(setOf("android"), logger)
        val result = filter.filter(parse("""{"x:":"value"}"""))
        assertEquals("""{}""", Json.encodeToString(JsonElement.serializer(), result))
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("suffix=''"))
    }

    @Test
    fun `known but inactive platform does NOT produce a warning`() {
        // ios is a known platform but not in Android's active set —
        // it's a valid drop, not a typo/future-platform case.
        val logger = CapturingLogger()
        val filter = PlatformFilter(setOf("android"), logger)
        filter.filter(parse("""{"tint:ios":"blue"}"""))
        assertTrue("Expected no warnings, got: ${logger.warnings}", logger.warnings.isEmpty())
    }

    @Test
    fun `multiple unknown suffixes each produce one warning`() {
        val logger = CapturingLogger()
        val filter = PlatformFilter(setOf("android"), logger)
        filter.filter(parse("""{"a:foo":1,"b:bar":2,"c:android":3}"""))
        assertEquals(2, logger.warnings.size)
    }

    @Test
    fun `primitives pass through unchanged`() {
        val input = """[1,2,3,"hello",true,null]"""
        assertEquals(input, filterJson(android, input))
    }

    @Test
    fun `nested platform suffixes deep in the tree are resolved independently`() {
        val input = """
            {
              "type:android": "HStack",
              "type:ios": "VStack",
              "children": [
                {
                  "type": "Text",
                  "properties": {
                    "text:android": "A",
                    "text:ios": "I"
                  }
                }
              ]
            }
        """.trimIndent()
        val expected = """{"type":"HStack","children":[{"type":"Text","properties":{"text":"A"}}]}"""
        assertEquals(expected, filterJson(android, input))
    }

    @Test
    fun `Android companion uses android active set only`() {
        val input = """{"tint:apple":"systemGray","tint:android":"primary"}"""
        assertEquals("""{"tint":"primary"}""", filterJson(PlatformFilter.Android, input))
    }

    @Test
    fun `withLogger returns copy with same active set and wired logger`() {
        val logger = CapturingLogger()
        val copy = PlatformFilter.Android.withLogger(logger)
        assertEquals(PlatformFilter.Android.active, copy.active)
        // Trigger a warning so we verify the logger is actually wired in.
        copy.filter(parse("""{"x:bogus":1}"""))
        assertEquals(1, logger.warnings.size)
    }

    @Test
    fun `null logger silences unknown-suffix warnings`() {
        // No logger means no NPE; key still gets dropped.
        val filter = PlatformFilter(setOf("android"), logger = null)
        val result = filter.filter(parse("""{"x:bogus":1,"tint:android":"primary"}"""))
        assertEquals("""{"tint":"primary"}""", Json.encodeToString(JsonElement.serializer(), result))
    }

    @Test
    fun `all platforms set covers documented tokens`() {
        // Sanity check: the canonical list includes every platform token referenced
        // in the plan §Design notes.
        val expected = setOf(
            "ios", "macos", "tvos", "watchos", "visionos", "apple",
            "android", "androidtv", "wear",
            "desktop", "web"
        )
        assertEquals(expected, PlatformFilter.ALL_PLATFORMS)
    }
}
