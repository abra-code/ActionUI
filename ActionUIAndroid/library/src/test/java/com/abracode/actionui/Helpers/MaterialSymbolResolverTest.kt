package com.abracode.actionui.Helpers

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

/**
 * Unit tests for the pure Material Symbol helpers: [parseCodepoints] (the
 * name->codepoint table parser) and [materialVariationSettings] (the
 * font-variation-settings string). The asset-bound [materialCodepoint] and the
 * Composable [MaterialSymbolGlyph] are exercised via the demo / instrumentation,
 * the stance the other resolver tests take for framework-bound code.
 */
class MaterialSymbolResolverTest {

    // -----------------------------------------------------------------------
    // parseCodepoints
    // -----------------------------------------------------------------------

    @Test
    fun `parses name and lowercase hex codepoint`() {
        val map = parseCodepoints("home e88a\nsettings e8b8")
        assertEquals(0xE88A, map["home"])
        assertEquals(0xE8B8, map["settings"])
        assertEquals(2, map.size)
    }

    @Test
    fun `names may start with digits`() {
        // Real entries in the table, e.g. "10k", "123".
        val map = parseCodepoints("10k e951\n123 eb8d")
        assertEquals(0xE951, map["10k"])
        assertEquals(0xEB8D, map["123"])
    }

    @Test
    fun `blank lines are skipped`() {
        val map = parseCodepoints("\nhome e88a\n\n   \nsettings e8b8\n")
        assertEquals(2, map.size)
        assertEquals(0xE88A, map["home"])
    }

    @Test
    fun `lines without a codepoint are skipped`() {
        val map = parseCodepoints("home\njustaname\nsettings e8b8")
        assertEquals(1, map.size)
        assertNull(map["home"])
        assertEquals(0xE8B8, map["settings"])
    }

    @Test
    fun `lines with non-hex codepoint are skipped`() {
        val map = parseCodepoints("home zzzz\nsettings e8b8")
        assertNull(map["home"])
        assertEquals(0xE8B8, map["settings"])
    }

    @Test
    fun `surrounding and trailing whitespace is tolerated`() {
        val map = parseCodepoints("  home   e88a  \n\tsettings e8b8")
        assertEquals(0xE88A, map["home"])
        assertEquals(0xE8B8, map["settings"])
    }

    @Test
    fun `empty input yields empty map`() {
        assertTrue(parseCodepoints("").isEmpty())
    }

    // -----------------------------------------------------------------------
    // materialVariationSettings
    // -----------------------------------------------------------------------

    @Test
    fun `variation settings string has all four axes`() {
        val s = materialVariationSettings(weight = 400, fill = 1f, grade = 0, opsz = 24f)
        assertEquals("'wght' 400, 'FILL' 1.000, 'GRAD' 0, 'opsz' 24.0", s)
    }

    @Test
    fun `variation settings uses a dot decimal regardless of default locale`() {
        // A comma-decimal locale (e.g. Germany) must not produce "'FILL' 1,000".
        val previous = Locale.getDefault()
        try {
            Locale.setDefault(Locale.GERMANY)
            val s = materialVariationSettings(weight = 300, fill = 0.5f, grade = -25, opsz = 20f)
            assertEquals("'wght' 300, 'FILL' 0.500, 'GRAD' -25, 'opsz' 20.0", s)
        } finally {
            Locale.setDefault(previous)
        }
    }
}
