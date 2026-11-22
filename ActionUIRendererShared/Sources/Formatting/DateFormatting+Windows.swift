// Sources/Formatting/DateFormatting+Windows.swift
/*
 DateFormatting without ICU on Windows: Windows' own short date and time (hours and minutes) for the
 user's locale for formats (GetDateFormatEx, GetTimeFormatEx), for the skeleton's date and time fields,
 as Linux's GLib fallback writes %x and %R. With no time zone named, the user's; a named one by its
 offset at that moment as FoundationEssentials knows it, which is little beyond GMT, UTC and fixed offsets,
 so most names are taken as UTC (as ICU takes an unknown one). Windows 11 always has ICU, so this rarely runs. It
 needs no toolkit, so it sits in the shared code (the Core-only check package leaves its own stub out on
 Windows).
*/

#if os(Windows)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import WinSDK

extension DateFormatting {
    /// Windows' short date and time in the user's locale, for the skeleton's date and time fields.
    static func fallbackString(_ date: Date, skeleton: String, timeZone: String?) -> String {
        let hasDate = skeleton.contains { "GyYuUQqMLwWdDFgEec".contains($0) }
        let hasTime = skeleton.contains { "jJCahHkKmsSA".contains($0) }
        guard var time = systemTime(date, timeZone: timeZone) else { return "" }
        var parts: [String] = []
        if hasDate || !hasTime,
           let text = windowsText({ GetDateFormatEx(nil, DWORD(DATE_SHORTDATE), &time, nil, $0, $1, nil) }) {
            parts.append(text)
        }
        if hasTime, let text = windowsText({ GetTimeFormatEx(nil, DWORD(TIME_NOSECONDS), &time, nil, $0, $1) }) {
            parts.append(text)
        }
        return parts.joined(separator: " ")
    }

    /// The moment as a SYSTEMTIME in the zone asked for; nil outside the years Windows writes (1601 to
    /// about 30000) or for a date that is not a number.
    private static func systemTime(_ date: Date, timeZone: String?) -> SYSTEMTIME? {
        let seconds = date.timeIntervalSince1970.rounded(.down)
        let offset = timeZone.map { Double(TimeZone(identifier: $0)?.secondsFromGMT(for: date) ?? 0) } ?? 0
        // FILETIME counts 100-nanosecond steps from 1601-01-01 UTC, 11644473600 seconds before 1970.
        let steps = (seconds + offset + 11_644_473_600) * 10_000_000
        guard steps.isFinite, steps >= 0, steps < 9.1e18 else { return nil }
        let value = UInt64(steps)
        var file = FILETIME(dwLowDateTime: DWORD(truncatingIfNeeded: value), dwHighDateTime: DWORD(truncatingIfNeeded: value >> 32))
        var utc = SYSTEMTIME()
        guard FileTimeToSystemTime(&file, &utc) else { return nil }
        // A named zone is applied above; with none, the user's own.
        guard timeZone == nil else { return utc }
        var local = SYSTEMTIME()
        guard SystemTimeToTzSpecificLocalTime(nil, &utc, &local) else { return nil }
        return local
    }

    /// The text a Windows formatting function writes: asked for its length first, then the text.
    private static func windowsText(_ format: (UnsafeMutablePointer<WCHAR>?, Int32) -> Int32) -> String? {
        let length = format(nil, 0)
        guard length > 1 else { return nil }
        var buffer = [WCHAR](repeating: 0, count: Int(length))
        let written = buffer.withUnsafeMutableBufferPointer { format($0.baseAddress, Int32($0.count)) }
        guard written > 1 else { return nil }
        return String(decoding: buffer[..<Int(written - 1)], as: UTF16.self)
    }
}

#endif
