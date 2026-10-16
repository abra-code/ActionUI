package com.abracode.actionui.Helpers

import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException

/**
 * Date-string parsing/formatting for ActionUI Android. The Android counterpart
 * of Apple's `ActionUI/Helpers/DateHelper.swift` - the single place that turns a
 * JSON ISO 8601 date string into the value-bridge [LocalDate] and back, used by
 * the `DatePicker` element and the `DATE` branch of the value-string bridge in
 * `ActionUIModel`.
 *
 * The value bridge carries a date as a [java.time.LocalDate] (date-only,
 * timezone-free). This matches Apple's `.withFullDate` serialization (`DatePicker`
 * uses `displayedComponents: .date`) and sidesteps the day-shift-across-timezones
 * problem the Swift helper works around by parsing to local noon: a [LocalDate]
 * has no time-of-day to shift.
 *
 * [parseDate] accepts the same flexible ISO 8601 inputs as the Swift helper, with
 * the same meanings: a bare full date (`2024-07-16`) is that calendar day; a
 * date-time with a zone designator (`2024-07-16T14:30:00Z`, `...+01:00`) is an
 * instant, converted to the device zone before it is reduced to a date; an
 * offset-less date-time (`2024-07-16T14:30:00`) is wall-clock time. Returns `null`
 * on anything else.
 */
object DateHelper {

    /**
     * Parses a flexible ISO 8601 [dateString] to a date-only [LocalDate], or
     * `null` if no supported form matches. A date-time input is reduced to its
     * date component; a zoned one is first converted to [zone] (the device zone).
     */
    fun parseDate(dateString: String, zone: ZoneId = ZoneId.systemDefault()): LocalDate? {
        val trimmed = dateString.trim()
        if (trimmed.isEmpty()) return null
        return tryParse { LocalDate.parse(trimmed) }                                   // 2024-07-16
            ?: tryParse { OffsetDateTime.parse(withExtendedOffset(trimmed)).atZoneSameInstant(zone).toLocalDate() } // ...T..Z / +hh:mm
            ?: tryParse { Instant.parse(trimmed).atZone(zone).toLocalDate() } // ...T..Z (instant)
            ?: tryParse { LocalDateTime.parse(trimmed).toLocalDate() }                 // ...T.. (no offset)
    }

    /** Formats [date] as a full ISO 8601 date (`yyyy-MM-dd`), matching Apple's `.withFullDate`. */
    fun formatDate(date: LocalDate): String = date.format(DateTimeFormatter.ISO_LOCAL_DATE)

    /**
     * Parses a flexible ISO 8601 [input] to a [LocalDateTime] (date + wall-clock
     * time), or `null` if no supported form matches. Used by the time-bearing
     * `DatePicker` modes (`hourAndMinute` / `dateAndTime`). Accepts:
     *   * a full local datetime (`2024-07-16T09:05:00`, `2024-07-16T09:05`);
     *   * an offset/instant datetime: an instant, converted to [zone] (the device
     *     zone) - the zone designator is honored, as on Apple and the web;
     *   * a bare time (`09:05`, `09:05:00`), seeded with today's date;
     *   * a bare date (`2024-07-16`), seeded at midnight.
     */
    fun parseDateTime(input: String, zone: ZoneId = ZoneId.systemDefault()): LocalDateTime? {
        val trimmed = input.trim()
        if (trimmed.isEmpty()) return null
        return tryParseDT { LocalDateTime.parse(trimmed) }                                    // ...T..:..(:..)
            ?: tryParseDT { OffsetDateTime.parse(withExtendedOffset(trimmed)).atZoneSameInstant(zone).toLocalDateTime() } // ...T..Z / +hh:mm
            ?: tryParseDT { Instant.parse(trimmed).atZone(zone).toLocalDateTime() } // ...T..Z (instant)
            ?: tryParseDT { LocalTime.parse(trimmed).atDate(LocalDate.now()) }                // 09:05(:..) -> today
            ?: tryParseDT { LocalDate.parse(trimmed).atStartOfDay() }                         // 2024-07-16 -> midnight
    }

    /**
     * Formats [dateTime] as a full local ISO 8601 datetime `yyyy-MM-ddTHH:mm:ss`
     * (no offset, seconds always present), the wire form the time-bearing
     * `DatePicker` modes emit so a host can read the wall-clock `HH:mm`.
     */
    fun formatDateTime(dateTime: LocalDateTime): String =
        dateTime.format(DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss"))

    // "+hhmm" -> "+hh:mm": Apple and the web accept the basic offset form, but
    // OffsetDateTime.parse takes only "Z", "+hh" and "+hh:mm".
    private val basicOffset = Regex("""([Tt].*[+-]\d{2})(\d{2})$""")

    private fun withExtendedOffset(s: String): String = basicOffset.replace(s, "\$1:\$2")

    private inline fun tryParse(block: () -> LocalDate): LocalDate? =
        try {
            block()
        } catch (e: DateTimeParseException) {
            null
        }

    private inline fun tryParseDT(block: () -> LocalDateTime): LocalDateTime? =
        try {
            block()
        } catch (e: DateTimeParseException) {
            null
        }
}
