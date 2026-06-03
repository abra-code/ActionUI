package com.abracode.actionui.Views

import androidx.compose.foundation.layout.height
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.booleanProperty
import com.abracode.actionui.Helpers.stringProperty
import kotlinx.serialization.json.JsonObject

/**
 * Multi-line text editor with an automatic internal scroller. Mirror of the
 * Apple `TextEditor` element (`ActionUI/Views/TextEditor.swift`), which wraps
 * `SwiftUI.TextEditor`.
 *
 * Rendered as a multi-line Material3 [OutlinedTextField] (consistent with
 * [TextField]/[SecureField]) with `singleLine = false` and a **bounded height**,
 * so its content scrolls internally once it overflows the visible area - the
 * "automatic scroller" the element is for. The height comes from the inherited
 * `frame.height` when supplied; otherwise a sensible [DEFAULT_HEIGHT] default is
 * applied so there is always something to scroll within.
 *
 * **Supported properties.**
 *   * `text`        - initial plain-text content (defaults to "").
 *   * `placeholder` - shown while the editor is empty.
 *   * `readOnly`    - when true the text is selectable/scrollable but not
 *     editable (Compose `readOnly`), distinct from a fully disabled field.
 *   * `valueChangeActionID` - dispatched through [ActionUIModel] on every edit,
 *     matching the Apple binding's `set` closure.
 *   * plus the universal modifiers resolved by `applyCommonProperties` (applied
 *     via [modifier]) - notably `frame.height` to size the editor.
 *
 * **State.** Held in local [rememberSaveable] keyed by element id, the same
 * Phase-1 stance [TextField]/[SecureField] take; the programmatic
 * `get/setElementValue` bridge is deferred until the `ViewModel` layer lands
 * (see `Private/Android_Porting_Notes.md` sections 6 and 14).
 *
 * **Deferred vs. Apple.** `markdown` (attributed editing, macOS/iOS 26+) has no
 * Compose equivalent: when supplied without `text`, its raw string is shown as
 * plain editable text and a warning is logged. There is no rich/attributed value.
 */
object TextEditor : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current

        val placeholder = props?.stringProperty("placeholder")
        val readOnly = props?.booleanProperty("readOnly") ?: false
        val valueChangeActionID = props?.stringProperty("valueChangeActionID")

        // Initial content: "text" wins. A "markdown" string (attributed editing
        // is unsupported on Android) is shown as raw plain text, with a warning.
        val markdown = props?.stringProperty("markdown")
        val initialValue = props?.stringProperty("text") ?: markdown ?: ""
        if (markdown != null) {
            logger.log(
                "TextEditor 'markdown' (attributed editing) is not supported on Android; " +
                    "showing it as plain text",
                LoggerLevel.warning
            )
        }

        // Bound the height so the editor scrolls internally instead of growing
        // without limit. An inherited frame.height (already on `modifier`) wins;
        // otherwise apply a default so there is always a scroller.
        val hasExplicitHeight = (props?.get("frame") as? JsonObject)?.get("height") != null
        val editorModifier = if (hasExplicitHeight) modifier else modifier.height(DEFAULT_HEIGHT)

        var text by rememberSaveable(element.id) { mutableStateOf(initialValue) }

        OutlinedTextField(
            value = text,
            onValueChange = { new ->
                if (new != text) {
                    text = new
                    if (valueChangeActionID != null) {
                        ActionUIModel.actionHandler(valueChangeActionID, viewID = element.id, viewPartID = 0)
                    }
                }
            },
            modifier = editorModifier,
            readOnly = readOnly,
            singleLine = false,
            placeholder = placeholder?.let { { M3Text(it) } },
        )
    }

    /** Default editor height when JSON supplies no `frame.height` (room for a few lines). */
    private val DEFAULT_HEIGHT = 140.dp
}
