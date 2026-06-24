package com.abracode.actionui.Views

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text as M3Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Helpers.LocalActionUITint
import com.abracode.actionui.Helpers.numberProperty
import com.abracode.actionui.Helpers.stringProperty

/**
 * Renders a determinate progress bar or an indeterminate spinner.
 *
 * Mirror of the Apple `ProgressView` element (`ActionUI/Views/ProgressView.swift`),
 * which wraps `SwiftUI.ProgressView`. The element is **determinate** when a valid
 * `value` is supplied (and `value <= total`), otherwise **indeterminate**:
 *
 *   * determinate   -> Material3 [LinearProgressIndicator] (a bar), matching
 *     SwiftUI's default `ProgressView(value:total:)` rendering.
 *   * indeterminate -> Material3 [CircularProgressIndicator] (a spinner),
 *     matching SwiftUI's `ProgressView()` / iOS `.progressViewStyle(.circular)`.
 *
 * **Supported properties.**
 *   * `value` - current progress, `0.0...total`. Omit (or supply an invalid /
 *     out-of-range value) for an indeterminate spinner.
 *   * `total` - maximum; defaults to `1.0` when `value` is present. Must be `> 0`.
 *   * `title` - optional label rendered above the indicator (in a [Column]).
 *   * `actionID` - dispatched through [ActionUIModel] on tap, like `Button`.
 *   * plus the universal modifiers resolved by `applyCommonProperties`, applied
 *     to the enclosing [Column] via [modifier].
 *
 * **Value bridge.** Like Apple, `ProgressView` declares [ActionUIValueType.DOUBLE]
 * (Apple's `Double?`): a host can drive the progress at runtime via
 * `ActionUIModel.setElementValue(id, <Double>)`. As on Apple, the
 * `states["progress"]` override (set with `setElementState`) wins over the value
 * bridge, which in turn wins over the static `value` property; setting the value
 * `null` (no override and no property) reverts to the indeterminate spinner.
 * `initialValue` seeds from a pre-set runtime value or the `value` property,
 * matching Apple's `ProgressView.swift`. Static usage is unchanged.
 *
 * Sample JSON:
 * ```
 * { "type": "ProgressView", "properties": { "value": 0.5, "total": 1.0, "title": "Loading" } }
 * { "type": "ProgressView" }   // indeterminate spinner
 * ```
 */
object ProgressView : ActionUIViewConstruction {
    /** Apple's `states["progress"]` key: a runtime override of the displayed progress. */
    private const val PROGRESS_STATE_KEY = "progress"

    override val valueType = ActionUIValueType.DOUBLE

    // Non-null only when a runtime value was set; null means "use the static
    // value property" (the builder reads it). Mirrors Apple's
    // `ProgressView.initialValue`, which returns `model.value as? Double`.
    override fun initialValue(element: ActionUIElement): Any? = null

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val title = props?.stringProperty("title")
        val actionID = props?.stringProperty("actionID")

        // Effective progress (Apple precedence): states["progress"] override >
        // the value bridge (a host write) > the static `value` property. Null at
        // every level -> indeterminate.
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        val stateProgress = viewModel?.states?.get(PROGRESS_STATE_KEY) as? Double
        val runtimeValue = viewModel?.value as? Double
        val value = stateProgress ?: runtimeValue ?: props?.numberProperty("value")
        val total = props?.numberProperty("total") ?: if (value != null) 1.0 else null
        val determinate = value != null && value >= 0.0 &&
            total != null && total > 0.0 && value <= total
        val fraction = if (determinate) (value!! / total!!).toFloat() else 0f

        val rootModifier = if (actionID != null) {
            modifier.clickable {
                ActionUIModel.actionHandler(actionID, viewID = element.id, viewPartID = 0)
            }
        } else {
            modifier
        }

        // SwiftUI `.tint` colors the progress indicator; an inherited tint maps
        // to the bar's / spinner's color.
        val tint = LocalActionUITint.current

        Column(modifier = rootModifier) {
            if (title != null) M3Text(text = title)
            when {
                determinate && tint != null -> LinearProgressIndicator(progress = { fraction }, color = tint)
                determinate -> LinearProgressIndicator(progress = { fraction })
                tint != null -> CircularProgressIndicator(color = tint)
                else -> CircularProgressIndicator()
            }
        }
    }
}
