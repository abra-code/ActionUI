// Core/LocalTimeTests.swift
/*
 Tests for LocalTime and the DateHelper forms that use it, with LocalTime.offset set to a fake zone
 the way the Linux and Windows renderers set it: New York's offsets in 2026, -5 hours, -4 from
 2026-03-08T07:00Z (2 AM becomes 3 AM) and -5 again from 2026-11-01T06:00Z (2 AM becomes 1 AM). The
 offset is set, so these run the arithmetic those renderers use, on any platform.
*/

import Foundation
import XCTest
@testable import ActionUI

final class LocalTimeTests: XCTestCase {
    // 2026-03-08T07:00:00Z and 2026-11-01T06:00:00Z.
    static let springForward = Date(timeIntervalSince1970: 1_772_953_200)
    static let fallBack = Date(timeIntervalSince1970: 1_793_512_800)
    static let newYork: @Sendable (Date) -> Int = { date in
        date >= springForward && date < fallBack ? -4 * 3600 : -5 * 3600
    }

    private var saved: (@Sendable (Date) -> Int)?

    override func setUp() {
        super.setUp()
        saved = LocalTime.offset
        LocalTime.offset = Self.newYork
    }

    override func tearDown() {
        LocalTime.offset = saved
        super.tearDown()
    }

    private func utc(_ text: String) throws -> Date {
        try Date(text, strategy: Date.ISO8601FormatStyle())
    }

    private func local(_ date: Date?) -> [Int?] {
        guard let date else { return [] }
        let c = LocalTime.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return [c.year, c.month, c.day, c.hour, c.minute, c.second]
    }

    func testTheFakeZoneChangesWhereNewYorkDoes() throws {
        XCTAssertEqual(Self.springForward, try utc("2026-03-08T07:00:00Z"))
        XCTAssertEqual(Self.fallBack, try utc("2026-11-01T06:00:00Z"))
    }

    func testABareTimeIsThatTimeTodayOnTheUsersClock() throws {
        let parsed = try XCTUnwrap(DateHelper.parseDate(from: "14:30"))
        let today = LocalTime.calendar.dateComponents([.year, .month, .day], from: Date())
        XCTAssertEqual(local(parsed), [today.year, today.month, today.day, 14, 30, 0])
    }

    func testAnInstantReadsInTheUsersZone() throws {
        let parsed = DateHelper.parseDate(from: "2026-09-20T14:30:00Z")
        XCTAssertEqual(local(parsed), [2026, 9, 20, 10, 30, 0])
        XCTAssertEqual(DateHelper.formatDateTime(from: try XCTUnwrap(parsed)), "2026-09-20T10:30:00")
        XCTAssertEqual(local(DateHelper.parseDate(from: "2026-01-20T14:30:00Z")), [2026, 1, 20, 9, 30, 0])
    }

    func testAWallClockTimeIsTheInstantOfThatTimeOnEachSideOfAChange() throws {
        XCTAssertEqual(DateHelper.parseDate(from: "2026-03-08T01:30:00"), try utc("2026-03-08T06:30:00Z"))
        XCTAssertEqual(DateHelper.parseDate(from: "2026-03-08T03:30:00"), try utc("2026-03-08T07:30:00Z"))
        XCTAssertEqual(DateHelper.parseDate(from: "2026-07-01T12:00"), try utc("2026-07-01T16:00:00Z"))
    }

    func testWallClockTimesRoundTripAcrossTheChanges() throws {
        for text in ["2026-03-07T23:30:00", "2026-03-08T00:00:00", "2026-03-08T01:59:59", "2026-03-08T03:00:00",
                     "2026-03-09T12:00:00", "2026-10-31T23:00:00", "2026-11-01T00:30:00", "2026-11-01T02:00:00",
                     "2026-11-02T08:15:00", "2026-12-31T23:59:59"] {
            let parsed = try XCTUnwrap(DateHelper.parseDate(from: text), text)
            XCTAssertEqual(DateHelper.formatDateTime(from: parsed), text)
        }
    }

