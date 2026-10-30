// Tests/Styling/SymbolNamesTests.swift
/*
 Tests for SymbolNames: an SF Symbol name is the Material Symbols icon of its map row, which the icon
 theme has; the lookup is the exact name, as on Android and Web, with no fallback to a shorter name;
 an icon theme name passes through; an unknown name shows image-missing.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class SymbolNamesTests: XCTestCase {
    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
    }

    func testCommonSymbolsAreMaterialIconsOfTheTheme() {
        let common = ["star", "star.fill", "plus", "trash", "folder", "gear", "magnifyingglass", "xmark",
                      "chevron.right", "square.and.arrow.up", "doc.on.doc", "person.crop.circle", "photo"]
        for symbol in common {
            let icon = SymbolNames.lookup(symbol)
            XCTAssertEqual(icon, MaterialSymbols.iconName(symbol), symbol)
            XCTAssertTrue(icon?.hasPrefix("actionui-material-") ?? false, "\(symbol) -> \(icon ?? "nil")")
            XCTAssertTrue(icon.map { Image.hasThemeIcon($0) } ?? false, "\(symbol): not in the icon theme")
        }
        // A filled variant is its own row: the same glyph at fill 1.
        XCTAssertNotEqual(SymbolNames.lookup("star"), SymbolNames.lookup("star.fill"))
    }

    func testTheLookupIsTheExactName() {
        // The map has star.fill and star, but not star.square.fill: no shorter name is tried.
        XCTAssertNil(SymbolNames.lookup("star.square.fill"))
        XCTAssertNil(SymbolNames.lookup("a.circle"))
    }

    func testThemeNamesPassAndUnknownNamesShowImageMissing() {
        XCTAssertEqual(SymbolNames.lookup("document-save-symbolic"), "document-save-symbolic")
        XCTAssertEqual(SymbolNames.iconName("example.unmapped.symbol"), SymbolNames.missing)
    }
}
