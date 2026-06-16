package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.LoggerLevel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [ScrollView] - the first element to read the single-child
 * `content` container. Covers registry resolution and the pure `axis` resolution
 * ([resolveScrollAxis], with its warn-and-default path). The `@Composable`
 * scrolling Box is exercised by running the app, the stance the rest of the
 * renderer takes.
 */
class ScrollViewTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    @Test
    fun `registry resolves ScrollView and it carries no value`() {
        assertSame(ScrollView, ActionUIRegistry.lookup("ScrollView"))
        assertEquals(ActionUIValueType.NONE, ScrollView.valueType)
    }

    @Test
    fun `axis defaults to vertical when absent or named vertical`() {
        val logger = CapturingLogger()
        assertEquals(ScrollAxis.Vertical, resolveScrollAxis(null, logger))
        assertEquals(ScrollAxis.Vertical, resolveScrollAxis("vertical", logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `horizontal and both axes are honored`() {
        val logger = CapturingLogger()
        assertEquals(ScrollAxis.Horizontal, resolveScrollAxis("horizontal", logger))
        assertEquals(ScrollAxis.Both, resolveScrollAxis("both", logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `unknown axis warns and falls back to vertical`() {
        val logger = CapturingLogger()
        assertEquals(ScrollAxis.Vertical, resolveScrollAxis("diagonal", logger))
        assertFalse(logger.warnings.isEmpty())
        assertTrue(logger.warnings.any { it.contains("vertical") })
    }

    // ---- unbounded-axis guard (resolveAppliedScroll) ----

    @Test
    fun `bounded vertical scroll is applied`() {
        assertEquals(
            ScrollAxesApplied(vertical = true, horizontal = false),
            resolveAppliedScroll(ScrollAxis.Vertical, boundedHeight = true, boundedWidth = false),
        )
    }

    @Test
    fun `unbounded vertical scroll is dropped`() {
        // The crash case: a vertical ScrollView nested in another vertical scroll
        // (infinite incoming height) - drop the axis instead of crashing.
        assertEquals(
            ScrollAxesApplied(vertical = false, horizontal = false),
            resolveAppliedScroll(ScrollAxis.Vertical, boundedHeight = false, boundedWidth = true),
        )
    }

    @Test
    fun `unbounded horizontal scroll is dropped`() {
        assertEquals(
            ScrollAxesApplied(vertical = false, horizontal = false),
            resolveAppliedScroll(ScrollAxis.Horizontal, boundedHeight = true, boundedWidth = false),
        )
    }

    @Test
    fun `both-axis scroll keeps only the bounded axes`() {
        // Height unbounded, width bounded -> vertical drops, horizontal stays.
        assertEquals(
            ScrollAxesApplied(vertical = false, horizontal = true),
            resolveAppliedScroll(ScrollAxis.Both, boundedHeight = false, boundedWidth = true),
        )
        assertEquals(
            ScrollAxesApplied(vertical = true, horizontal = true),
            resolveAppliedScroll(ScrollAxis.Both, boundedHeight = true, boundedWidth = true),
        )
    }

    @Test
    fun `the cross axis is never scrolled regardless of bounds`() {
        // A vertical ScrollView never scrolls horizontally even with bounded width.
        assertFalse(resolveAppliedScroll(ScrollAxis.Vertical, boundedHeight = true, boundedWidth = true).horizontal)
        assertFalse(resolveAppliedScroll(ScrollAxis.Horizontal, boundedHeight = true, boundedWidth = true).vertical)
    }
}
