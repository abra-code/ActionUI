package com.abracode.actionui.Helpers

import android.content.res.AssetManager
import android.graphics.BitmapFactory
import android.graphics.BlurMaskFilter
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.LinearGradientShader
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.PaintingStyle
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.RadialGradientShader
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.io.IOException
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * The Canvas draw-command interpreter - the Android counterpart of Apple's
 * `ActionUI/Helpers/CanvasRenderer.swift`. The `Canvas` element carries a JSON
 * display list (`operations`); this file turns it into Compose/Skia drawing.
 * The shared schema is deliberately platform-neutral (paths, fill/stroke,
 * transforms, clips, layers map onto the common subset of Core Graphics, Skia,
 * and HTML Canvas 2D), so one authored drawing renders on both platforms.
 *
 * ## Two halves, like the rest of the renderer
 *
 *   1. **Parse (pure).** [parseCanvasOperations] resolves the JSON into typed
 *      [CanvasOp]s, mirroring both Apple's `Canvas.validateProperties` (which
 *      drops malformed operations) and the per-operation guards inside the
 *      Swift renderer. Anything dropped is warned, the codebase's
 *      "unknown value -> warn + skip" contract (the Swift side is silent for
 *      some of these; warning is strictly more helpful and renders the same).
 *      Pure Kotlin, so the whole vocabulary is unit-testable.
 *   2. **Draw.** [drawCanvasOperations] walks the typed list inside a
 *      [DrawScope]. Verified by running the app, the stance Compose drawing
 *      takes elsewhere.
 *
 * ## Units (matches the Swift implementation, not the schema comments)
 *
 * Path/frame/gradient coordinates are normalized (0..1 of the canvas) unless
 * `coordinateMode` is `"points"`. Everything else - `lineWidth`, `dash`,
 * `fontSize`, `translate` x/y, shadow radius/offsets, blur radius - is in
 * **raw points** regardless of mode, because that is what the Swift renderer
 * does (it passes them unscaled into `StrokeStyle`/`Font`/filters; the demo
 * JSON is authored accordingly, e.g. `"lineWidth": 4`). Points map to dp here,
 * the same pt==dp equivalence the rest of the port uses. Gradient geometry is
 * always normalized, even in points mode - again matching the Swift renderer.
 *
 * ## Divergences from Apple (documented, all small)
 *
 *   * **Blur** uses [BlurMaskFilter] on geometry (and a zero-offset shadow for
 *     text), which blurs shapes/text but not raster images; SwiftUI's
 *     `.blur` filter is a full Gaussian over subsequent content. When both a
 *     shadow and a blur are active, text applies the shadow only.
 *   * **Shadow** ignores the optional `blendMode`/`drawAbove` knobs
 *     (`setShadowLayer` has no blend hook); shadows composite normally below
 *     content. Raster images draw without filters.
 *   * **Layer** opacity/blend apply to the composited group (`saveLayer`),
 *     not per-draw as `GraphicsContext` state does - the difference is only
 *     visible where shapes overlap *inside* one layer.
 *   * **Radial gradients** have no start radius in Compose; a non-zero
 *     `startRadius` is warned and treated as 0.
 *   * `text.alignment` is accepted but not applied - same as Apple, whose
 *     renderer logs it as unsupported.
 */

// ============================== Typed model ==============================

/** A resolved `[x, y, width, height]` frame, still in schema coordinates. */
internal data class CanvasFrame(
    val x: Double,
    val y: Double,
    val width: Double,
    val height: Double,
)

/** A path shape from a `"path"` dictionary (`circle`, `rect`, `path`, ...). */
internal sealed interface CanvasPathSpec {
    data class Circle(val centerX: Double, val centerY: Double, val radius: Double) : CanvasPathSpec
    data class Ellipse(val frame: CanvasFrame) : CanvasPathSpec
    data class Rectangle(val frame: CanvasFrame) : CanvasPathSpec
    data class RoundedRect(val frame: CanvasFrame, val cornerRadius: Double) : CanvasPathSpec
    data class Commands(val commands: List<CanvasPathCommand>) : CanvasPathSpec
}

/** One command of a custom Bezier path (`["lineTo", x, y]`, ...). */
internal sealed interface CanvasPathCommand {
    data class MoveTo(val x: Double, val y: Double) : CanvasPathCommand
    data class LineTo(val x: Double, val y: Double) : CanvasPathCommand
    data class QuadTo(
        val controlX: Double, val controlY: Double,
        val x: Double, val y: Double,
    ) : CanvasPathCommand
    data class CubicTo(
        val control1X: Double, val control1Y: Double,
        val control2X: Double, val control2Y: Double,
        val x: Double, val y: Double,
    ) : CanvasPathCommand
    data class Arc(
        val centerX: Double, val centerY: Double, val radius: Double,
        val startDegrees: Double, val endDegrees: Double, val clockwise: Boolean,
    ) : CanvasPathCommand
    data object Close : CanvasPathCommand
}

/** A fill gradient. Geometry is always normalized (0..1), matching Apple. */
internal sealed interface CanvasGradientSpec {
    val colors: List<Color>

