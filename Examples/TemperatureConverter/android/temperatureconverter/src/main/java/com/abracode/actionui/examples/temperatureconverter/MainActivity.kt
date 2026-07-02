//  TemperatureConverter - ActionUI Example, Level 1 (Android host)
//
//  Same three jobs as every ActionUI host: (1) load + render the shared JSON,
//  (2) register handlers for the actionIDs it fires, (3) read inputs by id,
//  compute, write the result back by id.
//
//  The shared JSON is copied into assets at build time by app/build.gradle.kts.

package com.abracode.actionui.examples.temperatureconverter

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

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // (2) One handler for the whole screen: the field's valueChangeActionID
        // and both Pickers' actionID all fire "temp.recompute". The lambda gets
        // the windowUUID we use to address this window's elements.
        ActionUIModel.registerActionHandler("temp.recompute") { _, windowUUID, _, _, _ ->
            recompute(windowUUID)
        }

        enableEdgeToEdge()
        setContent {
            MaterialTheme {
                Surface(Modifier.fillMaxSize()) {
                    // (1) Load + render the shared JSON from assets.
                    ActionUI.RenderAsset(assetPath = "TemperatureConverter.json", modifier = Modifier.fillMaxSize())
                }
            }
        }
    }

    // (3) Read the field text and each Picker's selected tag ("C"/"F"/"K"), convert, write result.
    private fun recompute(windowUUID: String) {
        val raw  = ActionUIModel.getElementValueAsString(windowUUID = windowUUID, viewID = 10) ?: ""
        val from = ActionUIModel.getElementValueAsString(windowUUID = windowUUID, viewID = 20) ?: "C"
        val to   = ActionUIModel.getElementValueAsString(windowUUID = windowUUID, viewID = 30) ?: "F"

        val n = raw.trim().toDoubleOrNull()
        if (n == null) {
            // Blank or not a number -> blank result (the "To" picker still shows the unit).
            ActionUIModel.setElementValueFromString(windowUUID = windowUUID, viewID = 40, value = "")
            return
        }
        // The result shows just the number; its unit is the adjacent "To" picker.
        val out = convert(n, from, to)
        ActionUIModel.setElementValueFromString(windowUUID = windowUUID, viewID = 40, value = String.format(Locale.US, "%.2f", out))
    }

    // Convert through Celsius as the common pivot.
    private fun convert(value: Double, from: String, to: String): Double {
        val celsius = when (from) {
            "F" -> (value - 32) * 5 / 9
            "K" -> value - 273.15
            else -> value            // "C"
        }
        return when (to) {
            "F" -> celsius * 9 / 5 + 32
            "K" -> celsius + 273.15
            else -> celsius          // "C"
        }
    }
}
