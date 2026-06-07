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

        // Demonstrate the host-side value bridge (View.stateBinding.json). "field.echo"
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

        // Toggle.json dispatches "toggle.changed" on every flip, passing the new
        // Boolean as the action context - shows a value-bearing control routing
        // its value through the action layer.
        ActionUIModel.registerActionHandler("toggle.changed") { _, _, viewID, _, context ->
            Toast.makeText(this, "Toggle $viewID is now $context", Toast.LENGTH_SHORT).show()
        }

        // Slider.json: read the live Double position on demand, and write it from
        // the host - the slider snaps to the new value because it is ViewModel state.
        ActionUIModel.registerActionHandler("slider.read") { _, windowUUID, _, _, _ ->
            val value = ActionUIModel.getElementValueAsString(windowUUID = windowUUID, viewID = 1)
            Toast.makeText(this, "Slider value: $value", Toast.LENGTH_SHORT).show()
        }
        ActionUIModel.registerActionHandler("slider.set") { _, windowUUID, _, _, _ ->
            ActionUIModel.setElementValueFromString(windowUUID = windowUUID, viewID = 1, value = "75")
        }

        // Picker.json: each picker passes its selected tag as the action context;
        // "picker.read" reads the menu picker's (id 1) current tag on demand.
        ActionUIModel.registerActionHandler("picker.changed") { _, _, viewID, _, context ->
            Toast.makeText(this, "Picker $viewID selected '$context'", Toast.LENGTH_SHORT).show()
        }
        ActionUIModel.registerActionHandler("picker.read") { _, windowUUID, _, _, _ ->
            val tag = ActionUIModel.getElementValueAsString(windowUUID = windowUUID, viewID = 1)
            Toast.makeText(this, "Language tag: '$tag'", Toast.LENGTH_SHORT).show()
        }

        // List.selection.json - mirrors the Swift test app's List demo. Load/Append/
        // Clear drive the rows API on the List (viewID 1); tapping a row fires the
        // selection handler, which toasts the selected item. (The Android demo
        // surfaces value feedback with toasts, as the Slider/Picker demos do; the
        // Swift app updates an in-document label instead, which needs a value-bound
        // Text - not yet ported.)
        val listExtraItems = listOf("Haskell", "Elixir", "Julia", "Zig", "Dart")
        var listAppendIndex = 0
        ActionUIModel.registerActionHandler("list.demo.load") { _, windowUUID, _, _, _ ->
            ActionUIModel.setElementRows(
                windowUUID = windowUUID, viewID = 1,
                rows = listOf(
                    listOf("Swift"), listOf("Python"), listOf("Kotlin"),
                    listOf("TypeScript"), listOf("Rust"), listOf("Go"),
                ),
            )
            ActionUIModel.setElementValue(windowUUID = windowUUID, viewID = 1, value = emptyList<String>())
        }
        ActionUIModel.registerActionHandler("list.demo.append") { _, windowUUID, _, _, _ ->
            val item = listExtraItems[listAppendIndex % listExtraItems.size]
            listAppendIndex += 1
            ActionUIModel.appendElementRows(windowUUID = windowUUID, viewID = 1, rows = listOf(listOf(item)))
        }
        ActionUIModel.registerActionHandler("list.demo.clear") { _, windowUUID, _, _, _ ->
            ActionUIModel.clearElementRows(windowUUID = windowUUID, viewID = 1)
            ActionUIModel.setElementValue(windowUUID = windowUUID, viewID = 1, value = emptyList<String>())
        }
        ActionUIModel.registerActionHandler("list.demo.selection.changed") { _, windowUUID, _, _, _ ->
            val selected = ActionUIModel.getElementValueAsString(windowUUID = windowUUID, viewID = 1)
            val label = if (selected.isNullOrEmpty()) "(none)" else selected
            Toast.makeText(this, "Selected: $label", Toast.LENGTH_SHORT).show()
        }

        // TabView.json: each tab switch passes the new 0-based index as context.
        ActionUIModel.registerActionHandler("tab.changed") { _, _, viewID, _, context ->
            Toast.makeText(this, "TabView $viewID selected tab $context", Toast.LENGTH_SHORT).show()
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
    // The synthetic RenderSource entry leads; the bundled assets follow (sorted).
    val files = remember { listOf(RENDER_SOURCE_DEMO_LABEL) + listJsonAssets(context) }
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
