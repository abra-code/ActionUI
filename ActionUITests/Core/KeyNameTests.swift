// Core/KeyNameTests.swift
/*
 Tests for KeyName: the special key names (any case), single characters, and what names no key.
*/

import XCTest
@testable import ActionUI

final class KeyNameTests: XCTestCase {

    func testSpecialKeysInAnyCase() {
        XCTAssertEqual(KeyName.parse("return"), .return)
        XCTAssertEqual(KeyName.parse("Return"), .return)
        XCTAssertEqual(KeyName.parse("upArrow"), .upArrow)
        XCTAssertEqual(KeyName.parse("UPARROW"), .upArrow)
        XCTAssertEqual(KeyName.parse("deleteForward"), .deleteForward)
        XCTAssertEqual(KeyName.parse("pageDown"), .pageDown)
        XCTAssertEqual(KeyName.parse("space"), .space)
        XCTAssertEqual(KeyName.specialCount, 15)
    }

    func testSingleCharacters() {
        XCTAssertEqual(KeyName.parse("s"), .character("s"))
        XCTAssertEqual(KeyName.parse("S"), .character("S"), "A character keeps its case")
        XCTAssertEqual(KeyName.parse("1"), .character("1"))
        XCTAssertEqual(KeyName.parse("/"), .character("/"))
        XCTAssertEqual(KeyName.parse("e\u{301}"), .character("e\u{301}"), "One character, two scalars")
    }

    func testNamesOfNoKey() {
        for text in ["", "ab", "enter", "up arrow", "ret"] {
            XCTAssertNil(KeyName.parse(text), text)
        }
    }
}
