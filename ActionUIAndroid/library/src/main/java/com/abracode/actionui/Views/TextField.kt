package com.abracode.actionui.Views

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction

/**
 * Single- or multi-line text input. Mirror of the Apple `TextField` element
 * (`ActionUI/Views/TextField.swift`); the rendering and property handling are
 * shared with [SecureField] via [TextInputField] (see that file for the full
 * property mapping, state model, and deferral notes).
 *
 * Sample JSON:
 * ```
 * {
 *   "type": "TextField",
 *   "id": 1,                                  // Optional: positive id for action routing
 *   "properties": {
 *     "title": "Username",                    // Optional: floating label
 *     "prompt": "Enter username",             // Optional: placeholder while empty
 *     "text": "",                             // Optional: initial value
 *     "axis": "vertical",                     // Optional: "vertical" = multi-line
 *     "lineLimit": { "min": 3, "max": 8 },    // Optional: Int or {min?, max?}
 *     "actionID": "text.submit",              // Optional: dispatched on IME submit
 *     "valueChangeActionID": "text.changed"   // Optional: dispatched on every edit
 *   }
 * }
 * ```
 */
object TextField : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        TextInputField(element, modifier, TextInputKind.Plain)
    }
}
