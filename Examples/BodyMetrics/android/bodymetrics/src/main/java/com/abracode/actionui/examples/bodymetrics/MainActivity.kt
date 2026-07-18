//  BodyMetrics (BMI) - ActionUI Example, Level 1 (Android host)
//
//  Same three jobs as every ActionUI host: (1) load + render the shared JSON,
//  (2) register the one actionID the inputs fire ("bmi.recompute"), (3) read
//  inputs by id, compute, write outputs (values + colors) by id.
//
//  Slider values are always stored in metric (cm, kg) regardless of the toggle;
//  the toggle only changes how the read-out labels are formatted (ft/in, lb).
//  BMI is unit-agnostic, computed from the metric values.
//
//  The COLOR shift is done with setElementProperty(..., "foregroundStyle", value):
//  Android merges the value into the element's propertyOverrides and recomposes,
//  so the named color applies dynamically to the Gauge and the category Text.
//
//  id map (keep in sync with shared/BodyMetrics.json):
//    10  Toggle  imperial units on/off (fires actionID)
//    20  Slider  height, 100-220 cm    (fires valueChangeActionID)
//    21  Text    height read-out
//    30  Slider  weight, 30-200 kg     (fires valueChangeActionID)
//    31  Text    weight read-out
//    40  Gauge   BMI 10-40 (value + foregroundStyle set at runtime)
//    50  Text    BMI numeric
//    60  Text    category (foregroundStyle set at runtime)
//
//  The shared JSON is packaged into assets at build time by build.gradle.kts.

package com.abracode.actionui.examples.bodymetrics

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
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

class MainActivity : ComponentActivity() {

    // id map (keep in sync with shared/BodyMetrics.json)
    private object Id {
        const val IMPERIAL = 10
        const val HEIGHT_SLIDER = 20
        const val HEIGHT_LABEL = 21
        const val WEIGHT_SLIDER = 30
        const val WEIGHT_LABEL = 31
        const val GAUGE = 40
        const val BMI_TEXT = 50
        const val CATEGORY = 60
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // (2) The Toggle and both Sliders all fire "bmi.recompute", so a single
        // handler covers the whole screen.
        ActionUIModel.registerActionHandler("bmi.recompute") { _, windowUUID, _, _, _ ->
            recompute(windowUUID)
        }

        enableEdgeToEdge()
        setContent {
            MaterialTheme {
                Surface(Modifier.fillMaxSize()) {
                    // (1) Load + render the shared JSON from assets.
                    ActionUI.RenderAsset(assetPath = "BodyMetrics.json", modifier = Modifier.fillMaxSize())
                }
            }
        }
    }

    // (3) Read inputs by id (string bridge), compute, write outputs by id.
    private fun recompute(windowUUID: String) {
        val imperial = (ActionUIModel.getElementValueAsString(windowUUID = windowUUID, viewID = Id.IMPERIAL) ?: "false")
            .trim().equals("true", ignoreCase = true)
        val cm = (ActionUIModel.getElementValueAsString(windowUUID = windowUUID, viewID = Id.HEIGHT_SLIDER) ?: "170")
            .trim().toDoubleOrNull() ?: 170.0
        val kg = (ActionUIModel.getElementValueAsString(windowUUID = windowUUID, viewID = Id.WEIGHT_SLIDER) ?: "70")
            .trim().toDoubleOrNull() ?: 70.0

        // BMI = kg / m^2 (unit-agnostic; always from the metric slider values).
        val meters = cm / 100.0
        val bmi = if (meters > 0) kg / (meters * meters) else 0.0

        // Unit-aware read-out labels.
        ActionUIModel.setElementValueFromString(windowUUID = windowUUID, viewID = Id.HEIGHT_LABEL, value = formatHeight(cm, imperial))
        ActionUIModel.setElementValueFromString(windowUUID = windowUUID, viewID = Id.WEIGHT_LABEL, value = formatWeight(kg, imperial))

        // Gauge value tracks BMI; clamp into the gauge's 10-40 range.
        val gaugeValue = min(max(bmi, 10.0), 40.0)
        ActionUIModel.setElementValueFromString(windowUUID = windowUUID, viewID = Id.GAUGE, value = gaugeValue.toString())

        // BMI numeric text.
        ActionUIModel.setElementValueFromString(windowUUID = windowUUID, viewID = Id.BMI_TEXT, value = String.format(Locale.US, "%.1f", bmi))

        // Category name + matching color, applied to both the Gauge and the category Text.
        // Gauge capacity styles also honor `tint`; set both so the ring tracks the zone color.
        val (name, color) = category(bmi)
        ActionUIModel.setElementValueFromString(windowUUID = windowUUID, viewID = Id.CATEGORY, value = name)
        ActionUIModel.setElementProperty(windowUUID = windowUUID, viewID = Id.CATEGORY, propertyName = "foregroundStyle", value = color)
        ActionUIModel.setElementProperty(windowUUID = windowUUID, viewID = Id.GAUGE, propertyName = "foregroundStyle", value = color)
        ActionUIModel.setElementProperty(windowUUID = windowUUID, viewID = Id.GAUGE, propertyName = "tint", value = color)
    }

    // Map BMI to a (label, color-name) pair. Named colors resolve on all platforms.
    private fun category(bmi: Double): Pair<String, String> = when {
        bmi < 18.5 -> "Underweight" to "cyan"
        bmi < 25.0 -> "Normal" to "green"
        bmi < 30.0 -> "Overweight" to "orange"
        else -> "Obese" to "red"
    }

    private fun formatHeight(cm: Double, imperial: Boolean): String {
        if (!imperial) return String.format(Locale.US, "%.0f cm", cm)
        val totalInches = cm / 2.54
        var feet = (totalInches / 12.0).toInt()
        var inches = (totalInches - feet * 12.0).roundToInt()
        if (inches == 12) { feet += 1; inches = 0 }
        return "$feet ft $inches in"
    }

    private fun formatWeight(kg: Double, imperial: Boolean): String {
        if (!imperial) return String.format(Locale.US, "%.0f kg", kg)
        return String.format(Locale.US, "%.0f lb", kg * 2.2046226218)
    }
}
