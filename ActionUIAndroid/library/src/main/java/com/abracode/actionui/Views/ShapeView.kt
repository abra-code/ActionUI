package com.abracode.actionui.Views

import androidx.compose.foundation.layout.Spacer as LayoutSpacer
import androidx.compose.foundation.layout.fillMaxSize
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
 * Shared rendering glue for the stateless shape elements - `Rectangle`,
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
 * ## Sizing: a shape is greedy
 *
 * A SwiftUI shape accepts the full proposal - it expands to fill whatever its
 * parent offers. The `fillMaxSize` below declares that greed in Compose terms;
 * without it the zero-content `Spacer` wraps to 0x0 inside a fixed `frame`'s
 * `wrapContentSize` (which hands the content *loose* constraints so natural-size
 * widgets like an M3 Button are never crushed - see `applyFrame` in
 * `ModifierResolver.kt`) and the shape draws nothing. With an unbounded axis
 * (e.g. height inside a vertical scroller) `fillMaxSize` cannot resolve, so a
 * shape there still needs an explicit `frame` to be visible - the remaining
 * "needs slack/size" caveat documented in section 11 of
 * `Private/Android_Porting_Notes.md`.
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
        modifier = modifier.fillMaxSize().drawBehind {
            val style: DrawStyle = paint.strokeWidthDp?.let { Stroke(it.dp.toPx()) } ?: Fill
            draw(paint.color, style)
        }
    )
}
