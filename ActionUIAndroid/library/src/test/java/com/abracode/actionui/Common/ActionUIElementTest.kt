package com.abracode.actionui.Common

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the [ActionUIElement] named-container decode: the array
 * container `children` and the single-child container `content` both decode from
 * their top-level JSON keys, and [subElements] flattens every container for tree
 * traversal. Uses the same lenient [Json] config as `ActionUI.Render`.
 */
class ActionUIElementTest {

    private val json = Json { ignoreUnknownKeys = true }

    private fun decode(text: String): ActionUIElement =
        json.decodeFromString(ActionUIElement.serializer(), text)

    @Test
    fun `decodes a single-child content container as one element`() {
        val element = decode(
            """
            { "type": "ScrollView", "id": 1,
              "content": { "type": "Text", "id": 2, "properties": { "text": "hi" } } }
            """.trimIndent()
        )

        assertEquals("ScrollView", element.type)
        assertNull(element.children)
        val content = element.content
        assertEquals("Text", content?.type)
        assertEquals(2, content?.id)
    }

    @Test
    fun `decodes the children array container`() {
        val element = decode(
            """
            { "type": "VStack",
              "children": [ { "type": "Text" }, { "type": "Text" } ] }
            """.trimIndent()
        )

        assertNull(element.content)
        assertEquals(2, element.children?.size)
    }

    @Test
    fun `content nests recursively`() {
        val element = decode(
            """
            { "type": "ScrollView",
              "content": { "type": "VStack",
                "children": [ { "type": "Text", "id": 5 } ] } }
            """.trimIndent()
        )

        assertEquals("VStack", element.content?.type)
        assertEquals(5, element.content?.children?.first()?.id)
    }

    @Test
    fun `unknown top-level keys are ignored`() {
        // ignoreUnknownKeys mirrors ActionUI.Render: a container key not yet
        // modeled on Android (e.g. Swift's `destination`) is dropped, not fatal.
        val element = decode(
            """
            { "type": "NavigationLink",
              "destination": { "type": "Text" },
              "content": { "type": "Text", "id": 3 } }
            """.trimIndent()
        )

        assertEquals(3, element.content?.id)
    }

    @Test
    fun `subElements flattens children then content`() {
        val element = ActionUIElement(
            id = 1, type = "Custom",
            children = listOf(
                ActionUIElement(id = 2, type = "Text"),
                ActionUIElement(id = 3, type = "Text"),
            ),
            content = ActionUIElement(id = 4, type = "Button"),
        )

        val ids = element.subElements().map { it.id }
        assertEquals(listOf(2, 3, 4), ids)
    }

    @Test
    fun `subElements is empty for a leaf element`() {
        assertTrue(ActionUIElement(id = 1, type = "Text").subElements().isEmpty())
    }

    @Test
    fun `decodes the single-child template container`() {
        val element = decode(
            """
            { "type": "List", "id": 1,
              "template": { "type": "Text", "id": 9, "properties": { "text": "${'$'}1" } } }
            """.trimIndent()
        )

        assertEquals("List", element.type)
        assertNull(element.children)
        assertEquals("Text", element.template?.type)
        assertEquals(9, element.template?.id)
    }

    @Test
    fun `template is excluded from subElements`() {
        // A template is instanced per row, not registered once in the window pool,
        // so tree traversal (subElements) must skip it - even when children exist.
        val element = ActionUIElement(
            id = 1, type = "List",
            children = listOf(ActionUIElement(id = 2, type = "Text")),
            template = ActionUIElement(id = 3, type = "Text"),
        )

        assertEquals(listOf(2), element.subElements().map { it.id })
    }
}