    data class Linear(
        val startX: Double, val startY: Double,
        val endX: Double, val endY: Double,
        override val colors: List<Color>,
    ) : CanvasGradientSpec

    data class Radial(
        val centerX: Double, val centerY: Double,
        val startRadius: Double, val endRadius: Double,
        override val colors: List<Color>,
    ) : CanvasGradientSpec
}

/** An image operation's source (the validated one-of-four contract). */
internal sealed interface CanvasImageSpec {
    /** SF Symbol name, drawn as the mapped Material glyph (`SystemSymbolResolver`). */
    data class SystemName(val name: String) : CanvasImageSpec
    /**
     * Explicit Material Symbol, the Android-only `materialName:android` axis
     * (normalized by `PlatformFilter`, which recurses into the operations
     * array). Wins over `systemName`, the same priority as the `Image` element.
     */
    data class MaterialName(val name: String) : CanvasImageSpec
    /** Bundle file in `assets/` (Apple: bundle resource), decoded to a bitmap. */
    data class ResourceName(val name: String) : CanvasImageSpec
    /** Absolute filesystem path, decoded to a bitmap. */
    data class FilePath(val path: String) : CanvasImageSpec
}

/** One validated drawing operation, in execution order. */
internal sealed interface CanvasOp {
    data class Fill(
        val path: CanvasPathSpec,
        val color: Color?,
        val gradient: CanvasGradientSpec?,
    ) : CanvasOp

    data class Stroke(
        val path: CanvasPathSpec,
        val color: Color,
        /** Points (see file header), default 1 like Apple's `StrokeStyle`. */
        val lineWidth: Float,
        val cap: StrokeCap,
        val join: StrokeJoin,
        val miterLimit: Float,
        /** Dash on/off lengths in points; empty means solid. */
        val dash: List<Float>,
        val dashPhase: Float,
    ) : CanvasOp

    data class Text(
        val text: String,
        val frame: CanvasFrame,
        /** Points, or null for the platform default size (Apple leaves the font unset). */
        val fontSize: Float?,
        val fontWeight: FontWeight?,
        val color: Color,
    ) : CanvasOp

    data class Image(
        val source: CanvasImageSpec,
        val frame: CanvasFrame,
        val opacity: Float,
    ) : CanvasOp

    data class Clip(val path: CanvasPathSpec) : CanvasOp

    /** Points; cumulative, like `GraphicsContext.translateBy`. */
    data class Translate(val x: Float, val y: Float) : CanvasOp
    data class Scale(val x: Float, val y: Float) : CanvasOp
    data class Rotate(val degrees: Float) : CanvasOp

    /** Drop-shadow filter for subsequent operations; values in points. */
    data class Shadow(
        val color: Color,
        val radius: Float,
        val x: Float,
        val y: Float,
    ) : CanvasOp

    /** Blur filter for subsequent operations; radius in points. */
    data class Blur(val radius: Float) : CanvasOp

    data class Layer(
        val frame: CanvasFrame,
        val opacity: Float,
        val blendMode: BlendMode,
        val operations: List<CanvasOp>,
    ) : CanvasOp
}

// ============================== Parsing ==============================

/**
 * Parses the element's `operations` JSON into typed [CanvasOp]s, dropping (with
 * a warning) anything malformed. Mirrors Apple's `validateOperations` plus the
 * Swift renderer's per-operation guards; notably, like Apple, a single non-object
 * item invalidates the whole array (`as? [[String: Any]]` fails wholesale).
 */
internal fun parseCanvasOperations(element: JsonElement?, logger: ActionUILogger?): List<CanvasOp> {
    if (element == null) return emptyList()
    val array = element as? JsonArray
    if (array == null || array.any { it !is JsonObject }) {
        logger?.log("Canvas operations must be an array of operation objects; ignoring.", LoggerLevel.warning)
        return emptyList()
    }
    return array.filterIsInstance<JsonObject>().mapNotNull { parseOperation(it, logger) }
}

private fun parseOperation(op: JsonObject, logger: ActionUILogger?): CanvasOp? {
    val type = (op["type"] as? JsonPrimitive)?.takeIf { it.isString }?.content
    if (type == null) {
        logger?.log("Canvas operation without a 'type' string skipped.", LoggerLevel.warning)
        return null
    }

    return when (type.lowercase()) {
        "fill" -> parseFill(op, logger)
        "stroke" -> parseStroke(op, logger)
        "text" -> parseText(op, logger)
        "image" -> parseImage(op, logger)
        "clip" -> parsePathSpec(op["path"], logger)?.let { CanvasOp.Clip(it) }
        "translate" -> CanvasOp.Translate(
            x = op.floatProperty("x") ?: 0f,
            y = op.floatProperty("y") ?: 0f,
        )
        "scale" -> CanvasOp.Scale(
            x = op.floatProperty("x") ?: 1f,
            y = op.floatProperty("y") ?: 1f,
        )
        "rotate" -> op.floatProperty("angle")?.let { CanvasOp.Rotate(it) }
        // Defaults match the Swift renderer's (raw points; near-invisible, but parity).
        "shadow" -> CanvasOp.Shadow(
            color = op.stringProperty("color")?.let { parseColor(it) } ?: Color.Black,
            radius = op.floatProperty("radius") ?: 0.005f,
            x = op.floatProperty("x") ?: 0.002f,
            y = op.floatProperty("y") ?: 0.004f,
        )
        "blur" -> {
            val radius = op.floatProperty("radius")
            if (radius == null) {
                logger?.log("Canvas blur missing valid 'radius' (expected number); skipped.", LoggerLevel.warning)
                null
            } else {
                // Apple warns but keeps a non-positive radius (it draws unblurred).
                if (radius <= 0f) {
                    logger?.log("Canvas blur radius should be > 0, got $radius", LoggerLevel.warning)
                }
                CanvasOp.Blur(radius)
            }
        }
        "layer" -> parseLayer(op, logger)
        else -> {
            logger?.log("Unknown Canvas operation type: $type", LoggerLevel.warning)
            null
        }
    }
}

