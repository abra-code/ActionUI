// Tests/Formatting/DateFormattingTests.swift
/*
 Tests for dates formatted by locale on Linux: through the system ICU, found at run time (the box
 has libicu76), with CLDR's patterns for a skeleton, and through GLib when ICU is not used. No
 display is needed.
*/

import XCTest
@testable import ActionUI

@MainActor
final class DateFormattingTests: XCTestCase {
    /// 2024-07-16 12:00 UTC.
    private let noon = Date(timeIntervalSince1970: 1_721_131_200)

    override func tearDown() async throws {
        ICULibrary.disabledForTesting = false
    }

    func testTheSystemICUIsFound() throws {
        let icu = try XCTUnwrap(ICULibrary.shared, "the box has libicu76")
        XCTAssertGreaterThanOrEqual(icu.version, 50)
    }

    func testADateIsWrittenAsItsLocaleWritesIt() {
        XCTAssertEqual(DateFormatting.string(noon, skeleton: "yMMMd", locale: "en_US", timeZone: "UTC"), "Jul 16, 2024")
        XCTAssertEqual(DateFormatting.string(noon, skeleton: "yMMMd", locale: "de_DE", timeZone: "UTC"), "16. Juli 2024")
    }

    func testATimeIsWrittenAsItsLocaleWritesIt() {
        // CLDR 42 and later (ICU 72) put a narrow no-break space before AM and PM.
        XCTAssertEqual(DateFormatting.string(noon, skeleton: "jm", locale: "en_US", timeZone: "UTC"), "12:00\u{202F}PM")
        XCTAssertEqual(DateFormatting.string(noon, skeleton: "jm", locale: "de_DE", timeZone: "UTC"), "12:00")
    }

    func testTheTimeZoneMovesTheDateAndTime() {
        XCTAssertEqual(DateFormatting.string(noon, skeleton: "jm", locale: "de_DE", timeZone: "Europe/Warsaw"), "14:00")
        XCTAssertEqual(DateFormatting.string(noon, skeleton: "yMMMd", locale: "en_US", timeZone: "Pacific/Kiritimati"), "Jul 17, 2024")
    }

    func testADateAndTimeTogether() {
        let text = DateFormatting.string(noon, skeleton: "yMMMdjm", locale: "en_US", timeZone: "UTC")
        XCTAssertTrue(text.hasPrefix("Jul 16, 2024"), text)
        XCTAssertTrue(text.hasSuffix("12:00\u{202F}PM"), text)
    }

    func testTheSameFormatAgainGivesTheSameText() {
        let first = DateFormatting.string(noon, skeleton: "yMMMd", locale: "en_US", timeZone: "UTC")
        XCTAssertEqual(DateFormatting.string(noon, skeleton: "yMMMd", locale: "en_US", timeZone: "UTC"), first)
    }

    func testWithoutICUDatesFollowTheCLibrarysLocale() {
        // GLib's %x and %R: the exact form depends on the C library's locale, so only the fields
        // are checked.
        ICULibrary.disabledForTesting = true
        let date = DateFormatting.string(noon, skeleton: "yMMMd", locale: "de_DE", timeZone: "UTC")
        XCTAssertTrue(date.contains("16") && date.contains("07"), date)
        XCTAssertFalse(date.contains("12:00"), "no time for a date skeleton: \(date)")
        XCTAssertEqual(DateFormatting.string(noon, skeleton: "jm", timeZone: "UTC"), "12:00")
        let both = DateFormatting.string(noon, skeleton: "yMMMdjm", timeZone: "Europe/Warsaw")
        XCTAssertTrue(both.contains("16") && both.hasSuffix("14:00"), both)
    }

    func testWithoutICUADateBeyondGLibsRangeGivesNoText() {
        // Seconds past Int64 (and NaN) once trapped converting to gint64.
        ICULibrary.disabledForTesting = true
        for seconds in [1e20, -1e20, Double.nan] {
            XCTAssertEqual(DateFormatting.string(Date(timeIntervalSince1970: seconds), skeleton: "yMMMd", timeZone: "UTC"), "")
        }
    }
}
