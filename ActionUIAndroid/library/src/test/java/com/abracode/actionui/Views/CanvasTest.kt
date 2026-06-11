package com.abracode.actionui.Views

import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.text.font.FontWeight
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.ActionUIRegistry
import com.abracode.actionui.Common.ActionUIValueType
import com.abracode.actionui.Common.LoggerLevel
import com.abracode.actionui.Helpers.CanvasFrame
import com.abracode.actionui.Helpers.CanvasGradientSpec
import com.abracode.actionui.Helpers.CanvasImageSpec
import com.abracode.actionui.Helpers.CanvasOp
import com.abracode.actionui.Helpers.CanvasPathCommand
import com.abracode.actionui.Helpers.CanvasPathSpec
import com.abracode.actionui.Helpers.arcSweepDegrees
import com.abracode.actionui.Helpers.blendModeFromString
import com.abracode.actionui.Helpers.dashIntervals
import com.abracode.actionui.Helpers.fontWeightFromString
import com.abracode.actionui.Helpers.parseCanvasOperations
import com.abracode.actionui.Helpers.strokeCapFromString
import com.abracode.actionui.Helpers.strokeJoinFromString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for the pure half of the Canvas port - the operation parser in
 * `Helpers/CanvasRenderer.kt` ([parseCanvasOperations] and its vocabulary
 * helpers) and the property resolution ([resolveCanvasConfig]). The drawing
 * walk is verified by running the app, the stance Compose code takes
 * elsewhere in the renderer.
 */
class CanvasTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    private fun props(json: String): JsonObject =
        Json.parseToJsonElement(json).jsonObject

    private fun parseOps(json: String, logger: ActionUILogger? = null): List<CanvasOp> =
        parseCanvasOperations(Json.parseToJsonElement(json), logger)

    // ===== Registration / config =====

    @Test
    fun `Canvas is registered and carries no value`() {
        assertSame(Canvas, ActionUIRegistry.lookup("Canvas"))
        assertEquals(ActionUIValueType.NONE, Canvas.valueType)
    }

    @Test
    fun `config defaults match Apple's builder`() {
        val config = resolveCanvasConfig(null, null)
        assertTrue(config.operations.isEmpty())
        assertNull(config.backgroundColor)
        assertEquals(false, config.pointsMode)
        assertNull(config.actionID)
    }

    @Test
    fun `config reads all properties`() {
        val logger = CapturingLogger()
        val config = resolveCanvasConfig(
            props(
                """{ "backgroundColor": "#F8F9FA", "coordinateMode": "points",
                     "actionID": "canvasTap",
                     "operations": [ { "type": "translate", "x": 10 } ] }"""
            ),
            logger,
        )
        assertEquals(Color(0xFFF8F9FA), config.backgroundColor)
        assertTrue(config.pointsMode)
        assertEquals("canvasTap", config.actionID)
        assertEquals(listOf<CanvasOp>(CanvasOp.Translate(10f, 0f)), config.operations)
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `invalid coordinateMode and backgroundColor warn and default`() {
        val logger = CapturingLogger()
        val config = resolveCanvasConfig(
            props("""{ "backgroundColor": "shiny", "coordinateMode": "inches" }"""),
            logger,
        )
        assertNull(config.backgroundColor)
        assertEquals(false, config.pointsMode)
        assertEquals(2, logger.warnings.size)
    }

    @Test
    fun `operations must be an array of objects, wholesale like Apple`() {
        val logger = CapturingLogger()
        // A single non-object item invalidates the whole array (Apple's
        // `as? [[String: Any]]` cast fails wholesale).
        assertTrue(parseOps("""[ { "type": "rotate", "angle": 45 }, "oops" ]""", logger).isEmpty())
        assertTrue(parseOps(""""not an array"""", logger).isEmpty())
        assertEquals(2, logger.warnings.size)
        assertTrue(parseCanvasOperations(null, logger).isEmpty())
    }

    // ===== fill =====

    @Test
    fun `fill parses solid color and shape paths`() {
        val ops = parseOps(
            """[ { "type": "fill",
                   "path": { "type": "circle", "center": [0.5, 0.5], "radius": 0.45 },
                   "color": "#FF3B30" } ]"""
        )
        val fill = ops.single() as CanvasOp.Fill
        assertEquals(Color(0xFFFF3B30), fill.color)
        assertNull(fill.gradient)
        assertEquals(CanvasPathSpec.Circle(0.5, 0.5, 0.45), fill.path)
    }

    @Test
    fun `fill prefers a valid gradient and ignores locations`() {
        val ops = parseOps(
            """[ { "type": "fill",
                   "path": { "type": "rect", "x": 0, "y": 0, "width": 1, "height": 1 },
                   "color": "#FF0000",
                   "gradient": { "type": "linear", "start": [0, 0], "end": [1, 1],
                                 "colors": ["#FF9500", "#007AFF"], "locations": [0.0, 1.0] } } ]"""
        )
        val fill = ops.single() as CanvasOp.Fill
        assertNull(fill.color)
        assertEquals(
            CanvasGradientSpec.Linear(0.0, 0.0, 1.0, 1.0, listOf(Color(0xFFFF9500), Color(0xFF007AFF))),
            fill.gradient,
        )
    }

    @Test
    fun `fill with an invalid gradient falls back to the color, like the Swift branch order`() {
        val ops = parseOps(
            """[ { "type": "fill",
                   "path": { "type": "rect", "x": 0, "y": 0, "width": 1, "height": 1 },
                   "color": "#FF0000",
                   "gradient": { "type": "linear", "colors": ["#FF9500"] } } ]""",
            CapturingLogger(),
        )
        val fill = ops.single() as CanvasOp.Fill
        assertEquals(Color(0xFFFF0000), fill.color)
        assertNull(fill.gradient)
    }

    @Test
    fun `fill without path or without any resolvable paint is dropped`() {
        val logger = CapturingLogger()
        assertTrue(parseOps("""[ { "type": "fill", "color": "#FF0000" } ]""", logger).isEmpty())
        assertTrue(
            parseOps(
                """[ { "type": "fill", "path": { "type": "circle", "center": [0.5, 0.5], "radius": 0.4 } } ]""",
                logger,
            ).isEmpty()
        )
        assertEquals(2, logger.warnings.size)
    }

    @Test
    fun `radial gradient parses center and radii`() {
        val ops = parseOps(
            """[ { "type": "fill",
                   "path": { "type": "ellipse", "frame": [0.1, 0.1, 0.8, 0.8] },
                   "gradient": { "type": "radial", "center": [0.5, 0.5],
                                 "endRadius": 0.4, "colors": ["red", "blue"] } } ]"""
        )
        val gradient = (ops.single() as CanvasOp.Fill).gradient as CanvasGradientSpec.Radial
        assertEquals(0.5, gradient.centerX, 0.0)
        assertEquals(0.0, gradient.startRadius, 0.0)
        assertEquals(0.4, gradient.endRadius, 0.0)
        assertEquals(2, gradient.colors.size)
    }

    // ===== stroke =====

    @Test
    fun `stroke defaults match Apple's StrokeStyle`() {
        val ops = parseOps(
            """[ { "type": "stroke",
                   "path": { "type": "circle", "center": [0.5, 0.5], "radius": 0.45 },
                   "color": "#000000" } ]"""
        )
        val stroke = ops.single() as CanvasOp.Stroke
        assertEquals(1f, stroke.lineWidth, 0f)
        assertEquals(StrokeCap.Butt, stroke.cap)
        assertEquals(StrokeJoin.Miter, stroke.join)
        assertEquals(10f, stroke.miterLimit, 0f)
        assertTrue(stroke.dash.isEmpty())
        assertEquals(0f, stroke.dashPhase, 0f)
    }

    @Test
    fun `stroke reads the full style and drops without a color`() {
        val logger = CapturingLogger()
        val ops = parseOps(
            """[ { "type": "stroke",
                   "path": { "type": "rect", "x": 0, "y": 0, "width": 1, "height": 1 },
                   "color": "#0000FF", "lineWidth": 6, "lineCap": "round",
                   "lineJoin": "bevel", "miterLimit": 4, "dash": [5, 2], "dashPhase": 1 },
                 { "type": "stroke",
                   "path": { "type": "rect", "x": 0, "y": 0, "width": 1, "height": 1 } } ]""",
            logger,
        )
        val stroke = ops.single() as CanvasOp.Stroke
        assertEquals(6f, stroke.lineWidth, 0f)
        assertEquals(StrokeCap.Round, stroke.cap)
        assertEquals(StrokeJoin.Bevel, stroke.join)
        assertEquals(4f, stroke.miterLimit, 0f)
        assertEquals(listOf(5f, 2f), stroke.dash)
        assertEquals(1f, stroke.dashPhase, 0f)
        assertEquals(1, logger.warnings.size)
    }

    // ===== text =====

    @Test
    fun `text parses with Apple defaults and requires text plus frame`() {
        val logger = CapturingLogger()
        val ops = parseOps(
            """[ { "type": "text", "text": "Hello", "frame": [0.1, 0.1, 0.8, 0.8] },
                 { "type": "text", "text": "No frame" } ]""",
            logger,
        )
        val text = ops.single() as CanvasOp.Text
        assertEquals("Hello", text.text)
        assertNull(text.fontSize)
        assertNull(text.fontWeight)
        assertEquals(Color.Black, text.color)
        assertEquals(1, logger.warnings.size)
    }

    @Test
    fun `text reads font and color, unknown weight is silently unset like Apple`() {
        val ops = parseOps(
            """[ { "type": "text", "text": "Hi", "frame": [0, 0, 1, 1],
                   "fontSize": 28, "fontWeight": "bold", "color": "#1E90FF" },
                 { "type": "text", "text": "Hi", "frame": [0, 0, 1, 1], "fontWeight": "chunky" } ]"""
        )
        val styled = ops[0] as CanvasOp.Text
        assertEquals(28f, styled.fontSize!!, 0f)
        assertEquals(FontWeight.W700, styled.fontWeight)
        assertEquals(Color(0xFF1E90FF), styled.color)
        assertNull((ops[1] as CanvasOp.Text).fontWeight)
    }

    // ===== image =====

    @Test
    fun `image requires exactly one source and a frame`() {
        val logger = CapturingLogger()
        val ops = parseOps(
            """[ { "type": "image", "resourceName": "logo.png", "frame": [0, 0, 1, 1], "opacity": 0.8 },
                 { "type": "image", "systemName": "star.fill", "resourceName": "x.png", "frame": [0, 0, 1, 1] },
                 { "type": "image", "systemName": "star.fill" } ]""",
            logger,
        )
        val image = ops.single() as CanvasOp.Image
        assertEquals(CanvasImageSpec.ResourceName("logo.png"), image.source)
        assertEquals(0.8f, image.opacity, 1e-6f)
        assertEquals(2, logger.warnings.size)
    }

    @Test
    fun `image assetName is deferred with a warning, like the Image element`() {
        val logger = CapturingLogger()
        assertTrue(
            parseOps("""[ { "type": "image", "assetName": "logo", "frame": [0, 0, 1, 1] } ]""", logger).isEmpty()
        )
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("assetName"))
    }

    @Test
    fun `image source kinds resolve to their specs`() {
        val ops = parseOps(
            """[ { "type": "image", "systemName": "swift", "frame": [0, 0, 1, 1] },
                 { "type": "image", "filePath": "/tmp/x.png", "frame": [0, 0, 1, 1] } ]"""
        )
        assertEquals(CanvasImageSpec.SystemName("swift"), (ops[0] as CanvasOp.Image).source)
        assertEquals(CanvasImageSpec.FilePath("/tmp/x.png"), (ops[1] as CanvasOp.Image).source)
    }

    @Test
    fun `an explicit materialName wins over systemName, like the Image element`() {
        // PlatformFilter has already normalized `materialName:android` by the
        // time properties reach the parser.
        val ops = parseOps(
            """[ { "type": "image", "systemName": "swift", "materialName": "raven",
                   "frame": [0, 0, 1, 1] },
                 { "type": "image", "materialName": "raven", "frame": [0, 0, 1, 1] } ]"""
        )
        assertEquals(CanvasImageSpec.MaterialName("raven"), (ops[0] as CanvasOp.Image).source)
        assertEquals(CanvasImageSpec.MaterialName("raven"), (ops[1] as CanvasOp.Image).source)
    }

    // ===== clip / transforms / filters =====

    @Test
    fun `clip requires a path, transforms read their defaults`() {
        val logger = CapturingLogger()
        val ops = parseOps(
            """[ { "type": "clip", "path": { "type": "circle", "center": [0.5, 0.5], "radius": 0.5 } },
                 { "type": "clip" },
                 { "type": "translate" },
                 { "type": "scale" },
                 { "type": "rotate", "angle": 45 },
                 { "type": "rotate" } ]""",
            logger,
        )
        assertEquals(4, ops.size)
        assertTrue(ops[0] is CanvasOp.Clip)
        assertEquals(CanvasOp.Translate(0f, 0f), ops[1])
        assertEquals(CanvasOp.Scale(1f, 1f), ops[2])
        assertEquals(CanvasOp.Rotate(45f), ops[3])
        assertEquals(1, logger.warnings.size) // the pathless clip
    }

    @Test
    fun `shadow defaults match the Swift renderer's raw-point defaults`() {
        val shadow = parseOps("""[ { "type": "shadow" } ]""").single() as CanvasOp.Shadow
        assertEquals(Color.Black, shadow.color)
        assertEquals(0.005f, shadow.radius, 1e-6f)
        assertEquals(0.002f, shadow.x, 1e-6f)
        assertEquals(0.004f, shadow.y, 1e-6f)
    }

    @Test
    fun `blur requires a radius and warns on a non-positive one`() {
        val logger = CapturingLogger()
        val ops = parseOps(
            """[ { "type": "blur", "radius": 4 },
                 { "type": "blur" },
                 { "type": "blur", "radius": -1 } ]""",
            logger,
        )
        assertEquals(listOf<CanvasOp>(CanvasOp.Blur(4f), CanvasOp.Blur(-1f)), ops)
        assertEquals(2, logger.warnings.size)
    }

    @Test
    fun `unknown operation types warn and are dropped`() {
        val logger = CapturingLogger()
        assertTrue(parseOps("""[ { "type": "sparkle" }, { "notype": true } ]""", logger).isEmpty())
        assertEquals(2, logger.warnings.size)
    }

    // ===== layer =====

    @Test
    fun `layer parses nested operations recursively`() {
        val ops = parseOps(
            """[ { "type": "layer", "frame": [0.1, 0.1, 0.8, 0.8],
                   "opacity": 0.85, "blendMode": "multiply",
                   "operations": [
                     { "type": "fill",
                       "path": { "type": "roundedRect", "x": 0, "y": 0, "width": 1, "height": 1,
                                 "cornerRadius": 0.2 },
                       "color": "#9C27B0" } ] } ]"""
        )
        val layer = ops.single() as CanvasOp.Layer
        assertEquals(0.85f, layer.opacity, 1e-6f)
        assertEquals(BlendMode.Multiply, layer.blendMode)
        val fill = layer.operations.single() as CanvasOp.Fill
        assertEquals(CanvasPathSpec.RoundedRect(CanvasFrame(0.0, 0.0, 1.0, 1.0), 0.2), fill.path)
    }

    @Test
    fun `layer without frame is dropped, missing operations mean an empty layer`() {
        val logger = CapturingLogger()
        val ops = parseOps(
            """[ { "type": "layer", "opacity": 0.5 },
                 { "type": "layer", "frame": [0, 0, 1, 1] } ]""",
            logger,
        )
        val layer = ops.single() as CanvasOp.Layer
        assertTrue(layer.operations.isEmpty())
        assertEquals(BlendMode.SrcOver, layer.blendMode)
        assertEquals(1, logger.warnings.size)
    }

    // ===== paths =====

    @Test
    fun `roundedRect takes cornerRadius or the first of cornerRadii`() {
        val ops = parseOps(
            """[ { "type": "fill", "color": "red",
                   "path": { "type": "roundedRect", "x": 0, "y": 0, "width": 1, "height": 1,
                             "cornerRadii": [0.05, 0.1, 0.05, 0.1] } } ]"""
        )
        val spec = (ops.single() as CanvasOp.Fill).path as CanvasPathSpec.RoundedRect
        assertEquals(0.05, spec.cornerRadius, 0.0)
    }

    @Test
    fun `custom path commands parse, skipping short and unknown ones`() {
        val logger = CapturingLogger()
        val ops = parseOps(
            """[ { "type": "stroke", "color": "#FF9800",
                   "path": { "type": "path", "commands": [
                     ["moveTo", 0.5, 0.1],
                     ["lineTo", 0.6, 0.4],
                     ["quadraticCurveTo", 0.7, 0.3, 0.8, 0.5],
                     ["curveTo", 0.9, 0.2, 1.0, 0.6, 0.8, 0.8],
                     ["arc", 0.5, 0.5, 0.3, 0, 180, 0],
                     ["lineTo", 0.6],
                     ["teleportTo", 0.1, 0.1],
                     ["closePath"] ] } } ]""",
            logger,
        )
        val commands = ((ops.single() as CanvasOp.Stroke).path as CanvasPathSpec.Commands).commands
        assertEquals(
            listOf(
                CanvasPathCommand.MoveTo(0.5, 0.1),
                CanvasPathCommand.LineTo(0.6, 0.4),
                CanvasPathCommand.QuadTo(0.7, 0.3, 0.8, 0.5),
                CanvasPathCommand.CubicTo(0.9, 0.2, 1.0, 0.6, 0.8, 0.8),
                CanvasPathCommand.Arc(0.5, 0.5, 0.3, 0.0, 180.0, clockwise = false),
                CanvasPathCommand.Close,
            ),
            commands,
        )
        assertEquals(1, logger.warnings.size) // the unknown command
    }

    @Test
    fun `invalid numbers in commands warn and read as zero, like Apple`() {
        val logger = CapturingLogger()
        val ops = parseOps(
            """[ { "type": "fill", "color": "red",
                   "path": { "type": "path", "commands": [["moveTo", "oops", 0.5], ["lineTo", 1, 1]] } } ]""",
            logger,
        )
        val commands = ((ops.single() as CanvasOp.Fill).path as CanvasPathSpec.Commands).commands
        assertEquals(CanvasPathCommand.MoveTo(0.0, 0.5), commands[0])
        assertEquals(1, logger.warnings.size)
    }

    @Test
    fun `empty or invalid command lists drop the operation`() {
        val logger = CapturingLogger()
        assertTrue(
            parseOps(
                """[ { "type": "fill", "color": "red", "path": { "type": "path", "commands": [] } },
                     { "type": "fill", "color": "red", "path": { "type": "path" } },
                     { "type": "fill", "color": "red", "path": { "type": "blob" } } ]""",
                logger,
            ).isEmpty()
        )
        assertEquals(2, logger.warnings.size) // missing commands + unsupported type
    }

    // ===== vocabulary helpers =====

    @Test
    fun `arc sweep mirrors SwiftUI's flipped clockwise flag`() {
        // clockwise=false appears clockwise in the y-down canvas: positive sweep.
        assertEquals(180f, arcSweepDegrees(0.0, 180.0, clockwise = false), 1e-6f)
        assertEquals(-180f, arcSweepDegrees(0.0, 180.0, clockwise = true), 1e-6f)
        assertEquals(90f, arcSweepDegrees(270.0, 0.0, clockwise = false), 1e-6f)
        // A distinct same-angle pair is a full circle, not an empty arc.
        assertEquals(360f, arcSweepDegrees(0.0, 360.0, clockwise = false), 1e-6f)
        assertEquals(-360f, arcSweepDegrees(0.0, 360.0, clockwise = true), 1e-6f)
        assertEquals(0f, arcSweepDegrees(90.0, 90.0, clockwise = false), 1e-6f)
    }

    @Test
    fun `dash intervals double an odd pattern for Android's even-count rule`() {
        assertNull(dashIntervals(emptyList()))
        assertEquals(listOf(5f, 2f), dashIntervals(listOf(5f, 2f)))
        assertEquals(listOf(5f, 5f), dashIntervals(listOf(5f)))
    }

    @Test
    fun `string vocabularies map like the Swift fromString extensions`() {
        assertEquals(StrokeCap.Round, strokeCapFromString("round"))
        assertEquals(StrokeCap.Square, strokeCapFromString("SQUARE"))
        assertEquals(StrokeCap.Butt, strokeCapFromString("weird"))
        assertEquals(StrokeCap.Butt, strokeCapFromString(null))
        assertEquals(StrokeJoin.Bevel, strokeJoinFromString("bevel"))
        assertEquals(StrokeJoin.Miter, strokeJoinFromString(null))
        assertEquals(BlendMode.Screen, blendModeFromString("screen"))
        assertEquals(BlendMode.Overlay, blendModeFromString("overlay"))
        assertEquals(BlendMode.SrcOver, blendModeFromString("glow"))
        assertEquals(FontWeight.W100, fontWeightFromString("ultralight"))
        assertEquals(FontWeight.W600, fontWeightFromString("semibold"))
        assertEquals(FontWeight.W900, fontWeightFromString("black"))
        assertNull(fontWeightFromString("chunky"))
    }
}
