package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIJson
import com.abracode.actionui.Common.subElements
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tests for the safe-area subview/property parsing - `ignoresSafeArea` (a property: Bool or an
 * object) and `safeAreaInset` (a single subview placed at an edge). The Compose rendering
 * (consumeWindowInsets / windowInsetsPadding, SafeAreaHelper.kt) is exercised by running the app.
 */
class SafeAreaTest {

    private fun decode(json: String) =
        ActionUIJson.decodeFromString(ActionUIElement.serializer(), json)

    @Test
    fun `safeAreaInset decodes as a single subview with its edge`() {
        val element = decode(
            """
            {
              "type": "ScrollView", "properties": {},
              "content": { "id": 9, "type": "Text", "properties": { "text": "body" } },
              "safeAreaInset": {
                "id": 2, "type": "HStack", "properties": { "safeAreaEdge": "bottom" },
                "children": [ { "id": 3, "type": "Text", "properties": { "text": "Bar" } } ]
              }
            }
            """
        )
        val inset = element.safeAreaInset
        assertEquals("HStack", inset?.type)
        assertEquals("bottom", inset?.properties?.stringProperty("safeAreaEdge"))
    }

    @Test
    fun `the safeAreaInset view is a traversed child`() {
        // Its id (and descendants) must seed the window's view-model pool.
        val element = decode(
            """
            {
              "type": "ScrollView", "properties": {},
              "safeAreaInset": { "id": 2, "type": "Text", "properties": { "text": "Bar" } }
            }
            """
        )
        assertTrue(element.subElements().map { it.id }.contains(2))
    }

    @Test
    fun `absent safeAreaInset is null`() {
        val element = decode("""{ "type": "ScrollView", "properties": {} }""")
        assertNull(element.safeAreaInset)
    }

    @Test
    fun `ignoresSafeArea decodes as a boolean property`() {
        val element = decode("""{ "type": "Color", "properties": { "color": "teal", "ignoresSafeArea": true } }""")
        assertEquals(true, element.properties?.booleanProperty("ignoresSafeArea"))
    }
}
