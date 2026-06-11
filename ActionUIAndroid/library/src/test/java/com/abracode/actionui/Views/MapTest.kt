package com.abracode.actionui.Views

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIJson
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.ActionUICoordinate
import com.abracode.actionui.Helpers.coordinateToJson
import com.abracode.actionui.Helpers.parseCoordinate
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the pure half of `Map.kt` - property validation
 * ([resolveMapConfig]), the Leaflet page generation ([leafletMapHtml]),
 * popup escaping ([escapeForPopup]) - and the `CoordinateHelper`
 * parse/serialize pair behind the COORDINATE value bridge. The WebView
 * hosting and the JS bridge are verified by running the app, the stance the
 * rest of the renderer takes for platform-view code.
 */
class MapTest {

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
    // Registry and value bridge
    // -----------------------------------------------------------------------

    @Test
    fun `Map is registered with the coordinate value bridge`() {
        assertSame(MapView, ActionUIRegistry.lookup("Map"))
        assertEquals(ActionUIValueType.COORDINATE, MapView.valueType)
    }

    @Test
    fun `initial value is the coordinate property or the zero coordinate`() {
        val withCoordinate = element(
            """{ "type": "Map", "id": 1, "properties":
                 { "coordinate": { "latitude": 37.33, "longitude": -122.03 } } }"""
        )
        assertEquals(ActionUICoordinate(37.33, -122.03), MapView.initialValue(withCoordinate))
        val without = element("""{ "type": "Map", "id": 1 }""")
        assertEquals(ActionUICoordinate(0.0, 0.0), MapView.initialValue(without))
    }

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

    // -----------------------------------------------------------------------
    // leafletMapHtml (the generated page)
    // -----------------------------------------------------------------------

    @Test
    fun `page centers on the start coordinate and reports through the bridge`() {
        val html = leafletMapHtml(MapConfig(), ActionUICoordinate(37.33, -122.03))
        assertTrue(html.contains("setView([37.33, -122.03], 12)"))
        assertTrue(html.contains("tile.openstreetmap.org"))
        assertTrue(html.contains("OpenStreetMap</a> contributors"))
        assertTrue(html.contains("ActionUIBridge.onCenterChanged(c.lat, c.lng)"))
        assertTrue(html.contains("function actionUISetCenter(lat, lng)"))
    }

    @Test
    fun `page uses the bundled Leaflet, never a CDN`() {
        // Leaflet is vendored in assets/leaflet/ and referenced relative to
        // the page's file base; a CDN script was a single point of failure
        // (one failed fetch = a permanently blank map). Only the OSM tile
        // server may be remote.
        val html = leafletMapHtml(MapConfig(), ActionUICoordinate(0.0, 0.0))
        assertTrue(html.contains("href=\"leaflet.css\""))
        assertTrue(html.contains("src=\"leaflet.js\""))
        assertFalse(html.contains("unpkg.com"))
        assertFalse(html.contains("cdn"))
    }

    @Test
    fun `interaction modes gate the Leaflet handlers`() {
        val zoomOnly = leafletMapHtml(
            MapConfig(interactionModes = listOf("zoom")),
            ActionUICoordinate(0.0, 0.0),
        )
        assertTrue(zoomOnly.contains("dragging: false"))
        assertTrue(zoomOnly.contains("touchZoom: true"))
        val panOnly = leafletMapHtml(
            MapConfig(interactionModes = listOf("pan")),
            ActionUICoordinate(0.0, 0.0),
        )
        assertTrue(panOnly.contains("dragging: true"))
        assertTrue(panOnly.contains("touchZoom: false"))
        assertTrue(panOnly.contains("zoomControl: false"))
    }

    @Test
    fun `annotations become markers with escaped popups`() {
        val html = leafletMapHtml(
            MapConfig(
                annotations = listOf(
                    MapAnnotation(ActionUICoordinate(1.5, 2.5), "Bob's <Place>", "A & B"),
                    MapAnnotation(ActionUICoordinate(3.0, 4.0), null, null),
                ),
            ),
            ActionUICoordinate(0.0, 0.0),
        )
        assertTrue(html.contains("L.marker([1.5, 2.5]).addTo(map).bindPopup('<b>Bob\\'s &lt;Place&gt;</b><br>A &amp; B');"))
        assertTrue(html.contains("L.marker([3.0, 4.0]).addTo(map);"))
    }

    @Test
    fun `popup escaping neutralizes markup and string breakouts`() {
        assertEquals("&lt;script&gt;", escapeForPopup("<script>"))
        assertEquals("a\\'b \\\"c\\\" d\\\\e", escapeForPopup("a'b \"c\" d\\e"))
        assertEquals("line\\nbreak", escapeForPopup("line\nbreak"))
    }
}
