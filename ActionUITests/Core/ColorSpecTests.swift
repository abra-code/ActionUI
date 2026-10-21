// Core/ColorSpecTests.swift
/*
 Tests for ColorSpec and ShapeStyleSpec: every form a document's color string can take, and the
 strings that describe no color.
*/

import XCTest
@testable import ActionUI

final class ColorSpecTests: XCTestCase {

    func testNamesIgnoreCaseAndWhiteSpace() {
        XCTAssertEqual(ColorSpec.parse("red"), .named(.red))
        XCTAssertEqual(ColorSpec.parse(" Red \n"), .named(.red))
        XCTAssertEqual(ColorSpec.parse("accentColor"), .named(.accentColor))
        XCTAssertEqual(ColorSpec.parse("ACCENTCOLOR"), .named(.accentColor))
        for name in ColorName.allCases {
            XCTAssertEqual(ColorSpec.parse(name.rawValue), .named(name), name.rawValue)
        }
        XCTAssertEqual(ColorName.allCases.count, 19)
    }

    func testHexForms() {
        XCTAssertEqual(ColorSpec.parse("#fff"), .rgba(red: 1, green: 1, blue: 1, alpha: 1))
        XCTAssertEqual(ColorSpec.parse("f00"), .rgba(red: 1, green: 0, blue: 0, alpha: 1), "The # is optional")
        XCTAssertEqual(ColorSpec.parse("#0F08"), .rgba(red: 0, green: 1, blue: 0, alpha: 8.0 / 15.0))
        XCTAssertEqual(ColorSpec.parse("#FF8800"), .rgba(red: 1, green: 136.0 / 255.0, blue: 0, alpha: 1))
        XCTAssertEqual(ColorSpec.parse("#ff880080"), .rgba(red: 1, green: 136.0 / 255.0, blue: 0, alpha: 128.0 / 255.0))
        XCTAssertEqual(ColorSpec.parse("##fff"), ColorSpec.parse("#fff"), "Every # is dropped, as before")
    }

    func testOpacity() {
        XCTAssertEqual(ColorSpec.parse("gray.opacity(0.15)"), .withOpacity(.named(.gray), 0.15))
        XCTAssertEqual(ColorSpec.parse("Red.opacity( 0.5 )"), .withOpacity(.named(.red), 0.5))
        XCTAssertEqual(ColorSpec.parse("#fff.opacity(0.5)"), .withOpacity(.rgba(red: 1, green: 1, blue: 1, alpha: 1), 0.5))
        XCTAssertEqual(ColorSpec.parse("red.opacity(2)"), .withOpacity(.named(.red), 1), "Clamped to 1")
        XCTAssertEqual(ColorSpec.parse("red.opacity(-1)"), .withOpacity(.named(.red), 0), "Clamped to 0")
        XCTAssertEqual(ColorSpec.parse("red.opacity(\n0.5\t)"), .withOpacity(.named(.red), 0.5), "Any white space around the fraction, line breaks too")
        XCTAssertNil(ColorSpec.parse("red.opacity(half)"))
        XCTAssertNil(ColorSpec.parse("nothing.opacity(0.5)"))
    }

    // The old parser read as many hex digits as it could and chose the form by the whole string's
    // length, so these gave unintended colors. They describe no color.
    func testStringsThatAreNoColor() {
        for text in ["", "#", "nope", "12zz34", "# fff", "0xfff", "0xffffff", "+fff", "-fff", "#ff", "#fffff",
                     "#fffffff", "#fffffffff", "\u{FF10}\u{FF10}\u{FF10}", "fff.opacity"] {
            XCTAssertNil(ColorSpec.parse(text), text)
        }
        XCTAssertNil(ColorSpec.parse(nil))
    }

    func testHexText() {
        XCTAssertEqual(ColorSpec.parse("#FF8800")?.hexText, "#FF8800")
        XCTAssertEqual(ColorSpec.parse("#ff880080")?.hexText, "#FF880080")
        XCTAssertEqual(ColorSpec.parse("#0f0")?.hexText, "#00FF00")
        XCTAssertNil(ColorSpec.parse("red")?.hexText, "A named color's components belong to the renderer")
        XCTAssertEqual(ColorSpec.parse("#ff0000.opacity(0.5)")?.hexText, "#FF00007F", "An opacity multiplies an rgba color's alpha")
        XCTAssertNil(ColorSpec.parse("red.opacity(0.5)")?.hexText)
        XCTAssertEqual(ColorSpec.rgba(red: .nan, green: .infinity, blue: 2, alpha: -1).hexText, "#00FFFF00", "Out of range components are clamped, never trap")
        XCTAssertEqual(PlainText.hex(0xAB, width: 4), "00AB")
        XCTAssertEqual(PlainText.hex(0, width: 2), "00")
    }

    func testShapeStyles() {
        XCTAssertEqual(ShapeStyleSpec.parse("background.secondary"), .style(.backgroundSecondary))
        XCTAssertEqual(ShapeStyleSpec.parse(" WindowBackground "), .style(.windowBackground))
        XCTAssertEqual(ShapeStyleSpec.parse("primary"), .style(.primary), "A semantic style before the color of that name")
        XCTAssertEqual(ShapeStyleSpec.parse("red"), .color(.named(.red)))
        XCTAssertEqual(ShapeStyleSpec.parse("#000"), .color(.rgba(red: 0, green: 0, blue: 0, alpha: 1)))
        XCTAssertNil(ShapeStyleSpec.parse("fill.quinary"))
        for name in ShapeStyleName.allCases {
            XCTAssertEqual(ShapeStyleSpec.parse(name.rawValue), .style(name), name.rawValue)
        }
        XCTAssertEqual(ShapeStyleName.allCases.count, 23)
    }
}
