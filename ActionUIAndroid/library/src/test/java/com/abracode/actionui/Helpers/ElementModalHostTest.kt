package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIJson
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.subElements
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the element-level modal plumbing in `ElementModalHost.kt`:
 * decoding the `sheet` / `fullScreenCover` subview keys, the
 * [collectModalCarriers] document walk, and the registration of modal content
 * in the window's ViewModel pool (so the host state API can address it). The
 * `ModalBottomSheet` / `Dialog` presentation itself is exercised by running
 * the app, the stance the rest of the renderer takes for Compose code.
 */
class ElementModalHostTest {

    @After
    fun tearDown() {
        ActionUIModel.unregisterWindow("")
    }

    private fun decode(json: String): ActionUIElement =
        ActionUIJson.decodeFromString(ActionUIElement.serializer(), json)

    private val document = """
        {
          "type": "VStack",
          "id": 1,
          "children": [
            {
              "type": "Button",
              "id": 2,
              "properties": { "title": "Open", "sheetOnDismissActionID": "sheet.dismissed" },
              "sheet": {
                "type": "VStack",
                "id": 10,
                "children": [
                  { "type": "Toggle", "id": 11, "properties": { "isOn": true } },
                  {
                    "type": "Button",
                    "id": 12,
                    "fullScreenCover": { "type": "Text", "id": 13, "properties": { "text": "Nested" } }
                  }
                ]
              }
            },
            { "type": "Text", "id": 3, "properties": { "text": "plain" } }
          ]
        }
    """.trimIndent()

    @Test
    fun `sheet and fullScreenCover subview keys decode`() {
        val root = decode(document)
        val button = root.children!![0]
        assertNotNull(button.sheet)
        assertEquals("VStack", button.sheet!!.type)
        val nestedCarrier = button.sheet!!.children!![1]
        assertNotNull(nestedCarrier.fullScreenCover)
        assertEquals("Text", nestedCarrier.fullScreenCover!!.type)
    }

    @Test
    fun `subElements includes the modal containers`() {
        val root = decode(document)
        val button = root.children!![0]
        assertTrue(button.subElements().contains(button.sheet))
        val nestedCarrier = button.sheet!!.children!![1]
        assertTrue(nestedCarrier.subElements().contains(nestedCarrier.fullScreenCover))
    }

    @Test
    fun `collectModalCarriers finds carriers in tree order, including inside modal content`() {
        val root = decode(document)
        val carriers = collectModalCarriers(root)
        assertEquals(listOf(2, 12), carriers.map { it.id })
    }

    @Test
    fun `collectModalCarriers is empty for a document without modal subviews`() {
        val root = decode("""{ "type": "VStack", "children": [ { "type": "Text" } ] }""")
        assertTrue(collectModalCarriers(root).isEmpty())
    }

    @Test
    fun `modal content registers in the window pool and is host-addressable`() {
        ActionUIModel.loadDescription(decode(document), windowUUID = "")

        // The Toggle inside the sheet has a ViewModel: the host value API reaches it.
        assertEquals(true, ActionUIModel.getElementValue(viewID = 11))

        // The carrier's presentation state is settable through the state API
        // (Boolean round-trip; a new key is created with the given type).
        ActionUIModel.setElementState(viewID = 2, key = SHEET_VISIBLE_STATE_KEY, value = true)
        assertEquals(true, ActionUIModel.getElementState(viewID = 2, key = SHEET_VISIBLE_STATE_KEY))
    }
}
