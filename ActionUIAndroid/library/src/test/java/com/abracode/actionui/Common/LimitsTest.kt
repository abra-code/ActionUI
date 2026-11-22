package com.abracode.actionui.Common

import com.abracode.actionui.Helpers.MAX_IMAGE_PIXELS
import com.abracode.actionui.Helpers.isTooLarge
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The 64-megapixel image cap and a window's load budget. */
class LimitsTest {

    @After
    fun tearDown() {
        ActionUIConfiguration.replaceForTesting()
    }

    @Test
    fun `an image over 64 megapixels is too large, in 64 bits`() {
        assertEquals(64L * 1024 * 1024, MAX_IMAGE_PIXELS)
        assertFalse(isTooLarge(8192, 8192))
        assertTrue(isTooLarge(8193, 8192))
        assertTrue("no overflow in 32 bits", isTooLarge(65536, 65536))
        assertFalse(isTooLarge(-1, 100_000_000))
    }

    @Test
    fun `a window's LoadableViews load at most the budget in its time`() {
        ActionUIConfiguration.replaceForTesting(ActionUIConfiguration(limits = ActionUIConfiguration.Limits(loadBudget = LoadBudget(loads = 3, seconds = 60.0))))
        val window = WindowModel(windowUUID = "budget", logger = ConsoleLogger())
        val second = 1_000_000_000L
        assertTrue(window.spendLoad(0) && window.spendLoad(1) && window.spendLoad(2))
        assertFalse(window.spendLoad(3))
        assertTrue("a minute after the first, one more", window.spendLoad(60 * second))
        assertFalse("and no second one at that moment", window.spendLoad(60 * second))
        assertEquals(LoadBudget(256, 60.0), LoadBudget(loads = 256, seconds = 60.0))
    }
}