    func testAMissingTimeMovesForwardAndATwiceSeenTimeIsTheFirst() throws {
        // 2:30 AM on March 8 is not on the clock: 3:30 AM, as Calendar takes it.
        let missing = try XCTUnwrap(DateHelper.parseDate(from: "2026-03-08T02:30:00"))
        XCTAssertEqual(missing, try utc("2026-03-08T07:30:00Z"))
        XCTAssertEqual(DateHelper.formatDateTime(from: missing), "2026-03-08T03:30:00")
        // 1:30 AM on November 1 is on the clock twice: the first, in daylight time.
        XCTAssertEqual(DateHelper.parseDate(from: "2026-11-01T01:30:00"), try utc("2026-11-01T05:30:00Z"))
    }

    func testDateOnlyValuesKeepTheirDaysOnEachSideOfAChange() throws {
        for text in ["2026-03-07", "2026-03-08", "2026-03-09", "2026-10-31", "2026-11-01", "2026-11-02"] {
            let parsed = try XCTUnwrap(DateHelper.parseDate(from: text), text)
            XCTAssertEqual(DateHelper.formatDate(from: parsed), text)
            XCTAssertEqual(local(parsed)[3], 12, "\(text) is noon")
        }
    }

    func testDaysAroundAChangeAre23And25Hours() throws {
        let calendar = LocalTime.calendar
        for (text, hours) in [("2026-03-08", 23.0), ("2026-11-01", 25.0), ("2026-07-04", 24.0)] {
            let day = try XCTUnwrap(calendar.dateInterval(of: .day, for: try XCTUnwrap(DateHelper.parseDate(from: text))))
            XCTAssertEqual(day.duration, hours * 3600, text)
            XCTAssertEqual(local(day.start), local(DateHelper.parseDate(from: text + "T00:00:00")), text)
        }
        XCTAssertEqual(calendar.startOfDay(for: try utc("2026-03-08T20:00:00Z")), try utc("2026-03-08T05:00:00Z"))
    }

    func testEachHourOfAnHourSeenTwiceIsAnIntervalOfItsOwn() throws {
        let calendar = LocalTime.calendar
        // 1:15 AM on November 1 in daylight time, then in standard time.
        for (text, start) in [("2026-11-01T05:15:00Z", "2026-11-01T05:00:00Z"), ("2026-11-01T06:15:00Z", "2026-11-01T06:00:00Z")] {
            let date = try utc(text)
            XCTAssertEqual(calendar.dateInterval(of: .hour, for: date), DateInterval(start: try utc(start), duration: 3600), text)
            let minute = try XCTUnwrap(calendar.dateInterval(of: .minute, for: date), text)
            XCTAssertEqual(minute.start, date, text)
            XCTAssertEqual(minute.duration, 60, text)
        }
    }

    func testAddingKeepsTheTimeOfDayForDaysAndElapsedTimeForHours() throws {
        let calendar = LocalTime.calendar
        let evening = try utc("2026-03-07T23:00:00Z")  // 6 PM, the day before the change
        XCTAssertEqual(local(calendar.date(byAdding: .day, value: 1, to: evening)), [2026, 3, 8, 18, 0, 0])
        XCTAssertEqual(calendar.date(byAdding: .hour, value: 24, to: evening), evening.addingTimeInterval(86400))
    }

    @MainActor
    func testAnAxisDayStartsAtTheUsersMidnight() throws {
        let date = try XCTUnwrap(DateHelper.parseDate(from: "2026-09-20"))
        XCTAssertEqual(ChartDescription.axisDate(date, writtenAs: "2026-09-20"), try utc("2026-09-20T04:00:00Z"))
    }

    func testWithoutAnOffsetCalendarCurrentDoesTheArithmetic() throws {
        LocalTime.offset = nil
        let date = try utc("2026-03-08T20:00:00Z")
        let calendar = LocalTime.calendar
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day, .hour], from: date),
                       Calendar.current.dateComponents([.year, .month, .day, .hour], from: date))
        XCTAssertEqual(calendar.dateInterval(of: .day, for: date), Calendar.current.dateInterval(of: .day, for: date))
        XCTAssertEqual(DateHelper.parseDate(from: "2026-09-20T14:30:00"),
                       Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 14, minute: 30)))
    }
}
