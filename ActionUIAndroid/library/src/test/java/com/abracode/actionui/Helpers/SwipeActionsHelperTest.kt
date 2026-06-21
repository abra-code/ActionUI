package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIJson
import com.abracode.actionui.Common.subElements
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tests for the `swipeActions` subview parsing - a top-level subview key (not a property
 * descriptor array), mirroring SwiftUI's `.swipeActions(edge:allowsFullSwipe:)`: an array
 * of real `Button` elements, each carrying its own title / systemImage / role / tint /
 * actionID plus the swipe-specific `edge` and `allowsFullSwipe`. The swipe-to-reveal
 * presentation itself (`SwipeActionsHelper.kt`) is exercised by running the app, the
 * renderer's stance for Compose code.
 */
class SwipeActionsHelperTest {

    private fun decode(json: String) =
        ActionUIJson.decodeFromString(ActionUIElement.serializer(), json)

    @Test
    fun `swipeActions decode as a subview array of Buttons`() {
        val element = decode(
            """
            {
              "type": "Text",
              "properties": { "text": "Inbox row" },
              "swipeActions": [
                { "id": 2, "type": "Button", "properties": { "title": "Flag", "systemImage": "flag", "tint": "orange", "edge": "leading", "actionID": "row.flag" } },
                { "id": 3, "type": "Button", "properties": { "title": "Delete", "systemImage": "trash", "role": "destructive", "edge": "trailing", "allowsFullSwipe": false, "actionID": "row.delete" } }
              ]
            }
            """
        )
        val actions = element.swipeActions
        assertEquals(2, actions?.size)
        assertEquals("Button", actions?.get(0)?.type)
        assertEquals("leading", actions?.get(0)?.properties?.stringProperty("edge"))
        assertEquals("orange", actions?.get(0)?.properties?.stringProperty("tint"))
        assertEquals("destructive", actions?.get(1)?.properties?.stringProperty("role"))
        assertEquals(false, actions?.get(1)?.properties?.booleanProperty("allowsFullSwipe"))
    }

    @Test
    fun `absent swipeActions leaves the field null`() {
        val element = decode("""{ "type": "Text", "properties": { "text": "Hi" } }""")
        assertNull(element.swipeActions)
    }

    @Test
    fun `swipe action buttons are traversed children`() {
        // They must join subElements() so their ids seed the window's view-model pool
        // (each Button needs its actionID wiring).
        val element = decode(
            """
            {
              "type": "Text", "properties": { "text": "Row" },
              "swipeActions": [ { "id": 2, "type": "Button", "properties": { "title": "Delete", "actionID": "del" } } ]
            }
            """
        )
        val childIds = element.subElements().map { it.id }
        assertTrue("swipe action button id is traversed", childIds.contains(2))
    }
}
