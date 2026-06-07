package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [selectLabelIcon] - the pure icon picker shared by `Label` and
 * Button image-labels. The glyph draw ([SystemSymbolIcon] / [MaterialNameIcon])
 * is Composable + AssetManager-bound, so it is exercised via the demo, the same
 * stance the other resolver tests take for framework-bound code.
 */
class LabelIconResolverTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    private fun props(json: String): JsonObject =
        Json.parseToJsonElement(json).jsonObject

    // -----------------------------------------------------------------------
    // systemImage -> SystemSymbol (the Apple-canonical key)
    // -----------------------------------------------------------------------

    @Test
    fun `systemImage resolves to a SystemSymbol with no explicit overrides`() {
        val log = CapturingLogger()
        val icon = selectLabelIcon(props("""{ "systemImage": "star.fill" }"""), "imageName", "Label", log)
        assertEquals(ImageSource.SystemSymbol("star.fill", null, null, null, null), icon)
        assertTrue(log.warnings.isEmpty())
    }

    @Test
    fun `systemImage carries explicit android axis overrides (unclamped here)`() {
        val icon = selectLabelIcon(
            props("""{ "systemImage": "person", "materialWeight": 700, "materialFill": 1, "materialGrade": 100, "materialSize": 28 }"""),
            "imageName", "Label",
        )
        assertEquals(ImageSource.SystemSymbol("person", 700, 1f, 100, 28f), icon)
    }

    // -----------------------------------------------------------------------
    // materialName -> MaterialSymbol (Android escape hatch), clamped + defaulted
    // -----------------------------------------------------------------------

    @Test
    fun `materialName resolves to a clamped MaterialSymbol with defaults`() {
        val icon = selectLabelIcon(props("""{ "materialName": "favorite" }"""), "imageName", "Label")
        assertEquals(
            ImageSource.MaterialSymbol("favorite", MATERIAL_WEIGHT_DEFAULT, MATERIAL_FILL_DEFAULT, MATERIAL_GRADE_DEFAULT, null),
            icon,
        )
    }

    @Test
    fun `materialName wins over systemImage (Android explicit glyph beats SF)`() {
        val icon = selectLabelIcon(
            props("""{ "materialName": "settings", "systemImage": "gearshape" }"""),
            "imageName", "Label",
        )
        assertTrue(icon is ImageSource.MaterialSymbol)
        assertEquals("settings", (icon as ImageSource.MaterialSymbol).name)
    }

    @Test
    fun `materialFill boolean true maps to fill 1`() {
        val icon = selectLabelIcon(props("""{ "materialName": "favorite", "materialFill": true }"""), "imageName", "Label")
        assertEquals(1f, (icon as ImageSource.MaterialSymbol).fill)
    }

    // -----------------------------------------------------------------------
    // No icon -> null (title-only; NOT an error, unlike Image's no-source)
    // -----------------------------------------------------------------------

    @Test
    fun `no icon source yields null with no warning (title-only)`() {
        val log = CapturingLogger()
        val icon = selectLabelIcon(props("""{ "title": "Hello" }"""), "imageName", "Label", log)
        assertNull(icon)
        assertTrue(log.warnings.isEmpty())
    }

    @Test
    fun `null properties yields null`() {
        assertNull(selectLabelIcon(null, "imageName", "Label"))
    }

    // -----------------------------------------------------------------------
    // Deferred asset-catalog source (imageName / assetImage) -> warn + null
    // -----------------------------------------------------------------------

    @Test
    fun `imageName (Label asset catalog) is deferred with a warning`() {
        val log = CapturingLogger()
        val icon = selectLabelIcon(props("""{ "title": "X", "imageName": "Logo" }"""), "imageName", "Label", log)
        assertNull(icon)
        assertEquals(1, log.warnings.size)
        assertTrue(log.warnings[0].contains("imageName"))
        assertTrue(log.warnings[0].contains("res/drawable"))
    }

    @Test
    fun `assetImage (Button asset catalog) is deferred under its own key`() {
        val log = CapturingLogger()
        val icon = selectLabelIcon(props("""{ "assetImage": "Logo" }"""), "assetImage", "Button", log)
        assertNull(icon)
        assertEquals(1, log.warnings.size)
        assertTrue(log.warnings[0].contains("Button"))
        assertTrue(log.warnings[0].contains("assetImage"))
    }

    @Test
    fun `systemImage outranks a deferred asset-catalog image (no warning)`() {
        val log = CapturingLogger()
        val icon = selectLabelIcon(
            props("""{ "systemImage": "star", "imageName": "Logo" }"""),
            "imageName", "Label", log,
        )
        assertEquals(ImageSource.SystemSymbol("star", null, null, null, null), icon)
        assertTrue(log.warnings.isEmpty())
    }
}
