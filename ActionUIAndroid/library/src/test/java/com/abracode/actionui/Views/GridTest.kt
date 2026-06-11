package com.abracode.actionui.Views

import androidx.compose.ui.unit.IntSize
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIJson
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.subElements
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the pure half of `Grid.kt` - property validation
 * ([resolveGridConfig]), the table layout math ([computeGridMetrics]), and the
 * `rows` named-container decoding. The custom [androidx.compose.ui.layout.Layout]
 * placement is verified by running the app, the stance the rest of the
 * renderer takes for Compose code.
 */
class GridTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    private fun props(json: String): JsonObject =
        Json.parseToJsonElement(json).jsonObject

    private fun element(json: String): ActionUIElement =
        ActionUIJson.decodeFromString(ActionUIElement.serializer(), json)

    @Test
    fun `Grid is registered`() {
        assertSame(Grid, ActionUIRegistry.lookup("Grid"))
    }

    @Test
    fun `rows decode as an array of arrays and register as sub elements`() {
        val grid = element(
            """{ "type": "Grid", "id": 1, "rows": [
                 [ { "type": "Text", "id": 2 }, { "type": "Text", "id": 3 } ],
                 [ { "type": "Image", "id": 4 } ]
               ] }"""
        )
        assertEquals(2, grid.rows?.size)
        assertEquals(2, grid.rows?.get(0)?.size)
        assertEquals(1, grid.rows?.get(1)?.size)
        // Flattened into subElements so populateViewModels reaches the cells.
        assertEquals(listOf(2, 3, 4), grid.subElements().map { it.id })
    }

    @Test
    fun `config defaults match Apple's builder`() {
        val config = resolveGridConfig(null, null)
        assertNull(config.alignment)
        assertEquals(0.0, config.horizontalSpacing, 0.0)
        assertEquals(0.0, config.verticalSpacing, 0.0)
    }

    @Test
    fun `config reads all properties`() {
        val logger = CapturingLogger()
        val config = resolveGridConfig(
            props("""{ "alignment": "topLeading", "horizontalSpacing": 16, "verticalSpacing": 8 }"""),
            logger
        )
        assertEquals("topLeading", config.alignment)
        assertEquals(16.0, config.horizontalSpacing, 0.0)
        assertEquals(8.0, config.verticalSpacing, 0.0)
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `invalid property types warn and fall back to defaults`() {
        val logger = CapturingLogger()
        val config = resolveGridConfig(
            props("""{ "alignment": "diagonal", "horizontalSpacing": "wide", "verticalSpacing": true }"""),
            logger
        )
        assertNull(config.alignment)
        assertEquals(0.0, config.horizontalSpacing, 0.0)
        assertEquals(0.0, config.verticalSpacing, 0.0)
        assertEquals(3, logger.warnings.size)
    }

    // -----------------------------------------------------------------------
    // computeGridMetrics (the table layout math)
    // -----------------------------------------------------------------------

    @Test
    fun `columns are as wide as their widest cell and rows as tall as their tallest`() {
        val metrics = computeGridMetrics(
            cellSizes = listOf(
                listOf(IntSize(100, 20), IntSize(30, 50)),
                listOf(IntSize(40, 10), IntSize(80, 25)),
            ),
            horizontalGap = 0,
            verticalGap = 0,
        )
        assertEquals(listOf(100, 80), metrics.columnWidths)
        assertEquals(listOf(50, 25), metrics.rowHeights)
        assertEquals(180, metrics.width)
        assertEquals(75, metrics.height)
    }

    @Test
    fun `gaps go between tracks only`() {
        val metrics = computeGridMetrics(
            cellSizes = listOf(
                listOf(IntSize(10, 10), IntSize(10, 10), IntSize(10, 10)),
                listOf(IntSize(10, 10), IntSize(10, 10), IntSize(10, 10)),
            ),
            horizontalGap = 5,
            verticalGap = 7,
        )
        assertEquals(40, metrics.width) // 3 * 10 + 2 * 5
        assertEquals(27, metrics.height) // 2 * 10 + 1 * 7
    }

    @Test
    fun `ragged rows contribute only to the columns they reach`() {
        val metrics = computeGridMetrics(
            cellSizes = listOf(
                listOf(IntSize(10, 10), IntSize(20, 10), IntSize(30, 10)),
                listOf(IntSize(50, 10)),
            ),
            horizontalGap = 0,
            verticalGap = 0,
        )
        assertEquals(listOf(50, 20, 30), metrics.columnWidths)
        assertEquals(100, metrics.width)
    }

    @Test
    fun `an empty grid spans nothing`() {
        val metrics = computeGridMetrics(emptyList(), 5, 5)
        assertTrue(metrics.columnWidths.isEmpty())
        assertEquals(0, metrics.width)
        assertEquals(0, metrics.height)
    }
}
