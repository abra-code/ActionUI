// Tests/Styling/SymbolIconsTests.swift
/*
 Tests for SymbolIcons: the icon resource the build compiles into the library registers, its table
 gives an icon name for every row, and the icon theme has every one of those icons (so the generator
 and the library agree on the names); a name the Material map lacks gets its Fluent glyph, and a
 name both maps have gets Material's.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class SymbolIconsTests: XCTestCase {
    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
    }

    func testTheCompiledInTableHasARowForCommonAndRenamedSymbols() {
        XCTAssertTrue(SymbolIcons.register())
        let names = SymbolIcons.names
        XCTAssertGreaterThan(names.count, 4000)
        for symbol in ["plus", "trash", "star.fill", "gearshape", "doc", "document", "mic", "list.bullet.page.fill"] {
            XCTAssertTrue(names[symbol]?.hasPrefix("actionui-material-") ?? false, "\(symbol) -> \(names[symbol] ?? "nil")")
        }
        // An old SF name has the row of its current name.
        XCTAssertEqual(names["doc"], names["document"])
        XCTAssertEqual(names["mic"], names["microphone"])
        XCTAssertNil(names["not.a.symbol"])
    }

    func testANameMaterialLacksIsItsFluentGlyph() {
        let names = SymbolIcons.names
        XCTAssertEqual(names["barometer"], "actionui-fluent-e973-symbolic")
        XCTAssertEqual(names["cube.transparent"], "actionui-fluent-e5f5-symbolic")
        XCTAssertEqual(names["ring.dashed"], "actionui-fluent-e49e-symbolic")
        // A filled face is a glyph of its own.
        XCTAssertEqual(names["key.card.fill"], "actionui-fluent-ee46-symbolic")
    }

    func testANameBothMapsHaveIsMaterials() {
        // bag.fill.badge.plus is in sf_to_fluent.map too.
        let name = SymbolIcons.names["bag.fill.badge.plus"]
        XCTAssertTrue(name?.hasPrefix("actionui-material-") ?? false, name ?? "nil")
    }

    func testEveryIconOfTheTableIsInTheIconTheme() throws {
        let display = try XCTUnwrap(gdk_display_get_default())
        SymbolIcons.addToIconTheme()
        let theme = gtk_icon_theme_get_for_display(display)
        let missing = Set(SymbolIcons.names.values).filter { gtk_icon_theme_has_icon(theme, $0) == 0 }
        XCTAssertEqual(missing.sorted(), [])
    }

    func testTableRowsAreNameAndIcon() {
        let names = SymbolIcons.parseTable("""
            # a comment
            star actionui-material-f09a-f0-w200-symbolic
            barometer actionui-fluent-e973-symbolic
            bad
            too many words
            """)
        XCTAssertEqual(names, [
            "star": "actionui-material-f09a-f0-w200-symbolic",
            "barometer": "actionui-fluent-e973-symbolic",
        ])
    }

    /// GTK recolors only icons it takes as symbolic (from the "-symbolic" name).
    func testAnIconIsSymbolic() throws {
        let display = try XCTUnwrap(gdk_display_get_default())
        let theme = gtk_icon_theme_get_for_display(display)
        for symbol in ["star.fill", "barometer"] {
            let name = try XCTUnwrap(SymbolIcons.iconName(symbol))
            let paintable = try XCTUnwrap(gtk_icon_theme_lookup_icon(theme, name, nil, 32, 1, GTK_TEXT_DIR_LTR, GtkIconLookupFlags(0)))
            defer { g_object_unref(UnsafeMutableRawPointer(paintable)) }
            XCTAssertTrue(gtk_icon_paintable_is_symbolic(paintable) != 0, symbol)
        }
    }
}
