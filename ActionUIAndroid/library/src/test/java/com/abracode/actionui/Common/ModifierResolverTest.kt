package com.abracode.actionui.Common

import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.unit.dp
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [applyCommonProperties] and the parse helpers in
 * `ModifierResolver.kt`. Scope-restricted overloads (`RowScope`/`ColumnScope`/
 * `BoxScope.buildChildModifier`) are exercised end-to-end in instrumentation
 * tests; they need a real scope receiver which is awkward to fake from plain
 * JUnit.
 */
class ModifierResolverTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    private fun props(json: String): JsonObject =
        Json.parseToJsonElement(json).jsonObject

    /** Counts how many Modifier.Element nodes are in [m]'s chain. */
    private fun chainLength(m: Modifier): Int =
        m.foldIn(0) { acc, _ -> acc + 1 }

    // -----------------------------------------------------------------------
    // applyCommonProperties - pass-through cases
    // -----------------------------------------------------------------------

    @Test
    fun `null properties returns the receiver unchanged`() {
        val base = Modifier
        assertSame(base, base.applyCommonProperties(null))
    }

    @Test
    fun `empty properties adds no elements to the chain`() {
        val base = Modifier
        val out = base.applyCommonProperties(props("{}"))
        assertEquals(chainLength(base), chainLength(out))
    }

    @Test
    fun `unrecognized property keys are ignored silently`() {
        // 'spacing' and 'text' belong to element builders, not the modifier
        // resolver - they must not log warnings or affect the chain.
        val logger = CapturingLogger()
        val base = Modifier
        val out = base.applyCommonProperties(
            props("""{"spacing":8,"text":"hello","foo":42}"""),
            logger
        )
        assertEquals(chainLength(base), chainLength(out))
        assertTrue("Expected no warnings, got: ${logger.warnings}", logger.warnings.isEmpty())
    }

    // -----------------------------------------------------------------------
    // Each universal property adds something to the chain
    // -----------------------------------------------------------------------

    @Test
    fun `padding adds at least one element to the chain`() {
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"padding":8}"""))
        assertTrue(chainLength(out) > chainLength(base))
    }

    @Test
    fun `frame width and height each add at least one element`() {
        // Sizing uses the SwiftUI 'frame' object - { width, height } - not
        // top-level width/height (which are not SwiftUI modifiers).
        val base = Modifier
        val widthOnly = base.applyCommonProperties(props("""{"frame":{"width":100}}"""))
        val heightOnly = base.applyCommonProperties(props("""{"frame":{"height":50}}"""))
        val both = base.applyCommonProperties(props("""{"frame":{"width":100,"height":50}}"""))
        assertTrue(chainLength(widthOnly) > chainLength(base))
        assertTrue(chainLength(heightOnly) > chainLength(base))
        assertTrue(chainLength(both) > chainLength(widthOnly))
        assertTrue(chainLength(both) > chainLength(heightOnly))
    }

    @Test
    fun `top-level width and height are ignored - sizing is frame-only`() {
        // Apple is canonical: there is no top-level width/height SwiftUI modifier,
        // so these keys must be treated as unrecognized (no chain growth, no warn).
        val logger = CapturingLogger()
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"width":100,"height":50}"""), logger)
        assertEquals(chainLength(base), chainLength(out))
        assertTrue("Expected no warnings, got: ${logger.warnings}", logger.warnings.isEmpty())
    }

    @Test
    fun `frame infinity fills the axis and adds an element`() {
        val base = Modifier
        val w = base.applyCommonProperties(props("""{"frame":{"width":"infinity"}}"""))
        val h = base.applyCommonProperties(props("""{"frame":{"height":"infinity"}}"""))
        assertTrue(chainLength(w) > chainLength(base))
        assertTrue(chainLength(h) > chainLength(base))
    }

    @Test
    fun `frame with unsupported axis value is skipped with warning`() {
        val logger = CapturingLogger()
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"frame":{"width":"wide"}}"""), logger)
        assertEquals(chainLength(base), chainLength(out))
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("frame.width"))
    }

    @Test
    fun `frame that is not an object is ignored`() {
        val logger = CapturingLogger()
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"frame":200}"""), logger)
        assertEquals(chainLength(base), chainLength(out))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `opacity adds at least one element to the chain`() {
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"opacity":0.5}"""))
        assertTrue(chainLength(out) > chainLength(base))
    }

    @Test
    fun `cornerRadius adds at least one element to the chain`() {
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"cornerRadius":12}"""))
        assertTrue(chainLength(out) > chainLength(base))
    }

    @Test
    fun `valid background color adds at least one element`() {
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"background":"red"}"""))
        assertTrue(chainLength(out) > chainLength(base))
    }

    @Test
    fun `combining many properties stacks them all into one chain`() {
        val base = Modifier
        val noOp = base.applyCommonProperties(props("{}"))
        val withAll = base.applyCommonProperties(
            props(
                """{"padding":8,"frame":{"width":100,"height":40},"background":"red",""" +
                """"cornerRadius":4,"opacity":0.8}"""
            )
        )
        // Expect at least six additional element appends - one per recognized
        // property. We use >= to remain robust to Compose internals layering
        // multiple Elements per public modifier function.
        assertTrue(
            "Expected combined chain to grow by at least 6, got " +
                "${chainLength(withAll)} vs ${chainLength(noOp)}",
            chainLength(withAll) >= chainLength(noOp) + 6
        )
    }

    // -----------------------------------------------------------------------
    // Invalid values: dropped, warning logged where appropriate
    // -----------------------------------------------------------------------

    @Test
    fun `background with unknown color name logs warning and skips`() {
        val logger = CapturingLogger()
        val base = Modifier
        val out = base.applyCommonProperties(
            props("""{"background":"not-a-color"}"""),
            logger
        )
        assertEquals(chainLength(base), chainLength(out))
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("'not-a-color'"))
        assertTrue(logger.warnings[0].contains("background"))
    }

    @Test
    fun `background with malformed hex logs warning and skips`() {
        val logger = CapturingLogger()
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"background":"#XYZ"}"""), logger)
        assertEquals(chainLength(base), chainLength(out))
        assertEquals(1, logger.warnings.size)
    }

    @Test
    fun `non-numeric padding value is skipped without warning`() {
        // doubleOrNull returns null for non-numbers - no spurious log noise.
        val logger = CapturingLogger()
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"padding":"big"}"""), logger)
        assertEquals(chainLength(base), chainLength(out))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `null logger silences invalid-color warnings without crashing`() {
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"background":"bogus"}"""), logger = null)
        assertEquals(chainLength(base), chainLength(out))
    }

    // -----------------------------------------------------------------------
    // Integer JSON values are accepted (not just floats)
    // -----------------------------------------------------------------------

    @Test
    fun `integer padding value is accepted same as float`() {
        val withInt = Modifier.applyCommonProperties(props("""{"padding":8}"""))
        val withFloat = Modifier.applyCommonProperties(props("""{"padding":8.0}"""))
        assertEquals(chainLength(withInt), chainLength(withFloat))
    }

    // -----------------------------------------------------------------------
    // The receiver is preserved (we chain onto it, not replace it)
    // -----------------------------------------------------------------------

    @Test
    fun `existing modifier on the receiver is preserved`() {
        val base = Modifier.padding(4.dp)
        val out = base.applyCommonProperties(props("""{"background":"red"}"""))
        // Result has more elements than base - appended, not discarded.
        assertTrue(chainLength(out) > chainLength(base))
    }

    @Test
    fun `result chain is different from base when properties are added`() {
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"padding":8}"""))
        assertNotEquals(base, out)
    }

    // -----------------------------------------------------------------------
    // parseVerticalAlignment / parseHorizontalAlignment / parseAlignment
    // -----------------------------------------------------------------------

    @Test
    fun `parseVerticalAlignment recognizes the three Row-scoped names`() {
        assertEquals(Alignment.Top, parseVerticalAlignment("top"))
        assertEquals(Alignment.CenterVertically, parseVerticalAlignment("center"))
        assertEquals(Alignment.CenterVertically, parseVerticalAlignment("centerVertically"))
        assertEquals(Alignment.Bottom, parseVerticalAlignment("bottom"))
    }

    @Test
    fun `parseVerticalAlignment rejects horizontal names`() {
        assertNull(parseVerticalAlignment("start"))
        assertNull(parseVerticalAlignment("end"))
    }

    @Test
    fun `parseVerticalAlignment is case insensitive`() {
        assertEquals(Alignment.Top, parseVerticalAlignment("Top"))
        assertEquals(Alignment.Bottom, parseVerticalAlignment("BOTTOM"))
    }

    @Test
    fun `parseHorizontalAlignment recognizes start center end`() {
        assertEquals(Alignment.Start, parseHorizontalAlignment("start"))
        assertEquals(Alignment.Start, parseHorizontalAlignment("leading"))
        assertEquals(Alignment.CenterHorizontally, parseHorizontalAlignment("center"))
        assertEquals(Alignment.CenterHorizontally, parseHorizontalAlignment("centerHorizontally"))
        assertEquals(Alignment.End, parseHorizontalAlignment("end"))
        assertEquals(Alignment.End, parseHorizontalAlignment("trailing"))
    }

    @Test
    fun `parseHorizontalAlignment rejects vertical names`() {
        assertNull(parseHorizontalAlignment("top"))
        assertNull(parseHorizontalAlignment("bottom"))
    }

    @Test
    fun `parseAlignment recognizes all nine box positions`() {
        assertEquals(Alignment.TopStart, parseAlignment("topStart"))
        assertEquals(Alignment.TopStart, parseAlignment("topLeading"))
        assertEquals(Alignment.TopCenter, parseAlignment("topCenter"))
        assertEquals(Alignment.TopCenter, parseAlignment("top"))
        assertEquals(Alignment.TopEnd, parseAlignment("topEnd"))
        assertEquals(Alignment.TopEnd, parseAlignment("topTrailing"))
        assertEquals(Alignment.CenterStart, parseAlignment("centerStart"))
        assertEquals(Alignment.Center, parseAlignment("center"))
        assertEquals(Alignment.CenterEnd, parseAlignment("centerEnd"))
        assertEquals(Alignment.BottomStart, parseAlignment("bottomStart"))
        assertEquals(Alignment.BottomCenter, parseAlignment("bottomCenter"))
        assertEquals(Alignment.BottomCenter, parseAlignment("bottom"))
        assertEquals(Alignment.BottomEnd, parseAlignment("bottomEnd"))
    }

    @Test
    fun `parseAlignment returns null for unknown name`() {
        assertNull(parseAlignment("nowhere"))
        assertNull(parseAlignment(""))
    }

    // -----------------------------------------------------------------------
    // parseRowAlignment - parent-level HStack alignment, with SwiftUI baseline
    // values handled gracefully.
    // -----------------------------------------------------------------------

    @Test
    fun `parseRowAlignment resolves the three standard values silently`() {
        val logger = CapturingLogger()
        assertEquals(Alignment.Top, parseRowAlignment("top", logger))
        assertEquals(Alignment.CenterVertically, parseRowAlignment("center", logger))
        assertEquals(Alignment.CenterVertically, parseRowAlignment("centerVertically", logger))
        assertEquals(Alignment.Bottom, parseRowAlignment("bottom", logger))
        assertTrue(
            "Expected no warnings for standard values, got: ${logger.warnings}",
            logger.warnings.isEmpty()
        )
    }

    @Test
    fun `parseRowAlignment returns null for firstTextBaseline with warning`() {
        // Baseline alignment has no Compose equivalent - caller's default
        // applies. See Private/Android_Porting_Notes.md.
        val logger = CapturingLogger()
        val out = parseRowAlignment("firstTextBaseline", logger)
        assertNull(out)
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("firstTextBaseline"))
        assertTrue(logger.warnings[0].contains("default alignment"))
    }

    @Test
    fun `parseRowAlignment returns null for lastTextBaseline with warning`() {
        val logger = CapturingLogger()
        val out = parseRowAlignment("lastTextBaseline", logger)
        assertNull(out)
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("lastTextBaseline"))
    }

    @Test
    fun `parseRowAlignment baseline name is case insensitive`() {
        val logger = CapturingLogger()
        assertNull(parseRowAlignment("FirstTextBaseline", logger))
        assertNull(parseRowAlignment("LASTTEXTBASELINE", logger))
        assertEquals(2, logger.warnings.size)
    }

    @Test
    fun `parseRowAlignment returns null for unknown name and warns`() {
        val logger = CapturingLogger()
        val out = parseRowAlignment("sideways", logger)
        assertNull(out)
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("Unknown alignment"))
    }

    @Test
    fun `parseRowAlignment rejects horizontal names with warning`() {
        // start/end belong to Column/VStack, not Row/HStack - should be flagged
        // as unknown for the Row context.
        val logger = CapturingLogger()
        assertNull(parseRowAlignment("start", logger))
        assertNull(parseRowAlignment("end", logger))
        assertEquals(2, logger.warnings.size)
    }

    @Test
    fun `parseRowAlignment with null logger does not crash on baseline or unknown`() {
        assertNull(parseRowAlignment("firstTextBaseline", logger = null))
        assertNull(parseRowAlignment("bogus", logger = null))
    }

    // -----------------------------------------------------------------------
    // parseColumnAlignment - parent-level VStack alignment.
    // -----------------------------------------------------------------------

    @Test
    fun `parseColumnAlignment resolves SwiftUI vocabulary silently`() {
        val logger = CapturingLogger()
        assertEquals(Alignment.Start, parseColumnAlignment("leading", logger))
        assertEquals(Alignment.End, parseColumnAlignment("trailing", logger))
        assertEquals(Alignment.CenterHorizontally, parseColumnAlignment("center", logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `parseColumnAlignment resolves Compose vocabulary silently`() {
        val logger = CapturingLogger()
        assertEquals(Alignment.Start, parseColumnAlignment("start", logger))
        assertEquals(Alignment.End, parseColumnAlignment("end", logger))
        assertEquals(Alignment.CenterHorizontally, parseColumnAlignment("centerHorizontally", logger))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `parseColumnAlignment returns null for unknown name and warns`() {
        val logger = CapturingLogger()
        assertNull(parseColumnAlignment("nowhere", logger))
        assertEquals(1, logger.warnings.size)
    }

    @Test
    fun `parseColumnAlignment rejects vertical names with warning`() {
        // top/bottom belong to Row/HStack, not Column/VStack.
        val logger = CapturingLogger()
        assertNull(parseColumnAlignment("top", logger))
        assertNull(parseColumnAlignment("bottom", logger))
        assertEquals(2, logger.warnings.size)
    }

    @Test
    fun `parseColumnAlignment does not silently translate baseline names`() {
        // VStack has no baseline alignment in SwiftUI either - these should
        // be flagged as unknown rather than fall back.
        val logger = CapturingLogger()
        assertNull(parseColumnAlignment("firstTextBaseline", logger))
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("Unknown alignment"))
    }

    // -----------------------------------------------------------------------
    // Transform / geometry modifiers: offset, rotationEffect, scaleEffect
    // -----------------------------------------------------------------------

    @Test
    fun `offset object adds an element to the chain`() {
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"offset":{"x":10,"y":-5}}"""))
        assertTrue(chainLength(out) > chainLength(base))
    }

    @Test
    fun `offset that is not an object is ignored`() {
        val logger = CapturingLogger()
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"offset":5}"""), logger)
        assertEquals(chainLength(base), chainLength(out))
        assertTrue(logger.warnings.isEmpty())
    }

    @Test
    fun `rotationEffect adds an element to the chain`() {
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"rotationEffect":45}"""))
        assertTrue(chainLength(out) > chainLength(base))
    }

    @Test
    fun `scaleEffect uniform number adds an element`() {
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"scaleEffect":1.5}"""))
        assertTrue(chainLength(out) > chainLength(base))
    }

    @Test
    fun `scaleEffect object with anchor adds an element`() {
        val base = Modifier
        val out = base.applyCommonProperties(
            props("""{"scaleEffect":{"x":1.5,"y":0.8,"anchor":"topLeading"}}""")
        )
        assertTrue(chainLength(out) > chainLength(base))
    }

    @Test
    fun `zIndex adds an element to the chain`() {
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"zIndex":3}"""))
        assertTrue(chainLength(out) > chainLength(base))
    }

    @Test
    fun `hidden true fades the view via an alpha element`() {
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"hidden":true}"""))
        assertTrue(chainLength(out) > chainLength(base))
    }

    @Test
    fun `hidden false adds nothing`() {
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"hidden":false}"""))
        assertEquals(chainLength(base), chainLength(out))
    }

    // -----------------------------------------------------------------------
    // Decoration modifiers: shadow, border, clipShape
    // -----------------------------------------------------------------------

    @Test
    fun `shadow object adds an element to the chain`() {
        val base = Modifier
        val out = base.applyCommonProperties(
            props("""{"shadow":{"color":"black","radius":5,"x":0,"y":2}}""")
        )
        assertTrue(chainLength(out) > chainLength(base))
    }

    @Test
    fun `shadow with unknown color still applies using the default color`() {
        // Color falls back to black (matching Swift's `?? .black`); no warning,
        // the shadow is still added.
        val logger = CapturingLogger()
        val base = Modifier
        val out = base.applyCommonProperties(
            props("""{"shadow":{"color":"not-a-color","radius":4}}"""), logger
        )
        assertTrue(chainLength(out) > chainLength(base))
    }

    @Test
    fun `border object adds an element to the chain`() {
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"border":{"color":"blue","width":2}}"""))
        assertTrue(chainLength(out) > chainLength(base))
    }

    @Test
    fun `clipShape named shape adds an element`() {
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"clipShape":"circle"}"""))
        assertTrue(chainLength(out) > chainLength(base))
    }

    @Test
    fun `clipShape rounded rectangle dict adds an element`() {
        val base = Modifier
        val out = base.applyCommonProperties(
            props("""{"clipShape":{"type":"roundedRectangle","cornerRadius":12}}""")
        )
        assertTrue(chainLength(out) > chainLength(base))
    }

    @Test
    fun `clipShape unknown name logs warning and skips`() {
        val logger = CapturingLogger()
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"clipShape":"triangle"}"""), logger)
        assertEquals(chainLength(base), chainLength(out))
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("triangle"))
    }

    // -----------------------------------------------------------------------
    // Flexible frame: min/ideal/max + alignment
    // -----------------------------------------------------------------------

    @Test
    fun `flexible frame min and max add an element`() {
        val base = Modifier
        val out = base.applyCommonProperties(
            props("""{"frame":{"minWidth":50,"maxWidth":200}}""")
        )
        assertTrue(chainLength(out) > chainLength(base))
    }

    @Test
    fun `flexible frame maxWidth infinity fills the axis`() {
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"frame":{"maxWidth":"infinity"}}"""))
        assertTrue(chainLength(out) > chainLength(base))
    }

    @Test
    fun `flexible frame idealWidth is ignored with a warning`() {
        // Compose has no preferred-size constraint, so idealWidth warns and skips.
        val logger = CapturingLogger()
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"frame":{"idealWidth":100}}"""), logger)
        assertEquals(chainLength(base), chainLength(out))
        assertEquals(1, logger.warnings.size)
        assertTrue(logger.warnings[0].contains("idealWidth"))
    }

    @Test
    fun `fixed frame with alignment adds size and wrapContentSize elements`() {
        val base = Modifier
        val sized = base.applyCommonProperties(props("""{"frame":{"width":100,"height":40}}"""))
        val aligned = base.applyCommonProperties(
            props("""{"frame":{"width":100,"height":40,"alignment":"topLeading"}}""")
        )
        assertTrue(chainLength(aligned) > chainLength(sized))
    }

    // -----------------------------------------------------------------------
    // Padding: EdgeInsets dict and "default"
    // -----------------------------------------------------------------------

    @Test
    fun `padding EdgeInsets dict adds an element`() {
        val base = Modifier
        val out = base.applyCommonProperties(
            props("""{"padding":{"top":10,"leading":5,"bottom":10,"trailing":5}}""")
        )
        assertTrue(chainLength(out) > chainLength(base))
    }

    @Test
    fun `padding default string adds an element`() {
        val base = Modifier
        val out = base.applyCommonProperties(props("""{"padding":"default"}"""))
        assertTrue(chainLength(out) > chainLength(base))
    }

    // -----------------------------------------------------------------------
    // parseFrameAlignment / parseClipShape / parseTransformOrigin
    // -----------------------------------------------------------------------

    @Test
    fun `parseFrameAlignment maps SwiftUI edge names with centered cross-axis`() {
        assertEquals(Alignment.CenterStart, parseFrameAlignment("leading"))
        assertEquals(Alignment.CenterEnd, parseFrameAlignment("trailing"))
        assertEquals(Alignment.TopCenter, parseFrameAlignment("top"))
        assertEquals(Alignment.BottomCenter, parseFrameAlignment("bottom"))
        assertEquals(Alignment.Center, parseFrameAlignment("center"))
        assertEquals(Alignment.TopStart, parseFrameAlignment("topLeading"))
        assertEquals(Alignment.BottomEnd, parseFrameAlignment("bottomTrailing"))
    }

    @Test
    fun `parseFrameAlignment returns null and warns for unknown name`() {
        val logger = CapturingLogger()
        assertNull(parseFrameAlignment("sideways", logger))
        assertEquals(1, logger.warnings.size)
    }

    @Test
    fun `parseClipShape resolves named shapes`() {
        assertEquals(CircleShape, parseClipShape(Json.parseToJsonElement(""""circle"""")))
        assertEquals(RectangleShape, parseClipShape(Json.parseToJsonElement(""""rectangle"""")))
        // capsule and ellipse have no shared singleton to compare against - assert
        // they resolve to a non-null shape.
        assertNotNull(parseClipShape(Json.parseToJsonElement(""""capsule"""")))
        assertNotNull(parseClipShape(Json.parseToJsonElement(""""ellipse"""")))
    }

    @Test
    fun `parseClipShape resolves rounded rectangle with cornerRadius`() {
        assertEquals(
            RoundedCornerShape(12.dp),
            parseClipShape(props("""{"type":"roundedRectangle","cornerRadius":12}"""))
        )
    }

    @Test
    fun `parseClipShape per-axis corners warn and approximate`() {
        val logger = CapturingLogger()
        val shape = parseClipShape(
            props("""{"type":"roundedRectangle","cornerRadiusX":12,"cornerRadiusY":8}"""),
            logger
        )
        assertNotNull(shape)
        assertEquals(1, logger.warnings.size)
    }

    @Test
    fun `parseClipShape returns null for unknown string`() {
        val logger = CapturingLogger()
        assertNull(parseClipShape(Json.parseToJsonElement(""""hexagon""""), logger))
        assertEquals(1, logger.warnings.size)
    }

    @Test
    fun `parseTransformOrigin maps anchors and defaults to center`() {
        assertEquals(TransformOrigin(0f, 0f), parseTransformOrigin("topLeading"))
        assertEquals(TransformOrigin(1f, 0.5f), parseTransformOrigin("trailing"))
        assertEquals(TransformOrigin(0.5f, 1f), parseTransformOrigin("bottom"))
        assertEquals(TransformOrigin.Center, parseTransformOrigin(null))
        assertEquals(TransformOrigin.Center, parseTransformOrigin("nonsense"))
    }
}
