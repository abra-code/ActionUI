package com.abracode.actionui.Views

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIViewConstruction

/**
 * Renders an ellipse filling its frame.
 *
 * Mirror of the Apple `Ellipse` element (`ActionUI/Views/Ellipse.swift`), which
 * wraps `SwiftUI.Ellipse`. Drawn with `drawOval`, which fills the box - an equal
 * width/height frame yields a circle. `fill` / `stroke` / `strokeLineWidth`
 * resolve through the shared [ShapeView] / `ShapeStyleHelper` path. Needs an
 * explicit `frame` to be visible - see [ShapeView].
 *
 * Sample JSON:
 * ```
 * { "type": "Ellipse", "properties": { "stroke": "purple", "strokeLineWidth": 3, "frame": { "width": 90, "height": 60 } } }
 * ```
 */
object Ellipse : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        ShapeView(element, modifier) { color, style ->
            drawOval(color = color, style = style)
        }
    }
}
