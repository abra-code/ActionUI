package com.abracode.actionui.Helpers

import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the grid track model shared by [com.abracode.actionui.Views.LazyVGrid]
 * and [com.abracode.actionui.Views.LazyHGrid]: the pure [resolveGridTracks]
 * parsing (mirroring the Swift element's validation, with its warn-and-default
 * paths) and the [ActionUIGridCells] cross-axis size math. The `@Composable`
 * grids themselves are exercised by running the app, the stance the rest of the
 * renderer takes.
 */
class GridTrackHelperTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    private fun json(text: String) = Json.parseToJsonElement(text)

    // -- resolveGridTracks ----------------------------------------------------

    @Test
    fun `absent track property defaults to one flexible track silently`() {
        val logger = CapturingLogger()
        assertEquals(listOf<GridTrack>(GridTrack.Flexible), resolveGridTracks(null, "LazyVGrid", "columns", logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `mixed minimum and flexible tracks parse in order`() {
        val logger = CapturingLogger()
        val tracks = resolveGridTracks(
            json("""[ { "minimum": 100.0 }, { "flexible": true } ]"""),
            "LazyVGrid", "columns", logger,
        )
        assertEquals(listOf(GridTrack.Fixed(100f.dp), GridTrack.Flexible), tracks)
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `minimum wins over flexible in the same track`() {
        val tracks = resolveGridTracks(
            json("""[ { "minimum": 80, "flexible": true } ]"""),
            "LazyVGrid", "columns", null,
        )
        assertEquals(listOf<GridTrack>(GridTrack.Fixed(80f.dp)), tracks)
    }

    @Test
    fun `flexible false tracks are skipped`() {
        val tracks = resolveGridTracks(
            json("""[ { "flexible": false }, { "minimum": 50 } ]"""),
            "LazyVGrid", "columns", null,
        )
        assertEquals(listOf<GridTrack>(GridTrack.Fixed(50f.dp)), tracks)
    }

    @Test
    fun `non-array track property warns and defaults`() {
        val logger = CapturingLogger()
        val tracks = resolveGridTracks(json("\"two\""), "LazyVGrid", "columns", logger)
        assertEquals(listOf<GridTrack>(GridTrack.Flexible), tracks)
        assertTrue(logger.warnings.any { it.contains("array of dictionaries") })
    }

    @Test
    fun `array with a non-object entry warns and defaults`() {
        val logger = CapturingLogger()
        val tracks = resolveGridTracks(json("""[ { "minimum": 100 }, 7 ]"""), "LazyHGrid", "rows", logger)
        assertEquals(listOf<GridTrack>(GridTrack.Flexible), tracks)
        assertTrue(logger.warnings.any { it.contains("LazyHGrid rows must be an array of dictionaries") })
    }

    @Test
    fun `array without any valid track warns and defaults`() {
        val logger = CapturingLogger()
        val tracks = resolveGridTracks(json("""[ { "flexible": false }, {} ]"""), "LazyVGrid", "columns", logger)
        assertEquals(listOf<GridTrack>(GridTrack.Flexible), tracks)
        assertTrue(logger.warnings.any { it.contains("minimum or flexible") })
        assertFalse(logger.warnings.any { it.contains("array of dictionaries") })
    }

    // -- ActionUIGridCells ----------------------------------------------------

    private val density = Density(1f)

    private fun sizes(tracks: List<GridTrack>, availableSize: Int, spacing: Int): List<Int> =
        with(ActionUIGridCells(tracks)) {
            with(density) { calculateCrossAxisCellSizes(availableSize, spacing) }
        }

    @Test
    fun `fixed tracks keep their size and flexible tracks split the remainder`() {
        val tracks = listOf(GridTrack.Fixed(100f.dp), GridTrack.Flexible, GridTrack.Flexible)
        // 500 total - 2 gaps of 10 - 100 fixed = 380 left, split 190/190.
        assertEquals(listOf(100, 190, 190), sizes(tracks, availableSize = 500, spacing = 10))
    }

    @Test
    fun `leftover pixels go one each to the leading flexible tracks`() {
        val tracks = listOf(GridTrack.Flexible, GridTrack.Flexible, GridTrack.Flexible)
        assertEquals(listOf(34, 33, 33), sizes(tracks, availableSize = 100, spacing = 0))
        assertEquals(100, sizes(tracks, availableSize = 100, spacing = 0).sum())
    }

    @Test
    fun `overflowing fixed tracks clamp flexible tracks to zero instead of going negative`() {
        val tracks = listOf(GridTrack.Fixed(200f.dp), GridTrack.Flexible)
        assertEquals(listOf(200, 0), sizes(tracks, availableSize = 150, spacing = 0))
    }

    // -- gridNaturalCrossExtent (the unbounded-cross-axis fallback) ------------

    @Test
    fun `natural extent sums fixed tracks (the periodic-table case)`() {
        val tracks = List(18) { GridTrack.Fixed(50f.dp) }
        assertEquals(900f.dp, gridNaturalCrossExtent(tracks, flexibleFallback = 100f.dp))
    }

    @Test
    fun `flexible tracks contribute the fallback`() {
        val tracks = listOf(GridTrack.Fixed(120f.dp), GridTrack.Flexible, GridTrack.Flexible)
        assertEquals(320f.dp, gridNaturalCrossExtent(tracks, flexibleFallback = 100f.dp))
    }

    @Test
    fun `all-flexible is the track count times the fallback`() {
        assertEquals(300f.dp, gridNaturalCrossExtent(List(3) { GridTrack.Flexible }, flexibleFallback = 100f.dp))
    }
}
