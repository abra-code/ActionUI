package com.abracode.actionui.Helpers

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the pure parts of `SystemSymbolResolver.kt` -
 * [parseSystemSymbolMap] and [withFluentRows] - and for the committed
 * Tools/fluent_symbols/sf_to_fluent.map the build packages. The asset load + cache ([systemSymbol]) needs an
 * [android.content.res.AssetManager], so it is exercised via the demo, the same
 * stance the other resolver tests take for framework-bound code.
 */
class SystemSymbolResolverTest {

    @Test
    fun `parses name and codepoint with no axes`() {
        val map = parseSystemSymbolMap("magnifyingglass ef7a\n")
        assertEquals(SystemSymbolEntry(0xEF7A, false, null), map["magnifyingglass"])
    }

    @Test
    fun `reads the fill token`() {
        val map = parseSystemSymbolMap("heart.fill e87d 1\n")
        assertEquals(SystemSymbolEntry(0xE87D, true, null), map["heart.fill"])
    }

    @Test
    fun `reads the weight token by range`() {
        val map = parseSystemSymbolMap("gearshape e8b8 600\n")
        assertEquals(SystemSymbolEntry(0xE8B8, false, 600), map["gearshape"])
    }

    @Test
    fun `reads fill and weight together regardless of token order`() {
        // Tokens are identified by value range, not position.
        assertEquals(SystemSymbolEntry(0xABCD, true, 500), parseSystemSymbolMap("a abcd 1 500\n")["a"])
        assertEquals(SystemSymbolEntry(0xABCD, true, 500), parseSystemSymbolMap("a abcd 500 1\n")["a"])
    }

    @Test
    fun `skips comment and blank lines`() {
        val map = parseSystemSymbolMap("# header\n\n   \nhome e9b2\n")
        assertEquals(1, map.size)
        assertEquals(SystemSymbolEntry(0xE9B2, false, null), map["home"])
    }

    @Test
    fun `skips rows without a valid hex codepoint`() {
        val map = parseSystemSymbolMap("broken\nbad zzzz\nhome e9b2\n")
        assertEquals(setOf("home"), map.keys)
    }

    @Test
    fun `ignores an out-of-range trailing token but keeps the row`() {
        // 50 is neither fill (1) nor a valid weight (100..700); the glyph still resolves.
        val map = parseSystemSymbolMap("x e001 50\n")
        assertEquals(SystemSymbolEntry(0xE001, false, null), map["x"])
    }

    @Test
    fun `empty text yields an empty map`() {
        assertTrue(parseSystemSymbolMap("").isEmpty())
    }

    @Test
    fun `fluent rows fill only the names material lacks`() {
        val material = parseSystemSymbolMap("star f09a 200\nheart.fill e87d 1\n")
        val merged = withFluentRows(material, "# comment\nstar e001\nbarometer e973\n")
        assertEquals(SystemSymbolEntry(0xF09A, false, 200), merged["star"])
        assertEquals(SystemSymbolEntry(0xE87D, true, null), merged["heart.fill"])
        assertEquals(SystemSymbolEntry(0xE973, false, null, SymbolFont.FLUENT), merged["barometer"])
        assertNull(merged["not.a.symbol"])
        assertEquals(material, withFluentRows(material, ""))
    }

    @Test
    fun `the fluent map fills in the symbols material lacks from the fluent font`() {
        // Unit tests run in the module folder. The build packages this map unchanged.
        val material = parseSystemSymbolMap(File("src/main/assets/symbols/sf_to_material.map").readText())
        val merged = withFluentRows(material, File("../../Tools/fluent_symbols/sf_to_fluent.map").readText())
        val fluent = merged.filterValues { it.font == SymbolFont.FLUENT }
        assertTrue(fluent.size > 800)
        assertTrue(fluent.keys.none { it in material })
        assertTrue(fluent.values.all { !it.fill && it.weight == null })
        assertTrue(material.all { (name, entry) -> merged[name] == entry })
        // A few the Linux and Windows renderers draw from Fluent too, at the Fluent font's own code points.
        assertEquals(0xE973, fluent["barometer"]?.codepoint)
        for (name in listOf("cube.transparent", "ring.dashed", "key.card.fill")) {
            assertTrue(name, name in fluent)
        }
    }
}
