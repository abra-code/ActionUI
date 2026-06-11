package com.abracode.actionui.map.google

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.ActionUICoordinate
import com.abracode.actionui.Helpers.mapInitialCoordinate
import com.abracode.actionui.Helpers.resolveMapConfig
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.MapUiSettings
import com.google.maps.android.compose.Marker
import com.google.maps.android.compose.MarkerState
import com.google.maps.android.compose.rememberCameraPositionState

/**
 * The Google Maps provider for the ActionUI `Map` element: the native map
 * through Google's official maps-compose wrapper around the Maps SDK for
 * Android. Mirror of the Apple `Map` element (`ActionUI/Views/Map.swift`,
 * MapKit); the provider-independent contract (validation, the COORDINATE
 * value bridge) lives in the core library's `Helpers/MapContract.kt` /
 * `Helpers/CoordinateHelper.kt` - this module renders the same JSON
 * documents as `:map-osm`, just on the native engine.
 *
 * Linking this module is all a client does code-wise: [GoogleMapProvider]
 * registers the element at app startup. Link exactly one Map provider
 * module (`:map-osm` or `:map-google`) - with both linked, whichever
 * initializer runs last wins, an undefined order.
 *
 * **Host requirements** (the price of the native map; `:map-osm` has
 * neither): a Maps API key in the app manifest
 * (`<meta-data android:name="com.google.android.geo.API_KEY" ...>`), tied
 * to a billing-enabled Google Cloud project - without it the map renders
 * an empty grid and the SDK logs an authorization failure - and Google
 * Play services on the device.
 *
 * **Contract mapping** (Apple's, key for key, same JSON as `:map-osm`):
 *   * `coordinate` - initial camera center, zoom 12 (the same 0.1-degree
 *     span approximation as the other providers).
 *   * `annotations` - native [Marker]s; `title`/`subtitle` map to the
 *     marker's title/snippet info window (tap to open).
 *   * `interactionModes` - [MapUiSettings] gestures: `pan` -> scroll,
 *     `zoom` -> zoom gestures + controls, and unlike Leaflet the native map
 *     CAN rotate, so `rotate` is honored, not ignored.
 *   * `showsUserLocation` - honored when the host app holds a location
 *     permission at render time (the module declares none - permission
 *     plumbing is the host's); requested without permission it warns and
 *     skips, the Android norm.
 *   * Value bridge ([ActionUIValueType.COORDINATE]): the value is the
 *     camera center. A host write animates the camera; a user gesture
 *     reports the new center back when the camera goes idle and fires
 *     `valueChangeActionID`; the plain `actionID` fires on every
 *     camera-change end, both Apple's behavior. Report-backs are told
 *     apart from host writes with the `lastTracked` guard.
 *
 * **Sizing.** Greedy like every map ([[android-bounded-height-scroll]]):
 * declares `fillMaxSize`, and needs a bounded height (an explicit `frame`)
 * when hosted in an unbounded scroll column.
 */
object GoogleMapView : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.COORDINATE

    override fun initialValue(element: ActionUIElement): Any? = mapInitialCoordinate(element)

    /** Registers this provider as the `Map` element. Called by [GoogleMapProvider] at startup. */
    fun register() {
        ActionUIRegistry.register("Map", this)
    }

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        val config = remember(element.properties) { resolveMapConfig(element.properties, logger) }
        val context = LocalContext.current

        val start = (viewModel?.value as? ActionUICoordinate)
            ?: config.coordinate
            ?: ActionUICoordinate(0.0, 0.0)
        val cameraPositionState = rememberCameraPositionState {
            position = CameraPosition.fromLatLngZoom(LatLng(start.latitude, start.longitude), 12f)
        }
        // The last center this element reported into the model itself, so a
        // host write can be told apart from our own report-back (the WebView
        // element's lastTrackedURL pattern). Starts as the seeded value.
        val lastTracked = remember { mutableStateOf(start) }

        val gestures = remember(config) { googleMapGestures(config.interactionModes) }
        // showsUserLocation is honored only when the host already holds a
        // location permission - enabling the layer without one throws.
        val myLocation = config.showsUserLocation && remember {
            val granted = hasLocationPermission(context)
            if (!granted) {
                logger.log(
                    "Map showsUserLocation requires a location permission the app does not hold; ignoring",
                    LoggerLevel.warning,
                )
            }
            granted
        }

        GoogleMap(
            // A map is greedy (SwiftUI's Map fills whatever its parent
            // offers): fillMaxSize, the ShapeView stance, expanding through
            // the wrapContentSize a fixed frame applies.
            modifier = modifier.fillMaxSize(),
            cameraPositionState = cameraPositionState,
            uiSettings = MapUiSettings(
                scrollGesturesEnabled = gestures.pan,
                scrollGesturesEnabledDuringRotateOrZoom = gestures.pan,
                zoomGesturesEnabled = gestures.zoom,
                zoomControlsEnabled = gestures.zoom,
                rotationGesturesEnabled = gestures.rotate,
                tiltGesturesEnabled = gestures.rotate,
            ),
            properties = MapProperties(isMyLocationEnabled = myLocation),
        ) {
            config.annotations.forEach { annotation ->
                Marker(
                    state = MarkerState(
                        position = LatLng(annotation.coordinate.latitude, annotation.coordinate.longitude),
                    ),
                    title = annotation.title,
                    snippet = annotation.subtitle,
                )
            }
        }

        // Camera-idle report: when a gesture (or animation) ends, push the
        // new center into the model. valueChangeActionID fires only when the
        // center actually changed; the plain actionID fires on every
        // camera-change end, both Apple's behavior.
        LaunchedEffect(cameraPositionState.isMoving) {
            if (cameraPositionState.isMoving) return@LaunchedEffect
            val target = cameraPositionState.position.target
            val coordinate = ActionUICoordinate(target.latitude, target.longitude)
            if (coordinate != lastTracked.value) {
                lastTracked.value = coordinate
                viewModel?.value = coordinate
                config.valueChangeActionID?.let {
                    ActionUIModel.actionHandler(it, viewID = element.id, viewPartID = 0)
                }
            }
            config.actionID?.let {
                ActionUIModel.actionHandler(it, viewID = element.id, viewPartID = 0)
            }
        }

        // Host-write bridge: a coordinate written through setElementValue
        // pans the map. Skips our own report-backs (value == lastTracked).
        val hostValue = viewModel?.value as? ActionUICoordinate
        LaunchedEffect(hostValue) {
            if (hostValue == null || hostValue == lastTracked.value) return@LaunchedEffect
            lastTracked.value = hostValue
            cameraPositionState.animate(
                CameraUpdateFactory.newLatLng(LatLng(hostValue.latitude, hostValue.longitude)),
            )
        }
    }

    private fun hasLocationPermission(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
}

/** The gesture toggles derived from `interactionModes`. */
internal data class GoogleMapGestures(
    val pan: Boolean,
    val zoom: Boolean,
    val rotate: Boolean,
)

/**
 * Maps the validated `interactionModes` (see `resolveMapConfig`) onto the
 * native map's gesture toggles. Unlike the Leaflet provider, `rotate` is
 * honored - the native map rotates (and tilts, its camera sibling). Pure so
 * it is unit-testable.
 */
internal fun googleMapGestures(modes: List<String>): GoogleMapGestures = GoogleMapGestures(
    pan = "pan" in modes,
    zoom = "zoom" in modes,
    rotate = "rotate" in modes,
)
