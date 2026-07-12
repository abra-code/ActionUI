package com.abracode.actionui.addon.richtext

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
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
 * Plain-JVM tests for the `RichText` element: registration (the ContentProvider lifecycle does not run in unit
 * tests, so `register()` is called directly, as CachedImage's / map-osm's tests do) and the pure property
 * resolver. The Compose `BuildView` and the wrapped RichText renderer are covered by the RichText library's own
 * instrumented tests; this pins the ActionUI element contract.
 */
class RichTextViewTest {

    private fun props(json: String): JsonObject = Json.parseToJsonElement(json).jsonObject

    @Test fun registrationBindsRichTextType() {
        RichTextView.register()
        assertSame(RichTextView, ActionUIRegistry.lookup("RichText"))
        assertEquals(ActionUIValueType.STRING, RichTextView.valueType)
    }

    @Test fun initialValueSeedsFromMarkdownProperty() {
        val element = ActionUIElement(
            id = 90, type = "RichText",
            properties = props("""{ "markdown": "# Hello" }"""),
        )
        assertEquals("# Hello", RichTextView.initialValue(element))
    }

    @Test fun initialValueIsNullWithoutMarkdown() {
        val element = ActionUIElement(id = 90, type = "RichText", properties = props("""{ "syntaxHighlighting": true }"""))
        assertNull(RichTextView.initialValue(element))
    }

    @Test fun resolvesAllProperties() {
        val config = resolveRichTextConfig(
            props(
                """
                {
                  "markdown": "# Title\n\nBody with `code`.",
                  "baseFontSize": 15,
                  "syntaxHighlighting": false,
                  "widthBehavior": "hug"
                }
                """.trimIndent(),
            ),
            logger = null,
        )
        assertEquals("# Title\n\nBody with `code`.", config.markdown)
        assertEquals(15f, config.baseFontSize)
        assertEquals(false, config.syntaxHighlighting)
        assertTrue(config.widthBehaviorHug)
    }

    @Test fun defaultsWhenPropertiesOmitted() {
        val config = resolveRichTextConfig(props("""{ "markdown": "x" }"""), logger = null)
        assertEquals("x", config.markdown)
        assertNull(config.baseFontSize)
        assertNull(config.syntaxHighlighting)     // null => keep the theme default
        assertFalse(config.widthBehaviorHug)      // default fill
    }

    @Test fun emptyMarkdownWhenAbsent() {
        val config = resolveRichTextConfig(props("""{ "syntaxHighlighting": true }"""), logger = null)
        assertEquals("", config.markdown)
        assertEquals(true, config.syntaxHighlighting)
    }

    @Test fun invalidWidthBehaviorFallsBackToFill() {
        val config = resolveRichTextConfig(props("""{ "widthBehavior": "bogus" }"""), logger = null)
        assertFalse(config.widthBehaviorHug)
    }

    @Test fun rejectsWronglyTypedScalars() {
        // A non-string markdown, a string baseFontSize, and a string syntaxHighlighting are ignored
        // (warn-and-skip), not coerced.
        val config = resolveRichTextConfig(
            props("""{ "markdown": 42, "baseFontSize": "big", "syntaxHighlighting": "yes" }"""),
            null,
        )
        assertEquals("", config.markdown)
        assertNull(config.baseFontSize)
        assertNull(config.syntaxHighlighting)
    }
}
