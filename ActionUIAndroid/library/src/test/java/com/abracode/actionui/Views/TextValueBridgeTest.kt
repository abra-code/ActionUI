package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ConsoleLogger
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

/**
 * Unit tests for [Text]'s value bridge - the [ActionUIValueType.STRING] parity
 * with SwiftUI (`ActionUI/Views/Text.swift`): the displayed content is the
 * element's value, seeded from `markdown`/`text` and host-settable at runtime.
 * The `@Composable` text run is exercised by the app.
 */
class TextValueBridgeTest {

    @After
    fun tearDown() {
        ActionUIModel.unregisterWindow("")
        ActionUIModel.logger = ConsoleLogger()
    }

    @Test
    fun `Text resolves and declares a String value`() {
        assertSame(Text, ActionUIRegistry.lookup("Text"))
        assertEquals(ActionUIValueType.STRING, Text.valueType)
    }

    @Test
    fun `initial value is the text property defaulting to empty`() {
        assertEquals(
            "Hello",
            Text.initialValue(ActionUIElement(id = 1, type = "Text",
                properties = buildJsonObject { put("text", "Hello") })),
        )
        assertEquals("", Text.initialValue(ActionUIElement(id = 1, type = "Text")))
    }

    @Test
    fun `markdown takes precedence over text as the seed (Apple order)`() {
        assertEquals(
            "**Bold**",
            Text.initialValue(ActionUIElement(id = 1, type = "Text",
                properties = buildJsonObject { put("markdown", "**Bold**"); put("text", "plain") })),
        )
    }

    @Test
    fun `host can read and update the displayed text`() {
        ActionUIModel.loadDescription(
            ActionUIElement(id = 1, type = "Text",
                properties = buildJsonObject { put("text", "Hello") }),
            windowUUID = "",
        )
        assertEquals("Hello", ActionUIModel.getElementValue(viewID = 1))

        ActionUIModel.setElementValueFromString(viewID = 1, value = "Goodbye")
        assertEquals("Goodbye", ActionUIModel.getElementValue(viewID = 1))
        assertEquals("Goodbye", ActionUIModel.getElementValueAsString(viewID = 1))
    }
}