private fun parseFill(op: JsonObject, logger: ActionUILogger?): CanvasOp? {
    val path = parsePathSpec(op["path"], logger) ?: return null
    // Gradient wins; an invalid gradient dictionary falls through to the color,
    // mirroring the Swift renderer's branch order.
    val gradient = (op["gradient"] as? JsonObject)?.let { parseGradient(it, logger) }
    if (gradient != null) return CanvasOp.Fill(path, color = null, gradient = gradient)
    val color = op.stringProperty("color")?.let { parseColor(it) }
    if (color == null) {
        logger?.log("No valid color or gradient for Canvas fill; skipped.", LoggerLevel.warning)
        return null
    }
    return CanvasOp.Fill(path, color = color, gradient = null)
}

private fun parseStroke(op: JsonObject, logger: ActionUILogger?): CanvasOp? {
    val path = parsePathSpec(op["path"], logger) ?: return null
    val color = op.stringProperty("color")?.let { parseColor(it) }
    if (color == null) {
        logger?.log("Missing/invalid color for Canvas stroke; skipped.", LoggerLevel.warning)
        return null
    }
    return CanvasOp.Stroke(
        path = path,
        color = color,
        lineWidth = op.floatProperty("lineWidth") ?: 1f,
        cap = strokeCapFromString(op.stringProperty("lineCap")),
        join = strokeJoinFromString(op.stringProperty("lineJoin")),
        miterLimit = op.floatProperty("miterLimit") ?: 10f,
        dash = floatList(op["dash"]) ?: emptyList(),
        dashPhase = op.floatProperty("dashPhase") ?: 0f,
    )
}

private fun parseText(op: JsonObject, logger: ActionUILogger?): CanvasOp? {
    val text = op.stringProperty("text")
    val frame = parseFrame(op["frame"])
    if (text == null || frame == null) {
        logger?.log("Canvas text needs 'text' and a 4-number 'frame'; skipped.", LoggerLevel.warning)
        return null
    }
    if (op["alignment"] != null) {
        // Same status as Apple: the Swift renderer logs alignment as unsupported.
        logger?.log("Text alignment currently not supported in Canvas - default alignment used", LoggerLevel.info)
    }
    return CanvasOp.Text(
        text = text,
        frame = frame,
        fontSize = op.floatProperty("fontSize"),
        fontWeight = fontWeightFromString(op.stringProperty("fontWeight")),
        color = op.stringProperty("color")?.let { parseColor(it) } ?: Color.Black,
    )
}

private fun parseImage(op: JsonObject, logger: ActionUILogger?): CanvasOp? {
    val frame = parseFrame(op["frame"])

    // The Android-only `materialName:android` glyph wins over any shared
    // source, mirroring the Image element's priority (Apple never sees the
    // key; PlatformFilter strips it there and normalizes it here).
    val materialName = op.stringProperty("materialName")
    if (materialName != null) {
        if (frame == null) {
            logger?.log("Canvas image needs a 4-number 'frame'; skipped.", LoggerLevel.warning)
            return null
        }
        return CanvasOp.Image(
            source = CanvasImageSpec.MaterialName(materialName),
            frame = frame,
            opacity = (op.numberProperty("opacity") ?: 1.0).toFloat(),
        )
    }

    val sources = listOf("systemName", "assetName", "resourceName", "filePath")
        .filter { op[it] != null }
    if (frame == null || sources.size != 1) {
        logger?.log(
            "Canvas image needs a 4-number 'frame' and exactly one source " +
                "(systemName/assetName/resourceName/filePath); skipped.",
            LoggerLevel.warning,
        )
        return null
    }
    val source = when (sources[0]) {
        "systemName" -> op.stringProperty("systemName")?.let { CanvasImageSpec.SystemName(it) }
        "resourceName" -> op.stringProperty("resourceName")?.let { CanvasImageSpec.ResourceName(it) }
        "filePath" -> op.stringProperty("filePath")?.let { CanvasImageSpec.FilePath(it) }
        else -> {
            // Same deferred status as the Image element's assetName (res/drawable
            // needs a name->resource contract); warn-and-skip rather than silent.
            logger?.log(
                "Canvas image 'assetName' maps to an Android res/drawable resource, " +
                    "which is not supported yet. Use 'resourceName', 'filePath', or " +
                    "'systemName'. Skipped.",
                LoggerLevel.warning,
            )
            null
        }
    } ?: return null
    return CanvasOp.Image(
        source = source,
        frame = frame,
        opacity = (op.numberProperty("opacity") ?: 1.0).toFloat(),
    )
}

