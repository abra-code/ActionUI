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
        // Parse in local timezone at noon to avoid day shifts across timezones
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
        
        // Try with date and time, no timezone
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        if let date = formatter.date(from: dateString) {
            return date
        }
        
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

        return nil
    }
}
