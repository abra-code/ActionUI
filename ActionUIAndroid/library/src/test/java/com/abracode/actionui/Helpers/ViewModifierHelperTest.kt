package com.abracode.actionui.Helpers

import androidx.compose.ui.Alignment
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [resolveDecorationAlignment] - the `overlayAlignment` /
 * `backgroundAlignment` resolution of the decoration subviews
 * (`ViewModifierHelper.kt`). Apple contract (`View.swift` `resolveAlignment`):
 * SwiftUI alignment vocabulary, default `center` when absent, warn-and-center
 * when unknown.
 */
class ViewModifierHelperTest {

    private class RecordingLogger : ActionUILogger {
        val messages = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            messages.add(message)
        }
    }

    @Test
    fun `missing alignment property defaults to center without warning`() {
        val logger = RecordingLogger()
        val alignment = resolveDecorationAlignment(
            buildJsonObject { put("text", "hi") }, "overlayAlignment", logger
        )

        assertEquals(Alignment.Center, alignment)
        assertTrue(logger.messages.isEmpty())
    }

    @Test
    fun `null properties default to center`() {
        assertEquals(
            Alignment.Center,
            resolveDecorationAlignment(null, "backgroundAlignment", null)
        )
    }

    @Test
    fun `resolves the SwiftUI alignment vocabulary`() {
        fun resolve(name: String): Alignment = resolveDecorationAlignment(
            buildJsonObject { put("overlayAlignment", name) }, "overlayAlignment", null
        )

        // Corners.
        assertEquals(Alignment.TopStart, resolve("topLeading"))
        assertEquals(Alignment.TopEnd, resolve("topTrailing"))
        assertEquals(Alignment.BottomStart, resolve("bottomLeading"))
        assertEquals(Alignment.BottomEnd, resolve("bottomTrailing"))
        // Edges center on the cross axis, like SwiftUI's plain edge alignments.
        assertEquals(Alignment.TopCenter, resolve("top"))
        assertEquals(Alignment.BottomCenter, resolve("bottom"))
        assertEquals(Alignment.CenterStart, resolve("leading"))
        assertEquals(Alignment.CenterEnd, resolve("trailing"))
        assertEquals(Alignment.Center, resolve("center"))
    }

    @Test
    fun `unknown alignment warns naming the property and defaults to center`() {
        val logger = RecordingLogger()
        val alignment = resolveDecorationAlignment(
            buildJsonObject { put("backgroundAlignment", "diagonal") },
            "backgroundAlignment", logger
        )

        assertEquals(Alignment.Center, alignment)
        assertEquals(1, logger.messages.size)
        assertTrue(logger.messages[0].contains("backgroundAlignment"))
        assertTrue(logger.messages[0].contains("diagonal"))
    }

    // MARK: - mergeProperties (the setElementProperty override merge)

    @Test
    fun `overrides layer over authored properties with override winning per key`() {
        val authored = buildJsonObject {
            put("title", "hello")
            put("opacity", 0.5)
        }
        val merged = mergeProperties(
            authored,
            mapOf("opacity" to JsonPrimitive(0.25), "hidden" to JsonPrimitive(true))
        )

        assertEquals(JsonPrimitive("hello"), merged["title"])     // authored kept
        assertEquals(JsonPrimitive(0.25), merged["opacity"])      // override wins
        assertEquals(JsonPrimitive(true), merged["hidden"])       // new key added
    }

    @Test
    fun `overrides alone form the properties when nothing was authored`() {
        val merged = mergeProperties(null, mapOf("opacity" to JsonPrimitive(0.1)))
        assertEquals(1, merged.size)
        assertEquals(JsonPrimitive(0.1), merged["opacity"])
    }

    // MARK: - Reactive foregroundStyle / tint (the setElementProperty recolor path)
    //
    // Regression: on Android these two were resolved off the parent's STATIC child
    // properties (ProvideTextStyleEnvironment), so a host setElementProperty recolor
    // never took effect - the BodyMetrics BMI gauge/category stayed the authored
    // green. They now resolve off the host-merged EFFECTIVE element
    // (ProvideReactiveEnvironment reads the mergeProperties output below). These tests
    // pin that data path: the authored color resolves before an override, the
    // override color after (green -> orange).

    @Test
    fun `foregroundStyle and tint overrides merge into the effective element`() {
        val authored = buildJsonObject {
            put("foregroundStyle", "green")
            put("tint", "green")
            put("value", 24.2)
        }
        // Before any host write the effective element is the authored one.
        assertEquals("green", authored.stringProperty("foregroundStyle"))
        assertEquals("green", authored.stringProperty("tint"))

        // A host setElementProperty(foregroundStyle/tint, "orange") lands here.
        val effective = mergeProperties(
            authored,
            mapOf(
                "foregroundStyle" to JsonPrimitive("orange"),
                "tint" to JsonPrimitive("orange"),
            )
        )
        assertEquals("orange", effective.stringProperty("foregroundStyle"))
        assertEquals("orange", effective.stringProperty("tint"))
        assertEquals(JsonPrimitive(24.2), effective["value"])   // untouched keys preserved
    }

    @Test
    fun `the merged color name resolves to the recolored Color`() {
        // Named colors resolve without a ColorScheme (only semantic names need one).
        val authored = buildJsonObject { put("foregroundStyle", "green") }
        val before = resolveColorOrSemantic(authored.stringProperty("foregroundStyle")!!, null)

        val effective = mergeProperties(authored, mapOf("foregroundStyle" to JsonPrimitive("orange")))
        val after = resolveColorOrSemantic(effective.stringProperty("foregroundStyle")!!, null)

        assertNotNull(before)
        assertNotNull(after)
        assertNotEquals("a host recolor must change the resolved Color", before, after)
    }
}
