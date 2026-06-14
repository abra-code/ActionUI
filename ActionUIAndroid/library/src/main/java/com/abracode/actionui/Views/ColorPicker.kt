package com.abracode.actionui.Views

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text as M3Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Helpers.LocalActionUIEnabled
import com.abracode.actionui.Helpers.LocalActionUILabelsHidden
import com.abracode.actionui.Helpers.colorToHex
import com.abracode.actionui.Helpers.hsvToColor
import com.abracode.actionui.Helpers.parseColor
import com.abracode.actionui.Helpers.stringProperty
import com.abracode.actionui.Helpers.toHsv
import kotlin.math.ceil

/**
 * Color selection. Mirror of the Apple `ColorPicker` element
 * (`ActionUI/Views/ColorPicker.swift`), which wraps `SwiftUI.ColorPicker`. The
 * first [ActionUIValueType.COLOR]-valued control on the value bridge (B6): its
 * value is a Compose [Color], so a host reads it with
 * `ActionUIModel.getElementValueAsString` (a `#RRGGBB`/`#RRGGBBAA` hex string) and
 * writes it with `setElementValueFromString(..., "#FF8800")`, and the control
 * recomposes.
 *
 * Property mapping:
 *   * `title` - leading label (defaults to empty, matching Apple).
 *   * `selectedColor` - initial color (hex or named, via
 *     [com.abracode.actionui.Helpers.parseColor]); defaults to transparent.
 *   * `actionID` - dispatched through [ActionUIModel] on every user change, with
 *     the new color's hex string as `context` (parity with Apple, which fires
 *     only on interaction, not on programmatic value changes).
 *
 * **Presentation.** Compose has no native color picker, so this renders two
 * affordances side by side, the Android analog of SwiftUI's native picker (which
 * shows a preview well that opens a full HSV picker):
 *   * an inline [FlowRow] of preset swatches for quick one-tap choices, plus
 *   * a tappable **preview swatch** that opens a free-form [HsvPickerDialog]
 *     (saturation/brightness area + hue + alpha tracks, all dependency-free
 *     Compose canvas) so a *user* can pick any color, not only a preset.
 *
 * The COLOR value bridge carries arbitrary `#RRGGBB(AA)`, so a host can still set
 * any color programmatically and the preview reflects it even when it is not a
 * preset.
 *
 * **State.** Bound to the element's `ViewModel` (via [LocalWindowModel] by id)
 * when a window is in scope; otherwise a local fallback. Host binding requires a
 * positive element `id`.
 */
object ColorPicker : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.COLOR

    override fun initialValue(element: ActionUIElement): Any? =
        element.properties?.stringProperty("selectedColor")?.let { parseColor(it) } ?: Color.Transparent

    @OptIn(ExperimentalLayoutApi::class)
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        // SwiftUI `.labelsHidden()` (set here or on any ancestor).
        val title = if (LocalActionUILabelsHidden.current) "" else props?.stringProperty("title") ?: ""
        val actionID = props?.stringProperty("actionID")

        val initial = (initialValue(element) as? Color) ?: Color.Transparent
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        var localColor by remember(element.id) { mutableStateOf(initial) }
        val current: Color = (viewModel?.value as? Color) ?: localColor

        val onSelect: (Color) -> Unit = { picked ->
            if (picked != current) {
                if (viewModel != null) viewModel.value = picked else localColor = picked
                actionID?.let {
                    ActionUIModel.actionHandler(
                        it, viewID = element.id, viewPartID = 0, context = colorToHex(picked),
                    )
                }
            }
        }

        // SwiftUI `.disabled` (set here or on any ancestor): a disabled palette
        // keeps its preview but neither the swatches nor the preview open/pick.
        val enabled = LocalActionUIEnabled.current
        var showDialog by remember(element.id) { mutableStateOf(false) }

        Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (title.isNotEmpty()) {
                    M3Text(title)
                    Spacer(Modifier.width(8.dp))
                }
                // The preview well: shows the current value (programmatic sets too)
                // and, when enabled, opens the free-form HSV picker on tap - the
                // Android stand-in for SwiftUI's tappable color well.
                Swatch(
                    color = current,
                    selected = false,
                    onClick = if (enabled) ({ showDialog = true }) else null,
                )
            }
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                ColorPickerSwatches.forEach { swatch ->
                    Swatch(
                        color = swatch,
                        selected = swatch == current,
                        onClick = if (enabled) ({ onSelect(swatch) }) else null,
                    )
                }
            }
        }

        if (showDialog) {
            HsvPickerDialog(
                title = title.ifEmpty { "Color" },
                initial = current,
                onColorChange = onSelect,
                onDismiss = { showDialog = false },
            )
        }
    }
}

