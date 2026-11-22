// Tests/Formatting/SystemLocaleWindowsTests.swift
/*
 Tests for Windows' locale names: a BCP 47 name (what GetUserDefaultLocaleName gives) becomes ICU's
 form, and an empty one names none.
*/

#if os(Windows)

import XCTest
@testable import ActionUI

@MainActor
final class SystemLocaleWindowsTests: XCTestCase {
    func testABCP47NameBecomesICUs() {
        XCTAssertEqual(SystemLocale.icuLocale(fromBCP47: "en-US"), "en_US")
        XCTAssertEqual(SystemLocale.icuLocale(fromBCP47: "sr-Latn-RS"), "sr_Latn_RS")
        XCTAssertEqual(SystemLocale.icuLocale(fromBCP47: "de"), "de")
    }

    func testAnEmptyNameNamesNone() {
        XCTAssertNil(SystemLocale.icuLocale(fromBCP47: ""))
    }

    func testTheUsersLocaleIsNamed() {
        XCTAssertNotNil(SystemLocale.icuLocale(for: .time))
    }
}

#endif
