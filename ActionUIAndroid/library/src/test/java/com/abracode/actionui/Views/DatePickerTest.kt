package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

/**
 * Unit tests for [DatePicker] - registry resolution, the DATE value seed, and the
 * pure helpers [resolveDateStyle] / [parseDateBounds]. The `@Composable` dialog /
 * inline-calendar surfaces are exercised by the app.
 */
class DatePickerTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    @Test
    fun `DatePicker resolves and is DATE-valued`() {
        assertSame(DatePicker, ActionUIRegistry.lookup("DatePicker"))
        assertEquals(ActionUIValueType.DATE, DatePicker.valueType)
    }

    @Test
    fun `initialValue parses selectedDate`() {
        val el = ActionUIElement(id = 1, type = "DatePicker", properties = buildJsonObject { put("selectedDate", "2024-07-16") })
        assertEquals(LocalDate.of(2024, 7, 16), DatePicker.initialValue(el))
    }

    @Test
    fun `initialValue defaults to today when selectedDate is absent or invalid`() {
        val none = ActionUIElement(id = 1, type = "DatePicker")
        assertEquals(LocalDate.now(), DatePicker.initialValue(none))
        val bad = ActionUIElement(id = 1, type = "DatePicker", properties = buildJsonObject { put("selectedDate", "oops") })
        assertEquals(LocalDate.now(), DatePicker.initialValue(bad))
    }

    @Test
    fun `resolveDateStyle maps automatic and compact to the dialog field`() {
        val logger = CapturingLogger()
        assertEquals(DatePickerStyle.Compact, resolveDateStyle(null, logger))
        assertEquals(DatePickerStyle.Compact, resolveDateStyle("automatic", logger))
        assertEquals(DatePickerStyle.Compact, resolveDateStyle("compact", logger))
        assertEquals(DatePickerStyle.Graphical, resolveDateStyle("graphical", logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `resolveDateStyle warn-downgrades the macOS-only styles to compact`() {
        val logger = CapturingLogger()
        assertEquals(DatePickerStyle.Compact, resolveDateStyle("stepperField", logger))
        assertEquals(DatePickerStyle.Compact, resolveDateStyle("field", logger))
        assertEquals(2, logger.warnings.size)
        assertTrue(logger.warnings.all { it.contains("macOS-only") })
    }

    @Test
    fun `resolveDateStyle warns and defaults to compact for an unknown style`() {
        val logger = CapturingLogger()
        assertEquals(DatePickerStyle.Compact, resolveDateStyle("wheel", logger))
        assertTrue(logger.warnings.any { it.contains("not recognized") })
    }

    @Test
    fun `parseDateBounds reads a valid range`() {
        val logger = CapturingLogger()
        val props = buildJsonObject {
            putJsonObject("range") { put("start", "2024-01-01"); put("end", "2024-12-31") }
        }
        val bounds = parseDateBounds(props, logger)
        assertEquals(DateBounds(LocalDate.of(2024, 1, 1), LocalDate.of(2024, 12, 31)), bounds)
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `parseDateBounds returns null with no warning when range is absent`() {
        val logger = CapturingLogger()
        assertNull(parseDateBounds(buildJsonObject { }, logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `parseDateBounds warns and ignores a malformed or inverted range`() {
        val missing = CapturingLogger()
        assertNull(parseDateBounds(buildJsonObject { putJsonObject("range") { put("start", "2024-01-01") } }, missing))
        assertTrue(missing.warnings.isNotEmpty())

        val inverted = CapturingLogger()
        val props = buildJsonObject {
            putJsonObject("range") { put("start", "2024-12-31"); put("end", "2024-01-01") }
        }
        assertNull(parseDateBounds(props, inverted))
        assertTrue(inverted.warnings.isNotEmpty())
    }

    @Test
    fun `DateBounds contains is inclusive`() {
        val bounds = DateBounds(LocalDate.of(2024, 1, 1), LocalDate.of(2024, 12, 31))
        assertTrue(bounds.contains(LocalDate.of(2024, 1, 1)))
        assertTrue(bounds.contains(LocalDate.of(2024, 6, 15)))
        assertTrue(bounds.contains(LocalDate.of(2024, 12, 31)))
        assertTrue(!bounds.contains(LocalDate.of(2023, 12, 31)))
        assertTrue(!bounds.contains(LocalDate.of(2025, 1, 1)))
    }
}
