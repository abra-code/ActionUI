package com.abracode.actionui.Views

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction

/**
 * Renders a rectangle filling its frame.
 *
 * Mirror of the Apple `Rectangle` element (`ActionUI/Views/Rectangle.swift`),
 * which wraps `SwiftUI.Rectangle`. Stateless (`valueType = Void`); `fill` /
 * `stroke` / `strokeLineWidth` resolve through the shared [ShapeView] /
 * `ShapeStyleHelper` seam. Needs an explicit `frame` to be visible — see
 * [ShapeView] for the sizing caveat.
 *
 * Sample JSON:
 * ```
 * { "type": "Rectangle", "properties": { "fill": "blue", "frame": { "width": 80, "height": 40 } } }
 * ```
 */
object Rectangle : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        ShapeView(element, modifier) { color, style ->
            drawRect(color = color, style = style)
        }
    }
}
