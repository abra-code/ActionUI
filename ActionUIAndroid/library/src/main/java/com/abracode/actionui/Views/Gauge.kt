package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.LocalActionUITint
import com.abracode.actionui.Helpers.numberProperty
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/**
 * Read-only level indicator for a value within a range. Mirror of the Apple
 * `Gauge` element (`ActionUI/Views/Gauge.swift`), which wraps `SwiftUI.Gauge`.
 * Like `Slider` it declares [ActionUIValueType.DOUBLE] on the value bridge, but
 * the control is non-interactive: only the host moves it
 * (`setElementValueFromString(..., "75")` recomposes the indicator).
 *
 * Property mapping (all optional, Apple's contract):
 *
 *   * `value` - current level (Double, defaults to `0.0`), seeded into the
 *     element's [com.abracode.actionui.Common.ViewModel] at populate time.
 *   * `title` - the gauge label.
 *   * `range` - `{ "min": .., "max": .. }`, defaults to `0.0..1.0`.
 *   * `style` - one of Apple's four accessory styles, or absent for the
 *     platform-default gauge.
 *   * `scaleEffect` - circular gauges reproduce SwiftUI's model: the ring has a
 *     fixed intrinsic diameter ([CircularGaugeIntrinsicSide], ~71dp, matching
 *     Apple's accessory-circular gauge) that the common-property `scaleEffect`
 *     graphics transform scales, so the visual diameter is
 *     `intrinsic * scaleEffect` on every platform. M3's circular indicator
 *     hardcodes 40dp, so it is scaled up to the intrinsic diameter (see
 *     [CircularRing]); the outer `scaleEffect` on the passed modifier does the
 *     rest. No parent measurement / fill - a framed `ZStack` only reserves
 *     layout space, exactly as on Apple.
 *
 * **Style mapping.** Compose Material3 has no gauge widget; the native fit is
 * its determinate progress indicators, so each SwiftUI style maps to the
 * closest one:
 *
 *   * absent style (SwiftUI's default `linearCapacity`: a bar with the label
 *     shown) -> [LinearProgressIndicator] with the title above it.
 *   * `accessoryLinear` / `accessoryLinearCapacity` (SwiftUI hides the label
 *     in both) -> a bare [LinearProgressIndicator]. The `accessoryLinear`
 *     dot-marker look has no M3 analog; both render as a filled bar.
 *   * `accessoryCircular` / `accessoryCircularCapacity` ->
 *     [CircularProgressIndicator] with the title centered in the ring.
 *     Divergences: M3 draws a full ring (SwiftUI's `accessoryCircular` is an
 *     open arc with a bottom gap), and the capacity variant centers the title
 *     (SwiftUI centers the `currentValueLabel` there, which the JSON contract
 *     never supplies).
 *
 * The rendered value is clamped to the range; SwiftUI performs the same
 * range-guarding in its binding setter. An inherited SwiftUI `.tint` colors
 * the indicator, like `ProgressView`.
 *
 * Sample JSON:
 * ```
 * { "type": "Gauge", "id": 7,
 *   "properties": { "value": 65, "title": "Battery", "style": "accessoryCircular",
 *                   "range": { "min": 0.0, "max": 100.0 } } }
 * ```
 */
object Gauge : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.DOUBLE

    override fun initialValue(element: ActionUIElement): Any? =
        element.properties?.numberProperty("value") ?: 0.0

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val config = resolveGaugeConfig(element.properties, logger)

        // ViewModel-backed when a window is in scope (host writes recompose);
        // else the static property. Non-interactive, so no local state needed.
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        val current = (viewModel?.value as? Double) ?: config.value
        val fraction = gaugeFraction(config.min, config.max, current)

        // SwiftUI `.tint` colors the gauge's indicator, like ProgressView.
        val tint = LocalActionUITint.current

        when (config.style) {
            "accessoryCircular", "accessoryCircularCapacity" ->
                CircularRing(
                    fraction = fraction,
                    tint = tint,
                    title = config.title,
                    modifier = modifier,
                )
            "accessoryLinear", "accessoryLinearCapacity" ->
                Box(modifier = modifier) { Bar(fraction, tint) }
            else ->
                Column(modifier = modifier, horizontalAlignment = Alignment.CenterHorizontally) {
                    if (config.title != null) M3Text(text = config.title)
                    Bar(fraction, tint)
                }
        }
    }
}

/**
 * Circular gauge ring, reproducing SwiftUI's model: a fixed intrinsic diameter
 * ([CircularGaugeIntrinsicSide]) that the common-property `scaleEffect` scales.
 * M3's [CircularProgressIndicator] hardcodes a 40dp diameter (its internal
 * `.size(CircularIndicatorDiameter)` overrides a caller `Modifier.size`), so it
 * is drawn at 40dp and scaled up to the intrinsic diameter with [Modifier.scale].
 * The wrapper [Box] is sized to the intrinsic diameter so the ring reserves the
 * right layout space; the outer `scaleEffect` on [modifier] (a graphics
 * transform) then scales the whole ring, so the visual diameter is
 * `intrinsic * scaleEffect` - matching Apple and Web. No parent measurement.
 */
