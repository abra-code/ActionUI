// Tests/Styling/ColorCSSTests.swift
/*
 Tests for ColorCSS and FontCSS: colors, named colors and shape styles as CSS values, fractions
 written without exponents, fonts as libadwaita classes and declarations, and font names that
 cannot break out of their CSS string. No display needed.
*/

import XCTest
@testable import ActionUI

final class ColorCSSTests: XCTestCase {

    func testRGBAColors() {
        XCTAssertEqual(ColorCSS.value(.rgba(red: 1, green: 0, blue: 0.5, alpha: 1)), "rgba(255, 0, 128, 1)")
        XCTAssertEqual(ColorCSS.value(.rgba(red: 2, green: -1, blue: .nan, alpha: 0.25)), "rgba(255, 0, 0, 0.25)",
                       "components are clamped; NaN is 0")
    }

    func testFractionsHaveNoExponent() {
        XCTAssertEqual(ColorCSS.value(.rgba(red: 0, green: 0, blue: 0, alpha: 0.00001)), "rgba(0, 0, 0, 0)")
        XCTAssertEqual(ColorCSS.value(.rgba(red: 0, green: 0, blue: 0, alpha: 0.05)), "rgba(0, 0, 0, 0.05)")
        XCTAssertEqual(ColorCSS.value(.rgba(red: 0, green: 0, blue: 0, alpha: 0.123456)), "rgba(0, 0, 0, 0.123)")
    }

    func testNamedColorsFollowTheTheme() {
        XCTAssertEqual(ColorCSS.value(.named(.accentColor)), "var(--accent-color)")
        XCTAssertEqual(ColorCSS.value(.named(.blue)), "var(--blue-3)")
        XCTAssertEqual(ColorCSS.value(.named(.clear)), "transparent")
        XCTAssertEqual(ColorCSS.value(.named(.indigo)), "#5856d6")
        // Every name has a value.
        for name in ColorName.allCases {
            XCTAssertFalse(ColorCSS.value(.named(name)).isEmpty, "\(name)")
        }
    }

    func testOpacity() {
        XCTAssertEqual(ColorCSS.value(.withOpacity(.named(.red), 0.3)), "alpha(var(--red-3), 0.3)")
        XCTAssertEqual(ColorCSS.value(ColorSpec.parse("blue.opacity(0.5)")!), "alpha(var(--blue-3), 0.5)")
    }

    func testShapeStyles() {
        XCTAssertEqual(ColorCSS.value(ShapeStyleSpec.parse("fill.tertiary")!), "alpha(currentColor, 0.08)")
        XCTAssertEqual(ColorCSS.value(ShapeStyleSpec.parse("separator")!), "var(--border-color)")
        XCTAssertEqual(ColorCSS.value(ShapeStyleSpec.parse("#00FF00")!), "rgba(0, 255, 0, 1)")
        for name in ShapeStyleName.allCases {
            XCTAssertFalse(ColorCSS.value(name).isEmpty, "\(name)")
        }
    }

    func testTextStylesAreLibadwaitaClasses() {
        XCTAssertEqual(FontCSS.style(.textStyle(.largeTitle)).classes, ["title-1"])
        XCTAssertEqual(FontCSS.style(.textStyle(.headline)).classes, ["heading"])
        XCTAssertTrue(FontCSS.style(.textStyle(.body)).classes.isEmpty)
        XCTAssertEqual(FontCSS.style(.textStyle(.caption2)).declarations, ["font-size: 70%;"])
    }

    func testSizedFonts() {
        let menlo = FontCSS.style(.sized(name: "Menlo", size: 13, weight: .bold, design: .default))
        XCTAssertEqual(menlo.declarations, ["font-size: 13px;", "font-weight: 700;", #"font-family: "Menlo";"#])
        let mono = FontCSS.style(.sized(name: nil, size: 12, weight: nil, design: .monospaced))
        XCTAssertEqual(mono.classes, ["monospace"])
        XCTAssertEqual(mono.declarations, ["font-size: 12px;", "font-family: monospace;"])
        XCTAssertEqual(FontCSS.style(.sized(name: nil, size: -3, weight: nil, design: .default)).declarations, [],
                       "a size that is not positive is left out")
        XCTAssertEqual(FontCSS.style(.sized(name: nil, size: 12.5, weight: nil, design: .default)).declarations, ["font-size: 12.5px;"])
        XCTAssertEqual(FontCSS.style(.sized(name: nil, size: 1e9, weight: nil, design: .default)).declarations, ["font-size: 4096px;"],
                       "a size GTK cannot draw is capped")
        XCTAssertEqual(FontCSS.pixels(0.01), "0.1")
        XCTAssertEqual(FontCSS.style(.textStyle(.subheadline)).classes, [], "regular weight, not libadwaita's bold caption-heading")
    }

    func testAFontNameCannotEndItsCSSString() {
        XCTAssertEqual(FontCSS.quoted(#"Evil"; } * { color: red"#), #""Evil\"; } * { color: red""#)
        XCTAssertEqual(FontCSS.quoted("Back\\slash"), #""Back\\slash""#)
        XCTAssertEqual(FontCSS.quoted("One\nTwo"), #""One""#, "only the first line")
        XCTAssertEqual(FontCSS.quoted("Tab\tName"), #""TabName""#, "control characters are dropped")
    }
}
