package com.abracode.actionui.map.osm

import android.annotation.SuppressLint
import android.webkit.JavascriptInterface
import android.webkit.WebView as AndroidWebView
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Common.ViewModel
import com.abracode.actionui.Helpers.ActionUICoordinate
import com.abracode.actionui.Helpers.MapConfig
import com.abracode.actionui.Helpers.mapInitialCoordinate
import com.abracode.actionui.Helpers.resolveMapConfig

/**
 * The OpenStreetMap provider for the ActionUI `Map` element: a Leaflet page
 * hosted in the platform [android.webkit.WebView]. Dependency- and key-free -
 * Leaflet 1.9.4 is bundled in this module's assets (`assets/leaflet/`, BSD-2
 * license included), so the map engine works offline; only the OSM tiles
 * need network. Mirror of the Apple `Map` element
 * (`ActionUI/Views/Map.swift`, MapKit); the provider-independent contract
 * (validation, the COORDINATE value bridge) lives in the core library's
 * `Helpers/MapContract.kt` / `Helpers/CoordinateHelper.kt`.
 *
 * Linking this module is all a client does: [OsmMapProvider] registers the
 * element at app startup. Link exactly one Map provider module (`:map-osm`
 * or `:map-google`) - with both linked, whichever initializer runs last
 * wins, an undefined order.
 *
 * Sample JSON (Apple's contract, key for key):
 * ```
 * {
 *   "type": "Map",
 *   "id": 1,                                  // Positive id for the value bridge
 *   "properties": {
 *     "coordinate": { "latitude": 37.33, "longitude": -122.03 }, // Initial center
 *     "showsUserLocation": false,             // Accepted; not rendered (below)
 *     "interactionModes": ["pan", "zoom"],    // Default all; "rotate" accepted, no-op
 *     "annotations": [
 *       { "coordinate": { "latitude": 37.332, "longitude": -122.031 },
 *         "title": "Point", "subtitle": "Subtitle" }
 *     ],
 *     "valueChangeActionID": "map.moved",     // Fired when the center changes
 *     "frame": { "height": 320 }              // A gesture-owning element: bound its height
 *   }
 * }
 * ```
 *
 * **Value bridge** ([ActionUIValueType.COORDINATE], Apple's contract): the
 * value is the map's center [ActionUICoordinate]. A host write pans the map
 * (`setElementValueFromString(.., "{\"latitude\":51.5,\"longitude\":-0.13}")`);
 * a user pan reports the new center back and fires `valueChangeActionID`.
 * Like Apple, the plain `actionID` fires on every camera-change end. The
 * element's own report-backs are told apart from host writes with the
 * `lastTracked` guard, the WebView element's `lastTrackedURL` pattern.
 *
 * **Divergences, all inherent to the OSM provider** (documented here, the
 * WebView Apple-only-toggles precedent):
 *   * `showsUserLocation` is accepted but not rendered - it needs the host
 *     app's location permission plumbing, which this provider does not
 *     force; the `:map-google` module is the upgrade path.
 *   * `interactionModes` `"rotate"` is accepted but a no-op (Leaflet does not
 *     rotate); `"pan"`/`"zoom"` map to Leaflet's dragging / zoom handlers.
 *   * Tiles come from OpenStreetMap's public servers (attribution shown, per
 *     OSM policy; fair-use traffic - fine for applets, not heavy consumer
 *     apps), needing network (`INTERNET` is already required by the core
 *     library); with no network the map degrades to a gray grid with
 *     pin/controls/attribution rather than rendering nothing. Page console
 *     errors and tile failures surface through the ActionUI logger.
 *
 * **Sizing.** Like every gesture-owning element ([[android-bounded-height-scroll]]),
 * it needs a bounded height (an explicit `frame`) when hosted in an
 * unbounded scroll column. The element is greedy (SwiftUI's Map fills
 * whatever its parent offers), declared via `fillMaxSize` like ShapeView.
 */
