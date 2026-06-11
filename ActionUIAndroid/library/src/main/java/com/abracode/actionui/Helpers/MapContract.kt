package com.abracode.actionui.Helpers

import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/**
 * The provider-independent half of the `Map` element: Apple's JSON contract
 * (`ActionUI/Views/Map.swift`), validated once here so every Map provider
 * module renders the same documents identically.
 *
 * The element itself does NOT ship in the core library - a map engine is
 * distribution baggage for clients that never show one. Instead a client
 * links exactly one **provider module** (`:map-osm` - Leaflet/OpenStreetMap
 * in the platform WebView, dependency- and key-free; or `:map-google` -
 * the native Google map via maps-compose, Play Services + API key), which
 * self-registers its `ActionUIViewConstruction` as `"Map"` at app startup.
 * What the providers share - this contract parsing, plus the
 * [ActionUIValueType.COORDINATE] value bridge and [ActionUICoordinate] -
 * lives here in core, public, because a provider module cannot add a value
 * type or registry semantics from outside.
 *
 * [com.abracode.actionui.Common.ActionUIValueType.COORDINATE]
 */

/** One validated annotation: a pin with an optional title/subtitle popup. */
data class MapAnnotation(
    val coordinate: ActionUICoordinate,
    val title: String? = null,
    val subtitle: String? = null,
)

/** The `Map` element's validated properties, resolved once per `properties` change. */
data class MapConfig(
    val coordinate: ActionUICoordinate? = null,
    val showsUserLocation: Boolean = false,
    val interactionModes: List<String> = listOf("pan", "zoom", "rotate"),
    val annotations: List<MapAnnotation> = emptyList(),
    val actionID: String? = null,
    val valueChangeActionID: String? = null,
)

private val VALID_MAP_MODES = listOf("pan", "zoom", "rotate")

/**
 * The seed for the `Map` element's [com.abracode.actionui.Common.ViewModel]:
 * the `coordinate` property, or the zero coordinate. Providers return this
 * from `initialValue`, mirroring the Apple `Map.initialValue`.
 */
fun mapInitialCoordinate(element: ActionUIElement): ActionUICoordinate =
    element.properties?.coordinateProperty("coordinate") ?: ActionUICoordinate(0.0, 0.0)

/**
 * Resolves and validates the map properties, mirroring the Apple
 * `Map.validateProperties` warnings: an invalid `coordinate` is dropped, a
 * non-Boolean `showsUserLocation` defaults to false, malformed
 * `interactionModes` default to all, and annotations are validated
 * per-entry (an invalid coordinate skips the annotation; a non-String
 * title/subtitle is dropped). Pure (logging aside) so it is unit-testable.
 */
fun resolveMapConfig(props: JsonObject?, logger: ActionUILogger?): MapConfig {
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
