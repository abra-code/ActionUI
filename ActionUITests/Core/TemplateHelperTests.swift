// Core/TemplateHelperTests.swift
/*
 Tests for TemplateHelper's column substitution ($0, $1 ... $N) and the column a property names.
 The template view building is tested in Helpers/TemplateHelperViewTests.swift.
*/

import XCTest
@testable import ActionUI

@MainActor
final class TemplateHelperTests: XCTestCase {

    // MARK: - substituteString

    func testSubstituteString_singleColumn() {
        let result = TemplateHelper.substituteString("Hello $1", row: ["World"])
        XCTAssertEqual(result, "Hello World")
    }

    func testSubstituteString_multipleColumns() {
        let result = TemplateHelper.substituteString("$1 scored $2 points", row: ["Alice", "42"])
        XCTAssertEqual(result, "Alice scored 42 points")
    }

    func testSubstituteString_zeroIndex_allColumnsJoined() {
        let result = TemplateHelper.substituteString("$0", row: ["star.fill", "Favorites"])
        XCTAssertEqual(result, "star.fill, Favorites")
    }

    func testSubstituteString_noTokens_unchanged() {
        let result = TemplateHelper.substituteString("No tokens here", row: ["x", "y"])
        XCTAssertEqual(result, "No tokens here")
    }

    func testSubstituteString_tokenBeyondColumns_leftAsIs() {
        // $3 when row only has 2 columns - no replacement
        let result = TemplateHelper.substituteString("$3", row: ["a", "b"])
        XCTAssertEqual(result, "$3")
    }

    func testSubstituteString_emptyRow() {
        let result = TemplateHelper.substituteString("$0 $1", row: [])
        XCTAssertEqual(result, " $1") // $0 -> "" (empty join), $1 has no match
    }

    func testSubstituteString_multiDigitColumns_notCorruptedByLowerIndex() {
        // Regression: the old ordered replace turned "$10"/"$11" into "<col1>0"/"<col1>1".
        // A 12-column row must resolve $10/$11/$12 to columns 10/11/12, not $1 + a literal.
        let row = (1...12).map { "c\($0)" } // ["c1", ..., "c12"]
        XCTAssertEqual(TemplateHelper.substituteString("$10", row: row), "c10")
        XCTAssertEqual(TemplateHelper.substituteString("$11", row: row), "c11")
        XCTAssertEqual(TemplateHelper.substituteString("$12", row: row), "c12")
        XCTAssertEqual(TemplateHelper.substituteString("$1/$10/$2/$11", row: row), "c1/c10/c2/c11")
    }

    func testSubstituteString_columnValueContainingToken_notReSubstituted() {
        // A column whose value contains "$2" must be emitted literally (single pass).
        let result = TemplateHelper.substituteString("$1 then $2", row: ["has $2 inside", "B"])
        XCTAssertEqual(result, "has $2 inside then B")
    }

    // MARK: - substituteProperties

    func testSubstituteProperties_flatDict() {
        let props: [String: Any] = ["title": "$2", "systemImage": "$1"]
        let result = TemplateHelper.substituteProperties(props, row: ["star.fill", "Favorites"])
        XCTAssertEqual(result["title"] as? String, "Favorites")
        XCTAssertEqual(result["systemImage"] as? String, "star.fill")
    }

    func testSubstituteProperties_nestedDict() {
        let props: [String: Any] = ["font": ["name": "$1", "size": 14.0]]
        let result = TemplateHelper.substituteProperties(props, row: ["Menlo"])
        let font = result["font"] as? [String: Any]
        XCTAssertEqual(font?["name"] as? String, "Menlo")
        XCTAssertEqual(font?["size"] as? Double, 14.0) // non-string unchanged
    }

    func testSubstituteProperties_nonStringValuesUnchanged() {
        let props: [String: Any] = ["opacity": 0.5, "disabled": true, "count": 3]
        let result = TemplateHelper.substituteProperties(props, row: ["ignored"])
        XCTAssertEqual(result["opacity"] as? Double, 0.5)
        XCTAssertEqual(result["disabled"] as? Bool, true)
        XCTAssertEqual(result["count"] as? Int, 3)
    }

    func testSubstituteProperties_multipleTokensInOneString() {
        let props: [String: Any] = ["text": "$1 — $2 ($3)"]
        let result = TemplateHelper.substituteProperties(props, row: ["Alice", "Engineer", "Platform"])
        XCTAssertEqual(result["text"] as? String, "Alice — Engineer (Platform)")
    }

    // MARK: - The column reference pattern

    // Matched by Unicode scalar, as NSRegularExpression matched: a combining mark after the digits
    // does not stop the reference (it stays after the substituted text).
    func testSubstituteString_combiningMarkAfterDigits() {
        XCTAssertEqual(TemplateHelper.substituteString("$1\u{301}", row: ["e"]), "e\u{301}")
    }

    // U+0600 is a prepended character: it forms one Character with the "$" after it.
    func testSubstituteString_prependedCharacterBeforeDollar() {
        XCTAssertEqual(TemplateHelper.substituteString("\u{0600}$1", row: ["a"]), "\u{0600}a")
    }

    func testSubstituteString_numberTooLargeForInt_leftAsIs() {
        XCTAssertEqual(TemplateHelper.substituteString("$99999999999999999999", row: ["a"]), "$99999999999999999999")
    }

    func testSubstituteString_dollarWithoutDigits_leftAsIs() {
        XCTAssertEqual(TemplateHelper.substituteString("cost: $ and $x", row: ["a"]), "cost: $ and $x")
    }

    func testSingleColumnIndex() {
        XCTAssertEqual(TemplateHelper.singleColumnIndex("$1"), 0)
        XCTAssertEqual(TemplateHelper.singleColumnIndex("$12"), 11)
        XCTAssertNil(TemplateHelper.singleColumnIndex("$0"), "$0 names all columns, not one")
        XCTAssertNil(TemplateHelper.singleColumnIndex("$1 "))
        XCTAssertNil(TemplateHelper.singleColumnIndex(" $1"))
        XCTAssertNil(TemplateHelper.singleColumnIndex("$1$2"))
        XCTAssertNil(TemplateHelper.singleColumnIndex(1))
    }
}
