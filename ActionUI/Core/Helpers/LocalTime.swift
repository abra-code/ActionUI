// Core/Helpers/LocalTime.swift
/*
 Calendar arithmetic in the user's time zone on every platform: a day, a wall-clock time, a chart's
 bins and ticks.

 With full Foundation (Apple), Calendar.current knows the user's zone and does it all. With
 FoundationEssentials alone (the Linux and Windows renderers), TimeZone.current is GMT whatever the
 system's zone is, and a named zone is nil: FoundationEssentials reaches the system's zone only
 through FoundationInternationalization, which those renderers do not load. There the renderer sets
 LocalTime.offset from the system's own zone data (Linux: localtime_r, in ActionUIRegistry+Adwaita),
 and LocalCalendar works on a GMT calendar, moving each date by the offset in force at it: a date's
 local components are the GMT components of the date plus its offset, and local components name the
 instant whose offset, added, gives them.

 Around a change of offset a wall-clock time can be missing (clocks go forward: 2:30 AM on the day
 daylight saving starts in New York) or there twice (clocks go back): a missing one is moved forward
 by the size of the gap (3:30 AM), and one there twice is the first, as Calendar takes them.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

enum LocalTime {
    /// The user's offset from GMT in seconds at an instant, daylight saving included. nil where
    /// Calendar.current knows the user's zone (Apple). A renderer sets it once, when it loads its
    /// built-in elements, before any date is read.
    nonisolated(unsafe) static var offset: (@Sendable (Date) -> Int)?

    /// A Gregorian calendar in the user's zone, as it is now.
    static var calendar: LocalCalendar { LocalCalendar(offset: offset) }

    /// The GMT calendar LocalCalendar works on when an offset is set.
    fileprivate static let gmtCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }()
}

/// The few Calendar operations ActionUI does in the user's zone (see the header). Without an offset
/// each is Calendar.current's own.
struct LocalCalendar {
    private var base: Calendar
    private let offset: (@Sendable (Date) -> Int)?

    init(offset: (@Sendable (Date) -> Int)?) {
        self.offset = offset
        base = offset == nil ? Calendar.current : LocalTime.gmtCalendar
    }

    /// The day a week starts on, 1 for Sunday.
    var firstWeekday: Int {
        get { base.firstWeekday }
        set { base.firstWeekday = newValue }
    }

    func dateComponents(_ components: Set<Calendar.Component>, from date: Date) -> DateComponents {
        base.dateComponents(components, from: wall(date))
    }

    func component(_ component: Calendar.Component, from date: Date) -> Int {
        base.component(component, from: wall(date))
    }

    func date(from components: DateComponents) -> Date? {
        base.date(from: components).map(instant)
    }

    func startOfDay(for date: Date) -> Date {
        instant(base.startOfDay(for: wall(date)))
    }

    /// The interval of `unit` holding `date`: a day around a change of offset is 23 or 25 hours.
    /// An hour or finer is that much elapsed time around `date`, so each hour of an hour seen twice
    /// (clocks going back) is an interval of its own.
    func dateInterval(of unit: Calendar.Component, for date: Date) -> DateInterval? {
        let local = wall(date)
        guard let interval = base.dateInterval(of: unit, for: local) else { return nil }
        switch unit {
        case .hour, .minute, .second, .nanosecond:
            return DateInterval(start: date.addingTimeInterval(interval.start.timeIntervalSince(local)), duration: interval.duration)
        default:
            break
        }
        let start = instant(interval.start)
        let end = instant(interval.end)
        return end >= start ? DateInterval(start: start, end: end) : nil
    }

    /// `date` moved by `value` of `unit`: hours and finer in elapsed time, as Calendar adds them;
    /// days and coarser in wall-clock time, so a day later is the same time of day.
    func date(byAdding unit: Calendar.Component, value: Int, to date: Date) -> Date? {
        switch unit {
        case .hour, .minute, .second, .nanosecond:
            return base.date(byAdding: unit, value: value, to: date)
        default:
            return base.date(byAdding: unit, value: value, to: wall(date)).map(instant)
        }
    }

    /// The instant whose local wall-clock time reads as `wallClock` reads in GMT: "2026-09-20T14:30"
    /// read as GMT, made 14:30 in the user's zone.
    func date(fromWallClock wallClock: Date) -> Date? {
        guard offset != nil else {
            return base.date(from: LocalTime.gmtCalendar.dateComponents(
                [.era, .year, .month, .day, .hour, .minute, .second, .nanosecond], from: wallClock))
        }
        return instant(wallClock)
    }

    /// `date` moved by its offset, so that the GMT calendar reads the user's wall-clock time in it.
    private func wall(_ date: Date) -> Date {
        guard let offset else { return date }
        return date.addingTimeInterval(TimeInterval(offset(date)))
    }

    /// The instant a wall-clock time (as wall(_:) gives one) names. The offsets a day before and a
    /// day after are the two that can be in force at it; a candidate holds when its own offset gives
    /// the wall-clock time back. Two hold where clocks went back: the first. None where clocks went
    /// forward: the earlier offset, which moves the time forward by the gap.
    private func instant(_ wallClock: Date) -> Date {
        guard let offset else { return wallClock }
        let before = TimeInterval(offset(wallClock.addingTimeInterval(-86400)))
        let after = TimeInterval(offset(wallClock.addingTimeInterval(86400)))
        let candidates = [wallClock.addingTimeInterval(-before), wallClock.addingTimeInterval(-after)]
        // Within a second: adding and taking away whole seconds can round a fraction's last bits.
        let holding = candidates.filter { abs($0.addingTimeInterval(TimeInterval(offset($0))).timeIntervalSince(wallClock)) < 1 }
        return holding.min() ?? candidates[0]
    }
}
