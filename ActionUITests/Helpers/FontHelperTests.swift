// Tests/Helpers/FontHelperTests.swift
/*
 FontHelperTests.swift

 Tests for FontHelper.resolveFont covering named text styles (String form)
 and dictionary form with name, size, weight, and design parameters.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class FontHelperTests: XCTestCase {
    private var logger: XCTestLogger!

    override func setUp() {
        super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
    }

    override func tearDown() {
        logger = nil
        super.tearDown()
    }

    // MARK: - String form: named text styles

    func testNamedTextStyles() {
        XCTAssertEqual(FontHelper.resolveFont("body", logger), .body)
        XCTAssertEqual(FontHelper.resolveFont("title", logger), .title)
        XCTAssertEqual(FontHelper.resolveFont("title2", logger), .title2)
        XCTAssertEqual(FontHelper.resolveFont("title3", logger), .title3)
        XCTAssertEqual(FontHelper.resolveFont("headline", logger), .headline)
        XCTAssertEqual(FontHelper.resolveFont("subheadline", logger), .subheadline)
        XCTAssertEqual(FontHelper.resolveFont("callout", logger), .callout)
        XCTAssertEqual(FontHelper.resolveFont("caption", logger), .caption)
        XCTAssertEqual(FontHelper.resolveFont("caption2", logger), .caption2)
        XCTAssertEqual(FontHelper.resolveFont("footnote", logger), .footnote)
        XCTAssertEqual(FontHelper.resolveFont("largeTitle", logger), .largeTitle)
    }

    // MARK: - String form: custom font name

    func testPlainFontName() {
        let font = FontHelper.resolveFont("Menlo", logger)
        let expected = Font.custom("Menlo", size: FontHelper.bodyFontSize, relativeTo: .body)
        XCTAssertEqual(font, expected, "Plain font name should use body font size")
    }

    // MARK: - Dictionary form: system font

    func testDictSystemFontSizeOnly() {
        let dict: [String: Any] = ["size": 14]
        let font = FontHelper.resolveFont(dict, logger)
        XCTAssertEqual(font, Font.system(size: 14, design: .default))
    }

    func testDictSystemFontWithDesign() {
        let dict: [String: Any] = ["size": 12, "design": "monospaced"]
        let font = FontHelper.resolveFont(dict, logger)
        XCTAssertEqual(font, Font.system(size: 12, design: .monospaced))
    }

    func testDictSystemFontWithRoundedDesign() {
        let dict: [String: Any] = ["size": 16, "design": "rounded"]
        let font = FontHelper.resolveFont(dict, logger)
        XCTAssertEqual(font, Font.system(size: 16, design: .rounded))
    }

    func testDictSystemFontWithSerifDesign() {
        let dict: [String: Any] = ["size": 14, "design": "serif"]
        let font = FontHelper.resolveFont(dict, logger)
        XCTAssertEqual(font, Font.system(size: 14, design: .serif))
    }

    func testDictSystemFontWithWeight() {
        let dict: [String: Any] = ["size": 14, "weight": "bold"]
        let font = FontHelper.resolveFont(dict, logger)
        XCTAssertEqual(font, Font.system(size: 14, design: .default).weight(.bold))
    }

    func testDictSystemFontWithWeightAndDesign() {
        let dict: [String: Any] = ["size": 14, "weight": "semibold", "design": "monospaced"]
        let font = FontHelper.resolveFont(dict, logger)
        XCTAssertEqual(font, Font.system(size: 14, design: .monospaced).weight(.semibold))
    }

    // MARK: - Dictionary form: custom named font

    func testDictCustomFont() {
        let dict: [String: Any] = ["name": "Menlo", "size": 12]
        let font = FontHelper.resolveFont(dict, logger)
        XCTAssertEqual(font, Font.custom("Menlo", size: 12))
    }

    func testDictCustomFontWithWeight() {
        let dict: [String: Any] = ["name": "Helvetica Neue", "size": 16, "weight": "light"]
        let font = FontHelper.resolveFont(dict, logger)
        XCTAssertEqual(font, Font.custom("Helvetica Neue", size: 16).weight(.light))
    }

    // MARK: - Dictionary form: missing size

    func testDictMissingSizeDefaultsToBody() {
        let dict: [String: Any] = ["name": "Menlo"]
        let font = FontHelper.resolveFont(dict, logger)
        XCTAssertEqual(font, .body, "Missing size should default to body")
    }

    // MARK: - Dictionary form: all weights

    func testDictAllWeights() {
        let weights: [(String, Font.Weight)] = [
            ("ultraLight", .ultraLight), ("thin", .thin), ("light", .light),
            ("regular", .regular), ("medium", .medium), ("semibold", .semibold),
            ("bold", .bold), ("heavy", .heavy), ("black", .black)
        ]
        for (name, weight) in weights {
            let dict: [String: Any] = ["size": 14, "weight": name]
            let font = FontHelper.resolveFont(dict, logger)
            XCTAssertEqual(font, Font.system(size: 14, design: .default).weight(weight), "Weight '\(name)' should resolve")
        }
    }

    // MARK: - Invalid input

    func testNilDefaultsToBody() {
        XCTAssertEqual(FontHelper.resolveFont(nil, logger), .body)
    }

    func testNonStringNonDictDefaultsToBody() {
        XCTAssertEqual(FontHelper.resolveFont(123, logger), .body)
    }

    func testDictUnknownWeightIgnored() {
        let dict: [String: Any] = ["size": 14, "weight": "extraBold"]
        let font = FontHelper.resolveFont(dict, logger)
        XCTAssertEqual(font, Font.system(size: 14, design: .default), "Unknown weight should be ignored")
    }

    func testDictUnknownDesignDefaultsToDefault() {
        let dict: [String: Any] = ["size": 14, "design": "fancy"]
        let font = FontHelper.resolveFont(dict, logger)
        XCTAssertEqual(font, Font.system(size: 14, design: .default), "Unknown design should default to .default")
    }
}
