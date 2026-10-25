// Tests/Formatting/SystemLocaleTests.swift
/*
 Tests for the locale dates and numbers follow: the C library's name for a category becomes ICU's
 (character set and modifier dropped), and the C locale names none. The box has only the C locales
 installed, so a named locale is checked through the name alone.
*/

import XCTest
import Glibc
@testable import ActionUI

@MainActor
final class SystemLocaleTests: XCTestCase {
    func testACLibraryNameBecomesICUs() {
        XCTAssertEqual(SystemLocale.icuLocale(fromPOSIX: "de_DE.UTF-8"), "de_DE")
        XCTAssertEqual(SystemLocale.icuLocale(fromPOSIX: "pl_PL.utf8"), "pl_PL")
        XCTAssertEqual(SystemLocale.icuLocale(fromPOSIX: "sr_RS.UTF-8@latin"), "sr_RS")
        XCTAssertEqual(SystemLocale.icuLocale(fromPOSIX: "en_GB"), "en_GB")
    }

    func testTheCLocaleNamesNone() {
        for name in ["C", "C.UTF-8", "C.utf8", "POSIX", ""] {
            XCTAssertNil(SystemLocale.icuLocale(fromPOSIX: name), name)
        }
    }

    func testTheCategoryIsReadFromTheCLibrary() {
        // The box runs with LANG=C.UTF-8, which GTK applied at startup.
        XCTAssertNil(SystemLocale.icuLocale(for: LC_NUMERIC))
        XCTAssertNil(SystemLocale.icuLocale(for: LC_TIME))
    }
}
