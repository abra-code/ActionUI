package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIJson
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Helpers.stringProperty
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

/**
 * Unit tests for [Color] - the SwiftUI `Color`-as-a-View element (registered as "Color").
 * The `@Composable` greedy block is exercised by the app; here we confirm registry resolution
 * and that the `color` string decodes off the element.
 */
class ColorTest {

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
}
