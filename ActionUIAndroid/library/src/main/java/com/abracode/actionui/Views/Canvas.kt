package com.abracode.actionui.Views

import androidx.compose.foundation.Canvas as ComposeCanvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.rememberTextMeasurer
import com.abracode.actionui.Common.ActionUIElement
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIModel
import com.abracode.actionui.Common.ActionUIViewConstruction
import com.abracode.actionui.Common.LocalActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.CanvasDrawEnv
import com.abracode.actionui.Helpers.CanvasOp
import com.abracode.actionui.Helpers.drawCanvasOperations
import com.abracode.actionui.Helpers.parseCanvasOperations
import com.abracode.actionui.Helpers.parseColor
import com.abracode.actionui.Helpers.stringProperty
import kotlinx.serialization.json.JsonObject

/**
 * Custom 2D drawing surface rendered from a JSON display list. Mirror of the
 * Apple `Canvas` element (`ActionUI/Views/Canvas.swift`), which wraps
 * `SwiftUI.Canvas`; the operation vocabulary is the shared schema
 * (`Documentation/Schemas/Canvas.md`) and the interpreter is
 * `Helpers/CanvasRenderer.kt` - one authored drawing renders on both
 * platforms.
 *
 * **Greedy, like SwiftUI's Canvas** (and the shapes / `GeometryReader`): it
 * fills all the space its parent offers, so it declares [fillMaxSize]. On an
 * unbounded axis (a vertical scroller's height) give it an explicit `frame`,
 * the usual bounded-height stance.
 *
 * **Supported properties** (Apple's contract):
 *   * `operations` - the drawing operations, executed in order: `fill`,
 *     `stroke`, `text`, `image`, `clip`, `translate` / `scale` / `rotate`
 *     (cumulative), `shadow` / `blur` (filters for subsequent operations), and
 *     `layer` (an isolated sub-list with its own opacity/blend). Parsed and
 *     validated once per properties change by [parseCanvasOperations]; invalid
 *     operations warn and are skipped, matching Apple's validate-then-draw.
 *   * `backgroundColor` - fill behind the operations, default clear.
 *   * `coordinateMode` - `"normalized"` (0..1 of the canvas, default) or
 *     `"points"` (absolute points == dp). Stroke widths, font sizes, and
 *     filter radii are always in points, matching the Swift renderer (see the
 *     `CanvasRenderer.kt` header for the unit contract and the documented
 *     fidelity divergences: geometry-only blur, shadow without blend, layer
 *     group-compositing, radial startRadius).
 *   * `actionID` - dispatched through [ActionUIModel.actionHandler] on tap
 *     with the element's `id` as `viewID`, like Apple's `onTapGesture`.
 *
 * `image` operations resolve `systemName` through the same SF->Material glyph
 * seam as the `Image` element, and `resourceName` / `filePath` as bitmaps
 * (decoded once and cached per source); `assetName` is deferred with the same
 * warn-and-skip as `Image`. Glyphs tint with the inherited content color, the
 * Android analog of SwiftUI's `.primary` resolution inside a canvas.
 *
 * Sample JSON:
 * ```
 * { "type": "Canvas", "id": 1,
 *   "properties": {
 *     "backgroundColor": "#F8F9FA",
 *     "frame": { "width": 140, "height": 140 },
 *     "operations": [
 *       { "type": "fill",
 *         "path": { "type": "circle", "center": [0.5, 0.5], "radius": 0.45 },
 *         "color": "#FF3B30" }
 *     ] } }
 * ```
 */
object Canvas : ActionUIViewConstruction {
    @Composable
    override fun BuildView(element: ActionUIElement, modifier: Modifier) {
        val logger = LocalActionUILogger.current
        val props = element.properties
        val config = remember(props) { resolveCanvasConfig(props, logger) }

        // Draw-walk dependencies captured at composition; the caches keep
        // per-frame redraws from re-decoding bitmaps or repeating warnings.
        val textMeasurer = rememberTextMeasurer()
        val assets = LocalContext.current.assets
        val glyphColor = LocalContentColor.current
        val bitmapCache = remember(props) { mutableMapOf<String, ImageBitmap?>() }
        val warnedSources = remember(props) { mutableSetOf<String>() }

        val actionID = config.actionID
        val tapModifier = if (actionID != null) {
            modifier.pointerInput(actionID, element.id) {
                detectTapGestures {
                    ActionUIModel.actionHandler(actionID, viewID = element.id)
                }
            }
        } else {
            modifier
        }

        ComposeCanvas(modifier = tapModifier.fillMaxSize()) {
            config.backgroundColor?.let { drawRect(color = it) }

            // Bracket the walk so cumulative transforms/clips cannot leak.
            val canvas = drawContext.canvas
            canvas.save()
            drawCanvasOperations(
                operations = config.operations,
                canvasSize = size,
                pointsMode = config.pointsMode,
                env = CanvasDrawEnv(
                    textMeasurer = textMeasurer,
                    assets = assets,
                    glyphColor = glyphColor,
                    bitmapCache = bitmapCache,
                    warnedSources = warnedSources,
                    logger = logger,
                ),
            )
            canvas.restore()
        }
    }
}

/** Resolved, validated Canvas properties. */
internal data class CanvasConfig(
    val operations: List<CanvasOp> = emptyList(),
    val backgroundColor: Color? = null,
    val pointsMode: Boolean = false,
    val actionID: String? = null,
)

/**
 * Resolves and validates the Canvas properties, mirroring the Apple
 * `Canvas.validateProperties` warnings: invalid `operations` are ignored
 * wholesale, an unresolvable `backgroundColor` falls back to clear, and an
 * unknown `coordinateMode` warns and defaults to normalized. Pure (logging
 * aside) so it is unit-testable.
 */
internal fun resolveCanvasConfig(props: JsonObject?, logger: ActionUILogger?): CanvasConfig {
    if (props == null) return CanvasConfig()

    var backgroundColor: Color? = null
    props.stringProperty("backgroundColor")?.let { name ->
        backgroundColor = parseColor(name)
        if (backgroundColor == null) {
            logger?.log(
                "Canvas backgroundColor '$name' is not a recognized color; using clear.",
                LoggerLevel.warning,
            )
        }
    }

    var pointsMode = false
    props.stringProperty("coordinateMode")?.let { mode ->
        when (mode) {
            "points" -> pointsMode = true
            "normalized" -> { /* default */ }
            else -> logger?.log(
                "Invalid coordinateMode value: $mode, defaulting to normalized",
                LoggerLevel.warning,
            )
        }
    }

    return CanvasConfig(
        operations = parseCanvasOperations(props["operations"], logger),
        backgroundColor = backgroundColor,
        pointsMode = pointsMode,
        actionID = props.stringProperty("actionID"),
    )
}
