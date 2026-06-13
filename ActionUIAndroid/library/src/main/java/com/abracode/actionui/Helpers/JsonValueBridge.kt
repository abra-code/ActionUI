package com.abracode.actionui.Helpers

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull

/**
 * Converts between host-side Kotlin values and the [JsonElement] tree the
 * element `properties` are stored as. The bridge behind the property API
 * (`ActionUIModel.get/setElementProperty`): a host passes plain Kotlin values
 * (`0.25`, `true`, `mapOf("x" to 8)`), the override store and the effective-
 * properties merge work in JSON, and reads come back out as plain values.
 *
 * On Apple no conversion exists - `validatedProperties` is `[String: Any]` on
 * both sides. Android's properties are a decoded [JsonObject], so the runtime
 * write-side must produce [JsonElement]s for the merge to be type-uniform.
 */

/**
 * [value] as a [JsonElement], or null when the type cannot be represented
 * (which the caller should warn about): supported are null, [Boolean], [Number],
 * [String], [List] (of supported values), [Map] (String keys, supported values),
 * and [JsonElement] pass-through.
 */
internal fun kotlinValueToJson(value: Any?): JsonElement? = when (value) {
    null -> JsonNull
    is JsonElement -> value
    is Boolean -> JsonPrimitive(value)
    is Int -> JsonPrimitive(value)
    is Long -> JsonPrimitive(value)
    is Float -> JsonPrimitive(value)
    is Double -> JsonPrimitive(value)
    is Number -> JsonPrimitive(value.toDouble())
    is String -> JsonPrimitive(value)
    is List<*> -> {
        val items = value.map { kotlinValueToJson(it) ?: return null }
        JsonArray(items)
    }
    is Map<*, *> -> {
        val entries = value.entries.associate { (k, v) ->
            (k as? String ?: return null) to (kotlinValueToJson(v) ?: return null)
        }
        JsonObject(entries)
    }
    else -> null
}

/**
 * [element] as a plain Kotlin value: [JsonNull] -> null, primitives -> [Boolean]
 * / [Long] / [Double] / [String] (a JSON number with no fraction reads as
 * [Long], otherwise [Double]), arrays -> [List], objects -> [Map].
 */
internal fun jsonToKotlinValue(element: JsonElement): Any? = when (element) {
    is JsonNull -> null
    is JsonPrimitive -> when {
        element.isString -> element.content
        else -> element.booleanOrNull
            ?: element.longOrNull
            ?: element.doubleOrNull
            ?: element.content
    }
    is JsonArray -> element.map { jsonToKotlinValue(it) }
    is JsonObject -> element.mapValues { (_, v) -> jsonToKotlinValue(v) }
}
