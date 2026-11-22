// Sources/Formatting/DateFormatting+GLib.swift
/*
 DateFormatting without ICU on Linux: GLib's g_date_time_format in the C library's locale, which GTK
 sets from the environment at startup: %x for a date, %R for a time, both for both. An unknown time
 zone name is UTC, as ICU takes it.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

extension DateFormatting {
    /// GLib's %x and %R in the C library's locale, for the skeleton's date and time fields.
    static func fallbackString(_ date: Date, skeleton: String, timeZone: String?) -> String {
        let hasDate = skeleton.contains { "GyYuUQqMLwWdDFgEec".contains($0) }
        let hasTime = skeleton.contains { "jJCahHkKmsSA".contains($0) }
        let format = [hasDate || !hasTime ? "%x" : nil, hasTime ? "%R" : nil].compactMap { $0 }.joined(separator: " ")
        // A Date beyond Int64 seconds (or NaN) would trap in gint64(_:); GLib refuses years past 9999.
        guard let seconds = gint64(exactly: date.timeIntervalSince1970.rounded(.down)),
              let utc = g_date_time_new_from_unix_utc(seconds) else { return "" }
        defer { g_date_time_unref(utc) }
        // An unknown zone name is UTC, as ICU takes it (GMT); no name is the system's zone.
        let zone = timeZone.map { g_time_zone_new_identifier($0) ?? g_time_zone_new_utc() } ?? g_time_zone_new_local()
        defer { g_time_zone_unref(zone) }
        guard let local = g_date_time_to_timezone(utc, zone) else { return "" }
        defer { g_date_time_unref(local) }
        return takeGString(g_date_time_format(local, format)) ?? ""
    }
}
