package com.abracode.actionui.Helpers

import androidx.compose.ui.layout.ContentScale
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.imageRegistryOf
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the pure parts of `ImageResolver.kt` - [selectImageSource] and
 * [resolveContentScale]. The Android-dependent [loadImagePainter] (assets / file
 * decoding) is exercised via the demo / instrumentation, the same stance the
 * other resolver tests take for Composable-only code.
 */
class ImageResolverTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        val infos = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            when (level) {
                LoggerLevel.warning -> warnings.add(message)
                LoggerLevel.info -> infos.add(message)
                else -> {}
            }
        }
    }

    private fun props(json: String): JsonObject =
        Json.parseToJsonElement(json).jsonObject

    // -----------------------------------------------------------------------
    // selectImageSource - supported sources
    // -----------------------------------------------------------------------

    @Test
    fun `resourceName resolves to an Asset source`() {
        val log = CapturingLogger()
        val source = selectImageSource(props("""{ "resourceName": "logo.png" }"""), log)
        assertEquals(ImageSource.Asset("logo.png"), source)
        assertTrue(log.warnings.isEmpty())
    }

    @Test
    fun `filePath resolves to a FilePath source`() {
        val log = CapturingLogger()
        val source = selectImageSource(props("""{ "filePath": "/tmp/a.png" }"""), log)
        assertEquals(ImageSource.FilePath("/tmp/a.png"), source)
        assertTrue(log.warnings.isEmpty())
    }

    // -----------------------------------------------------------------------
    // selectImageSource - Apple priority filePath > resourceName > assetName > systemName
    // -----------------------------------------------------------------------

    @Test
    fun `filePath wins over resourceName`() {
        val source = selectImageSource(
            props("""{ "filePath": "/tmp/a.png", "resourceName": "logo.png" }""")
        )
        assertEquals(ImageSource.FilePath("/tmp/a.png"), source)
    }

    @Test
    fun `resourceName wins over assetName (no warning)`() {
        val log = CapturingLogger()
        val source = selectImageSource(
            props("""{ "assetName": "drawableName", "resourceName": "logo.png" }"""), log
        )
        assertEquals(ImageSource.Asset("logo.png"), source)
        assertTrue(log.warnings.isEmpty())
    }

    @Test
    fun `cross-platform systemName plus resourceName resolves to the resource on Android`() {
        // The common shared-JSON shape: SF Symbol for Apple, bundled image for Android.
        val log = CapturingLogger()
        val source = selectImageSource(
            props("""{ "systemName": "star.fill", "resourceName": "logo.png" }"""), log
        )
        assertEquals(ImageSource.Asset("logo.png"), source)
        assertTrue(log.warnings.isEmpty())
    }

    // -----------------------------------------------------------------------
    // selectImageSource - assetName via the host image registry
    // -----------------------------------------------------------------------

    @Test
    fun `assetName resolves through the host registry`() {
        val log = CapturingLogger()
        val registry = imageRegistryOf("My Logo" to 42)
        val source = selectImageSource(props("""{ "assetName": "My Logo" }"""), log, registry)
        assertEquals(ImageSource.DrawableResource(42), source)
        assertTrue(log.warnings.isEmpty())
    }

    @Test
    fun `assetName without a registry warns and returns null`() {
        val log = CapturingLogger()
        val source = selectImageSource(props("""{ "assetName": "My Logo" }"""), log)
        assertNull(source)
        assertEquals(1, log.warnings.size)
        assertTrue(log.warnings.single().contains("assetName"))
        assertTrue(log.warnings.single().contains("no image registry"))
        // The warning teaches the discovery convention with the normalized name.
        assertTrue(log.warnings.single().contains("aui_my_logo"))
    }

    @Test
    fun `assetName the registry does not know warns and returns null - no fall-through`() {
        val log = CapturingLogger()
        val registry = imageRegistryOf("Something Else" to 7)
        val source = selectImageSource(
            // systemName is present but must NOT be used: assetName outranks it
            // (Apple's order) and an unresolvable name renders nothing, like a
            // name absent from Apple's catalog.
            props("""{ "assetName": "My Logo", "systemName": "heart" }"""), log, registry
        )
        assertNull(source)
        assertEquals(1, log.warnings.size)
        assertTrue(log.warnings.single().contains("does not resolve"))
    }

    @Test
    fun `assetName wins over systemName when the registry resolves it (Apple order)`() {
        val log = CapturingLogger()
        val registry = imageRegistryOf("My Logo" to 42)
        val source = selectImageSource(
            props("""{ "assetName": "My Logo", "systemName": "heart" }"""), log, registry
        )
        assertEquals(ImageSource.DrawableResource(42), source)
        assertTrue(log.warnings.isEmpty())
    }

    // -----------------------------------------------------------------------
    // selectImageSource - materialName (Material Symbol glyph)
    // -----------------------------------------------------------------------

    @Test
    fun `materialName resolves to a MaterialSymbol with axis defaults`() {
        val log = CapturingLogger()
        val source = selectImageSource(props("""{ "materialName": "home" }"""), log)
        assertEquals(
            ImageSource.MaterialSymbol(
                name = "home",
                weight = MATERIAL_WEIGHT_DEFAULT,
                fill = MATERIAL_FILL_DEFAULT,
                grade = MATERIAL_GRADE_DEFAULT,
                explicitSizeSp = null,
            ),
            source
        )
        assertTrue(log.warnings.isEmpty())
    }

    @Test
    fun `materialName carries axis overrides`() {
        val source = selectImageSource(
            props(
                """{ "materialName": "star", "materialWeight": 500,
                    "materialFill": 0.5, "materialGrade": 100, "materialSize": 32 }"""
            )
        )
        assertEquals(
            ImageSource.MaterialSymbol("star", 500, 0.5f, 100, 32f),
            source
        )
    }

    @Test
    fun `materialWeight and materialGrade are clamped to the font axis ranges`() {
        val low = selectImageSource(props("""{ "materialName": "a", "materialWeight": 10, "materialGrade": -999 }"""))
        assertEquals(ImageSource.MaterialSymbol("a", MATERIAL_WEIGHT_MIN, 0f, MATERIAL_GRADE_MIN, null), low)

        val high = selectImageSource(props("""{ "materialName": "a", "materialWeight": 9000, "materialGrade": 9000 }"""))
        assertEquals(ImageSource.MaterialSymbol("a", MATERIAL_WEIGHT_MAX, 0f, MATERIAL_GRADE_MAX, null), high)
    }

    @Test
    fun `materialFill accepts a boolean (fill variant)`() {
        val filled = selectImageSource(props("""{ "materialName": "a", "materialFill": true }""")) as ImageSource.MaterialSymbol
        assertEquals(1f, filled.fill, 0f)
        val unfilled = selectImageSource(props("""{ "materialName": "a", "materialFill": false }""")) as ImageSource.MaterialSymbol
        assertEquals(0f, unfilled.fill, 0f)
    }

    @Test
    fun `materialFill number is clamped to 0_1`() {
        val over = selectImageSource(props("""{ "materialName": "a", "materialFill": 5 }""")) as ImageSource.MaterialSymbol
        assertEquals(1f, over.fill, 0f)
    }

    // -----------------------------------------------------------------------
    // selectImageSource - priority involving materialName
    // -----------------------------------------------------------------------

    @Test
    fun `resourceName wins over materialName`() {
        val source = selectImageSource(
            props("""{ "materialName": "home", "resourceName": "logo.png" }""")
        )
        assertEquals(ImageSource.Asset("logo.png"), source)
    }

    @Test
    fun `materialName wins over a cross-platform systemName (no warning)`() {
        // The recommended shared shape: SF Symbol for Apple, Material name for Android.
        val log = CapturingLogger()
        val source = selectImageSource(
            props("""{ "systemName": "trash", "materialName": "delete" }"""), log
        )
        assertEquals(
            ImageSource.MaterialSymbol("delete", MATERIAL_WEIGHT_DEFAULT, 0f, 0, null),
            source
        )
        assertTrue(log.warnings.isEmpty())
    }

    @Test
    fun `materialName wins over assetName (the explicit Android key, no warning)`() {
        val log = CapturingLogger()
        val source = selectImageSource(
            props("""{ "assetName": "drawable", "materialName": "delete" }"""), log,
            imageRegistryOf("drawable" to 42),
        )
        assertTrue(source is ImageSource.MaterialSymbol)
        assertTrue(log.warnings.isEmpty())
    }

    @Test
    fun `filePath wins over materialName`() {
        val source = selectImageSource(
            props("""{ "materialName": "home", "filePath": "/tmp/a.png" }""")
        )
        assertEquals(ImageSource.FilePath("/tmp/a.png"), source)
    }

    // -----------------------------------------------------------------------
    // selectImageSource - systemName (SF Symbol, resolved via the SF->Material map)
    // -----------------------------------------------------------------------

    @Test
    fun `systemName resolves to a SystemSymbol with no explicit overrides`() {
        // Codepoint + per-row tuning are resolved at render time, not here.
        val log = CapturingLogger()
        val source = selectImageSource(props("""{ "systemName": "heart.fill" }"""), log)
        assertEquals(ImageSource.SystemSymbol("heart.fill", null, null, null, null), source)
        assertTrue(log.warnings.isEmpty())
    }

    @Test
    fun `systemName carries explicit android axis overrides (unclamped here)`() {
        val source = selectImageSource(
            props(
                """{ "systemName": "star", "materialWeight": 500,
                    "materialFill": 0.5, "materialGrade": 100, "materialSize": 32 }"""
            )
        )
        assertEquals(ImageSource.SystemSymbol("star", 500, 0.5f, 100, 32f), source)
    }

    // assetName vs systemName priority lives in the registry section above
    // (assetName outranks systemName, Apple's Image.swift order).

    // -----------------------------------------------------------------------
    // resolveSymbolSizeSp
    // -----------------------------------------------------------------------

    @Test
    fun `explicit size wins and is unscaled at medium`() {
        assertEquals(32f, resolveSymbolSizeSp(32f, "medium", 16f), 0.001f)
    }

    @Test
    fun `imageScale scales the base size`() {
        assertEquals(32f * IMAGE_SCALE_LARGE_FACTOR, resolveSymbolSizeSp(32f, "large", null), 0.001f)
        assertEquals(
            16f * SYMBOL_FONT_BOX_FACTOR * IMAGE_SCALE_SMALL_FACTOR,
            resolveSymbolSizeSp(null, "small", 16f),
            0.001f,
        )
    }

    @Test
    fun `inherited font size is scaled by the symbol box factor`() {
        // An SF Symbol's box renders larger than its font (~20pt at body 17);
        // the inherited-font path applies the calibration, the explicit
        // materialSize path (previous test) takes the author's value as-is.
        assertEquals(16f * SYMBOL_FONT_BOX_FACTOR, resolveSymbolSizeSp(null, null, 16f), 0.001f)
    }

    @Test
    fun `falls back to the default size when nothing is supplied`() {
        assertEquals(DEFAULT_SYMBOL_SIZE_SP, resolveSymbolSizeSp(null, null, null), 0.001f)
    }

    @Test
    fun `unknown imageScale leaves the size unscaled`() {
        assertEquals(20f, resolveSymbolSizeSp(20f, "huge", null), 0.001f)
    }

    // -----------------------------------------------------------------------
    // resolveResizableGlyphFrameDp - SwiftUI .resizable() frame-fit for glyphs
    // -----------------------------------------------------------------------

    @Test
    fun `resizable glyph fits the smaller frame axis`() {
        val size = resolveResizableGlyphFrameDp(
            props("""{ "resizable": true, "frame": { "width": 70, "height": 50 } }""")
        )
        assertEquals(50f, size!!, 0.001f)
    }

    @Test
    fun `resizable glyph with contentMode fill takes the larger axis`() {
        val size = resolveResizableGlyphFrameDp(
            props("""{ "resizable": true, "contentMode": "fill", "frame": { "width": 70, "height": 50 } }""")
        )
        assertEquals(70f, size!!, 0.001f)
    }

    @Test
    fun `contentMode implies resizable like the Apple contract`() {
        val size = resolveResizableGlyphFrameDp(
            props("""{ "contentMode": "fit", "frame": { "width": 80, "height": 80 } }""")
        )
        assertEquals(80f, size!!, 0.001f)
    }

    @Test
    fun `explicit resizable false wins over an implied contentMode`() {
        assertNull(
            resolveResizableGlyphFrameDp(
                props("""{ "resizable": false, "contentMode": "fit", "frame": { "width": 80 } }""")
            )
        )
    }

    @Test
    fun `single-axis frame uses that axis`() {
        val size = resolveResizableGlyphFrameDp(
            props("""{ "resizable": true, "frame": { "height": 60 } }""")
        )
        assertEquals(60f, size!!, 0.001f)
    }

    @Test
    fun `non-resizable or frameless glyphs return null`() {
        assertNull(resolveResizableGlyphFrameDp(null))
        assertNull(resolveResizableGlyphFrameDp(props("""{ "frame": { "width": 100 } }""")))
        assertNull(resolveResizableGlyphFrameDp(props("""{ "resizable": true }""")))
    }

    // -----------------------------------------------------------------------
    // resolveSymbolWeight / Fill / Grade - explicit override > map tuning >
    // default, then clamp to the font axis range (the systemName precedence)
    // -----------------------------------------------------------------------

    @Test
    fun `resolveSymbolWeight prefers explicit, then map, then default`() {
        assertEquals(MATERIAL_WEIGHT_DEFAULT, resolveSymbolWeight(null, null))
        assertEquals(600, resolveSymbolWeight(null, 600))   // per-row map tuning
        assertEquals(500, resolveSymbolWeight(500, 600))    // explicit override wins
    }

    @Test
    fun `resolveSymbolWeight clamps to the axis range`() {
        assertEquals(MATERIAL_WEIGHT_MAX, resolveSymbolWeight(9000, null))
        assertEquals(MATERIAL_WEIGHT_MIN, resolveSymbolWeight(10, null))
    }

    @Test
    fun `resolveSymbolFill maps the boolean default and honors explicit`() {
        assertEquals(0f, resolveSymbolFill(null, false), 0f)
        assertEquals(1f, resolveSymbolFill(null, true), 0f)
        assertEquals(0.5f, resolveSymbolFill(0.5f, true), 0f)  // explicit override wins
        assertEquals(1f, resolveSymbolFill(5f, false), 0f)     // clamped to 0..1
    }

    @Test
    fun `resolveSymbolGrade defaults and clamps`() {
        assertEquals(MATERIAL_GRADE_DEFAULT, resolveSymbolGrade(null))
        assertEquals(100, resolveSymbolGrade(100))
        assertEquals(MATERIAL_GRADE_MAX, resolveSymbolGrade(9000))
        assertEquals(MATERIAL_GRADE_MIN, resolveSymbolGrade(-9000))
    }

    // -----------------------------------------------------------------------
    // selectImageSource - missing / mistyped
    // -----------------------------------------------------------------------

    @Test
    fun `no source warns and returns null`() {
        val log = CapturingLogger()
        assertNull(selectImageSource(props("""{ "contentMode": "fit" }"""), log))
        assertEquals(1, log.warnings.size)
    }

    @Test
    fun `null properties warns and returns null`() {
        val log = CapturingLogger()
        assertNull(selectImageSource(null, log))
        assertEquals(1, log.warnings.size)
    }

    @Test
    fun `non-string resourceName is warned and treated as absent`() {
        val log = CapturingLogger()
        val source = selectImageSource(props("""{ "resourceName": 42 }"""), log)
        assertNull(source)
        // One warning for the bad type, one for "no usable source".
        assertTrue(log.warnings.any { it.contains("resourceName must be a String") })
    }

    @Test
    fun `non-string resourceName still falls through to a valid filePath`() {
        val log = CapturingLogger()
        val source = selectImageSource(
            props("""{ "resourceName": 42, "filePath": "/tmp/a.png" }"""), log
        )
        assertEquals(ImageSource.FilePath("/tmp/a.png"), source)
        assertTrue(log.warnings.any { it.contains("resourceName must be a String") })
    }

    // -----------------------------------------------------------------------
    // resolveContentScale
    // -----------------------------------------------------------------------

    @Test
    fun `contentMode fit maps to ContentScale Fit`() {
        assertSame(ContentScale.Fit, resolveContentScale(props("""{ "contentMode": "fit" }""")))
    }

    @Test
    fun `contentMode fill maps to ContentScale Crop`() {
        assertSame(ContentScale.Crop, resolveContentScale(props("""{ "contentMode": "fill" }""")))
    }

    @Test
    fun `missing contentMode defaults to Fit`() {
        assertSame(ContentScale.Fit, resolveContentScale(props("{}")))
        assertSame(ContentScale.Fit, resolveContentScale(null))
    }

    @Test
    fun `invalid contentMode warns and defaults to Fit`() {
        val log = CapturingLogger()
        assertSame(ContentScale.Fit, resolveContentScale(props("""{ "contentMode": "cover" }"""), log))
        assertEquals(1, log.warnings.size)
    }
}
