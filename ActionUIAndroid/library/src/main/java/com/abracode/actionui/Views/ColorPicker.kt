package com.abracode.actionui.Views

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Helpers.colorToHex
import com.abracode.actionui.Helpers.parseColor
import com.abracode.actionui.Helpers.stringProperty

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
 * **Presentation - deferred vs. Apple.** Compose has no native color picker, so
 * this renders a curated grid of preset swatches plus a preview of the current
 * color. A free-form HSV/eyedropper picker is deferred; the value bridge is fully
 * wired, so a host can still set *any* color programmatically (the preview shows
 * it even when it is not one of the presets). This is the same "pragmatic native
 * surface, documented divergence" stance taken elsewhere (e.g. Toggle's button
 * style, the macOS-only DatePicker styles).
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
        val title = props?.stringProperty("title") ?: ""
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

        Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (title.isNotEmpty()) {
                    M3Text(title)
                    Spacer(Modifier.width(8.dp))
                }
                // Preview of the current value (reflects programmatic sets too).
                Swatch(color = current, selected = false, onClick = null)
            }
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                ColorPickerSwatches.forEach { swatch ->
                    Swatch(color = swatch, selected = swatch == current, onClick = { onSelect(swatch) })
                }
            }
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
 * One color swatch. A bordered, rounded box filled with [color]; [selected] draws
 * a thicker accent ring. A non-null [onClick] makes it tappable (the palette
 * entries); the current-color preview passes `null`.
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
