package com.abracode.actionui.Helpers

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId

/**
 * Unit tests for [DateHelper] - the ISO 8601 date parsing/formatting that backs
 * the `DatePicker` element and the `DATE` value-bridge branch. The Android
 * counterpart of Apple's `DateHelperTests` (the value bridge carries a date-only
 * [LocalDate], so any date-time input is reduced to its date component; a zoned
 * one is first converted to the device zone, passed explicitly here).
 */
class DateHelperTest {

    @Test
    fun `parseDate reads a bare full date`() {
        assertEquals(LocalDate.of(2024, 7, 16), DateHelper.parseDate("2024-07-16"))
    }

    private val losAngeles = ZoneId.of("America/Los_Angeles")
    private val tokyo = ZoneId.of("Asia/Tokyo")

    @Test
    fun `parseDate converts a Z date-time to the device zone before taking its date`() {
        // UTC midnight on July 16 is the evening of July 15 in Los Angeles.
        assertEquals(LocalDate.of(2024, 7, 15), DateHelper.parseDate("2024-07-16T00:00:00Z", losAngeles))
        assertEquals(LocalDate.of(2024, 7, 16), DateHelper.parseDate("2024-07-16T00:00:00Z", tokyo))
    }

    @Test
    fun `parseDate converts a numeric-offset date-time to the device zone`() {
        // 23:30 at +01:00 is 07:30 the next day in Tokyo.
        assertEquals(LocalDate.of(2024, 7, 17), DateHelper.parseDate("2024-07-16T23:30:00+01:00", tokyo))
        assertEquals(LocalDate.of(2024, 7, 16), DateHelper.parseDate("2024-07-16T23:30:00+01:00", losAngeles))
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

    // MARK: - datetime (time-bearing DatePicker modes)

    @Test
    fun `parseDateTime reads a full local datetime`() {
        assertEquals(
            LocalDateTime.of(2024, 7, 16, 9, 5, 0),
            DateHelper.parseDateTime("2024-07-16T09:05:00"),
        )
        // Seconds optional.
        assertEquals(
            LocalDateTime.of(2024, 7, 16, 9, 5, 0),
            DateHelper.parseDateTime("2024-07-16T09:05"),
        )
    }

    @Test
    fun `parseDateTime converts a zoned datetime to the device zone`() {
        // 14:30 UTC is 23:30 in Tokyo and 07:30 in Los Angeles (PDT).
        assertEquals(LocalDateTime.of(2024, 7, 16, 23, 30, 0), DateHelper.parseDateTime("2024-07-16T14:30:00Z", tokyo))
        assertEquals(LocalDateTime.of(2024, 7, 16, 7, 30, 0), DateHelper.parseDateTime("2024-07-16T14:30:00Z", losAngeles))
        assertEquals(LocalDateTime.of(2024, 7, 16, 23, 30, 0), DateHelper.parseDateTime("2024-07-16T16:30:00+02:00", tokyo))
    }

    @Test
    fun `parseDateTime accepts the offset forms Apple and the web accept`() {
        val expected = LocalDateTime.of(2024, 7, 16, 21, 30, 0)
        assertEquals(expected, DateHelper.parseDateTime("2024-07-16T14:30:00+0200", tokyo))
        assertEquals(expected, DateHelper.parseDateTime("2024-07-16T14:30:00+02", tokyo))
        assertEquals(expected, DateHelper.parseDateTime("2024-07-16T14:30+02:00", tokyo))
        assertEquals(LocalDate.of(2024, 7, 17), DateHelper.parseDate("2024-07-16T23:30:00+0100", tokyo))
        assertEquals(null, DateHelper.parseDateTime("2024-07-16T14:30:00+02:00 junk", tokyo))
    }

    @Test
    fun `parseDateTime keeps an offset-less datetime as wall-clock time in any zone`() {
        assertEquals(LocalDateTime.of(2024, 7, 16, 9, 5, 0), DateHelper.parseDateTime("2024-07-16T09:05:00", tokyo))
        assertEquals(LocalDateTime.of(2024, 7, 16, 9, 5, 0), DateHelper.parseDateTime("2024-07-16T09:05:00", losAngeles))
    }

    @Test
    fun `parseDateTime seeds today for a bare time`() {
        val parsed = DateHelper.parseDateTime("14:30")!!
        assertEquals(LocalDate.now(), parsed.toLocalDate())
        assertEquals(LocalTime.of(14, 30), parsed.toLocalTime())
    }

    @Test
    fun `parseDateTime seeds midnight for a bare date`() {
        assertEquals(
            LocalDateTime.of(2024, 7, 16, 0, 0, 0),
            DateHelper.parseDateTime("2024-07-16"),
        )
    }

    @Test
    fun `parseDateTime returns null for unparseable input`() {
        assertNull(DateHelper.parseDateTime("not-a-date"))
        assertNull(DateHelper.parseDateTime(""))
    }

    @Test
    fun `formatDateTime emits a full ISO datetime with seconds`() {
        assertEquals("2024-07-16T09:05:00", DateHelper.formatDateTime(LocalDateTime.of(2024, 7, 16, 9, 5, 0)))
        assertEquals("2024-01-02T00:00:00", DateHelper.formatDateTime(LocalDateTime.of(2024, 1, 2, 0, 0, 0)))
    }

    @Test
    fun `parseDateTime then formatDateTime round-trips a full datetime`() {
        val s = "2025-12-31T23:59:00"
        assertEquals(s, DateHelper.formatDateTime(DateHelper.parseDateTime(s)!!))
    }
}
