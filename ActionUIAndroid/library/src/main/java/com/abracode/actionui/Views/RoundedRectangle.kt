package com.abracode.actionui.Views

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Helpers.floatProperty
import com.abracode.actionui.Helpers.warnUnsupportedCornerStyle

/**
 * Renders a rectangle with rounded corners.
 *
 * Mirror of the Apple `RoundedRectangle` element
 * (`ActionUI/Views/RoundedRectangle.swift`), which wraps
 * `SwiftUI.RoundedRectangle`. The `cornerRadius` (points/dp, default 0) sets the
 * corner geometry; `cornerStyle: "continuous"` (squircle) has no Compose
 * equivalent and warn-and-downgrades to `circular`. `fill` / `stroke` /
 * `strokeLineWidth` resolve through the shared [ShapeView] / `ShapeStyleHelper`
 * seam. Needs an explicit `frame` to be visible - see [ShapeView].
 *
 * Sample JSON:
 * ```
 * { "type": "RoundedRectangle",
 *   "properties": { "cornerRadius": 12, "fill": "#90CAF9", "frame": { "width": 120, "height": 60 } } }
 * ```
 */
object RoundedRectangle : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current
        // `remember` doubles as the warn-once guard for an unsupported squircle.
        val cornerRadiusDp = remember(props) {
            warnUnsupportedCornerStyle(props, "cornerStyle", "RoundedRectangle", logger)
            props?.floatProperty("cornerRadius") ?: 0f
        }
        ShapeView(element, modifier) { color, style ->
            val r = cornerRadiusDp.dp.toPx()
            drawRoundRect(color = color, cornerRadius = CornerRadius(r, r), style = style)
        }
    }
}
