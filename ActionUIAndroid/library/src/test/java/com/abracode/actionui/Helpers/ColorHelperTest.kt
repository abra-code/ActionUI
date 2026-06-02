package com.abracode.actionui.Helpers

import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Unit tests for [parseColor] in `ColorHelper.kt` - the named-color and hex
 * vocabulary shared by the universal `background` modifier and the shape
 * `fill`/`stroke` resolver. The Android counterpart of Apple's
 * `ColorHelperTests.swift`.
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
    fun `parseColor handles AARRGGBB hex including transparency`() {
        assertEquals(Color(0x80FF0000.toInt()), parseColor("#80FF0000"))
        assertEquals(Color(0x00000000), parseColor("#00000000"))
    }

    @Test
    fun `parseColor returns null for unknown name`() {
        assertNull(parseColor("magickaboo"))
        assertNull(parseColor(""))
    }

    @Test
    fun `parseColor returns null for malformed hex`() {
        assertNull(parseColor("#XYZ"))
        assertNull(parseColor("#12345"))   // 5 chars
        assertNull(parseColor("#1234567"))  // 7 chars
        assertNull(parseColor("#"))
    }
}
