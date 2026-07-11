package com.abracode.actionui.addon.cachedimage

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
 * Plain-JVM tests for the `CachedImage` element: registration (the ContentProvider lifecycle does not run in
 * unit tests, so `register()` is called directly, as `map-osm`'s test does) and the pure property resolver.
 */
class CachedImageViewTest {

    private fun props(json: String): JsonObject = Json.parseToJsonElement(json).jsonObject

    @Test fun registrationBindsCachedImageType() {
        CachedImageView.register()
        assertSame(CachedImageView, ActionUIRegistry.lookup("CachedImage"))
        assertEquals(ActionUIValueType.STRING, CachedImageView.valueType)
    }

    @Test fun initialValueSeedsFromUrlProperty() {
        val element = ActionUIElement(
            id = 1, type = "CachedImage",
            properties = props("""{ "url": "https://example.com/a.png" }"""),
        )
        assertEquals("https://example.com/a.png", CachedImageView.initialValue(element))
    }

    @Test fun initialValueIsNullWithoutUrl() {
        val element = ActionUIElement(id = 1, type = "CachedImage", properties = props("""{ "contentMode": "fit" }"""))
        assertNull(CachedImageView.initialValue(element))
    }

    @Test fun resolvesAllProperties() {
        val config = resolveCachedImageConfig(
            props(
                """
                {
                  "url": "https://example.com/photo.jpg",
                  "intrinsicSize": { "width": 1024, "height": 768 },
                  "contentMode": "fit",
                  "maxPixelWidth": 840,
                  "cornerRadius": 12
                }
                """.trimIndent(),
            ),
            logger = null,
        )
        assertEquals("https://example.com/photo.jpg", config.url)
        assertEquals(1024f, config.intrinsicSize?.width)
        assertEquals(768f, config.intrinsicSize?.height)
        assertFalse(config.contentModeFill)      // "fit"
        assertEquals(840f, config.maxPixelWidth)
        assertEquals(12f, config.cornerRadius)
    }

    @Test fun defaultsWhenPropertiesOmitted() {
        val config = resolveCachedImageConfig(props("""{ "url": "x" }"""), logger = null)
        assertNull(config.intrinsicSize)
        assertTrue(config.contentModeFill)       // default fill
        assertNull(config.maxPixelWidth)
        assertEquals(0f, config.cornerRadius)
    }

    @Test fun invalidContentModeFallsBackToFill() {
        val config = resolveCachedImageConfig(props("""{ "contentMode": "bogus" }"""), logger = null)
        assertTrue(config.contentModeFill)
    }

    @Test fun intrinsicSizeRejectsNonPositiveOrMalformed() {
        assertNull(resolveCachedImageConfig(props("""{ "intrinsicSize": { "width": 0, "height": 10 } }"""), null).intrinsicSize)
        assertNull(resolveCachedImageConfig(props("""{ "intrinsicSize": { "width": 10 } }"""), null).intrinsicSize)
        assertNull(resolveCachedImageConfig(props("""{ "intrinsicSize": "nope" }"""), null).intrinsicSize)
    }

    @Test fun rejectsWronglyTypedScalars() {
        // A non-string url and a string maxPixelWidth are ignored (warn-and-skip), not coerced.
        val config = resolveCachedImageConfig(props("""{ "url": 42, "maxPixelWidth": "wide" }"""), null)
        assertNull(config.url)
        assertNull(config.maxPixelWidth)
    }
}
