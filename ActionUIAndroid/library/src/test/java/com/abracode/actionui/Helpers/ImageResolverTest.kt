package com.abracode.actionui.Helpers

import androidx.compose.ui.layout.ContentScale
import com.abracode.actionui.Common.ActionUILogger
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
    fun `resourceName wins over a deferred assetName (no warning)`() {
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
    // selectImageSource - deferred sources warn and render nothing
    // -----------------------------------------------------------------------

    @Test
    fun `assetName alone is deferred - warns and returns null`() {
        val log = CapturingLogger()
        val source = selectImageSource(props("""{ "assetName": "drawableName" }"""), log)
        assertNull(source)
        assertEquals(1, log.warnings.size)
        assertTrue(log.warnings.single().contains("assetName"))
    }

    // systemName is now supported (resolves via the SF->Material map at render
    // time); its tests live in the SystemSymbol section below.

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
    fun `materialName wins over a deferred assetName (no warning)`() {
        val log = CapturingLogger()
        val source = selectImageSource(
            props("""{ "assetName": "drawable", "materialName": "delete" }"""), log
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

    @Test
    fun `systemName wins over a deferred assetName (no warning)`() {
        val log = CapturingLogger()
        val source = selectImageSource(
            props("""{ "assetName": "drawable", "systemName": "heart" }"""), log
        )
        assertTrue(source is ImageSource.SystemSymbol)
        assertTrue(log.warnings.isEmpty())
    }

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
        assertEquals(16f * IMAGE_SCALE_SMALL_FACTOR, resolveSymbolSizeSp(null, "small", 16f), 0.001f)
    }

    @Test
    fun `inherited font size is used when no explicit size`() {
        assertEquals(16f, resolveSymbolSizeSp(null, null, 16f), 0.001f)
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
