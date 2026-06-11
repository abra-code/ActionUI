package com.abracode.actionui.Helpers

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject

/**
 * Geographic-coordinate parsing/serialization for ActionUI Android. The
 * counterpart of Apple's `CLLocationCoordinate2D` value handling in
 * `ActionUI/Views/Map.swift` (`parseStringValue`/`serializeValueToString`) -
 * the single place that turns the canonical coordinate JSON string
 * `{"latitude": N, "longitude": N}` into a value and back, used by the `Map`
 * element and the `COORDINATE` value bridge.
 */

/**
 * A latitude/longitude pair in degrees. The Android analog of Apple's
 * `CLLocationCoordinate2D`: the `Map` element's value type, carried through
 * `getElementValue`/`setElementValue` and serialized to/from the JSON string
 * form by the value-string API.
 */
data class ActionUICoordinate(val latitude: Double, val longitude: Double)

/**
 * Parses the canonical coordinate JSON string
 * (`{"latitude": 37.33, "longitude": -122.03}`) into an [ActionUICoordinate],
 * or null when the string is not JSON or lacks numeric latitude/longitude -
 * mirroring Apple's `Map.parseStringValue` guard.
 */
internal fun parseCoordinate(value: String): ActionUICoordinate? {
    val obj = runCatching { Json.parseToJsonElement(value) }.getOrNull() as? JsonObject ?: return null
    val latitude = obj.numberProperty("latitude") ?: return null
    val longitude = obj.numberProperty("longitude") ?: return null
    return ActionUICoordinate(latitude, longitude)
}

/**
 * The canonical JSON string form of [coordinate], keys sorted like Apple's
 * `serializeValueToString` (`.sortedKeys`: latitude before longitude).
 */
internal fun coordinateToJson(coordinate: ActionUICoordinate): String =
    "{\"latitude\":${coordinate.latitude},\"longitude\":${coordinate.longitude}}"

/**
 * Reads a `{ "latitude": N, "longitude": N }` dictionary property, the JSON
 * shape `Map.coordinate` and each annotation's `coordinate` use. Null when
 * absent or when either member is missing/non-numeric, mirroring Apple's
 * `coordinate(forKey:)` extension.
 */
internal fun JsonObject.coordinateProperty(key: String): ActionUICoordinate? {
    val obj = this[key] as? JsonObject ?: return null
    val latitude = obj.numberProperty("latitude") ?: return null
    val longitude = obj.numberProperty("longitude") ?: return null
    return ActionUICoordinate(latitude, longitude)
}
