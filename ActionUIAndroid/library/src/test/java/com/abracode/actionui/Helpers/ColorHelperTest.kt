package com.abracode.actionui.Helpers

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Unit tests for [parseColor] / [colorToHex] in `ColorHelper.kt` - the named-color
 * and hex vocabulary shared by the universal `background` modifier, the shape
 * `fill`/`stroke` resolver, and the `ColorPicker` / `COLOR` value bridge. The
 * Android counterpart of Apple's `ColorHelperTests.swift`. Hex is the canonical
 * Apple byte order (`#RRGGBBAA`, alpha last).
 */
class ColorHelperTest {

    @Test
    fun `parseColor recognizes named colors`() {
        assertEquals(Color.Red, parseColor("red"))
        assertEquals(Color.Black, parseColor("black"))
        assertEquals(Color.White, parseColor("white"))
        assertEquals(Color.Blue, parseColor("blue"))
        assertEquals(Color.Green, parseColor("green"))
        assertEquals(Color.Gray, parseColor("gray"))
        assertEquals(Color.Gray, parseColor("grey"))
        assertEquals(Color.LightGray, parseColor("lightgray"))
        assertEquals(Color.DarkGray, parseColor("darkgrey"))
        assertEquals(Color.Transparent, parseColor("transparent"))
        assertEquals(Color.Transparent, parseColor("clear"))
        assertEquals(Color.Yellow, parseColor("yellow"))
    }

    @Test
    fun `parseColor recognizes the canonical Apple named colors`() {
        assertEquals(Color(0xFF3EB489.toInt()), parseColor("mint"))
        assertEquals(Color(0xFF008080.toInt()), parseColor("teal"))
        assertEquals(Color(0xFF4B0082.toInt()), parseColor("indigo"))
        assertEquals(Color(0xFFA52A2A.toInt()), parseColor("brown"))
    }

    @Test
    fun `parseColor is case insensitive`() {
        assertEquals(Color.Red, parseColor("Red"))
        assertEquals(Color.Red, parseColor("RED"))
        assertEquals(Color.Blue, parseColor("Blue"))
    }

    @Test
    fun `parseColor trims whitespace`() {
        assertEquals(Color.Red, parseColor("  red  "))
    }

    @Test
    fun `parseColor handles RRGGBB hex with implicit alpha`() {
        assertEquals(Color(0xFFFF0000.toInt()), parseColor("#FF0000"))
        assertEquals(Color(0xFF00FF00.toInt()), parseColor("#00FF00"))
        assertEquals(Color(0xFF0000FF.toInt()), parseColor("#0000FF"))
    }

    @Test
    fun `parseColor handles RRGGBBAA hex with alpha last`() {
        // Canonical Apple order: red=80, green=FF, blue=00, alpha=00 (fully transparent).
        assertEquals(Color(red = 0x80, green = 0xFF, blue = 0x00, alpha = 0x00), parseColor("#80FF0000"))
        assertEquals(Color(red = 0xFF, green = 0x00, blue = 0x00, alpha = 0x80), parseColor("#FF000080"))
        assertEquals(Color(0x00000000), parseColor("#00000000"))
    }

    @Test
    fun `parseColor handles 3 and 4 digit shorthand hex`() {
        assertEquals(Color(0xFFFF0000.toInt()), parseColor("#F00"))           // #RGB -> #FF0000
        assertEquals(Color(0xFF00FF00.toInt()), parseColor("#0F0"))
        assertEquals(Color(red = 0xFF, green = 0x00, blue = 0x00, alpha = 0xFF), parseColor("#F00F")) // #RGBA, opaque
        assertEquals(Color(red = 0xFF, green = 0x00, blue = 0x00, alpha = 0x00), parseColor("#F000")) // #RGBA, transparent
    }

    @Test
    fun `colorToHex round-trips through parseColor`() {
        assertEquals("#FF0000", colorToHex(Color.Red))
        assertEquals("#00FF00", colorToHex(Color.Green))
        assertEquals("#FF000080", colorToHex(Color(red = 0xFF, green = 0x00, blue = 0x00, alpha = 0x80)))
        assertEquals(parseColor("#1A2B3C"), parseColor(colorToHex(parseColor("#1A2B3C")!!)))
    }

    @Test
    fun `parseColor returns null for unknown name`() {
        assertNull(parseColor("magickaboo"))
        assertNull(parseColor(""))
    }

    @Test
    fun `parseColor returns null for malformed hex`() {
        assertNull(parseColor("#XYZ"))      // 3 chars but non-hex
        assertNull(parseColor("#12345"))    // 5 chars
        assertNull(parseColor("#1234567"))  // 7 chars
        assertNull(parseColor("#"))
    }
}
