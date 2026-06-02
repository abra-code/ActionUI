package com.abracode.actionui.Helpers

import androidx.compose.ui.graphics.Color
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
 * Unit tests for [resolveShapePaint] and [warnUnsupportedCornerStyle] in
 * `ShapeStyleHelper.kt`. Both are pure (no Compose runtime / no Android
 * framework), so they cover the fill/stroke fall-through and the squircle
 * warning here; the `DrawScope` geometry in the per-shape `Views` builders
 * only manifests at draw time and is left to the demo + instrumentation (the
 * stance section 9/section 10 take for framework-bound code).
 */
class ShapeStyleHelperTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    private fun props(json: String): JsonObject =
        Json.parseToJsonElement(json).jsonObject

    private val DEFAULT = Color.Black

    // -----------------------------------------------------------------------
    // resolveShapePaint
    // -----------------------------------------------------------------------

    @Test
    fun `null properties yields the default fill`() {
        val paint = resolveShapePaint(null, DEFAULT)
        assertEquals(DEFAULT, paint.color)
        assertNull("default paint should be a fill", paint.strokeWidthDp)
    }

    @Test
    fun `empty properties yields the default fill`() {
        val paint = resolveShapePaint(props("{}"), DEFAULT)
        assertEquals(DEFAULT, paint.color)
        assertNull(paint.strokeWidthDp)
    }

    @Test
    fun `fill resolves to a solid fill`() {
        val paint = resolveShapePaint(props("""{"fill":"red"}"""), DEFAULT)
        assertEquals(Color.Red, paint.color)
        assertNull(paint.strokeWidthDp)
    }

    @Test
    fun `fill takes priority over stroke`() {
        val logger = CapturingLogger()
        val paint = resolveShapePaint(
            props("""{"fill":"blue","stroke":"red","strokeLineWidth":4}"""),
            DEFAULT, logger
        )
        assertEquals(Color.Blue, paint.color)
        assertNull("fill wins, so it must be a fill not a stroke", paint.strokeWidthDp)
        assertTrue("a resolvable fill should not warn", logger.warnings.isEmpty())
    }

    @Test
    fun `stroke is used when fill is absent`() {
        val paint = resolveShapePaint(
            props("""{"stroke":"green","strokeLineWidth":3}"""),
            DEFAULT
        )
        assertEquals(Color.Green, paint.color)
        assertEquals(3f, paint.strokeWidthDp)
    }

    @Test
    fun `stroke width defaults to 1 when omitted`() {
        val paint = resolveShapePaint(props("""{"stroke":"green"}"""), DEFAULT)
        assertEquals(1f, paint.strokeWidthDp)
    }

    @Test
    fun `unresolvable fill falls through to a resolvable stroke`() {
        val logger = CapturingLogger()
        val paint = resolveShapePaint(
            props("""{"fill":"tint","stroke":"green","strokeLineWidth":2}"""),
            DEFAULT, logger
        )
        // Apple only enters the fill branch when the color resolves; an
        // unresolvable fill falls through to stroke.
        assertEquals(Color.Green, paint.color)
        assertEquals(2f, paint.strokeWidthDp)
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings.first().contains("fill 'tint'"))
    }

    @Test
    fun `unresolvable fill with no stroke falls back to the default fill`() {
        val logger = CapturingLogger()
        val paint = resolveShapePaint(props("""{"fill":"tint"}"""), DEFAULT, logger)
        assertEquals(DEFAULT, paint.color)
        assertNull(paint.strokeWidthDp)
        assertEquals(1, logger.warnings.size)
    }

    @Test
    fun `unresolvable stroke falls back to the default fill`() {
        val logger = CapturingLogger()
        val paint = resolveShapePaint(props("""{"stroke":"nope"}"""), DEFAULT, logger)
        assertEquals(DEFAULT, paint.color)
        assertNull(paint.strokeWidthDp)
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings.first().contains("stroke 'nope'"))
    }

    @Test
    fun `hex fill resolves`() {
        val paint = resolveShapePaint(props("""{"fill":"#FF0000"}"""), DEFAULT)
        assertEquals(Color.Red, paint.color)
        assertNull(paint.strokeWidthDp)
    }

    // -----------------------------------------------------------------------
    // warnUnsupportedCornerStyle
    // -----------------------------------------------------------------------

    @Test
    fun `circular corner style does not warn`() {
        val logger = CapturingLogger()
        warnUnsupportedCornerStyle(props("""{"cornerStyle":"circular"}"""), "cornerStyle", "RoundedRectangle", logger)
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `absent corner style does not warn`() {
        val logger = CapturingLogger()
        warnUnsupportedCornerStyle(props("{}"), "cornerStyle", "RoundedRectangle", logger)
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `continuous corner style warns about the squircle downgrade`() {
        val logger = CapturingLogger()
        warnUnsupportedCornerStyle(props("""{"style":"continuous"}"""), "style", "Capsule", logger)
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings.first().contains("continuous"))
    }

    @Test
    fun `unknown corner style warns about the invalid value`() {
        val logger = CapturingLogger()
        warnUnsupportedCornerStyle(props("""{"cornerStyle":"wat"}"""), "cornerStyle", "RoundedRectangle", logger)
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings.first().contains("invalid"))
    }
}
