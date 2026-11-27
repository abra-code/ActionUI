// Tests/Chart/ChartDatesLocalTimeTests.swift
/*
 A chart's bins and ticks in the user's time zone when LocalTime.offset is set, as the Linux and
 Windows renderers set it: the fake New York zone of Core/LocalTimeTests.swift, whose clocks go
 forward on 2026-03-08 and back on 2026-11-01.
*/

import Foundation
import XCTest
@testable import ActionUI

final class ChartDatesLocalTimeTests: XCTestCase {
    private var savedOffset: (@Sendable (Date) -> Int)?
    private var savedCalendar: LocalCalendar?

    override func setUp() {
        super.setUp()
        savedOffset = LocalTime.offset
        savedCalendar = ChartDates.calendar
        LocalTime.offset = { date in
            let springForward = Date(timeIntervalSince1970: 1_772_953_200)
            let fallBack = Date(timeIntervalSince1970: 1_793_512_800)
            return date >= springForward && date < fallBack ? -4 * 3600 : -5 * 3600
        }
        ChartDates.calendar = LocalTime.calendar
    }

    override func tearDown() {
        LocalTime.offset = savedOffset
        if let savedCalendar { ChartDates.calendar = savedCalendar }
        super.tearDown()
    }

    private func utc(_ text: String) throws -> Date {
        try Date(text, strategy: Date.ISO8601FormatStyle())
    }

    func testADayBinRunsFromMidnightToMidnightOnTheUsersClock() throws {
        let march8 = try XCTUnwrap(DateHelper.parseDate(from: "2026-03-08"))
        let bin = ChartDates.bin(march8, .day)
        XCTAssertEqual(bin.start, try utc("2026-03-08T05:00:00Z"))
        XCTAssertEqual(bin.end.timeIntervalSince(bin.start), 23 * 3600)
        let november1 = ChartDates.bin(try XCTUnwrap(DateHelper.parseDate(from: "2026-11-01")), .day)
        XCTAssertEqual(november1.end.timeIntervalSince(november1.start), 25 * 3600)
    }

    func testDateOnlyValuesFallInTheBinOfTheirOwnDay() throws {
        for text in ["2026-03-07", "2026-03-08", "2026-03-09"] {
            let date = try XCTUnwrap(DateHelper.parseDate(from: text))
            let start = ChartDates.bin(date, .day).start
            XCTAssertEqual(DateHelper.formatDateTime(from: start), text + "T00:00:00")
        }
    }

    func testDailyTicksStayAtMidnightAcrossAChange() throws {
        let ticks = ChartDates.ticks(try utc("2026-03-06T05:00:00Z"), try utc("2026-03-10T04:00:00Z"),
                                     stride: ChartDateStride(unit: .day, count: 1))
        XCTAssertEqual(ticks.map(DateHelper.formatDateTime(from:)),
                       ["2026-03-06T00:00:00", "2026-03-07T00:00:00", "2026-03-08T00:00:00", "2026-03-09T00:00:00",
                        "2026-03-10T00:00:00"])
    }
}
