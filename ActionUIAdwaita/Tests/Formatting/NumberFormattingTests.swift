// Tests/Formatting/NumberFormattingTests.swift
/*
 Tests for numbers formatted and read by locale on Linux, through the system ICU (the box has
 libicu76), against what SwiftUI's TextField(value:format:) shows and reads on macOS 27 (measured
 in en_US and de_DE); and through plain digits when ICU is not used. No display is needed.
*/

import XCTest
@testable import ActionUI

@MainActor
final class NumberFormattingTests: XCTestCase {
    private let decimal = NumberFormatSpec.decimal(minFraction: nil, maxFraction: nil)
    private let percent = NumberFormatSpec.percent(minFraction: nil, maxFraction: nil)
    private let dollars = NumberFormatSpec.currency(code: "USD", minFraction: nil, maxFraction: nil)

    override func tearDown() async throws {
        ICULibrary.disabledForTesting = false
    }

    private func string(_ value: Double, _ format: NumberFormatSpec, _ locale: String = "en_US") -> String {
        NumberFormatting.string(value, format: format, locale: locale)
    }

    private func number(_ text: String, _ format: NumberFormatSpec, _ locale: String = "en_US") -> Double? {
        NumberFormatting.number(from: text, format: format, locale: locale)
    }

    func testEachFormatIsWrittenAsSwiftUIWritesIt() {
        XCTAssertEqual(string(1234, .integer), "1,234")
        XCTAssertEqual(string(1234.5678, decimal), "1,234.5678")
        XCTAssertEqual(string(0.25, percent), "25%")
        XCTAssertEqual(string(9.99, dollars), "$9.99")
        XCTAssertEqual(string(-3, dollars), "-$3.00")
        XCTAssertEqual(string(1234.5, .currency(code: "EUR", minFraction: nil, maxFraction: nil)), "€1,234.50")
        XCTAssertEqual(string(1234.5, .currency(code: "JPY", minFraction: nil, maxFraction: nil)), "¥1,234", "the yen's own: no fraction")
    }

    func testDecimalsAndPercentsShowAtMostSixFractionDigits() {
        // ICU's own defaults are 3 for a decimal and 0 for a percent.
        XCTAssertEqual(string(0.12345678901234, decimal), "0.123457")
        XCTAssertEqual(string(1.5e-7, decimal), "0")
        XCTAssertEqual(string(1e20, decimal), "100,000,000,000,000,000,000")
        XCTAssertEqual(string(0.123456789, percent), "12.345679%")
    }

    func testAFractionLengthReplacesTheDefault() {
        XCTAssertEqual(string(1.239, .decimal(minFraction: 2, maxFraction: 2)), "1.24")
        XCTAssertEqual(string(12, .decimal(minFraction: 2, maxFraction: 2)), "12.00")
        XCTAssertEqual(string(1.5, .decimal(minFraction: 0, maxFraction: 2)), "1.5")
        XCTAssertEqual(string(0.12345, .percent(minFraction: 1, maxFraction: 1)), "12.3%")
        XCTAssertEqual(string(9.5, .currency(code: "USD", minFraction: 0, maxFraction: 2)), "$9.5")
        XCTAssertEqual(string(9, .currency(code: "JPY", minFraction: 2, maxFraction: 2)), "¥9.00", "after the currency's own")
    }

    func testTheLocaleWritesTheSeparatorsAndSymbols() {
        XCTAssertEqual(string(1234.5678, decimal, "de_DE"), "1.234,5678")
        XCTAssertEqual(string(1234, .integer, "de_DE"), "1.234")
        XCTAssertEqual(string(-1234.5, dollars, "de_DE"), "-1.234,50\u{A0}$")
        XCTAssertEqual(string(0.25, percent, "de_DE"), "25\u{A0}%")
    }

    func testReadingTakesTheNumberAtTheStartAsSwiftUIDoes() {
        // Each pair measured on macOS 27 in en_US; nil leaves SwiftUI's value as it was.
        let table: [(String, NumberFormatSpec, Double?)] = [
            ("abc", decimal, nil), ("", decimal, nil), ("12", decimal, 12), ("12abc", decimal, 12), (" 42 ", decimal, 42),
            ("1,234.5", decimal, 1234.5), ("12,5", decimal, 12), ("1.234,5", decimal, 1.234), ("$7", decimal, nil),
            ("7%", decimal, 7), ("7 $", decimal, 7), ("-3", decimal, -3), ("(3)", decimal, nil), ("+3", decimal, 3),
            ("1e3", decimal, 1000),
            ("12", percent, 0.12), ("12.5", percent, 0.125), ("7%", percent, 0.07), ("1,234.5", percent, 12.345), ("$7", percent, nil),
            ("12", dollars, 12), ("$7", dollars, 7), ("USD7", dollars, 7), ("€7", dollars, nil), ("EUR 7", dollars, nil),
            ("-$3.00", dollars, -3), ("7%", dollars, 7),
        ]
        for (text, format, expected) in table {
            XCTAssertEqual(number(text, format), expected, "'\(text)' in \(format)")
        }
    }

    func testReadingFollowsTheLocale() {
        // Measured on macOS 27 in de_DE.
        XCTAssertEqual(number("1.234,5", decimal, "de_DE"), 1234.5)
        XCTAssertEqual(number("12,5", decimal, "de_DE"), 12.5)
        XCTAssertEqual(number("12.5", decimal, "de_DE"), 12, "a grouping separator needs three digits after it")
        XCTAssertEqual(number("1,234.5", decimal, "de_DE"), 1.234)
        XCTAssertEqual(number("7 €", decimal, "de_DE"), 7)
    }

    func testWithoutICUNumbersArePlainDigits() {
        ICULibrary.disabledForTesting = true
        XCTAssertEqual(string(1234.5678, decimal), "1234.5678")
        XCTAssertEqual(string(1234, .integer), "1234")
        XCTAssertEqual(string(0.25, percent), "25%")
        XCTAssertEqual(string(9.5, dollars), "USD 9.50")
        XCTAssertEqual(string(1.239, .decimal(minFraction: 2, maxFraction: 2)), "1.24")
        XCTAssertEqual(number("12.5abc", decimal), 12.5)
        XCTAssertEqual(number("25%", percent), 0.25)
        XCTAssertEqual(number("USD 9.50", dollars), 9.5)
        XCTAssertEqual(number("-1.5e3", decimal), -1500)
        XCTAssertEqual(number("2e", decimal), 2, "an exponent with no digits is not part of the number")
        XCTAssertNil(number("abc", decimal))
        XCTAssertNil(number(".", decimal))
    }
}