/**
 * The preset swatch palette: the canonical named colors from
 * [com.abracode.actionui.Helpers.parseColor], resolved once. Internal so a test
 * can assert every name resolves (no silent gaps).
 */
internal val ColorPickerSwatches: List<Color> = listOf(
    "red", "orange", "yellow", "green", "mint", "teal", "cyan", "blue",
    "indigo", "purple", "pink", "brown", "gray", "black", "white",
).mapNotNull { parseColor(it) }

/**
 * The free-form HSV picker, opened from the preview well. A dependency-free
 * Compose [Dialog]: a saturation/brightness area for the current hue, a hue
 * track, and an alpha track, with a live preview + hex readout and a Done
 * dismiss. HSV is the source of truth while editing (seeded once from [initial]),
 * because a grayscale or black color has no recoverable hue to re-derive each
 * change. Every drag pushes the new color out through [onColorChange] - the same
 * live, every-change contract `Slider` uses (and the SwiftUI `ColorPicker`
 * binding).
 */
@Composable
private fun HsvPickerDialog(
    title: String,
    initial: Color,
    onColorChange: (Color) -> Unit,
    onDismiss: () -> Unit,
) {
    val seed = remember { initial.toHsv() }
    var hue by remember { mutableStateOf(seed.hue) }
    var saturation by remember { mutableStateOf(seed.saturation) }
    var value by remember { mutableStateOf(seed.value) }
    var alpha by remember { mutableStateOf(initial.alpha) }

    val color = hsvToColor(hue, saturation, value, alpha)

    Dialog(onDismissRequest = onDismiss) {
        Surface(shape = MaterialTheme.shapes.large, tonalElevation = 6.dp) {
            Column(
                modifier = Modifier.width(300.dp).padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                M3Text(title, style = MaterialTheme.typography.titleMedium)

                SaturationValueArea(hue = hue, saturation = saturation, value = value) { s, v ->
                    saturation = s
                    value = v
                    onColorChange(hsvToColor(hue, s, v, alpha))
                }
                HueTrack(hue = hue) { h ->
                    hue = h
                    onColorChange(hsvToColor(h, saturation, value, alpha))
                }
                AlphaTrack(color = color, alpha = alpha) { a ->
                    alpha = a
                    onColorChange(hsvToColor(hue, saturation, value, a))
                }

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Swatch(color = color, selected = false, onClick = null)
                    M3Text(colorToHex(color), style = MaterialTheme.typography.bodyMedium)
                }

                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = onDismiss) { M3Text("Done") }
                }
            }
        }
    }
}

/**
 * The 2D saturation (x) x brightness (y) plane for the fixed [hue]: a white->hue
 * horizontal gradient under a transparent->black vertical gradient, the standard
 * "color field". A tap or drag reports the picked `(saturation, value)` via
 * [onChange]; the thumb rings the current point (white over a faint dark halo so
 * it reads on any background).
 */
@Composable
private fun SaturationValueArea(
    hue: Float,
    saturation: Float,
    value: Float,
    onChange: (Float, Float) -> Unit,
) {
    val hueColor = hsvToColor(hue, 1f, 1f, 1f)
    Canvas(
        modifier = Modifier
            .fillMaxWidth()
            .height(180.dp)
            .clip(RoundedCornerShape(8.dp))
            .pickerGesture { pos, sz ->
                onChange(
                    (pos.x / sz.width).coerceIn(0f, 1f),
                    1f - (pos.y / sz.height).coerceIn(0f, 1f),
                )
            },
    ) {
        drawRect(Brush.horizontalGradient(listOf(Color.White, hueColor)))
        drawRect(Brush.verticalGradient(listOf(Color.Transparent, Color.Black)))
        val center = Offset(saturation.coerceIn(0f, 1f) * size.width, (1f - value.coerceIn(0f, 1f)) * size.height)
        drawCircle(Color.Black.copy(alpha = 0.5f), radius = 8.dp.toPx(), center = center, style = Stroke(width = 1.dp.toPx()))
        drawCircle(Color.White, radius = 7.dp.toPx(), center = center, style = Stroke(width = 2.dp.toPx()))
    }
}

