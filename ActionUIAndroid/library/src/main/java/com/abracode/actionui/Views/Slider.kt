package com.abracode.actionui.Views

import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.LocalActionUIEnabled
import com.abracode.actionui.Helpers.LocalActionUITint
import com.abracode.actionui.Helpers.numberProperty
import com.abracode.actionui.Helpers.stringProperty
import kotlinx.serialization.json.JsonObject
import kotlin.math.roundToInt

/**
 * Continuous (or stepped) value selector along a linear range. Mirror of the
 * Apple `Slider` element (`ActionUI/Views/Slider.swift`), which wraps
 * `SwiftUI.Slider`. The first **Double**-valued control on the Android state
 * bridge (entry 17): it declares [ActionUIValueType.DOUBLE], so a host reads its
 * position with `ActionUIModel.getElementValue(...)` and sets it with
 * `setElementValueFromString(..., "75")`, and the control recomposes.
 *
 * Rendered as a Material3 [Slider]. Property mapping:
 *
 *   * `value` - initial position (Double, defaults to `0.0`), seeded into the
 *     element's [com.abracode.actionui.Common.ViewModel] at populate time.
 *   * `range` - `{ "min": .., "max": .. }` (defaults to `0.0..1.0`; `min <= max`).
 *   * `step`  - increment; absent or non-positive => continuous. Clamped so it
 *     never exceeds the range size, matching the Apple validator.
 *   * `valueChangeActionID` - dispatched through [ActionUIModel] on every change,
 *     the analog of the Apple binding's `set` closure.
 *
 * **Float backing (the one platform divergence).** SwiftUI's `Slider` is
 * `Double`; Compose's is `Float`. The value is stored as `Double` (so the value
 * API stays `Double`-typed) and converted to `Float` for the control and back on
 * change. A continuous drag can therefore land on a value with `Float` precision
 * artifacts; stepped sliders stay clean. This is inherent to the Compose control.
 *
 * **Compose `steps` != step size.** Compose's `steps` is the number of discrete
 * stops *between* the endpoints, not the increment. [sliderStepCount] converts
 * a step size into that count.
 *
 * **State.** ViewModel-backed when a [com.abracode.actionui.Common.WindowModel]
 * is in scope (host binding; needs a positive `id`), else local
 * [rememberSaveable] - the same dual-path binding the other controls use.
 */
object Slider : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.DOUBLE

    override fun initialValue(element: ActionUIElement): Any? =
        element.properties?.numberProperty("value") ?: 0.0

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current

        val config = resolveSliderConfig(props, logger)
        val valueChangeActionID = props?.stringProperty("valueChangeActionID")
        val initial = props?.numberProperty("value") ?: 0.0

        // Bind to the ViewModel value when a window is in scope; else local state.
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        var localValue by rememberSaveable(element.id) { mutableStateOf(initial) }
        val current = if (viewModel != null) (viewModel.value as? Double) ?: initial else localValue

        val stepCount = sliderStepCount(config.min, config.max, config.step)

        // SwiftUI `.tint` colors the slider's thumb and the filled (active) part
        // of the track; an inherited tint maps to both.
        val tint = LocalActionUITint.current
        val colors = if (tint != null) {
            SliderDefaults.colors(thumbColor = tint, activeTrackColor = tint)
        } else {
            SliderDefaults.colors()
        }

        Slider(
            value = current.coerceIn(config.min, config.max).toFloat(),
            onValueChange = { new ->
                val asDouble = new.toDouble()
                if (asDouble != current) {
                    if (viewModel != null) viewModel.value = asDouble else localValue = asDouble
                    if (valueChangeActionID != null) {
                        ActionUIModel.actionHandler(valueChangeActionID, viewID = element.id, viewPartID = 0)
                    }
                }
            },
            modifier = modifier,
            // SwiftUI `.disabled` (set here or on any ancestor) -> M3 `enabled`.
            enabled = LocalActionUIEnabled.current,
            valueRange = config.min.toFloat()..config.max.toFloat(),
            steps = stepCount,
            colors = colors,
        )
    }
}

/** Resolved, validated slider bounds and (optional) step size. */
internal data class SliderConfig(val min: Double, val max: Double, val step: Double?)

/**
 * Resolves and validates `range`/`step` into a [SliderConfig], mirroring the
 * Apple `Slider.validateProperties`: an invalid/missing `range` defaults to
 * `0.0..1.0`; a non-positive or non-numeric `step` defaults to `1.0`; and a
 * step larger than the range size is clamped to it. Pure (logging aside) so it
 * is unit-testable.
 */
internal fun resolveSliderConfig(props: JsonObject?, logger: ActionUILogger): SliderConfig {
    var min = 0.0
    var max = 1.0
    val rangeObj = props?.get("range") as? JsonObject
    if (rangeObj != null) {
        val rMin = rangeObj.numberProperty("min")
        val rMax = rangeObj.numberProperty("max")
        if (rMin != null && rMax != null && rMin <= rMax) {
            min = rMin
            max = rMax
        } else {
            logger.log(
                "Slider range must have valid min/max numbers with min <= max; defaulting to 0.0..1.0",
                LoggerLevel.warning
            )
        }
    }

    var step: Double? = null
    if (props?.get("step") != null) {
        val rangeSize = max - min
        val rawStep = props.numberProperty("step")
        step = if (rawStep != null && rawStep > 0.0) {
            if (rawStep > rangeSize) {
                logger.log(
                    "Slider step must not exceed range (max - min); clamping to $rangeSize",
                    LoggerLevel.warning
                )
                rangeSize
            } else {
                rawStep
            }
        } else {
            logger.log("Slider step must be a positive number; defaulting to 1.0", LoggerLevel.warning)
            if (1.0 > rangeSize) rangeSize else 1.0
        }
    }
    return SliderConfig(min, max, step)
}

/**
 * Converts a step *size* into the Compose `steps` value - the number of discrete
 * stops between the endpoints (`(max - min) / step - 1`). Returns `0` (continuous)
 * when there is no positive step or the range is degenerate.
 */
internal fun sliderStepCount(min: Double, max: Double, step: Double?): Int {
    if (step == null || step <= 0.0 || max <= min) return 0
    return (((max - min) / step).roundToInt() - 1).coerceAtLeast(0)
}
