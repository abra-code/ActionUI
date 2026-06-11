package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIJson
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the provider-independent half of the `Map` element that
 * lives in core: the COORDINATE value-bridge serialization
 * (`CoordinateHelper`) and the shared contract validation (`MapContract`).
 * The element implementations themselves live in the provider modules
 * (`:map-osm` / `:map-google`) with their own tests.
 */
class MapContractTest {

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

    // -----------------------------------------------------------------------
    // CoordinateHelper (the COORDINATE value bridge)
    // -----------------------------------------------------------------------

    @Test
    fun `coordinate JSON string parses and serializes round trip`() {
        val coordinate = ActionUICoordinate(37.33233141, -122.0312186)
        val json = coordinateToJson(coordinate)
        assertEquals("{\"latitude\":37.33233141,\"longitude\":-122.0312186}", json)
        assertEquals(coordinate, parseCoordinate(json))
    }

    @Test
    fun `malformed coordinate strings parse to null`() {
        assertNull(parseCoordinate("not json"))
        assertNull(parseCoordinate("{\"latitude\": 1.0}"))
        assertNull(parseCoordinate("{\"latitude\": \"north\", \"longitude\": 2.0}"))
        assertNull(parseCoordinate("[1.0, 2.0]"))
    }

    @Test
    fun `initial coordinate is the coordinate property or the zero coordinate`() {
        val withCoordinate = element(
            """{ "type": "Map", "id": 1, "properties":
                 { "coordinate": { "latitude": 37.33, "longitude": -122.03 } } }"""
        )
        assertEquals(ActionUICoordinate(37.33, -122.03), mapInitialCoordinate(withCoordinate))
        val without = element("""{ "type": "Map", "id": 1 }""")
        assertEquals(ActionUICoordinate(0.0, 0.0), mapInitialCoordinate(without))
    }

    // -----------------------------------------------------------------------
    // resolveMapConfig (Apple's validateProperties parity)
    // -----------------------------------------------------------------------

    @Test
    fun `config defaults match Apple's builder`() {
        val config = resolveMapConfig(null, null)
        assertNull(config.coordinate)
        assertFalse(config.showsUserLocation)
        assertEquals(listOf("pan", "zoom", "rotate"), config.interactionModes)
        assertTrue(config.annotations.isEmpty())
        assertNull(config.actionID)
        assertNull(config.valueChangeActionID)
    }

    @Test
    fun `config reads all properties`() {
        val logger = CapturingLogger()
        val config = resolveMapConfig(
            props(
                """{ "coordinate": { "latitude": 37.33, "longitude": -122.03 },
                     "showsUserLocation": true,
                     "interactionModes": ["pan", "zoom"],
                     "annotations": [
                       { "coordinate": { "latitude": 37.332, "longitude": -122.031 },
                         "title": "Point", "subtitle": "Subtitle" }
                     ],
                     "actionID": "map.camera", "valueChangeActionID": "map.moved" }"""
            ),
            logger,
        )
        assertEquals(ActionUICoordinate(37.33, -122.03), config.coordinate)
        assertTrue(config.showsUserLocation)
        assertEquals(listOf("pan", "zoom"), config.interactionModes)
        assertEquals(
            listOf(MapAnnotation(ActionUICoordinate(37.332, -122.031), "Point", "Subtitle")),
            config.annotations,
        )
        assertEquals("map.camera", config.actionID)
        assertEquals("map.moved", config.valueChangeActionID)
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `invalid property types warn and fall back to defaults`() {
        val logger = CapturingLogger()
        val config = resolveMapConfig(
            props(
                """{ "coordinate": { "latitude": "north" },
                     "showsUserLocation": "yes",
                     "interactionModes": ["pan", "fly"],
                     "annotations": "none" }"""
            ),
            logger,
        )
        assertNull(config.coordinate)
        assertFalse(config.showsUserLocation)
        assertEquals(listOf("pan", "zoom", "rotate"), config.interactionModes)
        assertTrue(config.annotations.isEmpty())
        assertEquals(4, logger.warnings.size)
    }

    @Test
    fun `an annotation with an invalid coordinate is skipped, bad text fields are dropped`() {
        val logger = CapturingLogger()
        val config = resolveMapConfig(
            props(
                """{ "annotations": [
                       { "title": "No coordinate" },
                       { "coordinate": { "latitude": 1.0, "longitude": 2.0 },
                         "title": 42, "subtitle": true }
                     ] }"""
            ),
            logger,
        )
        assertEquals(
            listOf(MapAnnotation(ActionUICoordinate(1.0, 2.0), null, null)),
            config.annotations,
        )
        // Skipped annotation + bad title + bad subtitle.
        assertEquals(3, logger.warnings.size)
    }
}