/** The hue track: the full 0..360 spectrum; a tap/drag reports the new hue. */
@Composable
private fun HueTrack(hue: Float, onChange: (Float) -> Unit) {
    val spectrum = remember { (0..6).map { hsvToColor(it * 60f, 1f, 1f, 1f) } }
    Canvas(
        modifier = Modifier
            .fillMaxWidth()
            .height(28.dp)
            .clip(RoundedCornerShape(14.dp))
            .pickerGesture { pos, sz -> onChange((pos.x / sz.width).coerceIn(0f, 1f) * 360f) },
    ) {
        drawRect(Brush.horizontalGradient(spectrum))
        drawTrackThumb(hue / 360f)
    }
}

/**
 * The alpha track: a checkerboard under a transparent->opaque gradient of the
 * current [color]; a tap/drag reports the new alpha. Mirrors SwiftUI's opacity
 * support (default-on for `ColorPicker`).
 */
@Composable
private fun AlphaTrack(color: Color, alpha: Float, onChange: (Float) -> Unit) {
    val opaque = color.copy(alpha = 1f)
    Canvas(
        modifier = Modifier
            .fillMaxWidth()
            .height(28.dp)
            .clip(RoundedCornerShape(14.dp))
            .pickerGesture { pos, sz -> onChange((pos.x / sz.width).coerceIn(0f, 1f)) },
    ) {
        drawCheckerboard(cell = 7.dp.toPx())
        drawRect(Brush.horizontalGradient(listOf(opaque.copy(alpha = 0f), opaque)))
        drawTrackThumb(alpha)
    }
}

/**
 * Routes both an initial tap and any subsequent drag on a picker canvas to
 * [onPosition] (the pointer position and the node size), so a single gesture
 * covers tap-to-set and drag-to-track. Uses [awaitEachGesture] rather than
 * stacking `detectTapGestures` + `detectDragGestures` (which would compete to
 * consume the same down event).
 */
private fun Modifier.pickerGesture(onPosition: (Offset, IntSize) -> Unit): Modifier =
    this.pointerInput(Unit) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false)
            onPosition(down.position, size)
            down.consume()
            while (true) {
                val event = awaitPointerEvent()
                val change = event.changes.firstOrNull { it.id == down.id } ?: break
                if (!change.pressed) break
                onPosition(change.position, size)
                change.consume()
            }
        }
    }

/** A vertically centered round thumb at [fraction] along the track's width. */
private fun DrawScope.drawTrackThumb(fraction: Float) {
    val radius = size.height / 2f - 1.dp.toPx()
    val x = (fraction.coerceIn(0f, 1f) * size.width).coerceIn(radius, size.width - radius)
    val center = Offset(x, size.height / 2f)
    drawCircle(Color.Black.copy(alpha = 0.5f), radius = radius, center = center, style = Stroke(width = 1.dp.toPx()))
    drawCircle(Color.White, radius = radius - 1.dp.toPx(), center = center, style = Stroke(width = 2.dp.toPx()))
}

/** A light/white checkerboard, the conventional "transparent" backing for the alpha track. */
private fun DrawScope.drawCheckerboard(cell: Float) {
    val cols = ceil(size.width / cell).toInt()
    val rows = ceil(size.height / cell).toInt()
    for (row in 0 until rows) {
        for (col in 0 until cols) {
            val dark = (row + col) % 2 == 0
            drawRect(
                color = if (dark) Color(0xFFCCCCCC) else Color.White,
                topLeft = Offset(col * cell, row * cell),
                size = Size(cell, cell),
            )
        }
    }
}

/**
 * One color swatch. A bordered, rounded box filled with [color]; [selected] draws
 * a thicker accent ring. A non-null [onClick] makes it tappable (the palette
 * entries and the preview well); a `null` [onClick] is a static preview.
 */
@Composable
private fun Swatch(color: Color, selected: Boolean, onClick: (() -> Unit)?) {
    val ringColor = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline
    val ringWidth = if (selected) 3.dp else 1.dp
    val shape = RoundedCornerShape(6.dp)
    var box = Modifier
        .size(32.dp)
        .clip(shape)
        .background(color)
        .border(ringWidth, ringColor, shape)
    if (onClick != null) box = box.clickable(onClick = onClick)
    Box(modifier = box)
}
