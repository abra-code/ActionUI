package com.abracode.actionui.Helpers

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * Typed accessors for reading element `properties` out of a [JsonObject]. The
 * Android counterpart of Apple's `ActionUI/Helpers/Dictionary+Numeric.swift`
 * (`.double(forKey:)`, `.cgFloat(forKey:)`, ...) - leaf utilities that the
 * modifier pipeline and the element builders both lean on, so they live in
 * `Helpers`, not in the engine core.
 *
 * All return `null` for an absent key or a value of the wrong primitive kind, so
 * call sites can `?.let { ... }` an optional property uniformly.
 */

internal fun JsonObject.numberProperty(key: String): Double? =
    get(key)?.jsonPrimitive?.doubleOrNull

internal fun JsonObject.stringProperty(key: String): String? =
    get(key)?.jsonPrimitive?.contentOrNull

internal fun JsonObject.dpProperty(key: String): Dp? =
    numberProperty(key)?.let { it.toFloat().dp }

internal fun JsonObject.floatProperty(key: String): Float? =
    numberProperty(key)?.toFloat()
