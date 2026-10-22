// Core/NumberPrintfTests.swift
/*
 Tests for what NumberPrintf does beyond the shared parity cases (FormatParityTests): without a
 decimal separator it uses the system's; a process locale set with setlocale (as a host may do)
 does not change how the number is formatted; a format splits around its one conversion.
*/

import XCTest
@testable import ActionUI
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class NumberPrintfTests: XCTestCase {
    func testWithoutASeparatorTheSystemsIsUsed() {
        let separator = NumberPrintf.systemDecimalSeparator
        XCTAssertEqual(NumberPrintf.format("Rating: %.1f", 2.5), "Rating: 2\(separator)5")
        XCTAssertEqual(NumberPrintf.plain(2.5), "2\(separator)5")
    }

    func testAProcessLocaleDoesNotChangeTheNumber() throws {
        let previous = setlocale(LC_NUMERIC, nil).map { String(cString: $0) } ?? "C"
        guard setlocale(LC_NUMERIC, "de_DE.UTF-8") != nil else {
            throw XCTSkip("no de_DE.UTF-8 locale here")
        }
        defer { setlocale(LC_NUMERIC, previous) }
        XCTAssertEqual(NumberPrintf.format("%.1f", 2.5, decimalSeparator: "."), "2.5",
                       "formatted in the C locale, then given the separator asked for")
        XCTAssertEqual(NumberPrintf.format("%.1f", 2.5, decimalSeparator: ","), "2,5")
    }

    func testAFormatSplitsAroundItsConversion() {
        XCTAssertEqual(NumberPrintf.parse("100%% at %+.1f%% now"),
                       NumberPrintf.Parsed(prefix: "100% at ", conversion: "%+.1f", suffix: "% now", isInteger: false))
        XCTAssertEqual(NumberPrintf.parse("%05d"), NumberPrintf.Parsed(prefix: "", conversion: "%05ld", suffix: "", isInteger: true))
    }
}
