// Sources/Runtime/SystemTimeOffset.swift
/*
 The user's offset from GMT at an instant, from Windows' own zone data, for LocalTime.offset: FoundationEssentials
 alone has no zone but GMT (see ActionUI/Core/Helpers/LocalTime.swift). The zone is the one the system's settings
 name (GetDynamicTimeZoneInformation, read once), and the offset at a date follows that year's daylight saving
 rules (GetTimeZoneInformationForYear, read once per year), as the Linux renderer's localtime_r does. Dates written
 with no zone (DateFormatting) are written in the same zone.

 Not the same everywhere: ICU, which writes the labels, has the zones' whole history, while Windows applies its
 first recorded year's rules to every year before it. For old dates near a daylight saving change in a year whose
 rules differ (US dates before 2007, European ones before 1996), a chart's day can be binned and labeled an hour
 apart.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Synchronization
import WinSDK

enum SystemTimeOffset {
    /// Seconds east of GMT at `date`, daylight saving included; 0 for a date Windows cannot place (before 1601,
    /// past about 30000, or NaN) or when it cannot tell its zone.
    @Sendable static func seconds(at date: Date) -> Int {
        // FILETIME counts 100-nanosecond steps from 1601-01-01 UTC, 11644473600 seconds before 1970. Whole seconds
        // are exact in a Double; the steps are not past about the year 5250, and a step short of the second gave a
        // zone east of GMT an offset a second short, so they are counted in integers.
        let seconds = date.timeIntervalSince1970.rounded(.down) + 11_644_473_600
        guard seconds.isFinite, seconds >= 0, seconds < 910_000_000_000 else { return 0 }
        let utcSteps = UInt64(seconds) * 10_000_000
        var file = FILETIME(dwLowDateTime: DWORD(truncatingIfNeeded: utcSteps),
                            dwHighDateTime: DWORD(truncatingIfNeeded: utcSteps >> 32))
        var utc = SYSTEMTIME()
        guard FileTimeToSystemTime(&file, &utc), var rules = rules(forYear: utc.wYear) else { return 0 }
        var local = SYSTEMTIME()
        var localFile = FILETIME()
        guard SystemTimeToTzSpecificLocalTime(&rules, &utc, &local), SystemTimeToFileTime(&local, &localFile) else {
            return 0
        }
        let localSteps = UInt64(localFile.dwHighDateTime) << 32 | UInt64(localFile.dwLowDateTime)
        return Int((Int64(bitPattern: localSteps) - Int64(bitPattern: utcSteps)) / 10_000_000)
    }

    /// The system's zone, as the settings named it when first asked, kept for the life of the process, as ICU keeps
    /// its default zone (the labels' zone); nil when Windows cannot tell it.
    private static let zone: DYNAMIC_TIME_ZONE_INFORMATION? = {
        var zone = DYNAMIC_TIME_ZONE_INFORMATION()
        return GetDynamicTimeZoneInformation(&zone) != TIME_ZONE_ID_INVALID ? zone : nil
    }()

    /// The zone's rules for each year asked for (GetTimeZoneInformationForYear: its daylight saving dates and offsets
    /// that year), read once: a chart's bins and ticks ask for many dates, each a few times (LocalCalendar), and
    /// reading the rules goes to the registry. Converting with a year's rules is what
    /// SystemTimeToTzSpecificLocalTimeEx does after reading them.
    private static let rulesByYear = Mutex<[UInt16: TIME_ZONE_INFORMATION]>([:])

    private static func rules(forYear year: UInt16) -> TIME_ZONE_INFORMATION? {
        rulesByYear.withLock { known -> TIME_ZONE_INFORMATION? in
            if let rules = known[year] {
                return rules
            }
            guard var zone else { return nil }
            var rules = TIME_ZONE_INFORMATION()
            guard GetTimeZoneInformationForYear(year, &zone, &rules) else { return nil }
            known[year] = rules
            return rules
        }
    }
}
