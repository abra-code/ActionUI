package com.abracode.actionui.Helpers

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate

/**
 * Unit tests for [DateHelper] - the ISO 8601 date parsing/formatting that backs
 * the `DatePicker` element and the `DATE` value-bridge branch. The Android
 * counterpart of Apple's `DateHelperTests` (the value bridge carries a date-only
 * [LocalDate], so any date-time input is reduced to its date component).
 */
class DateHelperTest {

    @Test
    fun `parseDate reads a bare full date`() {
        assertEquals(LocalDate.of(2024, 7, 16), DateHelper.parseDate("2024-07-16"))
    }

    @Test
    fun `parseDate reduces a date-time with Z offset to its date`() {
        assertEquals(LocalDate.of(2024, 7, 16), DateHelper.parseDate("2024-07-16T14:30:00Z"))
    }

    @Test
    fun `parseDate reduces a date-time with numeric offset to its date`() {
        assertEquals(LocalDate.of(2024, 7, 16), DateHelper.parseDate("2024-07-16T14:30:00+01:00"))
    }

    @Test
    fun `parseDate reduces an offset-less date-time to its date`() {
        assertEquals(LocalDate.of(2024, 7, 16), DateHelper.parseDate("2024-07-16T14:30:00"))
    }

    @Test
    fun `parseDate trims surrounding whitespace`() {
        assertEquals(LocalDate.of(2024, 7, 16), DateHelper.parseDate("  2024-07-16  "))
    }

    @Test
    fun `parseDate returns null for unparseable input`() {
        assertNull(DateHelper.parseDate("not-a-date"))
        assertNull(DateHelper.parseDate(""))
        assertNull(DateHelper.parseDate("2024-13-99")) // out-of-range month/day
    }

    @Test
    fun `formatDate emits a full ISO date`() {
        assertEquals("2024-07-16", DateHelper.formatDate(LocalDate.of(2024, 7, 16)))
        assertEquals("2024-01-02", DateHelper.formatDate(LocalDate.of(2024, 1, 2)))
    }

    @Test
    fun `parse then format round-trips`() {
        val s = "2025-12-31"
        assertEquals(s, DateHelper.formatDate(DateHelper.parseDate(s)!!))
    }
}
