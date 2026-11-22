// Tests/Formatting/DateFormattingTests.swift
/*
 Tests for dates formatted by locale through the system's ICU, found at run time, with CLDR's
 patterns for a skeleton. Without ICU they skip, apart from the first, which expects it: every
 supported Linux desktop and Windows has one. The fallbacks without ICU are each platform's (GTK:
 ActionUIAdwaita/Tests/Formatting/FormattingLinuxTests.swift). No display is needed.
*/

import XCTest
@testable import ActionUI

@MainActor
final class DateFormattingTests: XCTestCase {
    /// 2024-07-16 12:00 UTC.
    private let noon = Date(timeIntervalSince1970: 1_721_131_200)

    func testTheSystemICUIsFound() {
        XCTAssertNotNil(ICULibrary.shared, "Linux desktops and Windows have an ICU")
    }

    func testAWeekStartsWhereItsLocaleStartsIt() throws {
        try XCTSkipIf(ICULibrary.shared == nil, "no ICU")
        XCTAssertEqual(DateFormatting.firstWeekday(locale: "en_US"), 1, "Sunday")
        XCTAssertEqual(DateFormatting.firstWeekday(locale: "de_DE"), 2, "Monday")
        XCTAssertEqual(DateFormatting.firstWeekday(locale: "ar_EG"), 7, "Saturday")
    }

    func testADateIsWrittenAsItsLocaleWritesIt() throws {
        try XCTSkipIf(ICULibrary.shared == nil, "no ICU")
        XCTAssertEqual(DateFormatting.string(noon, skeleton: "yMMMd", locale: "en_US", timeZone: "UTC"), "Jul 16, 2024")
        XCTAssertEqual(DateFormatting.string(noon, skeleton: "yMMMd", locale: "de_DE", timeZone: "UTC"), "16. Juli 2024")
    }

    func testATimeIsWrittenAsItsLocaleWritesIt() throws {
        try XCTSkipIf(ICULibrary.shared == nil, "no ICU")
        // CLDR 42 and later (ICU 72) put a narrow no-break space before AM and PM.
        XCTAssertEqual(DateFormatting.string(noon, skeleton: "jm", locale: "en_US", timeZone: "UTC"), "12:00\u{202F}PM")
        XCTAssertEqual(DateFormatting.string(noon, skeleton: "jm", locale: "de_DE", timeZone: "UTC"), "12:00")
    }

    func testTheTimeZoneMovesTheDateAndTime() throws {
        try XCTSkipIf(ICULibrary.shared == nil, "no ICU")
        XCTAssertEqual(DateFormatting.string(noon, skeleton: "jm", locale: "de_DE", timeZone: "Europe/Warsaw"), "14:00")
        XCTAssertEqual(DateFormatting.string(noon, skeleton: "yMMMd", locale: "en_US", timeZone: "Pacific/Kiritimati"), "Jul 17, 2024")
    }

    func testADateAndTimeTogether() throws {
        try XCTSkipIf(ICULibrary.shared == nil, "no ICU")
        let text = DateFormatting.string(noon, skeleton: "yMMMdjm", locale: "en_US", timeZone: "UTC")
        XCTAssertTrue(text.hasPrefix("Jul 16, 2024"), text)
        XCTAssertTrue(text.hasSuffix("12:00\u{202F}PM"), text)
    }

    func testTheSameFormatAgainGivesTheSameText() throws {
        try XCTSkipIf(ICULibrary.shared == nil, "no ICU")
        let first = DateFormatting.string(noon, skeleton: "yMMMd", locale: "en_US", timeZone: "UTC")
        XCTAssertEqual(DateFormatting.string(noon, skeleton: "yMMMd", locale: "en_US", timeZone: "UTC"), first)
    }
}
