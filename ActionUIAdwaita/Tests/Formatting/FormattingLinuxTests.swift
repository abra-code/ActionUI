// Tests/Formatting/FormattingLinuxTests.swift
/*
 Tests for the Linux parts of formatting by locale: the ICU found (the box has libicu76), the locale
 read from the C library for each category, and dates through GLib when ICU is not used. The shared
 parts' tests are in ActionUIRendererShared/Tests/Formatting. No display is needed.
*/

import XCTest
@testable import ActionUI

@MainActor
final class FormattingLinuxTests: XCTestCase {
    /// 2024-07-16 12:00 UTC.
    private let noon = Date(timeIntervalSince1970: 1_721_131_200)

    override func tearDown() async throws {
        ICULibrary.disabledForTesting = false
    }

    func testTheICUFoundHasAVersion() throws {
        let icu = try XCTUnwrap(ICULibrary.shared, "the box has libicu76")
        XCTAssertGreaterThanOrEqual(icu.version, 50)
    }

    func testTheCategoryIsReadFromTheCLibrary() {
        // The box runs with LANG=C.UTF-8, which GTK applied at startup.
        XCTAssertNil(SystemLocale.icuLocale(for: .numbers))
        XCTAssertNil(SystemLocale.icuLocale(for: .time))
        XCTAssertNil(SystemLocale.icuLocale(for: .money))
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
