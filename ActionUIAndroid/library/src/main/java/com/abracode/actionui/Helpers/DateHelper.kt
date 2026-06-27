package com.abracode.actionui.Helpers

import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.OffsetDateTime
import java.time.ZoneOffset
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
 * [parseDate] accepts the same flexible ISO 8601 inputs as the Swift helper -
 * a bare full date (`2024-07-16`), or a date-time with or without an offset
 * (`2024-07-16T14:30:00Z`, `2024-07-16T14:30:00+01:00`, `2024-07-16T14:30:00`) -
 * and reduces any of them to the date component. Returns `null` on anything else.
 */
object DateHelper {

    /**
     * Parses a flexible ISO 8601 [dateString] to a date-only [LocalDate], or
     * `null` if no supported form matches. A date-time input is reduced to its
     * date component.
     */
    fun parseDate(dateString: String): LocalDate? {
        val trimmed = dateString.trim()
        if (trimmed.isEmpty()) return null
        return tryParse { LocalDate.parse(trimmed) }                                   // 2024-07-16
            ?: tryParse { OffsetDateTime.parse(trimmed).toLocalDate() }                // ...T..Z / +hh:mm
            ?: tryParse { Instant.parse(trimmed).atZone(ZoneOffset.UTC).toLocalDate() } // ...T..Z (instant)
            ?: tryParse { LocalDateTime.parse(trimmed).toLocalDate() }                 // ...T.. (no offset)
    }

    /** Formats [date] as a full ISO 8601 date (`yyyy-MM-dd`), matching Apple's `.withFullDate`. */
    fun formatDate(date: LocalDate): String = date.format(DateTimeFormatter.ISO_LOCAL_DATE)

    /**
     * Parses a flexible ISO 8601 [input] to a [LocalDateTime] (date + wall-clock
     * time), or `null` if no supported form matches. Used by the time-bearing
     * `DatePicker` modes (`hourAndMinute` / `dateAndTime`). Accepts:
     *   * a full local datetime (`2024-07-16T09:05:00`, `2024-07-16T09:05`);
     *   * an offset/instant datetime, reduced to its local date+time;
     *   * a bare time (`09:05`, `09:05:00`), seeded with today's date;
     *   * a bare date (`2024-07-16`), seeded at midnight.
     */
    fun parseDateTime(input: String): LocalDateTime? {
        val trimmed = input.trim()
        if (trimmed.isEmpty()) return null
        return tryParseDT { LocalDateTime.parse(trimmed) }                                    // ...T..:..(:..)
            ?: tryParseDT { OffsetDateTime.parse(trimmed).toLocalDateTime() }                 // ...T..Z / +hh:mm
            ?: tryParseDT { Instant.parse(trimmed).atZone(ZoneOffset.UTC).toLocalDateTime() } // ...T..Z (instant)
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
