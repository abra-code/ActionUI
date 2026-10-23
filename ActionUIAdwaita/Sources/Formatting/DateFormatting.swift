// Sources/Formatting/DateFormatting.swift
/*
 Dates as the user's locale writes them, for a DatePicker's label: ICU's pattern for a CLDR
 skeleton (yMMMd: "Jul 16, 2024" in en_US, "16. Juli 2024" in de_DE; jm: a time; yMMMdjm: both),
 from the same Unicode locale data (CLDR) SwiftUI's FormatStyle uses on Apple, so the two agree
 except where their data versions differ.

 Without ICU (ICULibrary), GLib's g_date_time_format in the C library's locale, which GTK sets from
 the environment at startup: %x for a date, %R for a time, both for both (owner decision 15). An
 unknown time zone name is UTC on both paths, as ICU takes it.

 An ICU formatter is kept per locale, time zone and skeleton: a window asks for a few, often.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CAdwaita

@MainActor
enum DateFormatting {
    /// `date` as `locale` writes it in `timeZone`, in the form CLDR gives for `skeleton`. nil for
    /// the user's locale (ICU reads LC_ALL, LC_MESSAGES and LANG) and the system's time zone; a
    /// time zone is an IANA name ("Europe/Warsaw").
    static func string(_ date: Date, skeleton: String, locale: String? = nil, timeZone: String? = nil) -> String {
        if let icu = ICULibrary.shared, let text = icuString(icu, date, Key(locale: locale, timeZone: timeZone, skeleton: skeleton)) {
            return text
        }
        return fallbackString(date, skeleton: skeleton, timeZone: timeZone)
    }

    private struct Key: Hashable {
        var locale: String?
        var timeZone: String?
        var skeleton: String
    }

    /// ICU's UDateFormat for each key, kept for the life of the process.
    private static var formatters: [Key: OpaquePointer] = [:]
    /// Keys whose formatter ICU could not make: they go to GLib without asking ICU again.
    private static var failedKeys: Set<Key> = []
    private static var reportedFailure = false

    private static func icuString(_ icu: ICULibrary, _ date: Date, _ key: Key) -> String? {
        guard !failedKeys.contains(key) else { return nil }
        guard let formatter = formatters[key] ?? makeFormatter(icu, key) else {
            failedKeys.insert(key)
            return nil
        }
        formatters[key] = formatter
        // UDate: milliseconds since 1970.
        let milliseconds = date.timeIntervalSince1970 * 1000
        var capacity: Int32 = 64
        while true {
            var status = ICULibrary.noError
            var buffer = [UInt16](repeating: 0, count: Int(capacity))
            let length = icu.formatDate(formatter, milliseconds, &buffer, capacity, nil, &status)
            if length > capacity, capacity < 4096 {
                capacity = length + 1
                continue
            }
            guard status <= ICULibrary.noError, length >= 0, length <= capacity else {
                report("udat_format", status)
                return nil
            }
            return String(decoding: buffer.prefix(Int(length)), as: UTF16.self)
        }
    }

    /// A formatter for the key's locale and time zone with the locale's pattern for its skeleton.
    private static func makeFormatter(_ icu: ICULibrary, _ key: Key) -> OpaquePointer? {
        withOptionalCString(key.locale) { locale -> OpaquePointer? in
            var status = ICULibrary.noError
            guard let generator = icu.openPatternGenerator(locale, &status), status <= ICULibrary.noError else {
                report("udatpg_open", status)
                return nil
            }
            defer { icu.closePatternGenerator(generator) }
            let skeleton = Array(key.skeleton.utf16)
            var pattern = [UInt16](repeating: 0, count: 128)
            let patternLength = icu.bestPattern(generator, skeleton, Int32(skeleton.count), &pattern, Int32(pattern.count), &status)
            guard status <= ICULibrary.noError, patternLength > 0, patternLength <= pattern.count else {
                report("udatpg_getBestPattern", status)
                return nil
            }
            let zone = key.timeZone.map { Array($0.utf16) }
            let formatter = zone.withUnsafeBufferPointerIfPresent { zoneID in
                icu.openDateFormat(ICULibrary.patternStyle, ICULibrary.patternStyle, locale, zoneID?.baseAddress,
                                   Int32(zoneID?.count ?? 0), pattern, patternLength, &status)
            }
            guard let formatter, status <= ICULibrary.noError else {
                report("udat_open", status)
                return nil
            }
            return formatter
        }
    }

    /// Logs an ICU failure once (the call falls back to GLib).
    private static func report(_ function: String, _ status: ICULibrary.ErrorCode) {
        guard !reportedFailure else { return }
        reportedFailure = true
        ActionUIModel.shared.logger.log("ICU \(function) failed (status \(status)); dates follow the C library's locale", .warning)
    }

    /// GLib's %x and %R in the C library's locale, for the skeleton's date and time fields.
    private static func fallbackString(_ date: Date, skeleton: String, timeZone: String?) -> String {
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

    private static func withOptionalCString<Result>(_ string: String?, _ body: (UnsafePointer<CChar>?) -> Result) -> Result {
        guard let string else { return body(nil) }
        return string.withCString(body)
    }
}

private extension Optional where Wrapped == [UInt16] {
    /// The array's buffer when there is one, else nil, for a C argument that may be NULL.
    func withUnsafeBufferPointerIfPresent<Result>(_ body: (UnsafeBufferPointer<UInt16>?) -> Result) -> Result {
        switch self {
        case .some(let array): return array.withUnsafeBufferPointer { body($0) }
        case .none: return body(nil)
        }
    }
}
