package com.abracode.actionui.map.google

import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the pure half of the Google Maps provider - the
 * `interactionModes` gesture mapping and the self-registration entry point.
 * The map rendering itself needs Play services + an API key and is an
 * on-device check; the shared contract validation is tested in the core
 * library (`MapContractTest`).
 */
class GoogleMapTest {

    @Test
    fun `register installs this provider as the Map element`() {
        // The same call GoogleMapProvider makes at process start; unit tests
        // have no ContentProvider lifecycle, so invoke it directly.
        GoogleMapView.register()
        assertSame(GoogleMapView, ActionUIRegistry.lookup("Map"))
        assertEquals(ActionUIValueType.COORDINATE, GoogleMapView.valueType)
    }

    @Test
    fun `interaction modes map onto the native gesture toggles`() {
        val all = googleMapGestures(listOf("pan", "zoom", "rotate"))
        assertTrue(all.pan)
        assertTrue(all.zoom)
        // Unlike the Leaflet provider, the native map honors rotate.
        assertTrue(all.rotate)

        val panOnly = googleMapGestures(listOf("pan"))
        assertTrue(panOnly.pan)
        assertFalse(panOnly.zoom)
        assertFalse(panOnly.rotate)

        val none = googleMapGestures(emptyList())
        assertFalse(none.pan)
        assertFalse(none.zoom)
        assertFalse(none.rotate)
    }
}
