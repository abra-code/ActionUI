//  UnitConverter - ActionUI Example, Android host (shared-C edition).
//
//  Same three jobs as every ActionUI host: (1) load + render the shared JSON,
//  (2) register handlers for the actionIDs it fires, (3) read inputs by id,
//  compute, write the result back by id.
//
//  The distinctive part: step (3)'s math is NOT Kotlin. It runs in the shared C
//  file shared/c/convert.c, compiled by the NDK into libunitconverter_native.so
//  (see cpp/CMakeLists.txt) and reached through the NativeBridge JNI object below.
//  Apple compiles that very same convert.c, so both platforms return identical
//  numbers. The shared JSON is copied into assets at build time by build.gradle.kts.

package com.abracode.actionui.examples.unitconverter

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import com.abracode.actionui.ActionUI
import com.abracode.actionui.Common.ActionUIModel
import java.util.Locale

// JNI bridge to the shared C brain. `nativeConvert` forwards straight into
// aui_convert() in shared/c/convert.c. System.loadLibrary pulls in the .so the
// NDK built from that same .c.
object NativeBridge {
    init {
        System.loadLibrary("unitconverter_native")
        nativeHello()
    }
    external fun nativeHello()
    external fun nativeConvert(category: Int, fromUnit: Int, toUnit: Int, value: Double): Double
}

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // (2) Two actionIDs. "unit.recompute" fires from the amount field and both
        // unit pickers; "unit.category" fires from the segmented category picker and
        // snaps both unit pickers to that category's first unit.
        ActionUIModel.registerActionHandler("unit.recompute") { _, windowUUID, _, _, _ ->
            recompute(windowUUID)
        }
        ActionUIModel.registerActionHandler("unit.category") { _, windowUUID, _, _, _ ->
            categoryChanged(windowUUID)
        }

        enableEdgeToEdge()
        setContent {
            MaterialTheme {
                Surface(Modifier.fillMaxSize()) {
                    // (1) Load + render the shared JSON from assets.
                    ActionUI.RenderAsset(assetPath = "UnitConverter.json", modifier = Modifier.fillMaxSize())
                }
            }
        }
    }

    // (3) Read inputs, call the shared C function over JNI, write the result.
    private fun recompute(windowUUID: String) {
        val raw     = ActionUIModel.getElementValueAsString(windowUUID = windowUUID, viewID = 10) ?: ""
        val fromTag = ActionUIModel.getElementValueAsString(windowUUID = windowUUID, viewID = 20) ?: "L0"
        val toTag   = ActionUIModel.getElementValueAsString(windowUUID = windowUUID, viewID = 30) ?: "L0"

        val n = raw.trim().toDoubleOrNull()
        if (n == null) {
            ActionUIModel.setElementValueFromString(windowUUID = windowUUID, viewID = 40, value = "")
            return
        }
        val cat = categoryIndex(fromTag)
        if (cat == null || categoryIndex(toTag) != cat) {
            ActionUIModel.setElementValueFromString(windowUUID = windowUUID, viewID = 40, value = "-")
            return
        }
        val out = NativeBridge.nativeConvert(cat, unitIndex(fromTag), unitIndex(toTag), n)
        ActionUIModel.setElementValueFromString(windowUUID = windowUUID, viewID = 40, value = trimmed(out))
    }

    // On category change (and once on appear, via the picker's onAppearActionID):
    // repopulate both unit pickers with only that category's units (setElementProperty
    // "options" - the Picker recomposes off the merged effective element), then select
    // the category's default from/to pair (which keeps from/to in the same category so a
    // conversion is always valid), then recompute. Setting the options before the values
    // keeps the new selections inside the fresh list. Both writes are portable across hosts.
    private fun categoryChanged(windowUUID: String) {
        val category = ActionUIModel.getElementValueAsString(windowUUID = windowUUID, viewID = 5) ?: "length"
        val options = unitOptions(category)
        ActionUIModel.setElementProperty(windowUUID = windowUUID, viewID = 20, propertyName = "options", value = options)
        ActionUIModel.setElementProperty(windowUUID = windowUUID, viewID = 30, propertyName = "options", value = options)
        val (from, to) = defaultTags(category)
        ActionUIModel.setElementValueFromString(windowUUID = windowUUID, viewID = 20, value = from)
        ActionUIModel.setElementValueFromString(windowUUID = windowUUID, viewID = 30, value = to)
        recompute(windowUUID)
    }

    // The from/to unit menus are populated per category, so a conversion is always
    // within one category (no nonsensical length -> temperature). Tags mirror the enum
    // indices in shared/c/convert.h. categoryChanged pushes this list into both pickers.
    private fun unitOptions(category: String): List<Map<String, String>> = when (category) {
        "mass" -> listOf(
            mapOf("title" to "kilogram", "tag" to "M0"),
            mapOf("title" to "gram", "tag" to "M1"),
            mapOf("title" to "pound", "tag" to "M2"),
            mapOf("title" to "ounce", "tag" to "M3"),
        )
        "temperature" -> listOf(
            mapOf("title" to "Celsius", "tag" to "T0"),
            mapOf("title" to "Fahrenheit", "tag" to "T1"),
            mapOf("title" to "Kelvin", "tag" to "T2"),
        )
        else -> listOf( // "length"
            mapOf("title" to "meter", "tag" to "L0"),
            mapOf("title" to "centimeter", "tag" to "L1"),
            mapOf("title" to "kilometer", "tag" to "L2"),
            mapOf("title" to "inch", "tag" to "L3"),
            mapOf("title" to "foot", "tag" to "L4"),
            mapOf("title" to "mile", "tag" to "L5"),
        )
    }

    // from/to tags are "L0".."L5" (length), "M0".."M3" (mass), "T0".."T2" (temp).
    // Leading letter = category, trailing integer = unit index within the category,
    // exactly the enum values in shared/c/convert.h.
    private fun categoryIndex(tag: String): Int? = when (tag.firstOrNull()) {
        'L' -> 0 // AUI_CAT_LENGTH
        'M' -> 1 // AUI_CAT_MASS
        'T' -> 2 // AUI_CAT_TEMPERATURE
        else -> null
    }

    private fun unitIndex(tag: String): Int = tag.drop(1).toIntOrNull() ?: 0

    // Each category opens on a sensible, non-trivial conversion rather than unit -> same
    // unit: meter -> foot, kilogram -> pound, Celsius -> Fahrenheit. categoryChanged
    // applies this pair on every switch, and the category picker's onAppearActionID
    // fires categoryChanged once on appear to apply the initial (length) pair too.
    private fun defaultTags(category: String): Pair<String, String> = when (category) {
        "mass" -> "M0" to "M2"          // kilogram -> pound
        "temperature" -> "T0" to "T1"   // Celsius -> Fahrenheit
        else -> "L0" to "L4"            // meter -> foot ("length")
    }

    // Tidy number: integers print whole; otherwise cap at 2 decimals (enough for a
    // readable result, and short enough that the result field never wraps and grows).
    private fun trimmed(value: Double): String {
        if (value == Math.rint(value) && Math.abs(value) < 1e15) {
            return value.toLong().toString()
        }
        var s = String.format(Locale.US, "%.2f", value)
        s = s.trimEnd('0').trimEnd('.')
        return s
    }
}
