//
//  DateHelper.swift
//  ActionUI

import Foundation

/// Helper for parsing and formatting dates in ActionUI
struct DateHelper {
    // Zoned forms are fixed; the local forms are built per call because they read
    // the current time zone, which can change while the app runs.
    private static let zonedStyle = Date.ISO8601FormatStyle()
    private static let zonedFractionalStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// Parses an ISO 8601 date string. The forms, and what each one means:
    /// - "2024-07-16": a calendar day, at noon in the current time zone so the day
    ///   survives small zone shifts.
    /// - "2024-07-16T14:30:00Z", "2024-07-16T14:30:00+02:00" (also "+02", "+0200"; seconds
    ///   and fractional seconds optional): an instant. The zone designator is honored.
    /// - "2024-07-16T14:30:00" or "2024-07-16T14:30", no designator: wall-clock time in
    ///   the current time zone (the form time-bearing DatePickers emit).
    /// - "14:30" or "14:30:00": that wall-clock time today.
    /// - Returns: The parsed Date, or nil when no form matches.
    /// - Note: Android's DateHelper.kt and the web DatePicker's parseParts follow the
    ///   same rules.
    static func parseDate(from rawString: String) -> Date? {
        let dateString = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        let zone = Calendar.current.timeZone
        if !dateString.contains("T") {
            let dayStyle = Date.ISO8601FormatStyle(timeZone: zone).year().month().day()
            if let midnight = try? Date(dateString, strategy: dayStyle) {
                var components = Calendar.current.dateComponents([.year, .month, .day], from: midnight)
                components.hour = 12
                return Calendar.current.date(from: components) ?? midnight
            }
            return parseLocalTime(from: dateString)
        }

        // Check the shape first: the format styles ignore text after what they read,
        // so "...14:30:00,5Z" or "...14:30:00 junk" would parse as wall-clock time with
        // the designator dropped. Android and the web refuse those, so Swift does too.
        guard let designatorStart = designatorOffset(dateString) else { return nil }
        // A missing seconds field ("2024-07-16T09:05", "...T09:05Z") is accepted, as on
        // Android and the web.
        var local = String(dateString.prefix(designatorStart))
        if local.count == 16 {
            local += ":00"
        }
        let designator = dateString.dropFirst(designatorStart)

        // A designator ("Z", "+hh", "+hhmm" or "+hh:mm") must be honored: an instant.
        if !designator.isEmpty {
            let zoned = local + designator
            if let date = try? Date(zoned, strategy: zonedStyle) {
                return date
            }
            return try? Date(zoned, strategy: zonedFractionalStyle)
        }

        // Offset-less: wall-clock time in the current time zone.
        let localDay = Date.ISO8601FormatStyle(timeZone: zone).year().month().day().dateTimeSeparator(.standard)
        if let date = try? Date(local, strategy: localDay.time(includingFractionalSeconds: false)) {
            return date
        }
        return try? Date(local, strategy: localDay.time(includingFractionalSeconds: true))
    }

    /// Checks that `string` is "YYYY-MM-DDTHH:mm[:ss[.f...]]" followed by nothing or
    /// by "Z", "z", "+hh", "+hhmm" or "+hh:mm" ("-" too), with ASCII digits. Returns
    /// the offset where the designator starts (the length when there is none), or nil
    /// when the shape does not match.
    private static func designatorOffset(_ string: String) -> Int? {
        let b = Array(string.utf8)
        func isDigit(_ i: Int) -> Bool { i < b.count && b[i] >= UInt8(ascii: "0") && b[i] <= UInt8(ascii: "9") }
        func digits(_ r: Range<Int>) -> Bool { r.allSatisfy(isDigit) }
        func byte(_ i: Int, _ c: Unicode.Scalar) -> Bool { i < b.count && b[i] == UInt8(ascii: c) }
        guard digits(0..<4), byte(4, "-"), digits(5..<7), byte(7, "-"), digits(8..<10), byte(10, "T"),
              digits(11..<13), byte(13, ":"), digits(14..<16) else { return nil }
        var i = 16
        if byte(i, ":") {
            guard digits(17..<19) else { return nil }
            i = 19
            if byte(i, ".") {
                var j = i + 1
                while isDigit(j) { j += 1 }
                guard j > i + 1 else { return nil }
                i = j
            }
        }
        let rest = b.count - i
        if rest == 0 || (rest == 1 && (byte(i, "Z") || byte(i, "z"))) {
            return i
        }
        guard byte(i, "+") || byte(i, "-") else { return nil }
        let isOffset = (rest == 3 && digits(i + 1..<i + 3))
            || (rest == 5 && digits(i + 1..<i + 5))
            || (rest == 6 && digits(i + 1..<i + 3) && byte(i + 3, ":") && digits(i + 4..<i + 6))
        return isOffset ? i : nil
    }

    /// Parses a bare local time string ("HH:mm" or "HH:mm:ss") into today's date
    /// at that time in the current timezone, or nil if it is not a bare time.
    static func parseLocalTime(from string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        guard let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        let second = parts.count == 3 ? (Int(parts[2]) ?? -1) : 0
        guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { return nil }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = second
        return Calendar.current.date(from: components)
    }

    /// Formats a date as a full ISO 8601 calendar date "yyyy-MM-dd" (date-only), the
    /// day in the current time zone. The value-bridge serialization for date-only
    /// DatePickers and other Date-valued elements.
    static func formatDate(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Formats a date as a full local ISO 8601 datetime "yyyy-MM-ddTHH:mm:ss"
    /// (no timezone designator), used by the time-bearing DatePicker modes so a
    /// host can read the wall-clock HH:mm. The components are taken in the
    /// current timezone to match what the user sees in the picker.
    static func formatDateTime(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0,
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}
