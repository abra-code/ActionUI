package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIJson
import com.abracode.actionui.Common.subElements
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tests for the `contextMenu` / `contextMenuPreview` subview parsing. They are
 * top-level subview keys (not a property descriptor array), mirroring SwiftUI's
 * `.contextMenu(menuItems:preview:)`: `contextMenu` is the action-item array (real
 * Button / Divider elements) and `contextMenuPreview` is the optional single
 * arbitrary preview view. The Material DropdownMenu presentation itself
 * (`ContextMenuHelper.kt`) is exercised by running the app, the renderer's stance
 * for Compose code.
 */
class ContextMenuHelperTest {

    private fun decode(json: String) =
        ActionUIJson.decodeFromString(ActionUIElement.serializer(), json)

    @Test
    fun `contextMenu and contextMenuPreview decode as subview trees`() {
        val element = decode(
            """
            {
              "type": "Image",
              "properties": { "systemName": "photo" },
              "contextMenu": [
                { "id": 2, "type": "Button", "properties": { "title": "Rename", "systemImage": "pencil", "actionID": "ctx.rename" } },
                { "id": 3, "type": "Divider" },
                { "id": 4, "type": "Button", "properties": { "title": "Delete", "role": "destructive", "actionID": "ctx.delete" } }
              ],
              "contextMenuPreview": { "id": 5, "type": "Image", "properties": { "systemName": "photo", "imageScale": "large" } }
            }
            """
        )
        val items = element.contextMenu
        assertEquals(3, items?.size)
        assertEquals("Button", items?.get(0)?.type)
        assertEquals("Divider", items?.get(1)?.type)
        assertEquals("Image", element.contextMenuPreview?.type)
    }

    @Test
    fun `the preview is optional - a menu can be just an action list`() {
        val element = decode(
            """
            {
              "type": "Text", "properties": { "text": "Hi" },
              "contextMenu": [ { "id": 2, "type": "Button", "properties": { "title": "A", "actionID": "a" } } ]
            }
            """
        )
        assertEquals(1, element.contextMenu?.size)
        assertNull(element.contextMenuPreview)
    }

    @Test
    fun `absent contextMenu leaves both fields null`() {
        val element = decode("""{ "type": "Text", "properties": { "text": "Hi" } }""")
        assertNull(element.contextMenu)
        assertNull(element.contextMenuPreview)
    }

    @Test
    fun `menu items and the preview are traversed children`() {
        // They must join subElements() so their ids seed the window's view-model pool.
        val element = decode(
            """
            {
              "type": "Text", "properties": { "text": "Hi" },
              "contextMenu": [ { "id": 2, "type": "Button", "properties": { "title": "A", "actionID": "a" } } ],
              "contextMenuPreview": { "id": 3, "type": "Image", "properties": { "systemName": "star" } }
            }
            """
        )
        val childIds = element.subElements().map { it.id }
        assertTrue("menu item id is traversed", childIds.contains(2))
        assertTrue("preview id is traversed", childIds.contains(3))
    }
}
