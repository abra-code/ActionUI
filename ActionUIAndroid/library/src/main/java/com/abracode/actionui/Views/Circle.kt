package com.abracode.actionui.Views

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction

/**
 * Renders a circle inscribed in (and centered within) its frame.
 *
 * Mirror of the Apple `Circle` element (`ActionUI/Views/Circle.swift`), which
 * wraps `SwiftUI.Circle`. Drawn with `drawCircle(radius = minDimension/2)` so it
 * stays a true circle on a non-square frame - Compose's `CircleShape` would
 * degenerate to a capsule there. `fill` / `stroke` / `strokeLineWidth` resolve
 * through the shared [ShapeView] / `ShapeStyleHelper` path. Needs an explicit
 * `frame` to be visible - see [ShapeView].
 *
 * Sample JSON:
 * ```
 * { "type": "Circle", "properties": { "fill": "green", "frame": { "width": 60, "height": 60 } } }
 * ```
 */
object Circle : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        ShapeView(element, modifier) { color, style ->
            // Inscribed circle, centered - matches SwiftUI `Circle`.
            drawCircle(color = color, radius = size.minDimension / 2f, style = style)
        }
    }
}
