package com.abracode.actionui.Helpers

import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIJson
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.subElements
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the element-level popover plumbing in `PopoverHelper.kt`:
 * decoding the `popover` subview key, `popoverArrowEdge` parsing (Apple's
 * warn-and-default validation), the pure [popoverPosition] placement math, and
 * registration of popover content in the window pool. The [androidx.compose.ui.window.Popup]
 * presentation itself is exercised by running the app, the stance the rest of
 * the renderer takes for Compose code.
 */
class PopoverHelperTest {

    @After
    fun tearDown() {
        ActionUIModel.unregisterWindow("")
    }

    private fun decode(json: String): ActionUIElement =
        ActionUIJson.decodeFromString(ActionUIElement.serializer(), json)

    private class RecordingLogger : ActionUILogger {
        val messages = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            messages.add(message)
        }
    }

    private val document = """
        {
          "type": "VStack",
          "id": 1,
          "children": [
            {
              "type": "Button",
              "id": 2,
              "properties": { "title": "Show", "popoverActionID": "popover.shown" },
              "popover": {
                "type": "VStack",
                "id": 10,
                "children": [ { "type": "Toggle", "id": 11, "properties": { "isOn": true } } ]
              }
            },
            {
              "type": "Text",
              "id": 3,
              "properties": { "text": "tap me", "popoverArrowEdge": "trailing" },
              "popover": { "type": "Text", "id": 12, "properties": { "text": "anchored" } }
            }
          ]
        }
    """.trimIndent()

    // ===== decoding =====

    @Test
    fun `popover subview key decodes and is included in subElements`() {
        val root = decode(document)
        val button = root.children!![0]
        assertNotNull(button.popover)
        assertEquals("VStack", button.popover!!.type)
        assertTrue(button.subElements().contains(button.popover))
    }

    @Test
    fun `popover content registers in the window pool and the carrier state is addressable`() {
        ActionUIModel.loadDescription(decode(document), windowUUID = "")

        // The Toggle inside the popover has a ViewModel: the host value API reaches it.
        assertEquals(true, ActionUIModel.getElementValue(viewID = 11))

        // The carrier's presentation state is settable through the state API.
        ActionUIModel.setElementState(viewID = 2, key = POPOVER_VISIBLE_STATE_KEY, value = true)
        assertEquals(true, ActionUIModel.getElementState(viewID = 2, key = POPOVER_VISIBLE_STATE_KEY))
    }

    // ===== popoverArrowEdge parsing =====

    @Test
    fun `arrow edge parses the four SwiftUI edges and defaults to top`() {
        val root = decode(document)
        assertEquals(PopoverEdge.TOP, parsePopoverArrowEdge(root.children!![0].properties, null))
        assertEquals(PopoverEdge.TRAILING, parsePopoverArrowEdge(root.children!![1].properties, null))

        fun edgeOf(value: String): PopoverEdge = parsePopoverArrowEdge(
            decode("""{ "type": "Text", "properties": { "popoverArrowEdge": "$value" } }""").properties,
            null,
        )
        assertEquals(PopoverEdge.TOP, edgeOf("top"))
        assertEquals(PopoverEdge.BOTTOM, edgeOf("bottom"))
        assertEquals(PopoverEdge.LEADING, edgeOf("leading"))
        assertEquals(PopoverEdge.TRAILING, edgeOf("trailing"))
    }

    @Test
    fun `invalid arrow edge warns and falls back to top`() {
        val logger = RecordingLogger()
        val props = decode("""{ "type": "Text", "properties": { "popoverArrowEdge": "diagonal" } }""").properties
        assertEquals(PopoverEdge.TOP, parsePopoverArrowEdge(props, logger))
        assertTrue(logger.messages.single().contains("diagonal"))
    }

    // ===== placement math =====

    private val window = IntSize(1000, 2000)
    private val anchor = IntRect(400, 900, 600, 1000) // 200x100, centered-ish
    private val popup = IntSize(100, 50)

    private fun place(edge: PopoverEdge, direction: LayoutDirection = LayoutDirection.Ltr): IntOffset =
        popoverPosition(anchor, window, direction, popup, edge)

    @Test
    fun `top arrow places the popover above the anchor, centered`() {
        assertEquals(IntOffset(450, 850), place(PopoverEdge.TOP))
    }

    @Test
    fun `bottom arrow places the popover below the anchor, centered`() {
        assertEquals(IntOffset(450, 1000), place(PopoverEdge.BOTTOM))
    }

    @Test
    fun `leading arrow places the popover before the anchor, vertically centered`() {
        assertEquals(IntOffset(300, 925), place(PopoverEdge.LEADING))
    }

    @Test
    fun `trailing arrow places the popover after the anchor, vertically centered`() {
        assertEquals(IntOffset(600, 925), place(PopoverEdge.TRAILING))
    }

    @Test
    fun `leading and trailing swap under right-to-left layout`() {
        assertEquals(place(PopoverEdge.TRAILING), place(PopoverEdge.LEADING, LayoutDirection.Rtl))
        assertEquals(place(PopoverEdge.LEADING), place(PopoverEdge.TRAILING, LayoutDirection.Rtl))
    }

    @Test
    fun `placement clamps into the window`() {
        // Anchor at the top edge: a top-arrow popover would overflow above.
        val topAnchor = IntRect(400, 0, 600, 50)
        val clamped = popoverPosition(topAnchor, window, LayoutDirection.Ltr, popup, PopoverEdge.TOP)
        assertEquals(IntOffset(450, 0), clamped)

        // Anchor at the left edge: a leading-arrow popover would overflow left.
        val leftAnchor = IntRect(0, 900, 50, 1000)
        val pinned = popoverPosition(leftAnchor, window, LayoutDirection.Ltr, popup, PopoverEdge.LEADING)
        assertEquals(IntOffset(0, 925), pinned)
    }

    @Test
    fun `popup larger than the window pins to the origin`() {
        val huge = IntSize(3000, 4000)
        assertEquals(
            IntOffset(0, 0),
            popoverPosition(anchor, window, LayoutDirection.Ltr, huge, PopoverEdge.TOP),
        )
    }
}
