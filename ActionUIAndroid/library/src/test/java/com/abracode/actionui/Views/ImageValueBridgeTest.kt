package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ConsoleLogger
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [Image]'s value bridge - the [ActionUIValueType.STRING] parity
 * with SwiftUI (Apple's `String?`, `ActionUI/Views/Image.swift`): a runtime
 * value overrides the static source using the "mixed" interpretation
 * ([mixedImageSourceProperties]); [Image.initialValue] returns null (use the
 * static properties). The `@Composable` render is exercised by the app.
 */
class ImageValueBridgeTest {

    @After
    fun tearDown() {
        ActionUIModel.unregisterWindow("")
        ActionUIModel.logger = ConsoleLogger()
    }

    @Test
    fun `Image resolves and declares a String value with a null initial seed`() {
        assertSame(Image, ActionUIRegistry.lookup("Image"))
        assertEquals(ActionUIValueType.STRING, Image.valueType)
        // Apple's initialValue returns model.value (null until a host sets it).
        assertNull(Image.initialValue(ActionUIElement(id = 1, type = "Image",
            properties = buildJsonObject { put("systemName", "star.fill") })))
    }

    @Test
    fun `mixed interpretation routes a path-like string to filePath`() {
        val key = mixedImageSourceProperties("/tmp/photo.png")
        assertEquals("/tmp/photo.png", key["filePath"]?.jsonPrimitive?.contentOrNull)
        assertNull(key["systemName"])
        assertNull(key["resourceName"])
    }

    @Test
    fun `mixed interpretation routes an image-extension name to resourceName`() {
        val key = mixedImageSourceProperties("logo.png")
        assertEquals("logo.png", key["resourceName"]?.jsonPrimitive?.contentOrNull)
        assertNull(key["filePath"])
        assertNull(key["systemName"])
    }

    @Test
    fun `mixed interpretation routes a bare name to systemName`() {
        val key = mixedImageSourceProperties("star.fill")
        assertEquals("star.fill", key["systemName"]?.jsonPrimitive?.contentOrNull)
        assertNull(key["filePath"])
        assertNull(key["resourceName"])
    }

    @Test
    fun `host can set the source value through the string bridge`() {
        ActionUIModel.loadDescription(
            ActionUIElement(id = 1, type = "Image",
                properties = buildJsonObject { put("systemName", "star.fill") }),
            windowUUID = "",
        )
        // No seeded value: the static property is used until a host writes.
        assertNull(ActionUIModel.getElementValue(viewID = 1))

        ActionUIModel.setElementValueFromString(viewID = 1, value = "heart.fill")
        assertEquals("heart.fill", ActionUIModel.getElementValue(viewID = 1))
        assertTrue(mixedImageSourceProperties("heart.fill").containsKey("systemName"))
    }
}