@Composable
private fun CircularRing(
    fraction: Float,
    tint: Color?,
    title: String?,
    modifier: Modifier,
) {
    Box(
        modifier = modifier.size(CircularGaugeIntrinsicSide),
        contentAlignment = Alignment.Center,
    ) {
        // Draw the fixed-40dp M3 indicator at the intrinsic diameter.
        val innerScale = CircularGaugeIntrinsicSide / CircularGaugeM3Side
        val color = tint ?: MaterialTheme.colorScheme.primary
        val track = MaterialTheme.colorScheme.surfaceVariant
        CircularProgressIndicator(
            progress = { fraction },
            modifier = Modifier.scale(innerScale),
            color = color,
            trackColor = track,
            strokeWidth = circularGaugeStrokeWidth(),
            strokeCap = StrokeCap.Round,
        )
        if (title != null) {
            M3Text(text = title, style = MaterialTheme.typography.labelSmall)
        }
    }
}

@Composable
private fun Bar(fraction: Float, tint: Color?) {
    if (tint != null) {
        LinearProgressIndicator(progress = { fraction }, color = tint)
    } else {
        LinearProgressIndicator(progress = { fraction })
    }
}

/** Resolved, validated gauge properties. */
internal data class GaugeConfig(
    val value: Double = 0.0,
    val title: String? = null,
    val style: String? = null,
    val min: Double = 0.0,
    val max: Double = 1.0,
)

private val VALID_GAUGE_STYLES = setOf(
    "accessoryCircular", "accessoryCircularCapacity", "accessoryLinear", "accessoryLinearCapacity",
)

/** M3 circular indicator's fixed diameter (CircularProgressIndicatorTokens.Size).
 *  The indicator hardcodes this via an internal `.size()`; [CircularRing] scales
 *  it up to [CircularGaugeIntrinsicSide]. */
internal val CircularGaugeM3Side: Dp = 40.dp

/**
 * Intrinsic circular-gauge diameter, matching SwiftUI's accessory-circular gauge
 * (~71pt, measured). `scaleEffect` (the common graphics transform on the passed
 * modifier) scales this, so every platform renders `intrinsic * scaleEffect` -
 * Web uses the same 71 base. Not a fill-the-parent size: a framed `ZStack` only
 * reserves layout space, as on Apple.
 */
internal val CircularGaugeIntrinsicSide: Dp = 71.dp

/**
 * Stroke width in the M3 indicator's native (pre-scale) space. After the inner
 * scale to the intrinsic diameter (and any outer `scaleEffect`), the visual
 * stroke stays about 8% of the ring: `stroke * (intrinsic/40) ~= 0.08 * intrinsic`.
 */
internal fun circularGaugeStrokeWidth(): Dp = CircularGaugeM3Side * 0.08f

/**
 * Resolves and validates the gauge properties, mirroring the Apple
 * `Gauge.validateProperties` warnings: a non-numeric `value` defaults to 0.0,
 * a non-String `title` to nil, an unknown `style` to the platform default, and
 * `range` members are individually defaulted. Pure (logging aside) so it is
 * unit-testable.
 */
internal fun resolveGaugeConfig(props: JsonObject?, logger: ActionUILogger?): GaugeConfig {
    if (props == null) return GaugeConfig()

    var value = 0.0
    if (props["value"] != null) {
        val number = props.numberProperty("value")
        if (number != null) {
            value = number
        } else {
            logger?.log("Gauge value must be a number; defaulting to 0.0", LoggerLevel.warning)
        }
    }

    var title: String? = null
    if (props["title"] != null) {
        val string = (props["title"] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
        if (string != null) {
            title = string
        } else {
            logger?.log("Gauge title must be a String; defaulting to nil", LoggerLevel.warning)
        }
    }

    var style: String? = null
    if (props["style"] != null) {
        val name = (props["style"] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
        if (name != null && name in VALID_GAUGE_STYLES) {
            style = name
        } else {
            logger?.log("Gauge style '${name ?: props["style"]}' invalid; defaulting to nil", LoggerLevel.warning)
        }
    }

    var min = 0.0
    var max = 1.0
    val range = props["range"]
    if (range is JsonObject) {
        val rMin = range.numberProperty("min")
        if (rMin != null) {
            min = rMin
        } else {
            logger?.log("Gauge range.min must be a number; defaulting to 0.0", LoggerLevel.warning)
        }
        val rMax = range.numberProperty("max")
        if (rMax != null) {
            max = rMax
        } else {
            logger?.log("Gauge range.max must be a number; defaulting to 1.0", LoggerLevel.warning)
        }
    } else if (range != null) {
        logger?.log("Gauge range must be a dictionary with min/max; defaulting to 0.0...1.0", LoggerLevel.warning)
    }

    return GaugeConfig(value, title, style, min, max)
}

/**
 * The filled fraction for [value] within [min]..[max], clamped to `0..1`.
 * A degenerate range (`max <= min`) renders empty rather than dividing by
 * zero (SwiftUI's `min...max` would crash outright on such a range).
 */
internal fun gaugeFraction(min: Double, max: Double, value: Double): Float {
    if (max <= min) return 0f
    return ((value - min) / (max - min)).coerceIn(0.0, 1.0).toFloat()
}
