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
import com.abracode.actionui.Common.ActionUIViewConstruction
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
 * **Deferred vs. Apple.** Apple's `states["progress"]` runtime override is **not**
 * ported - Android has no `ViewModel`/state layer yet (see
 * `Private/Android_Porting_Notes.md` section 6), so progress is taken from the static
 * JSON `value` only, the same Phase-1 stance `Image` takes for its runtime value.
 *
 * Sample JSON:
 * ```
 * { "type": "ProgressView", "properties": { "value": 0.5, "total": 1.0, "title": "Loading" } }
 * { "type": "ProgressView" }   // indeterminate spinner
 * ```
 */
object ProgressView : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val title = props?.stringProperty("title")
        val actionID = props?.stringProperty("actionID")

        // Determinate only when value is valid (>= 0), total (default 1.0) is
        // positive, and value <= total - mirrors Apple's buildView guard.
        val value = props?.numberProperty("value")
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

        Column(modifier = rootModifier) {
            if (title != null) M3Text(text = title)
            if (determinate) LinearProgressIndicator(progress = { fraction })
            else CircularProgressIndicator()
        }
    }
}
