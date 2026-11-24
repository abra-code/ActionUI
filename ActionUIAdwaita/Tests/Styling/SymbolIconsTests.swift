// Tests/Styling/MaterialSymbolsTests.swift
/*
 Tests for MaterialSymbols: the icon resource the build compiles into the library registers, its
 map gives an icon name for every row, and the icon theme has every one of those icons (so the
 generator and the library agree on the names); a row's fill and weight make the name.
*/

import XCTest
import CAdwaita
@testable import ActionUI

@MainActor
final class MaterialSymbolsTests: XCTestCase {
    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
    }

    func testTheCompiledInMapHasARowForCommonAndRenamedSymbols() {
        XCTAssertTrue(MaterialSymbols.register())
        let names = MaterialSymbols.names
        XCTAssertGreaterThan(names.count, 3000)
        for symbol in ["plus", "trash", "star.fill", "gearshape", "doc", "document", "mic", "list.bullet.page.fill"] {
            XCTAssertNotNil(names[symbol], symbol)
        }
        // An old SF name has the row of its current name.
        XCTAssertEqual(names["doc"], names["document"])
        XCTAssertEqual(names["mic"], names["microphone"])
        XCTAssertNil(names["not.a.symbol"])
    }

    func testEveryIconOfTheMapIsInTheIconTheme() throws {
        let display = try XCTUnwrap(gdk_display_get_default())
        MaterialSymbols.addToIconTheme()
        let theme = gtk_icon_theme_get_for_display(display)
        let missing = Set(MaterialSymbols.names.values).filter { gtk_icon_theme_has_icon(theme, $0) == 0 }
        XCTAssertEqual(missing.sorted(), [])
    }

    func testIconNameComesFromTheRowsFillAndWeight() {
        let names = MaterialSymbols.parseMap("""
            # a comment
            star f09a 200
            star.fill f09a 1
            pencil f097 1 100
            plus e145
            bad zzzz
            """)
        XCTAssertEqual(names, [
            "star": "actionui-material-f09a-f0-w200-symbolic",
            "star.fill": "actionui-material-f09a-f1-w400-symbolic",
            "pencil": "actionui-material-f097-f1-w100-symbolic",
            "plus": "actionui-material-e145-f0-w400-symbolic",
        ])
    }

    /// GTK recolors only icons it takes as symbolic (from the "-symbolic" name).
    func testAnIconIsSymbolic() throws {
        let display = try XCTUnwrap(gdk_display_get_default())
        let name = try XCTUnwrap(MaterialSymbols.iconName("star.fill"))
        let theme = gtk_icon_theme_get_for_display(display)
        let paintable = try XCTUnwrap(gtk_icon_theme_lookup_icon(theme, name, nil, 32, 1, GTK_TEXT_DIR_LTR, GtkIconLookupFlags(0)))
        defer { g_object_unref(UnsafeMutableRawPointer(paintable)) }
        XCTAssertTrue(gtk_icon_paintable_is_symbolic(paintable) != 0)
    }
}
