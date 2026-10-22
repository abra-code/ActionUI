// Tests/Styling/SymbolNamesTests.swift
/*
 Tests for SymbolNames: every icon the table names is in the icon theme GTK uses (Adwaita and
 libadwaita's own); filled and enclosed variants fall back to the plain name; an icon theme name
 passes through; an unknown name shows image-missing.
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

    func testEveryIconOfTheTableIsInTheTheme() {
        let missing = SymbolNames.table.filter { !Image.hasThemeIcon($0.value + "-symbolic") }
        XCTAssertEqual(missing.map { "\($0.key) -> \($0.value)" }.sorted(), [])
    }

    func testFilledAndEnclosedVariantsFallBackToThePlainName() {
        XCTAssertEqual(SymbolNames.lookup("plus.circle.fill"), "list-add-symbolic")
        XCTAssertEqual(SymbolNames.lookup("envelope.fill"), "mail-unread-symbolic")
        XCTAssertEqual(SymbolNames.lookup("trash.square"), "user-trash-symbolic")
        // Adwaita's filled star is its own icon.
        XCTAssertEqual(SymbolNames.lookup("star"), "non-starred-symbolic")
        XCTAssertEqual(SymbolNames.lookup("star.fill"), "starred-symbolic")
        XCTAssertEqual(SymbolNames.lookup("star.circle.fill"), "starred-symbolic")
    }

    func testThemeNamesPassAndUnknownNamesShowImageMissing() {
        XCTAssertEqual(SymbolNames.lookup("document-save-symbolic"), "document-save-symbolic")
        XCTAssertNil(SymbolNames.lookup("a.circle"))
        XCTAssertEqual(SymbolNames.iconName("example.unmapped.symbol"), SymbolNames.missing)
    }
}
