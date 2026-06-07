package com.abracode.actionui.Helpers

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the pure parser of `SystemSymbolResolver.kt` -
 * [parseSystemSymbolMap]. The asset load + cache ([systemSymbol]) needs an
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
}
