// Core/NumberPrintfTests.swift
/*
 Tests for NumberPrintf: one d i f F e E g G conversion with flags, width and precision, plus "%%",
 is accepted; integer conversions get the value as an Int; other formats ("%@", "%s", two
 conversions, a "*" width, a length modifier, a trailing "%") and integer conversions of values no
 Int holds are refused. Tests run in the C numeric locale (on Apple and in the box), so the decimal
 point is ".".
*/

import XCTest
@testable import ActionUI

final class NumberPrintfTests: XCTestCase {
    func testOneNumberConversionIsAccepted() {
        XCTAssertEqual(NumberPrintf.format("Count: %d", 5), "Count: 5")
        XCTAssertEqual(NumberPrintf.format("%i items", 7.9), "7 items", "an integer conversion truncates, as Int() does")
        XCTAssertEqual(NumberPrintf.format("Rating: %.1f", 2.5), "Rating: 2.5")
        XCTAssertEqual(NumberPrintf.format("%5.2f%%", 3.14159), " 3.14%")
        XCTAssertEqual(NumberPrintf.format("Volume: %g%%", 50), "Volume: 50%")
        XCTAssertEqual(NumberPrintf.format("%+.0f", 3), "+3")
        XCTAssertEqual(NumberPrintf.format("%e", 1500), "1.500000e+03")
        XCTAssertEqual(NumberPrintf.format("\u{E9}t\u{E9} %.1f \u{4E2D}", 2), "\u{E9}t\u{E9} 2.0 \u{4E2D}", "text around it is kept")
    }

    /// A Prepend scalar joins the "%" after it in one Character; the C library still reads that "%"
    /// as a conversion, so it counts as one.
    func testAConversionInsideACharacterCounts() {
        XCTAssertNil(NumberPrintf.format("\u{600}%s %.0f", 1))
        XCTAssertEqual(NumberPrintf.format("\u{600}%.0f", 1), "\u{600}1")
    }

    func testOtherFormatsAreRefused() {
        for format in ["%@", "%s", "%d %d", "%*d", "%ld", "no conversion", "50%", "%.1f and %%d %f"] {
            XCTAssertNil(NumberPrintf.format(format, 1), format)
        }
    }

    func testAnIntegerConversionRefusesValuesNoIntHolds() {
        XCTAssertNil(NumberPrintf.format("%d", .infinity))
        XCTAssertNil(NumberPrintf.format("%d", .nan))
        XCTAssertNil(NumberPrintf.format("%d", 1e300))
        XCTAssertEqual(NumberPrintf.format("%.0f", 1e3), "1000")
    }

    func testThePlainValue() {
        XCTAssertEqual(NumberPrintf.plain(5), "5")
        XCTAssertEqual(NumberPrintf.plain(2.5), "2.5")
    }
}
