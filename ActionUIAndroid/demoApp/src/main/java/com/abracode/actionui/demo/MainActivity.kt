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
import com.abracode.actionui.ActionUI
import com.abracode.actionui.Common.ActionUIImageRegistry
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.DialogButton
import com.abracode.actionui.Common.DialogButtonRole
import com.abracode.actionui.Common.DiscoveringImageRegistry
import com.abracode.actionui.Common.ModalStyle
import com.abracode.actionui.Common.imageRegistryOf
import com.abracode.actionui.demo.ui.theme.ActionUIAndroidTheme

/**
 * Bundled modal sub-document presented by [presentModal] in Modal.json's handlers
 * (see [MainActivity.loadAssetText]). Uses ids (100+) that don't collide with the
 * host document, and a Close button that routes "modal.close" back to
 * [ActionUIModel.dismissModal]. Mirrors the Swift test app's `Sheet.modal.json`.
 */
private const val MODAL_CONTENT_ASSET = "Modal.content.json"

class MainActivity : ComponentActivity() {

    /** Reads a bundled `assets/` document to a String, or null if it can't be read. */
    private fun loadAssetText(path: String): String? =
        runCatching { assets.open(path).bufferedReader().use { it.readText() } }.getOrNull()

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

        // View.template.json - the data-driven template containers. Load/Append/
        // Clear drive the rows API on three template hosts at once (VStack 10,
        // LazyVGrid 40, LazyHStack 30); tapping a templated Button dispatches with
        // viewID = owning container, viewPartID = row index, which the select/chip
        // handlers toast.
        val templateDemoRows = listOf(
            listOf("star.fill", "Favorites"),
            listOf("heart.fill", "Liked"),
            listOf("clock", "Recent"),
            listOf("bookmark.fill", "Saved"),
            listOf("bell.fill", "Notifications"),
            listOf("folder.fill", "Folders"),
        )
        val templateDemoExtraRows = listOf(
            listOf("archivebox.fill", "Archive"),
            listOf("trash.fill", "Trash"),
            listOf("paperplane.fill", "Sent"),
        )
        val templateDemoIDs = listOf(10, 40, 30)
        var templateDemoAppendIndex = 0
        ActionUIModel.registerActionHandler("template.demo.load") { _, windowUUID, _, _, _ ->
            templateDemoIDs.forEach { id ->
                ActionUIModel.setElementRows(windowUUID = windowUUID, viewID = id, rows = templateDemoRows)
            }
        }
        ActionUIModel.registerActionHandler("template.demo.append") { _, windowUUID, _, _, _ ->
            val row = templateDemoExtraRows[templateDemoAppendIndex % templateDemoExtraRows.size]
            templateDemoAppendIndex += 1
            templateDemoIDs.forEach { id ->
                ActionUIModel.appendElementRows(windowUUID = windowUUID, viewID = id, rows = listOf(row))
            }
        }
        ActionUIModel.registerActionHandler("template.demo.clear") { _, windowUUID, _, _, _ ->
            templateDemoIDs.forEach { id ->
                ActionUIModel.clearElementRows(windowUUID = windowUUID, viewID = id)
            }
        }
        ActionUIModel.registerActionHandler("template.demo.select") { _, windowUUID, viewID, viewPartID, _ ->
            val row = ActionUIModel.getElementRows(windowUUID = windowUUID, viewID = viewID).getOrNull(viewPartID)
            Toast.makeText(this, "Cell tapped: ${row?.lastOrNull() ?: "?"} (row $viewPartID)", Toast.LENGTH_SHORT).show()
        }
        ActionUIModel.registerActionHandler("template.demo.chip") { _, windowUUID, viewID, viewPartID, _ ->
            val row = ActionUIModel.getElementRows(windowUUID = windowUUID, viewID = viewID).getOrNull(viewPartID)
            Toast.makeText(this, "Chip tapped: ${row?.lastOrNull() ?: "?"} (row $viewPartID)", Toast.LENGTH_SHORT).show()
        }

        // GeometryReader.json: read the reader's observable states["size"]
        // ([width, height] in dp) on demand - the Android demo surfaces it with
        // a toast where the Swift app leaves the state for the host to poll.
        ActionUIModel.registerActionHandler("geometry.read") { _, windowUUID, _, _, _ ->
            val size = ActionUIModel.getElementState(windowUUID = windowUUID, viewID = 1, key = "size")
            Toast.makeText(this, "GeometryReader size: $size", Toast.LENGTH_SHORT).show()
        }

        // Map.json: the COORDINATE value bridge. "map.read" reads the map's
        // center as the canonical {"latitude":..,"longitude":..} JSON string
        // (updated as the user pans); "map.london" writes a coordinate, panning
        // the map from the host side.
        ActionUIModel.registerActionHandler("map.read") { _, windowUUID, _, _, _ ->
            val center = ActionUIModel.getElementValueAsString(windowUUID = windowUUID, viewID = 1)
            Toast.makeText(this, "Map center: $center", Toast.LENGTH_SHORT).show()
        }
        ActionUIModel.registerActionHandler("map.london") { _, windowUUID, _, _, _ ->
            ActionUIModel.setElementValueFromString(
                windowUUID = windowUUID, viewID = 1,
                value = "{\"latitude\": 51.5074, \"longitude\": -0.1278}",
            )
        }

