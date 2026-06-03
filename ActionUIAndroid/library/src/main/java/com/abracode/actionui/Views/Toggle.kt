package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Switch
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.booleanProperty
import com.abracode.actionui.Helpers.stringProperty

/**
 * On/off control. Mirror of the Apple `Toggle` element
 * (`ActionUI/Views/Toggle.swift`), which wraps `SwiftUI.Toggle`. The first
 * **Boolean**-valued control on the Android state bridge (entry 17): it declares
 * [ActionUIValueType.BOOLEAN], so a host can read it with
 * `ActionUIModel.getElementValue(...)` and write it with
 * `setElementValueFromString(..., "true")`, and the control recomposes.
 *
 * Rendered as a Material3 [Switch] (default) or [Checkbox], with the `title`
 * label leading. Property mapping:
 *
 *   * `isOn`  - initial on/off state (defaults to `false`), seeded into the
 *     element's [com.abracode.actionui.Common.ViewModel] at populate time.
 *   * `title` - label text (defaults to `"Toggle"`, matching Apple).
 *   * `style` - `"switch"` (default) or `"checkbox"`; `"button"` is deferred.
 *   * `actionID` - dispatched through [ActionUIModel] on every user change, with
 *     the new Boolean as `context` (parity with the Apple binding setter, which
 *     fires only on interaction - not on programmatic value changes).
 *
 * **State.** When a [com.abracode.actionui.Common.WindowModel] is in scope the
 * value is owned by the element's `ViewModel` (looked up via [LocalWindowModel]
 * by id); otherwise it falls back to local [rememberSaveable] state. Host binding
 * requires a positive element `id`. Same dual-path binding the text controls use.
 *
 * **Deferred vs. Apple.** `style: "button"` (SwiftUI `ButtonToggleStyle`) renders
 * its label inside a pressable button rather than beside a control; its clean
 * Compose analog (a labeled toggle button / `FilterChip`) has a different layout
 * and selection affordance, so it warn-and-downgrades to `switch` for now - the
 * same warn-and-fallback stance used for unsupported shape corner styles.
 */
object Toggle : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.BOOLEAN

    override fun initialValue(element: ActionUIElement): Any? =
        element.properties?.booleanProperty("isOn") ?: false

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current

        val title = props?.stringProperty("title") ?: "Toggle"
        val actionID = props?.stringProperty("actionID")
        val initial = props?.booleanProperty("isOn") ?: false
        val style = resolveToggleStyle(props?.stringProperty("style"), logger)

        // Bind to the ViewModel value when a window is in scope; else local state.
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        var localChecked by rememberSaveable(element.id) { mutableStateOf(initial) }
        val checked = if (viewModel != null) (viewModel.value as? Boolean) ?: initial else localChecked

        val onChange: (Boolean) -> Unit = { new ->
            if (new != checked) {
                if (viewModel != null) viewModel.value = new else localChecked = new
                if (actionID != null) {
                    ActionUIModel.actionHandler(actionID, viewID = element.id, viewPartID = 0, context = new)
                }
            }
        }

        Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
            if (title.isNotEmpty()) {
                M3Text(title)
                Spacer(Modifier.width(8.dp))
            }
            when (style) {
                ToggleStyle.Checkbox -> Checkbox(checked = checked, onCheckedChange = onChange)
                ToggleStyle.Switch -> Switch(checked = checked, onCheckedChange = onChange)
            }
        }
    }
}

/** The Toggle visual styles the Android renderer supports. */
internal enum class ToggleStyle { Switch, Checkbox }

/**
 * Maps the JSON `style` to a [ToggleStyle]. `null`/`"switch"` -> [ToggleStyle.Switch],
 * `"checkbox"` -> [ToggleStyle.Checkbox]. `"button"` warn-and-downgrades to switch
 * (the labeled toggle-button style is not ported); any other value warns and
 * falls back to switch, parity with the Apple `validateProperties` default.
 */
internal fun resolveToggleStyle(raw: String?, logger: ActionUILogger): ToggleStyle = when (raw) {
    null, "switch" -> ToggleStyle.Switch
    "checkbox" -> ToggleStyle.Checkbox
    "button" -> {
        logger.log(
            "Toggle style 'button' (ButtonToggleStyle) is not ported on Android; using switch",
            LoggerLevel.warning
        )
        ToggleStyle.Switch
    }
    else -> {
        logger.log("Toggle style '$raw' is not recognized; using switch", LoggerLevel.warning)
        ToggleStyle.Switch
    }
}
