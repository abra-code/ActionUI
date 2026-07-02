//  TipBillSplitter - ActionUI Example (Android host)
//
//  Same three jobs as every ActionUI host: (1) load + render the shared JSON,
//  (2) register a handler for the actionID the inputs fire ("tip.recompute"),
//  (3) read inputs by integer id, compute, and write the result Texts back by id.
//
//  The id map matches shared/TipBillSplitter.json exactly:
//    10  TextField  bill amount (currency-formatted, fires valueChangeActionID)
//    20  Slider     tip %, 0-30 step 1 (fires valueChangeActionID)
//    30  Stepper    party size, 1-20 step 1 (fires actionID)
//    40  Text       tip amount   (output)
//    50  Text       total        (output)
//    60  Text       per person   (output)
//    80  Text       "Tip: N%"    (output, slider read-out)
//
//  The shared JSON is packaged into assets from ../../shared by build.gradle.kts.

package com.abracode.actionui.examples.tipbillsplitter

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import com.abracode.actionui.ActionUI
import com.abracode.actionui.Common.ActionUIModel
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // (2) One handler for every input. The lambda args are
        // (actionID, windowUUID, viewID, viewPartID, context); we need windowUUID
        // to address this window's elements. All three inputs route here.
        ActionUIModel.registerActionHandler("tip.recompute") { _, windowUUID, _, _, _ ->
            TipBillSplitter.recompute(windowUUID)
        }

        enableEdgeToEdge()
        setContent {
            MaterialTheme {
                Surface(Modifier.fillMaxSize()) {
                    // (1) Load + render the shared JSON from assets.
                    ActionUI.RenderAsset(assetPath = "TipBillSplitter.json", modifier = Modifier.fillMaxSize())

                    // Seed the outputs from the JSON's initial input values once the UI
                    // has loaded, mirroring the Apple/web hosts that recompute() at
                    // launch. Android is single-window, so the window is addressed by
                    // the default empty windowUUID.
                    LaunchedEffect(Unit) { TipBillSplitter.recompute("") }
                }
            }
        }
    }
}

// (3) The recompute. Identical to the Apple/Web hosts apart from the read/write
// call shapes. Reads inputs by id, computes, writes the result Texts back by id.
private object TipBillSplitter {

    private const val BILL_FIELD_ID = 10
    private const val TIP_SLIDER_ID = 20
    private const val PARTY_STEPPER_ID = 30
    private const val TIP_OUT_ID = 40
    private const val TOTAL_OUT_ID = 50
    private const val PER_PERSON_OUT_ID = 60
    private const val TIP_LABEL_ID = 80

    fun recompute(windowUUID: String) {
        // Bill: the currency TextField hands back a String (may carry "$", commas,
        // spaces). Strip to digits and the decimal point, then parse.
        val billRaw = ActionUIModel.getElementValueAsString(windowUUID = windowUUID, viewID = BILL_FIELD_ID) ?: ""
        val bill = parseAmount(billRaw)

        // Tip %: the Slider value is a Double.
        val pct = (ActionUIModel.getElementValue(windowUUID = windowUUID, viewID = TIP_SLIDER_ID) as? Double) ?: 0.0

        // Party size: the Stepper value is a Double; guard people >= 1.
        val peopleRaw = (ActionUIModel.getElementValue(windowUUID = windowUUID, viewID = PARTY_STEPPER_ID) as? Double) ?: 1.0
        val people = max(1, peopleRaw.roundToInt())

        val tip = bill * pct / 100.0
        val total = bill + tip
        val perPerson = total / people

        ActionUIModel.setElementValueFromString(windowUUID = windowUUID, viewID = TIP_OUT_ID, value = currency(tip))
        ActionUIModel.setElementValueFromString(windowUUID = windowUUID, viewID = TOTAL_OUT_ID, value = currency(total))
        ActionUIModel.setElementValueFromString(windowUUID = windowUUID, viewID = PER_PERSON_OUT_ID, value = currency(perPerson))

        // Mirror the tip % into the read-out label.
        ActionUIModel.setElementValueFromString(windowUUID = windowUUID, viewID = TIP_LABEL_ID, value = "Tip: ${pct.roundToInt()}%")
    }

    private fun parseAmount(raw: String): Double {
        val filtered = raw.filter { it.isDigit() || it == '.' }
        return filtered.toDoubleOrNull() ?: 0.0
    }

    private fun currency(value: Double): String {
        val v = if (value.isFinite()) value else 0.0
        // Pin period-decimal output (Locale.US) so the currency string matches the
        // Apple/web hosts regardless of the device's default locale.
        return String.format(Locale.US, "$%.2f", v)
    }
}