        // VideoPlayer.json: the String value bridge. "video.read" reads the
        // current source URL; "video.swap" writes a different URL, swapping the
        // video from the host side.
        ActionUIModel.registerActionHandler("video.read") { _, windowUUID, _, _, _ ->
            val url = ActionUIModel.getElementValueAsString(windowUUID = windowUUID, viewID = 1)
            Toast.makeText(this, "VideoPlayer URL: $url", Toast.LENGTH_SHORT).show()
        }
        ActionUIModel.registerActionHandler("video.swap") { _, windowUUID, _, _, _ ->
            ActionUIModel.setElementValueFromString(
                windowUUID = windowUUID, viewID = 1,
                value = "https://www.w3schools.com/html/mov_bbb.mp4",
            )
        }

        // TabView.json: each tab switch passes the new 0-based index as context.
        ActionUIModel.registerActionHandler("tab.changed") { _, _, viewID, _, context ->
            Toast.makeText(this, "TabView $viewID selected tab $context", Toast.LENGTH_SHORT).show()
        }

        // Dialog.json: window-level dialogs presented by the host. "dialog.alert"
        // raises a destructive alert; "dialog.confirm" raises a multi-option
        // confirmation dialog. The dialog buttons' own actionIDs (dialog.deleted /
        // dialog.optionA / ...) route back through the action layer and land on the
        // default handler's toast - showing a dialog button is just another action
        // source. The windowUUID forwarded here targets the window the button fired
        // from, so the dialog attaches to the right window.
        ActionUIModel.registerActionHandler("dialog.alert") { _, windowUUID, _, _, _ ->
            ActionUIModel.presentAlert(
                windowUUID = windowUUID,
                title = "Delete file?",
                message = "This cannot be undone.",
                buttons = listOf(
                    DialogButton("Delete", DialogButtonRole.DESTRUCTIVE, actionID = "dialog.deleted"),
                    DialogButton("Cancel", DialogButtonRole.CANCEL),
                ),
            )
        }
        ActionUIModel.registerActionHandler("dialog.confirm") { _, windowUUID, _, _, _ ->
            ActionUIModel.presentConfirmationDialog(
                windowUUID = windowUUID,
                title = "Choose an option",
                buttons = listOf(
                    DialogButton("Option A", actionID = "dialog.optionA"),
                    DialogButton("Option B", actionID = "dialog.optionB"),
                    DialogButton("Cancel", DialogButtonRole.CANCEL),
                ),
            )
        }

        // Modal.json: window-level modals load a JSON sub-document from assets
        // (MODAL_CONTENT_ASSET) and present it as a bottom sheet or full-screen cover.
        // The modal's Close button fires "modal.close" -> dismissModal. The cover also
        // carries an onDismissActionID ("modal.dismissed") that fires on close (back
        // press or Close), landing on the default handler's toast. Reading the document
        // from the bundle mirrors the Swift handler that loads Sheet.modal.json.
        ActionUIModel.registerActionHandler("modal.sheet") { _, windowUUID, _, _, _ ->
            val json = loadAssetText(MODAL_CONTENT_ASSET) ?: return@registerActionHandler
            ActionUIModel.presentModal(
                windowUUID = windowUUID,
                jsonString = json,
                style = ModalStyle.SHEET,
            )
        }
        ActionUIModel.registerActionHandler("modal.cover") { _, windowUUID, _, _, _ ->
            val json = loadAssetText(MODAL_CONTENT_ASSET) ?: return@registerActionHandler
            ActionUIModel.presentModal(
                windowUUID = windowUUID,
                jsonString = json,
                style = ModalStyle.FULL_SCREEN_COVER,
                onDismissActionID = "modal.dismissed",
            )
        }
        ActionUIModel.registerActionHandler("modal.close") { _, windowUUID, _, _, _ ->
            ActionUIModel.dismissModal(windowUUID)
        }

        ActionUIModel.setDefaultActionHandler { actionID, _, viewID, _, _ ->
            Toast.makeText(this, "Default handler: '$actionID' (viewID=$viewID)", Toast.LENGTH_SHORT).show()
        }

        // Image.assetName.json - the host image registry that resolves Apple
        // asset-catalog names (assetName / assetImage / imageName) to
        // res/drawable, composing both mechanisms: the explicit map first
        // ("ActionUI Logo" is a free-form name an Android resource cannot
        // carry), then the aui_* discovery convention ("Star Badge" ->
        // aui_star_badge, kept through shrinking by the library's keep rule).
        val explicitImages = imageRegistryOf("ActionUI Logo" to R.drawable.actionui_logo)
        val discoveredImages = DiscoveringImageRegistry(this)
        ActionUI.defaultImageRegistry = ActionUIImageRegistry { name ->
            explicitImages.drawableFor(name) ?: discoveredImages.drawableFor(name)
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
