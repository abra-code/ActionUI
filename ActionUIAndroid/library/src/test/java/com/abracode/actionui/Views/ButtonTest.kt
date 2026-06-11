package com.abracode.actionui.Views

import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Helpers.ActionUIControlSize
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [Button]'s non-Composable surface: registry resolution and the
 * `controlSize` metrics ladder ([controlSizeMetrics]). The Material rendering
 * itself (filled/tonal/text variants, `enabled`) is exercised by running the
 * app, the stance the rest of the renderer takes for Compose code.
 */
class ButtonTest {

    @Test
    fun `registry resolves Button to the builder`() {
        assertEquals(Button, ActionUIRegistry.lookup("Button"))
    }

    @Test
    fun `regular and absent controlSize keep the Material defaults`() {
        assertNull(controlSizeMetrics(null))
        assertNull(controlSizeMetrics(ActionUIControlSize.REGULAR))
    }

    @Test
    fun `the size ladder is strictly increasing around the 40dp Material default`() {
        val mini = controlSizeMetrics(ActionUIControlSize.MINI)!!
        val small = controlSizeMetrics(ActionUIControlSize.SMALL)!!
        val large = controlSizeMetrics(ActionUIControlSize.LARGE)!!
        val extraLarge = controlSizeMetrics(ActionUIControlSize.EXTRA_LARGE)!!

        assertTrue(mini.minHeight < small.minHeight)
        assertTrue(small.minHeight < 40.dp)
        assertTrue(40.dp <= large.minHeight)
        assertTrue(large.minHeight < extraLarge.minHeight)
    }

    @Test
    fun `each metrics carries its own size`() {
        for (size in listOf(
            ActionUIControlSize.MINI,
            ActionUIControlSize.SMALL,
            ActionUIControlSize.LARGE,
            ActionUIControlSize.EXTRA_LARGE,
        )) {
            assertEquals(size, controlSizeMetrics(size)!!.size)
        }
    }
}
