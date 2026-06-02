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
 * Unit tests for the pure parts of `ImageResolver.kt` — [selectImageSource] and
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
    // selectImageSource — supported sources
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
    // selectImageSource — Apple priority filePath > resourceName > assetName > systemName
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
    // selectImageSource — deferred sources warn and render nothing
    // -----------------------------------------------------------------------

    @Test
    fun `assetName alone is deferred — warns and returns null`() {
        val log = CapturingLogger()
        val source = selectImageSource(props("""{ "assetName": "drawableName" }"""), log)
        assertNull(source)
        assertEquals(1, log.warnings.size)
        assertTrue(log.warnings.single().contains("assetName"))
    }

    @Test
    fun `systemName alone is deferred — warns and returns null`() {
        val log = CapturingLogger()
        val source = selectImageSource(props("""{ "systemName": "star.fill" }"""), log)
        assertNull(source)
        assertEquals(1, log.warnings.size)
        assertTrue(log.warnings.single().contains("systemName"))
    }

    // -----------------------------------------------------------------------
    // selectImageSource — missing / mistyped
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
