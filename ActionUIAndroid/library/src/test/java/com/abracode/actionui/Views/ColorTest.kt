package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIJson
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ConsoleLogger
import com.abracode.actionui.Helpers.stringProperty
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

/**
 * Unit tests for [Color] - the SwiftUI `Color`-as-a-View element (registered as "Color").
 * The `@Composable` greedy block is exercised by the app; here we confirm registry resolution,
 * that the `color` string decodes off the element, and the [ActionUIValueType.COLOR] value
 * bridge (Apple's `Color?`): a runtime override wins over the `color` property.
 */
class ColorTest {

    @After
    fun tearDown() {
        ActionUIModel.unregisterWindow("")
        ActionUIModel.logger = ConsoleLogger()
    }

    @Test
    fun `Color resolves from the registry as the element type Color`() {
        assertSame(Color, ActionUIRegistry.lookup("Color"))
    }

    @Test
    fun `color string decodes off the element`() {
        val element = ActionUIJson.decodeFromString(
            ActionUIElement.serializer(),
            """{ "type": "Color", "properties": { "color": "blue.opacity(0.3)" } }""",
        )
        assertEquals("Color", element.type)
        assertEquals("blue.opacity(0.3)", element.properties?.stringProperty("color"))
    }

    @Test
    fun `Color declares a Color value with a null initial seed`() {
        assertEquals(ActionUIValueType.COLOR, Color.valueType)
        // Apple's initialValue returns model.value (null until a host sets it).
        assertNull(Color.initialValue(ActionUIElement(id = 1, type = "Color",
            properties = buildJsonObject { put("color", "blue") })))
    }

    @Test
    fun `host can override the color through the string bridge and serialize back`() {
        ActionUIModel.loadDescription(
            ActionUIElement(id = 1, type = "Color",
                properties = buildJsonObject { put("color", "blue") }),
            windowUUID = "",
        )
        // No seeded value: the `color` property is used until a host writes.
        assertNull(ActionUIModel.getElementValue(viewID = 1))

        ActionUIModel.setElementValueFromString(viewID = 1, value = "red")
        assertEquals("#FF0000", ActionUIModel.getElementValueAsString(viewID = 1))
    }
}