object OsmMapView : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.COORDINATE

    override fun initialValue(element: ActionUIElement): Any? = mapInitialCoordinate(element)

    /** Registers this provider as the `Map` element. Called by [OsmMapProvider] at startup. */
    fun register() {
        ActionUIRegistry.register("Map", this)
    }

    @SuppressLint("SetJavaScriptEnabled")
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        val config = remember(element.properties) { resolveMapConfig(element.properties, logger) }

        var mapView by remember { mutableStateOf<AndroidWebView?>(null) }
        // The last center this element reported into the model itself, so a
        // host write can be told apart from our own report-back (the WebView
        // element's lastTrackedURL pattern). Starts as the seeded value.
        val lastTracked = remember {
            mutableStateOf(
                (viewModel?.value as? ActionUICoordinate)
                    ?: config.coordinate
                    ?: ActionUICoordinate(0.0, 0.0)
            )
        }

        // A map is greedy (SwiftUI's Map fills whatever its parent offers), so
        // like ShapeView it declares fillMaxSize - expanding through the
        // wrapContentSize a fixed frame applies, which would otherwise hand
        // the WebView loose constraints and let the page's percentage-height
        // layout collapse or overflow the frame box.
        AndroidView(
            modifier = modifier.fillMaxSize(),
            factory = { context ->
                AndroidWebView(context).apply {
                    settings.javaScriptEnabled = true
                    // The page loads with a file:///android_asset base so the
                    // bundled Leaflet js/css/marker images resolve from the
                    // APK; file subresource loads need this opt-in (off by
                    // default since API 30). The page content is entirely
                    // module-generated (annotation text is escaped) and the
                    // only remote subresources are tile images.
                    settings.allowFileAccess = true
                    // Surface page errors (a failed tile load, a JS error)
                    // through the ActionUI logger instead of swallowing them.
                    webChromeClient = object : android.webkit.WebChromeClient() {
                        override fun onConsoleMessage(message: android.webkit.ConsoleMessage): Boolean {
                            logger.log(
                                "Map page console: ${message.message()} " +
                                    "(${message.sourceId()}:${message.lineNumber()})",
                                LoggerLevel.debug,
                            )
                            return true
                        }
                    }
                    val view = this
                    addJavascriptInterface(
                        object {
                            // Leaflet's moveend reports the new center here.
                            // JS-interface calls arrive on a WebView-internal
                            // thread; hop to main before touching snapshot state.
                            @JavascriptInterface
                            fun onCenterChanged(latitude: Double, longitude: Double) {
                                view.post {
                                    reportCenter(
                                        ActionUICoordinate(latitude, longitude),
                                        viewModel, lastTracked, config, element,
                                    )
                                }
                            }
                        },
                        "ActionUIBridge",
                    )
                    val start = (viewModel?.value as? ActionUICoordinate)
                        ?: config.coordinate
                        ?: ActionUICoordinate(0.0, 0.0)
                    // The asset base resolves the bundled Leaflet files; the
                    // https tile images load fine from a file-origin page.
                    loadDataWithBaseURL(
                        "file:///android_asset/leaflet/", leafletMapHtml(config, start),
                        "text/html", "utf-8", null,
                    )
                }.also { mapView = it }
            },
            onRelease = {
                if (mapView === it) mapView = null
                it.destroy()
            },
        )

        // Host-write bridge: a coordinate written through setElementValue pans
        // the map. Skips our own report-backs (value == lastTracked).
        val hostValue = viewModel?.value as? ActionUICoordinate
        LaunchedEffect(hostValue) {
            val view = mapView ?: return@LaunchedEffect
            if (hostValue == null || hostValue == lastTracked.value) return@LaunchedEffect
            lastTracked.value = hostValue
            view.evaluateJavascript(
                "actionUISetCenter(${hostValue.latitude}, ${hostValue.longitude});", null,
            )
        }
    }

    /**
     * Pushes a moved-to center into the model. `valueChangeActionID` fires only
     * when the center actually changed; the plain `actionID` fires on every
     * camera-change end, both Apple's behavior.
     */
    private fun reportCenter(
        coordinate: ActionUICoordinate,
        viewModel: ViewModel?,
        lastTracked: MutableState<ActionUICoordinate>,
        config: MapConfig,
        element: ActionUIElement,
    ) {
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
}

/**
 * Escapes annotation text for inclusion inside a single-quoted JS string that
 * Leaflet renders as popup HTML: HTML entities first (the text shows as
 * literal text, no markup injection), then the JS string escapes. Pure so it
 * is unit-testable.
 */
internal fun escapeForPopup(text: String): String = text
    .replace("&", "&amp;")
    .replace("<", "&lt;")
    .replace(">", "&gt;")
    .replace("\\", "\\\\")
    .replace("'", "\\'")
    .replace("\"", "\\\"")
    .replace("\r", "")
    .replace("\n", "\\n")

