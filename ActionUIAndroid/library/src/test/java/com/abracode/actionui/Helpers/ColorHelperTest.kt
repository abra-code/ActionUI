package com.abracode.actionui.Helpers

import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
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

    // --- HSV conversion (the ColorPicker free-form dialog) ---

    // Compose's sRGB Color packs each channel at 8-bit precision, so a component
    // round-trips to within 1/255 (~0.004), not exactly - hence the tolerance.
    private fun assertHsvEquals(expected: Hsv, actual: Hsv, tol: Float = 0.004f) {
        assertEquals(expected.hue, actual.hue, tol)
        assertEquals(expected.saturation, actual.saturation, tol)
        assertEquals(expected.value, actual.value, tol)
    }

    private fun assertColorEquals(expected: Color, actual: Color, tol: Float = 0.004f) {
        assertEquals(expected.red, actual.red, tol)
        assertEquals(expected.green, actual.green, tol)
        assertEquals(expected.blue, actual.blue, tol)
        assertEquals(expected.alpha, actual.alpha, tol)
    }

    @Test
    fun `toHsv decomposes the primaries`() {
        assertHsvEquals(Hsv(0f, 1f, 1f), Color.Red.toHsv())
        assertHsvEquals(Hsv(120f, 1f, 1f), Color.Green.toHsv())
        assertHsvEquals(Hsv(240f, 1f, 1f), Color.Blue.toHsv())
    }

    @Test
    fun `toHsv reports zero hue and saturation for grayscale`() {
        // Black: value and saturation both 0; white: full value, no saturation;
        // mid gray: half value, no saturation. Hue is undefined -> 0 by convention.
        assertHsvEquals(Hsv(0f, 0f, 0f), Color.Black.toHsv())
        assertHsvEquals(Hsv(0f, 0f, 1f), Color.White.toHsv())
        assertHsvEquals(Hsv(0f, 0f, 0.5f), Color(0.5f, 0.5f, 0.5f).toHsv())
    }

    @Test
    fun `hsvToColor builds the primaries`() {
        assertColorEquals(Color.Red, hsvToColor(0f, 1f, 1f))
        assertColorEquals(Color.Green, hsvToColor(120f, 1f, 1f))
        assertColorEquals(Color.Blue, hsvToColor(240f, 1f, 1f))
        assertColorEquals(Color.White, hsvToColor(0f, 0f, 1f))
        assertColorEquals(Color.Black, hsvToColor(123f, 0.5f, 0f))
    }

    @Test
    fun `hsvToColor wraps hue and clamps the fractions`() {
        // 360 wraps to 0 (red); negative hue wraps too; out-of-range s/v/a clamp.
        assertColorEquals(Color.Red, hsvToColor(360f, 1f, 1f))
        assertColorEquals(Color.Red, hsvToColor(-360f, 1f, 1f))
        assertColorEquals(Color.Red, hsvToColor(0f, 2f, 2f, 2f))
    }

    @Test
    fun `toHsv and hsvToColor round-trip an arbitrary chromatic color`() {
        // A saturated orange has a recoverable hue, so RGB->HSV->RGB is lossless.
        val orange = parseColor("#FF8800")!!
        val hsv = orange.toHsv()
        assertColorEquals(orange, hsvToColor(hsv.hue, hsv.saturation, hsv.value, orange.alpha))
    }

    @Test
    fun `hsvToColor preserves alpha`() {
        assertEquals(0.5f, hsvToColor(0f, 1f, 1f, 0.5f).alpha, 0.004f)
        assertEquals(0f, hsvToColor(0f, 1f, 1f, 0f).alpha, 0.004f)
    }

    @Test
    fun `parseColor handles the SwiftUI opacity suffix`() {
        // `<color>.opacity(<fraction>)`: resolve the base color and scale its alpha.
        val gray = parseColor("gray.opacity(0.15)")!!
        assertEquals(0.15f, gray.alpha, 0.004f)
        assertEquals(Color.Gray.red, gray.red, 0.004f)
        assertEquals(0.5f, parseColor("red.opacity(0.5)")!!.alpha, 0.004f)
        assertNull(parseColor("notacolor.opacity(0.3)"))
    }

    // --- Semantic color resolution (the composition-aware path) ---
    //
    // resolveSemanticColor maps Apple semantic names onto Material 3 roles drawn
    // from a ColorScheme; lightColorScheme()/darkColorScheme() build real schemes
    // in a pure JVM test (no Android Context). resolveColorOrSemantic is the
    // combined entry point the appliers call: semantic first, then parseColor.

    private val light = lightColorScheme()
    private val dark = darkColorScheme()

    @Test
    fun `resolveSemanticColor maps the content levels to onSurface roles`() {
        assertEquals(light.onSurface, resolveSemanticColor("primary", light))
        assertEquals(light.onSurfaceVariant, resolveSemanticColor("secondary", light))
        // foreground is the primary content style; foreground.secondary == secondary.
        assertEquals(light.onSurface, resolveSemanticColor("foreground", light))
        assertEquals(light.onSurfaceVariant, resolveSemanticColor("foreground.secondary", light))
    }

    @Test
    fun `resolveSemanticColor maps background levels to surface-container tones`() {
        assertEquals(light.surface, resolveSemanticColor("background", light))
        assertEquals(light.surfaceContainerLow, resolveSemanticColor("background.secondary", light))
        assertEquals(light.surfaceContainer, resolveSemanticColor("background.tertiary", light))
        assertEquals(light.surfaceContainerHigh, resolveSemanticColor("background.quaternary", light))
        assertEquals(light.surfaceDim, resolveSemanticColor("windowBackground", light))
    }

    @Test
    fun `resolveSemanticColor maps fills to translucent onSurface`() {
        // The iOS fill-opacity ladder over onSurface (0.20 / 0.16 / 0.12 / 0.08).
        assertEquals(light.onSurface.copy(alpha = 0.20f), resolveSemanticColor("fill", light))
        assertEquals(light.onSurface.copy(alpha = 0.16f), resolveSemanticColor("fill.secondary", light))
        assertEquals(light.onSurface.copy(alpha = 0.12f), resolveSemanticColor("fill.tertiary", light))
        assertEquals(light.onSurface.copy(alpha = 0.08f), resolveSemanticColor("fill.quaternary", light))
    }

    @Test
    fun `resolveSemanticColor maps the discrete roles`() {
        assertEquals(light.outlineVariant, resolveSemanticColor("separator", light))
        assertEquals(light.primary, resolveSemanticColor("tint", light))
        assertEquals(light.primary, resolveSemanticColor("link", light))
        assertEquals(light.secondaryContainer, resolveSemanticColor("selection", light))
        assertEquals(light.onSurfaceVariant.copy(alpha = 0.5f), resolveSemanticColor("placeholder", light))
    }

    @Test
    fun `resolveSemanticColor is case-insensitive and trims`() {
        assertEquals(light.onSurface, resolveSemanticColor("  PRIMARY  ", light))
        assertEquals(light.surfaceContainer, resolveSemanticColor("Background.Tertiary", light))
    }

    @Test
    fun `resolveSemanticColor returns null for a non-semantic name`() {
        // Hex / literal named colors are NOT semantic - they belong to parseColor.
        assertNull(resolveSemanticColor("#FF0000", light))
        assertNull(resolveSemanticColor("magickaboo", light))
    }

    @Test
    fun `semantic colors adapt to the scheme (light vs dark differ)`() {
        // The whole point: no hardcoded hex, so the role tracks the theme.
        assertNotEquals(resolveSemanticColor("background", light), resolveSemanticColor("background", dark))
        assertNotEquals(resolveSemanticColor("primary", light), resolveSemanticColor("primary", dark))
    }

    @Test
    fun `resolveColorOrSemantic tries semantic first then parseColor`() {
        // Semantic wins when the name is a known semantic style...
        assertEquals(light.onSurfaceVariant, resolveColorOrSemantic("secondary", light))
        // ...and literal colors still resolve through parseColor.
        assertEquals(Color.Red, resolveColorOrSemantic("red", light))
        assertEquals(Color(0xFFFF0000.toInt()), resolveColorOrSemantic("#FF0000", light))
        assertNull(resolveColorOrSemantic("notacolor", light))
    }

    @Test
    fun `resolveColorOrSemantic with a null scheme is the pure parseColor path`() {
        // No theme in scope -> semantic names are unknown, literals still work.
        assertNull(resolveColorOrSemantic("secondary.opacity(0.5)", null)) // semantic base unresolvable
        assertEquals(Color.Red, resolveColorOrSemantic("red", null))
        // "secondary" IS a parseColor name on Apple? No - parseColor has no
        // "secondary", so it returns null without a scheme.
        assertNull(resolveColorOrSemantic("primary", null))
    }

    @Test
    fun `resolveColorOrSemantic applies opacity to a semantic base`() {
        // secondary.opacity(0.5) - resolve the role, scale its alpha by the fraction.
        val faded = resolveColorOrSemantic("secondary.opacity(0.5)", light)!!
        val base = light.onSurfaceVariant
        assertEquals(base.alpha * 0.5f, faded.alpha, 0.004f)
        assertEquals(base.red, faded.red, 0.004f)
        assertEquals(base.green, faded.green, 0.004f)
        assertEquals(base.blue, faded.blue, 0.004f)
        // tint.opacity(0.25) - the accent role faded.
        val tintFaded = resolveColorOrSemantic("tint.opacity(0.25)", light)!!
        assertEquals(light.primary.alpha * 0.25f, tintFaded.alpha, 0.004f)
        // A clearly-translucent result, not the opaque role.
        assertTrue(faded.alpha < base.alpha)
    }
}
