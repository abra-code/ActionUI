package com.abracode.actionui.Views

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Helpers.warnUnsupportedCornerStyle

/**
 * Renders a capsule - a rectangle with fully-rounded ends.
 *
 * Mirror of the Apple `Capsule` element (`ActionUI/Views/Capsule.swift`), which
 * wraps `SwiftUI.Capsule`. The corner radius is half the shorter side, so the
 * ends are always fully rounded regardless of frame; `style: "continuous"`
 * (squircle) has no Compose equivalent and warn-and-downgrades to `circular`.
 * `fill` / `stroke` / `strokeLineWidth` resolve through the shared [ShapeView] /
 * `ShapeStyleHelper` seam. Needs an explicit `frame` to be visible - see
 * [ShapeView].
 *
 * Sample JSON:
 * ```
 * { "type": "Capsule", "properties": { "fill": "orange", "frame": { "width": 160, "height": 32 } } }
 * ```
 */
object Capsule : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val props = element.properties
        val logger = LocalActionUILogger.current
        remember(props) { warnUnsupportedCornerStyle(props, "style", "Capsule", logger) }
        ShapeView(element, modifier) { color, style ->
            // Fully-rounded ends: corner radius = half the shorter side.
            val r = size.minDimension / 2f
            drawRoundRect(color = color, cornerRadius = CornerRadius(r, r), style = style)
        }
    }
}
