package com.abracode.actionui.Helpers

import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the non-`@Composable` helpers in `TextStyleEnvironment.kt`:
 * [resolveFontWeight] and [resolveFontDesign]. The composable surface
 * ([ProvideTextStyleEnvironment], [resolveFontStyle], named-text-style mapping)
 * reads `MaterialTheme` and is exercised in instrumentation tests, which is
 * awkward to drive from plain JUnit.
 */
class TextStyleEnvironmentTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    // -----------------------------------------------------------------------
    // resolveFontWeight - SwiftUI's nine weights map onto Compose's nine.
    // -----------------------------------------------------------------------

    @Test
    fun `null weight resolves to null`() {
        assertNull(resolveFontWeight(null))
    }

    @Test
    fun `the nine SwiftUI weights map to the nine Compose weights in order`() {
        assertEquals(FontWeight.Thin, resolveFontWeight("ultraLight"))
        assertEquals(FontWeight.ExtraLight, resolveFontWeight("thin"))
        assertEquals(FontWeight.Light, resolveFontWeight("light"))
        assertEquals(FontWeight.Normal, resolveFontWeight("regular"))
        assertEquals(FontWeight.Medium, resolveFontWeight("medium"))
        assertEquals(FontWeight.SemiBold, resolveFontWeight("semibold"))
        assertEquals(FontWeight.Bold, resolveFontWeight("bold"))
        assertEquals(FontWeight.ExtraBold, resolveFontWeight("heavy"))
        assertEquals(FontWeight.Black, resolveFontWeight("black"))
    }

    @Test
    fun `unknown weight resolves to null and warns`() {
        val logger = CapturingLogger()
        assertNull(resolveFontWeight("extraChunky", logger))
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings.single().contains("font weight"))
    }

    @Test
    fun `null weight does not warn`() {
        val logger = CapturingLogger()
        resolveFontWeight(null, logger)
        assertTrue(logger.warnings.isEmpty())
    }

    // -----------------------------------------------------------------------
    // resolveFontDesign - SwiftUI Font.Design to a Compose FontFamily.
    // -----------------------------------------------------------------------

    @Test
    fun `null and default design resolve to the default family without warning`() {
        val logger = CapturingLogger()
        assertEquals(FontFamily.Default, resolveFontDesign(null, logger))
        assertEquals(FontFamily.Default, resolveFontDesign("default", logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `monospaced and serif designs resolve to their families`() {
        assertEquals(FontFamily.Monospace, resolveFontDesign("monospaced"))
        assertEquals(FontFamily.Serif, resolveFontDesign("serif"))
    }

    @Test
    fun `rounded design falls back to default with a warning`() {
        val logger = CapturingLogger()
        assertEquals(FontFamily.Default, resolveFontDesign("rounded", logger))
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings.single().contains("rounded"))
    }

    @Test
    fun `unknown design falls back to default with a warning`() {
        val logger = CapturingLogger()
        assertEquals(FontFamily.Default, resolveFontDesign("art-deco", logger))
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings.single().contains("font design"))
    }
}
