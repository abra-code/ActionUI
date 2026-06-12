package com.abracode.actionui.Helpers

import androidx.compose.ui.Alignment
import com.abracode.actionui.Common.ActionUILogger
import com.abracode.actionui.Common.LoggerLevel
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
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
}
