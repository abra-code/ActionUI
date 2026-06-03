package com.abracode.actionui.Views

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction

/**
 * Secure (masked) single-line text input. Mirror of the Apple `SecureField`
 * element (`ActionUI/Views/SecureField.swift`); the rendering and property
 * handling are shared with [TextField] via [TextInputField] (see that file for
 * the full property mapping, state model, and deferral notes). The displayed
 * characters are masked with a password visual transformation; it is always
 * single-line (no `axis`/`lineLimit`).
 *
 * Sample JSON:
 * ```
 * {
 *   "type": "SecureField",
 *   "id": 1,                                 // Optional: positive id for action routing
 *   "properties": {
 *     "title": "Password",                   // Optional: floating label
 *     "prompt": "Enter password",            // Optional: placeholder while empty
 *     "text": "",                            // Optional: initial value
 *     "textContentType": "password",         // Optional: "password" | "newPassword" | "oneTimeCode"
 *     "actionID": "secure.submit"            // Optional: dispatched on IME submit
 *   }
 * }
 * ```
 */
object SecureField : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        TextInputField(element, modifier, TextInputKind.Secure)
    }
}
