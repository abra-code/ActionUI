package com.abracode.actionui.Helpers

import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
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

    private inline fun tryParse(block: () -> LocalDate): LocalDate? =
        try {
            block()
        } catch (e: DateTimeParseException) {
            null
        }
}
