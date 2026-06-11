package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIJson
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the pure half of `GeometryReader.kt` - alignment validation
 * ([resolveGeometryReaderAlignment]), the size-state conversion
 * ([geometrySizeState]), and the seeded `states["size"]`. The greedy Box
 * rendering and live size reporting are verified by running the app, the
 * stance the rest of the renderer takes for Compose code.
 */
class GeometryReaderTest {

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
    fun `GeometryReader is registered with no value bridge`() {
        assertSame(GeometryReader, ActionUIRegistry.lookup("GeometryReader"))
        assertEquals(ActionUIValueType.NONE, GeometryReader.valueType)
    }

    @Test
    fun `initial states seed a zero size`() {
        val states = GeometryReader.initialStates(element("""{ "type": "GeometryReader", "id": 1 }"""))
        assertEquals(listOf(0.0, 0.0), states["size"])
    }

    @Test
    fun `alignment defaults to topLeading, the SwiftUI native default`() {
        assertEquals("topLeading", resolveGeometryReaderAlignment(null, null))
        assertEquals("topLeading", resolveGeometryReaderAlignment(props("{}"), null))
    }

    @Test
    fun `a valid alignment is kept`() {
        val logger = CapturingLogger()
        assertEquals(
            "bottomTrailing",
            resolveGeometryReaderAlignment(props("""{ "alignment": "bottomTrailing" }"""), logger),
        )
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `an invalid alignment warns and falls back to topLeading`() {
        val logger = CapturingLogger()
        assertEquals(
            "topLeading",
            resolveGeometryReaderAlignment(props("""{ "alignment": "diagonal" }"""), logger),
        )
        assertEquals(
            "topLeading",
            resolveGeometryReaderAlignment(props("""{ "alignment": 42 }"""), logger),
        )
        assertEquals(2, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("defaulting to 'topLeading'"))
    }

    @Test
    fun `size state converts pixels to dp doubles`() {
        assertEquals(listOf(100.0, 50.0), geometrySizeState(200, 100, 2.0f))
        assertEquals(listOf(360.0, 240.0), geometrySizeState(360, 240, 1.0f))
        assertEquals(listOf(0.0, 0.0), geometrySizeState(0, 0, 2.625f))
    }
}
