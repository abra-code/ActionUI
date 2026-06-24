package com.abracode.actionui.Views

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color as ComposeColor
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LocalWindowModel
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.parseColor
import com.abracode.actionui.Helpers.stringProperty

/**
 * Renders a solid `Color` as a view - the Android mirror of SwiftUI's `Color`, which is
 * itself a View (`ActionUI/Views/Color.swift`). Registered as the element type "Color".
 *
 * A `Color` is a greedy block that fills the proposed space (a colored divider, a tinted
 * background block) - simpler than a `Rectangle` with a `fill`. Like the shape views it is
 * greedy ([fillMaxSize]); give it a `frame` (e.g. `height: 2`) to size it, and note the same
 * "needs slack/size in an unbounded axis" caveat as [ShapeView].
 *
 * The `color` string resolves through the shared [parseColor] (named / "primary" / hex /
 * `<color>.opacity(<fraction>)`); a missing or unresolvable color warns and draws transparent.
 * (Compose's own `Color` is imported as `ComposeColor` so this object can take the name `Color`.)
 *
 * **Value bridge.** Like Apple, `Color` declares [ActionUIValueType.COLOR]
 * (Apple's `Color?`): a host can override the rendered color at runtime via
 * `ActionUIModel.setElementValue(id, <Color>)` /
 * `setElementValueFromString(id, "red")`. A runtime value takes precedence over
 * the `color` property; when none is set the `color` property is used, so static
 * usage is unchanged. `initialValue` returns only a pre-set runtime value (`null`
 * means "use the `color` property"), matching Apple's `Color.swift`.
 *
 * Sample JSON:
 * ```
 * { "type": "Color", "properties": { "color": "blue", "frame": { "height": 2 } } }
 * ```
 */
object Color : ActionUIViewConstruction {
    override val valueType = ActionUIValueType.COLOR

    // Non-null only when a color was set at runtime; null means "use the `color`
    // property" (the builder resolves it). Mirrors Apple's `Color.initialValue`,
    // which returns `model.value as? SwiftUI.Color`.
    override fun initialValue(element: ActionUIElement): Any? = null

    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current

        // A runtime override (a host write) wins over the `color` property.
        val viewModel = LocalWindowModel.current?.viewModels?.get(element.id)
        val runtimeColor = viewModel?.value as? ComposeColor

        val color = when {
            runtimeColor != null -> runtimeColor
            else -> {
                val colorStr = element.properties?.stringProperty("color")
                when {
                    colorStr.isNullOrEmpty() -> {
                        logger.log("Color view requires a 'color' string; rendering transparent", LoggerLevel.warning)
                        ComposeColor.Transparent
                    }
                    else -> parseColor(colorStr) ?: run {
                        logger.log("Unknown color '$colorStr' for Color view; rendering transparent", LoggerLevel.warning)
                        ComposeColor.Transparent
                    }
                }
            }
        }
        Spacer(modifier.fillMaxSize().background(color))
    }
}