private fun parseLayer(op: JsonObject, logger: ActionUILogger?): CanvasOp? {
    val frame = parseFrame(op["frame"])
    if (frame == null) {
        logger?.log("Canvas layer needs a 4-number 'frame'; skipped.", LoggerLevel.warning)
        return null
    }
    return CanvasOp.Layer(
        frame = frame,
        opacity = (op.numberProperty("opacity") ?: 1.0).toFloat(),
        blendMode = blendModeFromString(op.stringProperty("blendMode")),
        operations = parseCanvasOperations(op["operations"], logger),
    )
}

/** Parses a `"path"` shape dictionary, warning with Apple's reasons on failure. */
internal fun parsePathSpec(element: JsonElement?, logger: ActionUILogger?): CanvasPathSpec? {
    val dict = element as? JsonObject
    val type = dict?.stringProperty("type")
    if (dict == null || type == null) {
        logger?.log("Missing or invalid Canvas path type", LoggerLevel.warning)
        return null
    }

    return when (type.lowercase()) {
        "circle" -> {
            val center = floatPair(dict["center"])
            val radius = dict.numberProperty("radius")
            if (center == null || radius == null) {
                logger?.log("Invalid circle: missing center or radius", LoggerLevel.warning)
                null
            } else {
                CanvasPathSpec.Circle(center.first, center.second, radius)
            }
        }
        "ellipse" -> {
            val frame = parseFrame(dict["frame"])
            if (frame == null) {
                logger?.log("Invalid ellipse: frame must be [x,y,w,h]", LoggerLevel.warning)
                null
            } else {
                CanvasPathSpec.Ellipse(frame)
            }
        }
        "rect" -> {
            val frame = xywhFrame(dict)
            if (frame == null) {
                logger?.log("Invalid rect: missing x/y/width/height", LoggerLevel.warning)
                null
            } else {
                CanvasPathSpec.Rectangle(frame)
            }
        }
        "roundedrect" -> {
            val frame = xywhFrame(dict)
            if (frame == null) {
                logger?.log("Invalid roundedRect: missing x/y/width/height", LoggerLevel.warning)
                null
            } else {
                // Like Apple: a single cornerRadius, or the first of cornerRadii.
                val corner = dict.numberProperty("cornerRadius")
                    ?: doubleList(dict["cornerRadii"])?.takeIf { it.size == 4 }?.first()
                    ?: 0.0
                CanvasPathSpec.RoundedRect(frame, corner)
            }
        }
        "path" -> {
            val commandsJson = dict["commands"] as? JsonArray
            if (commandsJson == null || commandsJson.any { it !is JsonArray }) {
                logger?.log("Custom Canvas path missing 'commands' array", LoggerLevel.warning)
                null
            } else {
                val commands = commandsJson.filterIsInstance<JsonArray>()
                    .mapNotNull { parsePathCommand(it, logger) }
                // An empty path is nil on Apple, which skips the operation.
                if (commands.isEmpty()) null else CanvasPathSpec.Commands(commands)
            }
        }
        else -> {
            logger?.log("Unsupported Canvas path type: $type", LoggerLevel.warning)
            null
        }
    }
}

