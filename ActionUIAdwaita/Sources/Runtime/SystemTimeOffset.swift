// Sources/Runtime/SystemTimeOffset.swift
/*
 The user's offset from GMT at an instant, from the C library's zone data (the TZ variable, else
 /etc/localtime), for LocalTime.offset: FoundationEssentials alone has no zone but GMT (see
 ActionUI/Core/Helpers/LocalTime.swift). ICU and GLib read the same zone data, so a date is written
 in the zone its day and hour were computed in.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Glibc

enum SystemTimeOffset {
    /// Seconds east of GMT at `date`, daylight saving included; 0 for a date the C library cannot
    /// place (beyond time_t, or NaN).
    @Sendable static func seconds(at date: Date) -> Int {
        guard var seconds = time_t(exactly: date.timeIntervalSince1970.rounded(.down)) else { return 0 }
        var parts = tm()
        guard localtime_r(&seconds, &parts) != nil else { return 0 }
        return Int(parts.tm_gmtoff)
    }
}
