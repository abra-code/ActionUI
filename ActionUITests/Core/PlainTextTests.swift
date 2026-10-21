// Core/PlainTextTests.swift
/*
 Tests for PlainText, Core's stand-ins for trimmingCharacters(in:) and String(format:). Each is
 compared with the Foundation call it replaces, which these Apple tests can still make.
*/

import Foundation
import XCTest
@testable import ActionUI

final class PlainTextTests: XCTestCase {

    // MARK: - trimmed

    func testTrimmedMatchesFoundationForEveryBasicPlaneScalar() {
        var mismatches: [String] = []
        for code in UInt32(0)...0xFFFF {
            guard let scalar = Unicode.Scalar(code) else { continue }
            let s = String(scalar)
            let text = s + s + "a" + s + "b" + s
            let expected = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if PlainText.trimmed(text) != expected {
                mismatches.append(String(code, radix: 16))
            }
        }
        XCTAssertEqual(mismatches, [], "Scalars PlainText.trimmed treats differently from .whitespacesAndNewlines")
    }

    func testTrimmedKeepsInnerWhiteSpaceAndHandlesEdges() {
        XCTAssertEqual(PlainText.trimmed("  14:30 \n"), "14:30")
        XCTAssertEqual(PlainText.trimmed("\r\n2024-07-16\r\n"), "2024-07-16")
        XCTAssertEqual(PlainText.trimmed(" a b "), "a b")
        XCTAssertEqual(PlainText.trimmed(""), "")
        XCTAssertEqual(PlainText.trimmed(" \t\n "), "")
        XCTAssertEqual(PlainText.trimmed("x"), "x")
        XCTAssertEqual(PlainText.trimmed(" e\u{301} "), "e\u{301}", "A combining mark stays with its letter")
        XCTAssertEqual(PlainText.trimmed("  ab  ".dropFirst()), "ab", "A Substring works too")
    }

    // MARK: - zeroPadded

    func testZeroPaddedMatchesStringFormat() {
        let values = [0, 1, 7, 9, 10, 59, 99, 100, 999, 1000, 2024, 9999, 10000, 123456, -1, -7, -10, -123, -2024]
        for width in 0...6 {
            for value in values {
                XCTAssertEqual(PlainText.zeroPadded(value, width: width), String(format: "%0*d", width, value),
                               "value \(value), width \(width)")
            }
        }
    }

    // Compared with String(Int), not String(format:): %d reads 32 bits and would cut these.
    func testZeroPaddedExtremes() {
        XCTAssertEqual(PlainText.zeroPadded(Int.max, width: 4), String(Int.max))
        XCTAssertEqual(PlainText.zeroPadded(Int.min, width: 4), String(Int.min))
    }

    // MARK: - doubleArray (Dictionary+Numeric), which no longer reads NSNumber

    func testDoubleArrayReadsEachNumberLikeDoubleForKey() {
        let dict: [String: Any] = ["v": [1, 2.5, Float(0.5), Int64(3), "inf", "x", NSNull()]]
        XCTAssertEqual(dict.doubleArray(forKey: "v"), [1, 2.5, 0.5, 3, .infinity, 0, 0])
        XCTAssertNil(dict.doubleArray(forKey: "missing"))
        XCTAssertNil(["v": 1.0].doubleArray(forKey: "v"))
    }
}
