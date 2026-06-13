package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tests for the pure parts of the ScrollViewReader machinery
 * (`Helpers/ScrollReaderHelper.kt`): property resolution (Apple-parity
 * warnings), the anchor offset math, and the id-to-row-index resolver the
 * lazy containers enroll with.
 */
class ScrollReaderHelperTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    // ---- resolveScrollTarget ----

    @Test
    fun `resolveScrollTarget absent key and null properties resolve to null without warning`() {
        val logger = CapturingLogger()
        assertNull(resolveScrollTarget(null, logger))
        assertNull(resolveScrollTarget(buildJsonObject { put("anchor", "top") }, logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `resolveScrollTarget reads an Int id`() {
        val logger = CapturingLogger()
        val props = buildJsonObject { put("scrollTo", 42) }
        assertEquals(42, resolveScrollTarget(props, logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `resolveScrollTarget warns and ignores non-Int values`() {
        val logger = CapturingLogger()
        assertNull(resolveScrollTarget(buildJsonObject { put("scrollTo", "5") }, logger))
        assertNull(resolveScrollTarget(buildJsonObject { put("scrollTo", 5.5) }, logger))
        assertNull(resolveScrollTarget(buildJsonObject { put("scrollTo", true) }, logger))
        assertNull(resolveScrollTarget(buildJsonObject { putJsonObject("scrollTo") {} }, logger))
        assertEquals(4, logger.warnings.size)
        assertTrue(logger.warnings.all { it.contains("must be an Int") })
    }

    // ---- resolveScrollAnchor ----

    @Test
    fun `resolveScrollAnchor resolves the vocabulary and defaults to center`() {
        val logger = CapturingLogger()
        assertEquals(ScrollAnchor.Center, resolveScrollAnchor(null, logger))
        assertEquals(ScrollAnchor.Top, resolveScrollAnchor(buildJsonObject { put("anchor", "top") }, logger))
        assertEquals(ScrollAnchor.Center, resolveScrollAnchor(buildJsonObject { put("anchor", "center") }, logger))
        assertEquals(ScrollAnchor.Bottom, resolveScrollAnchor(buildJsonObject { put("anchor", "bottom") }, logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `resolveScrollAnchor warns on an unknown string but ignores non-strings silently`() {
        val logger = CapturingLogger()
        // Unknown string: warn-and-center (the Apple validator's rule).
        assertEquals(ScrollAnchor.Center, resolveScrollAnchor(buildJsonObject { put("anchor", "leading") }, logger))
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("invalid"))
        // Non-string: silently center (Apple only validates string values).
        assertEquals(ScrollAnchor.Center, resolveScrollAnchor(buildJsonObject { put("anchor", 3) }, logger))
        assertEquals(1, logger.warnings.size)
    }

    // ---- anchorOffset ----

    @Test
    fun `anchorOffset places the item edge per anchor`() {
        assertEquals(0, anchorOffset(ScrollAnchor.Top, viewportExtent = 600, itemExtent = 100))
        assertEquals(250, anchorOffset(ScrollAnchor.Center, viewportExtent = 600, itemExtent = 100))
        assertEquals(500, anchorOffset(ScrollAnchor.Bottom, viewportExtent = 600, itemExtent = 100))
    }

    @Test
    fun `anchorOffset pins an item taller than the viewport to the top`() {
        assertEquals(0, anchorOffset(ScrollAnchor.Center, viewportExtent = 300, itemExtent = 400))
        assertEquals(0, anchorOffset(ScrollAnchor.Bottom, viewportExtent = 300, itemExtent = 400))
    }

    // ---- lazyChildIndexOf ----

    @Test
    fun `lazyChildIndexOf finds a direct child by id`() {
        val children = listOf(
            ActionUIElement(id = 10, type = "Text"),
            ActionUIElement(id = 11, type = "Text"),
            ActionUIElement(id = 12, type = "Text"),
        )
        assertEquals(1, lazyChildIndexOf(children, 11))
        assertEquals(2, lazyChildIndexOf(children, 12))
    }

    @Test
    fun `lazyChildIndexOf finds the row whose subtree contains the id`() {
        val children = listOf(
            ActionUIElement(id = 10, type = "Text"),
            // The target sits two levels down inside row 1 (HStack > VStack > Text 99)
            ActionUIElement(
                id = 11, type = "HStack",
                children = listOf(
                    ActionUIElement(
                        id = 20, type = "VStack",
                        children = listOf(ActionUIElement(id = 99, type = "Text")),
                    )
                ),
            ),
            // ... and a `content` named container is searched too.
            ActionUIElement(
                id = 12, type = "GroupBox",
                content = ActionUIElement(id = 88, type = "Text"),
            ),
        )
        assertEquals(1, lazyChildIndexOf(children, 99))
        assertEquals(2, lazyChildIndexOf(children, 88))
    }

    @Test
    fun `lazyChildIndexOf returns null when no row owns the id`() {
        val children = listOf(ActionUIElement(id = 10, type = "Text"))
        assertNull(lazyChildIndexOf(children, 77))
        assertNull(lazyChildIndexOf(emptyList(), 10))
    }

    // ---- properties carried as JsonPrimitive edge ----

    @Test
    fun `resolveScrollTarget accepts a large id and zero`() {
        // Zero and negative ids resolve (the dispatcher simply finds no
        // target for them); resolution itself only enforces the Int type.
        assertEquals(0, resolveScrollTarget(buildJsonObject { put("scrollTo", JsonPrimitive(0)) }))
        assertEquals(123456, resolveScrollTarget(buildJsonObject { put("scrollTo", 123456) }))
    }
}