private fun parsePathCommand(command: JsonArray, logger: ActionUILogger?): CanvasPathCommand? {
    val name = (command.firstOrNull() as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
    // Like Apple's `numbers(from:)`: a non-numeric argument warns and reads as 0.
    val args = command.drop(1).map { arg ->
        (arg as? JsonPrimitive)?.doubleOrNull ?: run {
            logger?.log("Invalid number in Canvas path command: $arg", LoggerLevel.warning)
            0.0
        }
    }

    // Commands with too few arguments are skipped, matching the Swift guards.
    return when (name.lowercase()) {
        "moveto" -> if (args.size >= 2) CanvasPathCommand.MoveTo(args[0], args[1]) else null
        "lineto" -> if (args.size >= 2) CanvasPathCommand.LineTo(args[0], args[1]) else null
        "quadraticcurveto", "quadcurveto" ->
            if (args.size >= 4) CanvasPathCommand.QuadTo(args[0], args[1], args[2], args[3]) else null
        "curveto", "cubiccurveto" ->
            if (args.size >= 6) {
                CanvasPathCommand.CubicTo(args[0], args[1], args[2], args[3], args[4], args[5])
            } else null
        "arc" ->
            if (args.size >= 6) {
                CanvasPathCommand.Arc(args[0], args[1], args[2], args[3], args[4], clockwise = args[5] != 0.0)
            } else null
        "closepath", "close" -> CanvasPathCommand.Close
        else -> {
            logger?.log("Unknown Canvas path command: $name", LoggerLevel.warning)
            null
        }
    }
}

/**
 * Parses a `"gradient"` dictionary. Mirrors the Swift `makeShading`: at least
 * two color *strings* are required, unresolvable ones are dropped, and the
 * optional `locations` are ignored (Apple distributes colors evenly).
 */
internal fun parseGradient(dict: JsonObject, logger: ActionUILogger?): CanvasGradientSpec? {
    val type = dict.stringProperty("type")
    // Apple's `colors as? [String]`: any non-string item invalidates the list.
    val colorItems = (dict["colors"] as? JsonArray)
        ?.map { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content }
    val colorStrings = colorItems?.takeIf { items -> items.none { it == null } }?.filterNotNull()
    if (type == null || colorStrings == null || colorStrings.size < 2) {
        logger?.log("Invalid Canvas gradient: missing type or colors", LoggerLevel.warning)
        return null
    }
    val colors = colorStrings.mapNotNull { parseColor(it) }
    if (colors.isEmpty()) return null

    return when (type.lowercase()) {
        "linear" -> {
            val start = floatPair(dict["start"]) ?: return null
            val end = floatPair(dict["end"]) ?: return null
            CanvasGradientSpec.Linear(start.first, start.second, end.first, end.second, colors)
        }
        "radial" -> {
            val center = floatPair(dict["center"]) ?: return null
            val endRadius = dict.numberProperty("endRadius") ?: return null
            CanvasGradientSpec.Radial(
                centerX = center.first,
                centerY = center.second,
                startRadius = dict.numberProperty("startRadius") ?: 0.0,
                endRadius = endRadius,
                colors = colors,
            )
        }
        else -> {
            logger?.log("Unsupported Canvas gradient type: $type", LoggerLevel.warning)
            null
        }
    }
}

private fun parseFrame(element: JsonElement?): CanvasFrame? {
    val values = doubleList(element)?.takeIf { it.size == 4 } ?: return null
    return CanvasFrame(values[0], values[1], values[2], values[3])
}

private fun xywhFrame(dict: JsonObject): CanvasFrame? {
    val x = dict.numberProperty("x") ?: return null
    val y = dict.numberProperty("y") ?: return null
    val width = dict.numberProperty("width") ?: return null
    val height = dict.numberProperty("height") ?: return null
    return CanvasFrame(x, y, width, height)
}

private fun floatPair(element: JsonElement?): Pair<Double, Double>? =
    doubleList(element)?.takeIf { it.size == 2 }?.let { it[0] to it[1] }

private fun doubleList(element: JsonElement?): List<Double>? {
    val array = element as? JsonArray ?: return null
    return array.map { (it as? JsonPrimitive)?.doubleOrNull ?: return null }
}

private fun floatList(element: JsonElement?): List<Float>? =
    doubleList(element)?.map { it.toFloat() }

internal fun strokeCapFromString(name: String?): StrokeCap = when (name?.lowercase()) {
    "round" -> StrokeCap.Round
    "square" -> StrokeCap.Square
    else -> StrokeCap.Butt
}

internal fun strokeJoinFromString(name: String?): StrokeJoin = when (name?.lowercase()) {
    "round" -> StrokeJoin.Round
    "bevel" -> StrokeJoin.Bevel
    else -> StrokeJoin.Miter
}

/** The same blend vocabulary the Swift renderer resolves; anything else is normal. */
internal fun blendModeFromString(name: String?): BlendMode = when (name?.lowercase()) {
    "multiply" -> BlendMode.Multiply
    "screen" -> BlendMode.Screen
    "overlay" -> BlendMode.Overlay
    else -> BlendMode.SrcOver
}

/** SwiftUI's nine weight names by lightness rank; unknown is null (font unset), like Apple. */
internal fun fontWeightFromString(name: String?): FontWeight? = when (name?.lowercase()) {
    "ultralight" -> FontWeight.W100
    "thin" -> FontWeight.W200
    "light" -> FontWeight.W300
    "regular" -> FontWeight.W400
    "medium" -> FontWeight.W500
    "semibold" -> FontWeight.W600
    "bold" -> FontWeight.W700
    "heavy" -> FontWeight.W800
    "black" -> FontWeight.W900
    else -> null
}

/**
 * The Android sweep angle for an Apple `["arc", ...]` command. SwiftUI's
 * `clockwise` flag describes a y-up space, so in the canvas's y-down space
 * `clockwise: false` *appears* clockwise - which is Android's positive sweep.
 * A same-angle pair with distinct start/end (e.g. 0 -> 360) is a full circle,
 * as on Apple, not an empty arc.
 */
internal fun arcSweepDegrees(startDegrees: Double, endDegrees: Double, clockwise: Boolean): Float {
    var delta = (endDegrees - startDegrees) % 360.0
    if (!clockwise) {
        if (delta < 0) delta += 360.0
        if (delta == 0.0 && startDegrees != endDegrees) delta = 360.0
    } else {
        if (delta > 0) delta -= 360.0
        if (delta == 0.0 && startDegrees != endDegrees) delta = -360.0
    }
    return delta.toFloat()
}

// ============================== Drawing ==============================

/**
 * Everything the draw walk needs beyond the [DrawScope] itself, captured once
 * per composition by the `Canvas` element. The caches keep per-frame redraws
 * from re-decoding bitmaps or re-warning about the same missing symbol.
 */
internal class CanvasDrawEnv(
    val textMeasurer: TextMeasurer,
    val assets: AssetManager,
    /** Tint for `systemName` glyphs - the `.primary` analog (inherited content color). */
    val glyphColor: Color,
    val bitmapCache: MutableMap<String, ImageBitmap?>,
    val warnedSources: MutableSet<String>,
    val logger: ActionUILogger?,
)

/**
 * Walks the typed operations against the current canvas. [canvasSize] is the
 * normalization space (the element size, or the layer frame inside a layer);
 * [shadow]/[blur] seed the inherited filter state for nested layers.
 *
 * The caller brackets the walk with `canvas.save()`/`restore()` so cumulative
 * transforms and clips cannot leak past the element's draw block.
 */
internal fun DrawScope.drawCanvasOperations(
    operations: List<CanvasOp>,
    canvasSize: Size,
    pointsMode: Boolean,
    env: CanvasDrawEnv,
    shadow: CanvasOp.Shadow? = null,
    blur: Float? = null,
) {
    val canvas = drawContext.canvas
    var activeShadow = shadow
    var activeBlur = blur

    // Raw-point values (lineWidth, fontSize, filters, translate) are pt==dp.
    fun pt(value: Float): Float = value.dp.toPx()
    fun sx(value: Double): Float =
        if (pointsMode) pt(value.toFloat()) else (value * canvasSize.width).toFloat()
    fun sy(value: Double): Float =
        if (pointsMode) pt(value.toFloat()) else (value * canvasSize.height).toFloat()
    fun rect(frame: CanvasFrame): Rect {
        val left = sx(frame.x)
        val top = sy(frame.y)
        return Rect(left, top, left + sx(frame.width), top + sy(frame.height))
    }

    fun textShadow(textColor: Color): Pair<Color, Shadow?> {
        val currentShadow = activeShadow
        val currentBlur = activeBlur
        return when {
            currentShadow != null -> textColor to Shadow(
                color = currentShadow.color,
                offset = Offset(pt(currentShadow.x), pt(currentShadow.y)),
                blurRadius = pt(currentShadow.radius),
            )
            // Blur-only: the classic transparent-text + zero-offset-shadow blur.
            currentBlur != null && currentBlur > 0f ->
                Color.Transparent to Shadow(textColor, Offset.Zero, pt(currentBlur))
            else -> textColor to null
        }
    }

    for (op in operations) {
        when (op) {
            is CanvasOp.Fill, is CanvasOp.Stroke -> {
                val spec = if (op is CanvasOp.Fill) op.path else (op as CanvasOp.Stroke).path
                val path = buildCanvasPath(spec, canvasSize, pointsMode, this)
                val paint = Paint()
                if (op is CanvasOp.Fill) {
                    when {
                        // Gradient geometry is always normalized, like Apple's makeShading.
                        op.gradient != null -> paint.shader = makeGradientShader(op.gradient, canvasSize, env.logger)
                        op.color != null -> paint.color = op.color
                    }
                } else if (op is CanvasOp.Stroke) {
                    paint.style = PaintingStyle.Stroke
                    paint.color = op.color
                    paint.strokeWidth = pt(op.lineWidth)
                    paint.strokeCap = op.cap
                    paint.strokeJoin = op.join
                    paint.strokeMiterLimit = op.miterLimit
                    dashIntervals(op.dash)?.let { intervals ->
                        paint.pathEffect = PathEffect.dashPathEffect(
                            intervals.map { pt(it) }.toFloatArray(),
                            pt(op.dashPhase),
                        )
                    }
                }
                applyFilters(paint, activeShadow, activeBlur, ::pt)
                canvas.drawPath(path, paint)
            }

            is CanvasOp.Text -> {
                val frame = rect(op.frame)
                val (color, composeShadow) = textShadow(op.color)
                drawText(
                    textMeasurer = env.textMeasurer,
                    text = op.text,
                    topLeft = frame.topLeft,
                    style = TextStyle(
                        color = color,
                        fontSize = op.fontSize?.let { pt(it).toSp() } ?: TextUnit.Unspecified,
                        fontWeight = op.fontWeight,
                        shadow = composeShadow,
                    ),
                    size = frame.size,
                )
            }

            is CanvasOp.Image -> drawCanvasImage(op, rect(op.frame), env, ::textShadow)

            is CanvasOp.Clip -> canvas.clipPath(buildCanvasPath(op.path, canvasSize, pointsMode, this))

            is CanvasOp.Translate -> canvas.translate(pt(op.x), pt(op.y))
            is CanvasOp.Scale -> canvas.scale(op.x, op.y)
            is CanvasOp.Rotate -> canvas.rotate(op.degrees)

            is CanvasOp.Shadow -> activeShadow = op
            is CanvasOp.Blur -> activeBlur = op.radius

            is CanvasOp.Layer -> {
                val frame = rect(op.frame)
                // Generous layer bounds: saveLayer clips to its bounds, but a
                // rotation inside the layer may sweep content outside the frame
                // (GraphicsContext.drawLayer does not clip).
                val inflate = max(max(frame.width, frame.height), 1f)
                val paint = Paint().apply {
                    alpha = op.opacity
                    blendMode = op.blendMode
                }
                canvas.saveLayer(
                    Rect(
                        frame.left - inflate, frame.top - inflate,
                        frame.right + inflate, frame.bottom + inflate,
                    ),
                    paint,
                )
                canvas.translate(frame.left, frame.top)
                drawCanvasOperations(
                    op.operations, frame.size, pointsMode, env,
                    shadow = activeShadow, blur = activeBlur,
                )
                canvas.restore()
            }
        }
    }
}

/**
 * Normalizes a dash pattern for Android's even-count requirement: empty means
 * solid (null), an odd-length pattern repeats itself, like Core Graphics.
 */
internal fun dashIntervals(dash: List<Float>): List<Float>? = when {
    dash.isEmpty() -> null
    dash.size % 2 == 0 -> dash
    else -> dash + dash
}

/** Applies the active shadow/blur filter state to a geometry paint. */
private fun applyFilters(
    paint: Paint,
    shadow: CanvasOp.Shadow?,
    blur: Float?,
    pt: (Float) -> Float,
) {
    if (shadow == null && (blur == null || blur <= 0f)) return
    val frameworkPaint = paint.asFrameworkPaint()
    if (shadow != null) {
        frameworkPaint.setShadowLayer(pt(shadow.radius), pt(shadow.x), pt(shadow.y), shadow.color.toArgb())
    }
    if (blur != null && blur > 0f) {
        frameworkPaint.maskFilter = BlurMaskFilter(pt(blur), BlurMaskFilter.Blur.NORMAL)
    }
}

private fun makeGradientShader(
    gradient: CanvasGradientSpec,
    size: Size,
    logger: ActionUILogger?,
): androidx.compose.ui.graphics.Shader = when (gradient) {
    is CanvasGradientSpec.Linear -> LinearGradientShader(
        from = Offset((gradient.startX * size.width).toFloat(), (gradient.startY * size.height).toFloat()),
        to = Offset((gradient.endX * size.width).toFloat(), (gradient.endY * size.height).toFloat()),
        colors = gradient.colors,
    )
    is CanvasGradientSpec.Radial -> {
        if (gradient.startRadius > 0.0) {
            logger?.log(
                "Canvas radial gradient startRadius is not supported on Android; using 0.",
                LoggerLevel.warning,
            )
        }
        RadialGradientShader(
            center = Offset((gradient.centerX * size.width).toFloat(), (gradient.centerY * size.height).toFloat()),
            radius = (gradient.endRadius * minOf(size.width, size.height)).toFloat().coerceAtLeast(0.01f),
            colors = gradient.colors,
        )
    }
}

/** Builds the Compose [Path] for a shape spec in the current coordinate space. */
private fun buildCanvasPath(
    spec: CanvasPathSpec,
    size: Size,
    pointsMode: Boolean,
    density: Density,
): Path {
    fun sx(value: Double): Float =
        if (pointsMode) with(density) { value.toFloat().dp.toPx() } else (value * size.width).toFloat()
    fun sy(value: Double): Float =
        if (pointsMode) with(density) { value.toFloat().dp.toPx() } else (value * size.height).toFloat()
    fun smin(value: Double): Float =
        if (pointsMode) with(density) { value.toFloat().dp.toPx() }
        else (value * minOf(size.width, size.height)).toFloat()
    fun rect(frame: CanvasFrame): Rect {
        val left = sx(frame.x)
        val top = sy(frame.y)
        return Rect(left, top, left + sx(frame.width), top + sy(frame.height))
    }

    val path = Path()
    when (spec) {
        is CanvasPathSpec.Circle -> {
            val r = smin(spec.radius)
            path.addOval(Rect(sx(spec.centerX) - r, sy(spec.centerY) - r, sx(spec.centerX) + r, sy(spec.centerY) + r))
        }
        is CanvasPathSpec.Ellipse -> path.addOval(rect(spec.frame))
        is CanvasPathSpec.Rectangle -> path.addRect(rect(spec.frame))
        is CanvasPathSpec.RoundedRect -> {
            val corner = smin(spec.cornerRadius)
            path.addRoundRect(RoundRect(rect(spec.frame), CornerRadius(corner, corner)))
        }
        is CanvasPathSpec.Commands -> {
            for (command in spec.commands) {
                when (command) {
                    is CanvasPathCommand.MoveTo -> path.moveTo(sx(command.x), sy(command.y))
                    is CanvasPathCommand.LineTo -> path.lineTo(sx(command.x), sy(command.y))
                    is CanvasPathCommand.QuadTo -> path.quadraticTo(
                        sx(command.controlX), sy(command.controlY),
                        sx(command.x), sy(command.y),
                    )
                    is CanvasPathCommand.CubicTo -> path.cubicTo(
                        sx(command.control1X), sy(command.control1Y),
                        sx(command.control2X), sy(command.control2Y),
                        sx(command.x), sy(command.y),
                    )
                    is CanvasPathCommand.Arc -> {
                        val r = smin(command.radius)
                        path.arcTo(
                            rect = Rect(
                                sx(command.centerX) - r, sy(command.centerY) - r,
                                sx(command.centerX) + r, sy(command.centerY) + r,
                            ),
                            startAngleDegrees = command.startDegrees.toFloat(),
                            sweepAngleDegrees = arcSweepDegrees(
                                command.startDegrees, command.endDegrees, command.clockwise,
                            ),
                            forceMoveTo = false,
                        )
                    }
                    CanvasPathCommand.Close -> path.close()
                }
            }
        }
    }
    return path
}

/**
 * Draws an image operation: raster sources stretch into the frame (Apple's
 * `context.draw(img, in:)`; `resizingMode` is accepted-but-ignored there too),
 * a `systemName` draws the mapped Material glyph centered in the frame, sized
 * to its height. Failures warn once per source and draw nothing.
 */
private fun DrawScope.drawCanvasImage(
    op: CanvasOp.Image,
    frame: Rect,
    env: CanvasDrawEnv,
    textShadow: (Color) -> Pair<Color, Shadow?>,
) {
    when (val source = op.source) {
        is CanvasImageSpec.SystemName, is CanvasImageSpec.MaterialName -> {
            // Resolve to a codepoint plus axis tuning: an SF name goes through
            // the SF->Material map (with its per-row fill/weight), an explicit
            // Material name through the codepoints table at the defaults.
            val resolved: Triple<Int, Int, Float>? = when (source) {
                is CanvasImageSpec.SystemName ->
                    systemSymbol(source.name, env.assets, env.logger)?.let {
                        Triple(
                            it.codepoint,
                            resolveSymbolWeight(explicit = null, mapWeight = it.weight),
                            resolveSymbolFill(explicit = null, mapFill = it.fill),
                        )
                    }
                is CanvasImageSpec.MaterialName ->
                    materialCodepoint(source.name, env.assets, env.logger)?.let {
                        Triple(it, MATERIAL_WEIGHT_DEFAULT, MATERIAL_FILL_DEFAULT)
                    }
                else -> null
            }
            if (resolved == null) {
                if (env.warnedSources.add(source.toString())) {
                    env.logger?.log(
                        "Canvas image glyph $source has no Material mapping " +
                            "(or the symbol assets are absent). Nothing rendered.",
                        LoggerLevel.warning,
                    )
                }
                return
            }
            val (codepoint, weight, fill) = resolved
            val fontSize = frame.height.toSp()
            val family = materialSymbolFontFamily(
                assets = env.assets,
                weight = weight,
                fill = fill,
                grade = resolveSymbolGrade(explicit = null),
                opsz = fontSize.value.coerceIn(MATERIAL_OPSZ_MIN, MATERIAL_OPSZ_MAX),
            )
            val tint = env.glyphColor.copy(alpha = env.glyphColor.alpha * op.opacity)
            val (color, shadow) = textShadow(tint)
            val layout = env.textMeasurer.measure(
                text = String(Character.toChars(codepoint)),
                style = TextStyle(color = color, fontSize = fontSize, fontFamily = family, shadow = shadow),
            )
            drawText(
                textLayoutResult = layout,
                topLeft = Offset(
                    frame.center.x - layout.size.width / 2f,
                    frame.center.y - layout.size.height / 2f,
                ),
            )
        }

        is CanvasImageSpec.ResourceName, is CanvasImageSpec.FilePath -> {
            val key = when (source) {
                is CanvasImageSpec.ResourceName -> "asset:${source.name}"
                is CanvasImageSpec.FilePath -> "file:${source.path}"
                else -> return
            }
            if (!env.bitmapCache.containsKey(key)) {
                env.bitmapCache[key] = decodeCanvasBitmap(source, env)
            }
            val bitmap = env.bitmapCache[key] ?: return
            drawImage(
                image = bitmap,
                dstOffset = IntOffset(frame.left.roundToInt(), frame.top.roundToInt()),
                dstSize = IntSize(
                    frame.width.roundToInt().coerceAtLeast(1),
                    frame.height.roundToInt().coerceAtLeast(1),
                ),
                alpha = op.opacity,
            )
        }
    }
}

private fun decodeCanvasBitmap(source: CanvasImageSpec, env: CanvasDrawEnv): ImageBitmap? = when (source) {
    is CanvasImageSpec.ResourceName -> try {
        env.assets.open(source.name).use { BitmapFactory.decodeStream(it) }?.asImageBitmap().also {
            if (it == null) {
                env.logger?.log(
                    "Canvas image: asset '${source.name}' could not be decoded. Nothing rendered.",
                    LoggerLevel.warning,
                )
            }
        }
    } catch (e: IOException) {
        env.logger?.log(
            "Canvas image: resourceName '${source.name}' not found in assets/. Nothing rendered.",
            LoggerLevel.warning,
        )
        null
    }
    is CanvasImageSpec.FilePath -> BitmapFactory.decodeFile(source.path)?.asImageBitmap().also {
        if (it == null) {
            env.logger?.log(
                "Canvas image: filePath '${source.path}' missing or undecodable. Nothing rendered.",
                LoggerLevel.warning,
            )
        }
    }
    is CanvasImageSpec.SystemName, is CanvasImageSpec.MaterialName -> null
}
