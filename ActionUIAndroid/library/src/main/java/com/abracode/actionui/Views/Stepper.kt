package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
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
import com.abracode.actionui.Helpers.LocalActionUIEnabled
import com.abracode.actionui.Helpers.LocalActionUILabelsHidden
import com.abracode.actionui.Helpers.LocalActionUITint
import com.abracode.actionui.Helpers.numberProperty
import com.abracode.actionui.Helpers.stringProperty
import kotlinx.serialization.json.JsonObject
import java.util.Locale

/**
 * Discrete value stepper: a label plus decrement/increment controls. Mirror of
 * the Apple `Stepper` element (`ActionUI/Views/Stepper.swift`), which wraps
 * `SwiftUI.Stepper`. A **Double**-valued control on the Android state bridge: it
 * declares [ActionUIValueType.DOUBLE], so a host reads its value with
 * `ActionUIModel.getElementValue(...)` and writes it with
 * `setElementValueFromString(..., "5")`, and the control recomposes. (SwiftUI's
 * `Stepper` is itself `Double`-backed, so this matches; the `INT` bridge type the
 * inventory once pencilled in is unnecessary.)
 *
 * Compose has no native stepper, so it is composed from a label and two
 * [OutlinedButton]s ("-" / "+") - no icon assets, keeping it off the
 * image/icon-resolution track. Property mapping:
 *
 *   * `value` - initial value (Double, defaults to `0.0`), seeded into the
 *     element's [com.abracode.actionui.Common.ViewModel] at populate time.
 *   * `range` - `{ "min": .., "max": .. }` (optional; `min <= max`). When present
 *     the value is clamped to it and the matching button disables at a bound.
 *   * `step`  - increment per tap (defaults to `1.0`; non-positive => `1.0`).
 *   * `label` / `labelFormat` - the label text. `labelFormat` is a printf-style
 *     format applied to the current value (e.g. `"Count: %.0f"`) and takes
 *     precedence over `label`, matching the Apple element.
 *   * `actionID` - dispatched through [ActionUIModel] on every user-initiated
 *     change with the new Double as `context` (parity with the Apple binding
 *     setter, which fires only on interaction, not on programmatic updates).
 *
 * **State.** ViewModel-backed when a [com.abracode.actionui.Common.WindowModel]
 * is in scope (host binding; needs a positive `id`), else local
 * [rememberSaveable] - the same dual-path binding the other controls use.
 *
 * **Tint.** An inherited [LocalActionUITint] colors the +/- buttons, matching
 * SwiftUI `.tint`; literal colors only (see `TextStyleEnvironment.kt`).
 */
object Stepper : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.DOUBLE

    override fun initialValue(element: ActionUIElement): Any? =
        element.properties?.numberProperty("value") ?: 0.0

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current

        val config = resolveStepperConfig(props, logger)
        val actionID = props?.stringProperty("actionID")
        val initial = props?.numberProperty("value") ?: 0.0

        // Bind to the ViewModel value when a window is in scope; else local state.
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        var localValue by rememberSaveable(element.id) { mutableStateOf(initial) }
        val current = (if (viewModel != null) (viewModel.value as? Double) ?: initial else localValue)
            .let { if (config.range != null) it.coerceIn(config.range.first, config.range.second) else it }

        // SwiftUI `.labelsHidden()` (set here or on any ancestor).
        val label = if (LocalActionUILabelsHidden.current) "" else stepperLabel(props, current, logger)

        val commit: (Double) -> Unit = { next ->
            if (next != current) {
                if (viewModel != null) viewModel.value = next else localValue = next
                if (actionID != null) {
                    ActionUIModel.actionHandler(actionID, viewID = element.id, viewPartID = 0, context = next)
                }
            }
        }

        // SwiftUI `.disabled` (set here or on any ancestor) gates both buttons,
        // on top of the per-bound disabling a `range` already applies.
        val enabled = LocalActionUIEnabled.current
        val canDecrement = enabled && (config.range == null || current > config.range.first)
        val canIncrement = enabled && (config.range == null || current < config.range.second)

        // SwiftUI `.tint` colors the stepper's +/- control; map it to the button
        // content color when an ancestor (or this element) provides one.
        val tint = LocalActionUITint.current
        val buttonColors = if (tint != null) {
            ButtonDefaults.outlinedButtonColors(contentColor = tint)
        } else {
            ButtonDefaults.outlinedButtonColors()
        }

        Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
            if (label.isNotEmpty()) {
                M3Text(label)
                Spacer(Modifier.width(8.dp))
            }
            OutlinedButton(
                onClick = { commit(steppedValue(current, config.step, increment = false, range = config.range)) },
                enabled = canDecrement,
                colors = buttonColors,
            ) { M3Text("-") }
            Spacer(Modifier.width(4.dp))
            OutlinedButton(
                onClick = { commit(steppedValue(current, config.step, increment = true, range = config.range)) },
                enabled = canIncrement,
                colors = buttonColors,
            ) { M3Text("+") }
        }
    }
}

/** Resolved, validated stepper bounds (optional) and step size. */
internal data class StepperConfig(val range: Pair<Double, Double>?, val step: Double)

/**
 * Resolves and validates `range`/`step` into a [StepperConfig], mirroring the
 * Apple `Stepper.validateProperties`: a `range` missing/with non-numeric bounds
 * or `min > max` is dropped (warn, no clamping); a non-positive or non-numeric
 * `step` defaults to `1.0`. Pure (logging aside) so it is unit-testable.
 */
internal fun resolveStepperConfig(props: JsonObject?, logger: ActionUILogger): StepperConfig {
    var range: Pair<Double, Double>? = null
    val rangeObj = props?.get("range") as? JsonObject
    if (rangeObj != null) {
        val min = rangeObj.numberProperty("min")
        val max = rangeObj.numberProperty("max")
        if (min != null && max != null && min <= max) {
            range = min to max
        } else {
            logger.log(
                "Stepper range must have valid min/max numbers with min <= max; ignoring range",
                LoggerLevel.warning
            )
        }
    }

    var step = 1.0
    if (props?.get("step") != null) {
        val rawStep = props.numberProperty("step")
        step = if (rawStep != null && rawStep > 0.0) {
            rawStep
        } else {
            logger.log("Stepper step must be a positive number; defaulting to 1.0", LoggerLevel.warning)
            1.0
        }
    }
    return StepperConfig(range, step)
}

/**
 * Computes the next value when a stepper button is tapped: `current +/- step`,
 * clamped into [range] when one is set. Pure and unit-testable.
 */
internal fun steppedValue(current: Double, step: Double, increment: Boolean, range: Pair<Double, Double>?): Double {
    val raw = if (increment) current + step else current - step
    return if (range != null) raw.coerceIn(range.first, range.second) else raw
}

/**
 * Resolves the stepper label, mirroring the Apple precedence: a `labelFormat`
 * printf-style string applied to [value] wins over a plain `label`; absent both,
 * the empty string. A malformed format (e.g. an integer conversion against the
 * Double value) warns and falls back to the plain `label`. Locale-fixed to
 * [Locale.US] so `"%.1f"` formats with a dot on every device.
 */
internal fun stepperLabel(props: JsonObject?, value: Double, logger: ActionUILogger): String {
    val plain = props?.stringProperty("label") ?: ""
    val format = props?.stringProperty("labelFormat") ?: return plain
    return try {
        String.format(Locale.US, format, value)
    } catch (e: IllegalArgumentException) {
        logger.log(
            "Stepper labelFormat '$format' is not a valid float format; ignoring",
            LoggerLevel.warning
        )
        plain
    }
}
