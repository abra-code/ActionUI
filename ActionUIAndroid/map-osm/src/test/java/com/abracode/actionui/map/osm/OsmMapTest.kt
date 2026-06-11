package com.abracode.actionui.map.osm

import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Helpers.ActionUICoordinate
import com.abracode.actionui.Helpers.MapAnnotation
import com.abracode.actionui.Helpers.MapConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the pure half of the OSM Map provider - the Leaflet page
 * generation ([leafletMapHtml]), popup escaping ([escapeForPopup]), and the
 * self-registration entry point. The WebView hosting and the JS bridge are
 * verified by running the app; the shared contract validation is tested in
 * the core library (`MapContractTest`).
 */
class OsmMapTest {

    @Test
    fun `register installs this provider as the Map element`() {
        // The same call OsmMapProvider makes at process start; unit tests
        // have no ContentProvider lifecycle, so invoke it directly.
        OsmMapView.register()
        assertSame(OsmMapView, ActionUIRegistry.lookup("Map"))
        assertEquals(ActionUIValueType.COORDINATE, OsmMapView.valueType)
    }

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
        // Leaflet is vendored in this module's assets/leaflet/ and referenced
        // relative to the page's file base; a CDN script was a single point
        // of failure (one failed fetch = a permanently blank map). Only the
        // OSM tile server may be remote.
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
