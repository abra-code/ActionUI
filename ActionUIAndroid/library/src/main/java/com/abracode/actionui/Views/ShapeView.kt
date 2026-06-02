package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Spacer as LayoutSpacer
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.DrawStyle
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Helpers.resolveShapePaint

/**
 * Shared rendering glue for the stateless shape elements — `Rectangle`,
 * `RoundedRectangle`, `Capsule`, `Circle`, `Ellipse` (each in its own file,
 * mirroring `ActionUI/Views/Rectangle.swift` and siblings).
 *
 * Every shape renders by drawing its geometry into a zero-content
 * [androidx.compose.foundation.layout.Spacer] via `Modifier.drawBehind`. This is
 * deliberately uniform and maps each SwiftUI shape onto the [DrawScope]
 * primitive with the **same geometry**, which is more faithful than reusing
 * Compose `Shape` objects (e.g. Compose's `CircleShape` degenerates to a capsule
 * on a non-square box, unlike SwiftUI `Circle`).
 *
 * `fill` / `stroke` / `strokeLineWidth` resolve through the shared
 * [resolveShapePaint] (`Helpers/ShapeStyleHelper.kt`); a stroke maps to a Compose
 * [Stroke] `DrawStyle`, a fill to [Fill]. Each shape builder only describes its
 * geometry by passing a [draw] lambda to [ShapeView].
 *
 * ## Sizing caveat (documented divergence)
 *
 * A `Spacer` wraps to zero size with no constraints, whereas a SwiftUI shape is
 * *greedy* — it expands to fill the space offered by its parent. So on Android a
 * shape needs an explicit `frame` (or a parent that stretches it) to be visible;
 * a frameless shape renders nothing. This is the same "needs slack/size" class
 * of caveat already documented for per-child `align` (§1) and `Divider`/`Spacer`
 * (§9) in `Private/Android_Porting_Notes.md`; see §11 there.
 */
@Composable
internal fun ShapeView(
    element: ActionUIElement,
    modifier: Modifier,
    draw: DrawScope.(color: Color, style: DrawStyle) -> Unit
) {
    val props = element.properties
    val logger = LocalActionUILogger.current
    // SwiftUI fills an unstyled shape with `.primary`; onSurface is its analog.
    val defaultColor = MaterialTheme.colorScheme.onSurface
    val paint = remember(props, defaultColor) { resolveShapePaint(props, defaultColor, logger) }

    LayoutSpacer(
        modifier = modifier.drawBehind {
            val style: DrawStyle = paint.strokeWidthDp?.let { Stroke(it.dp.toPx()) } ?: Fill
            draw(paint.color, style)
        }
    )
}
