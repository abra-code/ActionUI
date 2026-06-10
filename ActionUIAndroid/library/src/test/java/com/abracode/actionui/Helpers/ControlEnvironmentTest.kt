package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the control-environment parsing in `ControlEnvironment.kt`:
 * the `buttonStyle` / `controlSize` vocabularies (mirroring the `View.swift`
 * validators) and the `disabled` flag. The CompositionLocal propagation itself
 * is Compose runtime plumbing, exercised by running the app - the stance the
 * rest of the renderer takes for `@Composable` code.
 */
class ControlEnvironmentTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    // ---- parseButtonStyle ----

    @Test
    fun `parseButtonStyle resolves the full SwiftUI vocabulary`() {
        val logger = CapturingLogger()
        assertEquals(ActionUIButtonStyle.AUTOMATIC, parseButtonStyle("automatic", logger))
        assertEquals(ActionUIButtonStyle.PLAIN, parseButtonStyle("plain", logger))
        assertEquals(ActionUIButtonStyle.BORDERLESS, parseButtonStyle("borderless", logger))
        assertEquals(ActionUIButtonStyle.BORDERED, parseButtonStyle("bordered", logger))
        assertEquals(ActionUIButtonStyle.BORDERED_PROMINENT, parseButtonStyle("borderedProminent", logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `parseButtonStyle warns and skips an unknown style`() {
        val logger = CapturingLogger()
        assertNull(parseButtonStyle("fancy", logger))
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("buttonStyle 'fancy'"))
    }

    // ---- parseControlSize ----

    @Test
    fun `parseControlSize resolves the full SwiftUI vocabulary`() {
        val logger = CapturingLogger()
        assertEquals(ActionUIControlSize.MINI, parseControlSize("mini", logger))
        assertEquals(ActionUIControlSize.SMALL, parseControlSize("small", logger))
        assertEquals(ActionUIControlSize.REGULAR, parseControlSize("regular", logger))
        assertEquals(ActionUIControlSize.LARGE, parseControlSize("large", logger))
        assertEquals(ActionUIControlSize.EXTRA_LARGE, parseControlSize("extraLarge", logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `parseControlSize warns and skips an unknown size`() {
        val logger = CapturingLogger()
        assertNull(parseControlSize("huge", logger))
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("controlSize 'huge'"))
    }

    // ---- resolveDisabled ----

    @Test
    fun `resolveDisabled is false when the property is absent`() {
        val logger = CapturingLogger()
        assertFalse(resolveDisabled(buildJsonObject { put("title", "x") }, logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `resolveDisabled reads a Boolean`() {
        val logger = CapturingLogger()
        assertTrue(resolveDisabled(buildJsonObject { put("disabled", true) }, logger))
        assertFalse(resolveDisabled(buildJsonObject { put("disabled", false) }, logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `resolveDisabled warns and ignores a non-Boolean value`() {
        val logger = CapturingLogger()
        assertFalse(resolveDisabled(buildJsonObject { put("disabled", 1) }, logger))
        assertFalse(resolveDisabled(buildJsonObject { putJsonObject("disabled") {} }, logger))
        assertEquals(2, logger.warnings.size)
        assertTrue(logger.warnings.all { it.contains("disabled") })
    }
}
