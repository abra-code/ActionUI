//
//  DateHelper.swift
//  ActionUI

import Foundation

/// Helper for parsing and formatting dates in ActionUI
struct DateHelper {
    /// Parses ISO 8601 date strings flexibly
    /// Supports: "2024-07-16", "2024-07-16T14:30:00Z", "2024-07-16T14:30:00+00:00", etc.
    /// - Parameter dateString: ISO 8601 formatted date string
    /// - Returns: Parsed Date, or nil if parsing fails
    /// - Note: Date-only strings (YYYY-MM-DD) are parsed to noon in the current timezone to avoid day shifts
    static func parseDate(from dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        
        // Try with date only (YYYY-MM-DD)
        // Parse in local timezone at noon to avoid day shifts across timezones.
        // Skip when a time component is present (contains 'T'): a full datetime
        // must keep its time, not be snapped to noon (the time-bearing branches
        // below handle it).
        if !dateString.contains("T") {
            formatter.formatOptions = [.withFullDate]
            formatter.timeZone = TimeZone.current
            if let date = formatter.date(from: dateString) {
                // Adjust to noon in the current timezone
                var components = Calendar.current.dateComponents([.year, .month, .day], from: date)
                components.hour = 12
                components.minute = 0
                components.second = 0
                if let noonDate = Calendar.current.date(from: components) {
                    return noonDate
                }
                return date
            }
        }

        // Try with date and time, no timezone designator (e.g.
        // "2024-07-16T09:05:00"). An offset-less datetime is wall-clock local
        // time, so parse it in the current timezone (the time-bearing DatePicker
        // serialization emits this form via formatDateTime).
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        formatter.timeZone = TimeZone.current
        if let date = formatter.date(from: dateString) {
            return date
        }
        formatter.timeZone = nil
        
        // Try with date and time (no fractional seconds)
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            return date
        }
        
        // Try with full date-time format first (with time and timezone)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            return date
        }

        // Try a bare local time "HH:mm" or "HH:mm:ss" - seed today's date with it.
        // Used by time-bearing DatePicker modes whose initial value is a clock time.
        if let timed = parseLocalTime(from: dateString) {
            return timed
        }

        return nil
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

    /// Formats a date as a full ISO 8601 calendar date "yyyy-MM-dd" (date-only).
    /// Mirrors the value-bridge serialization for date-only DatePickers.
    static func formatDate(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
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
