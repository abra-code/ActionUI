package com.abracode.actionui.demo

import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.demo.ui.theme.ActionUIAndroidTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Demonstrate client-side action registration, mirroring how an Apple
        // host wires up ActionUIModel.shared handlers. The specific handler
        // fires for "button.tap"; everything else (e.g. "button.delete") falls
        // through to the default handler. Exercised by Button.json.
        ActionUIModel.registerActionHandler("button.tap") { actionID, _, viewID, _, _ ->
            Toast.makeText(this, "Handled '$actionID' (viewID=$viewID)", Toast.LENGTH_SHORT).show()
        }

        // Demonstrate the host-side value bridge (StateBinding.json). "field.echo"
        // reads the TextField (viewID 1) out-of-band; "field.fill" writes it, and
        // because the value is the element's ViewModel state the field recomposes.
        // The windowUUID forwarded to the handler is the one the button fired from.
        ActionUIModel.registerActionHandler("field.echo") { _, windowUUID, _, _, _ ->
            val value = ActionUIModel.getElementValueAsString(windowUUID = windowUUID, viewID = 1)
            Toast.makeText(this, "Field value: \"$value\"", Toast.LENGTH_SHORT).show()
        }
        ActionUIModel.registerActionHandler("field.fill") { _, windowUUID, _, _, _ ->
            ActionUIModel.setElementValueFromString(windowUUID = windowUUID, viewID = 1, value = "Filled by host")
        }

        ActionUIModel.setDefaultActionHandler { actionID, _, viewID, _, _ ->
            Toast.makeText(this, "Default handler: '$actionID' (viewID=$viewID)", Toast.LENGTH_SHORT).show()
        }

        enableEdgeToEdge()
        setContent {
            ActionUIAndroidTheme {
                DemoApp()
            }
        }
    }
}

/**
 * Top-level demo shell: a native JSON picker (start screen) that lists the
 * bundled `.json` examples in `assets/` and renders the selected one. Mirrors the
 * Swift test app's selector-then-view flow; see [JsonSelectorScreen]. ActionUI
 * on Android has no navigation elements yet, so this routing lives in plain
 * Compose rather than in an ActionUI document.
 */
@Composable
fun DemoApp() {
    val context = LocalContext.current
    val files = remember { listJsonAssets(context) }
    var selected by rememberSaveable { mutableStateOf<String?>(null) }

    when (val current = selected) {
        null -> JsonSelectorScreen(
            files = files,
            onSelect = { selected = it },
            modifier = Modifier.fillMaxSize(),
        )
        else -> ExampleDetailScreen(
            assetPath = current,
            onBack = { selected = null },
            modifier = Modifier.fillMaxSize(),
        )
    }
}
