package com.abracode.actionui.Views

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
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.ActionUICoordinate
import com.abracode.actionui.Helpers.booleanProperty
import com.abracode.actionui.Helpers.coordinateProperty
import com.abracode.actionui.Helpers.stringProperty
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/**
 * Interactive map. Mirror of the Apple `Map` element
 * (`ActionUI/Views/Map.swift`, MapKit), rendered as the **default
 * OpenStreetMap provider**: a Leaflet page hosted in the platform
 * [android.webkit.WebView] - zero Gradle dependency, zero API key (see
 * `Private/Android_Porting_Notes.md` entry 53). Android has no in-OS map
 * widget (Google's Maps SDK is a Play Services library needing a billed API
 * key); a host that wants the native Google map can ship its own
 * `ActionUIViewConstruction` and re-register `"Map"` over this default -
 * `ActionUIRegistry.register` is public and last-write-wins.
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
 * **Divergences, all inherent to the OSM default** (documented here, the
 * WebView Apple-only-toggles precedent):
 *   * `showsUserLocation` is accepted but not rendered - it needs the host
 *     app's location permission plumbing, which a library default should not
 *     force; a Google-provider module is the upgrade path.
 *   * `interactionModes` `"rotate"` is accepted but a no-op (Leaflet does not
 *     rotate); `"pan"`/`"zoom"` map to Leaflet's dragging / zoom handlers.
 *   * Leaflet 1.9.4 is **bundled in the library assets**
 *     (`assets/leaflet/`, BSD-2 license included), so the map engine works
 *     offline and has no CDN dependency; only the tiles need network
 *     (`INTERNET` is already required by `LoadableView`). Tiles come from
 *     OpenStreetMap's public servers (attribution shown, per OSM policy;
 *     fair-use traffic - fine for applets, not heavy consumer apps); with no
 *     network the map degrades to a gray grid with controls rather than
 *     rendering nothing.
 *
 * **Sizing.** Like every gesture-owning element here
 * ([[android-bounded-height-scroll]]), it needs a bounded height (an explicit
 * `frame`) when hosted in an unbounded scroll column.
 *
 * Named `MapView` because `Map` collides with `kotlin.collections.Map` (the
 * `ListView`-for-`List` precedent); registered as `"Map"`.
 */
object MapView : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.COORDINATE

    override fun initialValue(element: ActionUIElement): Any? =
        element.properties?.coordinateProperty("coordinate") ?: ActionUICoordinate(0.0, 0.0)

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
                    // library-generated (annotation text is escaped) and the
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
        viewModel: com.abracode.actionui.Common.ViewModel?,
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

/** One validated annotation: a pin with an optional title/subtitle popup. */
internal data class MapAnnotation(
    val coordinate: ActionUICoordinate,
    val title: String? = null,
    val subtitle: String? = null,
)

/** The element's validated properties, resolved once per `properties` change. */
internal data class MapConfig(
    val coordinate: ActionUICoordinate? = null,
    val showsUserLocation: Boolean = false,
    val interactionModes: List<String> = VALID_MAP_MODES,
    val annotations: List<MapAnnotation> = emptyList(),
    val actionID: String? = null,
    val valueChangeActionID: String? = null,
)

private val VALID_MAP_MODES = listOf("pan", "zoom", "rotate")

/**
 * Resolves and validates the map properties, mirroring the Apple
 * `Map.validateProperties` warnings: an invalid `coordinate` is dropped, a
 * non-Boolean `showsUserLocation` defaults to false, malformed
 * `interactionModes` default to all, and annotations are validated
 * per-entry (an invalid coordinate skips the annotation; a non-String
 * title/subtitle is dropped). Pure (logging aside) so it is unit-testable.
 */
internal fun resolveMapConfig(props: JsonObject?, logger: ActionUILogger?): MapConfig {
    if (props == null) return MapConfig()

    var coordinate: ActionUICoordinate? = null
    if (props["coordinate"] != null) {
        coordinate = props.coordinateProperty("coordinate")
        if (coordinate == null) {
            logger?.log(
                "Map coordinate must be a dictionary with latitude/longitude numeric values",
                LoggerLevel.warning,
            )
        }
    }

    var showsUserLocation = false
    if (props["showsUserLocation"] != null) {
        val flag = props.booleanProperty("showsUserLocation")
        if (flag != null) {
            showsUserLocation = flag
        } else {
            logger?.log("Map showsUserLocation must be a Boolean; defaulting to false", LoggerLevel.warning)
        }
    }

    var modes = VALID_MAP_MODES
    val rawModes = props["interactionModes"]
    if (rawModes is JsonArray) {
        val names = rawModes.map { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.contentOrNull }
        if (names.all { it != null && it in VALID_MAP_MODES }) {
            modes = names.filterNotNull()
        } else {
            logger?.log(
                "Map interactionModes must be an array of 'pan', 'zoom', 'rotate'; defaulting to all",
                LoggerLevel.warning,
            )
        }
    } else if (rawModes != null) {
        logger?.log("Map interactionModes must be an array; defaulting to all", LoggerLevel.warning)
    }

    val annotations = mutableListOf<MapAnnotation>()
    val rawAnnotations = props["annotations"]
    if (rawAnnotations is JsonArray) {
        rawAnnotations.forEach { entry ->
            val dict = entry as? JsonObject
            val annotationCoordinate = dict?.coordinateProperty("coordinate")
            if (annotationCoordinate == null) {
                logger?.log("Map annotation coordinate invalid; skipping annotation", LoggerLevel.warning)
                return@forEach
            }
            var title: String? = null
            if (dict["title"] != null) {
                title = (dict["title"] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
                if (title == null) {
                    logger?.log("Map annotation title must be a String; defaulting to nil", LoggerLevel.warning)
                }
            }
            var subtitle: String? = null
            if (dict["subtitle"] != null) {
                subtitle = (dict["subtitle"] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
                if (subtitle == null) {
                    logger?.log("Map annotation subtitle must be a String; defaulting to nil", LoggerLevel.warning)
                }
            }
            annotations.add(MapAnnotation(annotationCoordinate, title, subtitle))
        }
    } else if (rawAnnotations != null) {
        logger?.log("Map annotations must be an array of dictionaries; defaulting to empty", LoggerLevel.warning)
    }

    return MapConfig(
        coordinate = coordinate,
        showsUserLocation = showsUserLocation,
        interactionModes = modes,
        annotations = annotations,
        actionID = props.stringProperty("actionID"),
        valueChangeActionID = props.stringProperty("valueChangeActionID"),
    )
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
 * bundled in the library assets and referenced relative to the page's
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
        val popup = when {
            annotation.title != null && annotation.subtitle != null ->
                "'<b>${escapeForPopup(annotation.title)}</b><br>${escapeForPopup(annotation.subtitle)}'"
            annotation.title != null -> "'<b>${escapeForPopup(annotation.title)}</b>'"
            annotation.subtitle != null -> "'${escapeForPopup(annotation.subtitle)}'"
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