/**
 * The Leaflet/OSM page for [config], centered on [start]. Leaflet 1.9.4 is
 * bundled in this module's assets and referenced relative to the page's
 * `file:///android_asset/leaflet/` base (a CDN `<script src>` was a single
 * point of failure: one failed fetch left a permanently blank map); OSM
 * tiles with the required attribution, one marker per annotation (title
 * bold, subtitle beneath, as Apple's annotation view stacks them),
 * interaction handlers per `interactionModes`, and the
 * `ActionUIBridge.onCenterChanged` report on `moveend`. The initial zoom 12
 * approximates Apple's fixed 0.1-degree span. Pure so it is unit-testable.
 *
 * ## Sizing inside the hosted WebView (two traps, both hit during bring-up)
 *
 * CSS viewport heights do not work in this page: `height: 100%` chains AND
 * absolute-inset positioning both compute to 0px even while
 * `documentElement.clientHeight` reports the real height - so the map div
 * gets an **explicit pixel height** from the measured client height,
 * re-applied on `resize` (with `map.invalidateSize()`). And the page begins
 * loading while the hosting View may still be unmeasured (the AndroidView
 * factory runs before layout), so Leaflet initializes only once the viewport
 * has nonzero height - a Leaflet map created into a zero-size container
 * stays blank.
 */
internal fun leafletMapHtml(config: MapConfig, start: ActionUICoordinate): String {
    val pan = "pan" in config.interactionModes
    val zoom = "zoom" in config.interactionModes
    val markers = config.annotations.joinToString("\n") { annotation ->
        val title = annotation.title
        val subtitle = annotation.subtitle
        val popup = when {
            title != null && subtitle != null ->
                "'<b>${escapeForPopup(title)}</b><br>${escapeForPopup(subtitle)}'"
            title != null -> "'<b>${escapeForPopup(title)}</b>'"
            subtitle != null -> "'${escapeForPopup(subtitle)}'"
            else -> null
        }
        val marker = "L.marker([${annotation.coordinate.latitude}, ${annotation.coordinate.longitude}]).addTo(map)"
        if (popup != null) "$marker.bindPopup($popup);" else "$marker;"
    }
    return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <link rel="stylesheet" href="leaflet.css"/>
        <script src="leaflet.js"></script>
        <style>
        html, body { margin: 0; }
        #map { width: 100%; }
        </style>
        </head>
        <body>
        <div id="map"></div>
        <script>
        window.onerror = function(m, s, l) { console.log('Map page error: ' + m + ' @' + s + ':' + l); };
        var map = null;
        function actionUISetCenter(lat, lng) {
            if (map) { map.setView([lat, lng], map.getZoom()); }
        }
        function initMap() {
            map = L.map('map', {
                dragging: $pan,
                touchZoom: $zoom,
                scrollWheelZoom: $zoom,
                doubleClickZoom: $zoom,
                boxZoom: $zoom,
                zoomControl: $zoom,
                keyboard: false
            }).setView([${start.latitude}, ${start.longitude}], 12);
            var tiles = L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
                maxZoom: 19,
                attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
            }).addTo(map);
            tiles.on('tileerror', function(e) { console.log('Map tile error: ' + e.tile.src); });
            $markers
            map.on('moveend', function() {
                var c = map.getCenter();
                if (window.ActionUIBridge) { ActionUIBridge.onCenterChanged(c.lat, c.lng); }
            });
        }
        // CSS viewport heights (percentage chains, absolute insets) all
        // resolve to 0 in this hosted page, so the map div gets an explicit
        // pixel height from the document's measured client height instead,
        // re-applied on resize. The page also loads while the hosting View
        // may still be 0x0 (the factory runs before layout), so wait for the
        // viewport to gain height before initializing Leaflet.
        function sizeMapDiv() {
            document.getElementById('map').style.height =
                document.documentElement.clientHeight + 'px';
        }
        window.addEventListener('resize', function() {
            sizeMapDiv();
            if (map) { map.invalidateSize(); }
        });
        function initWhenSized() {
            if (document.documentElement.clientHeight > 0) {
                sizeMapDiv();
                initMap();
            } else {
                setTimeout(initWhenSized, 50);
            }
        }
        initWhenSized();
        </script>
        </body>
        </html>
    """.trimIndent()
}
