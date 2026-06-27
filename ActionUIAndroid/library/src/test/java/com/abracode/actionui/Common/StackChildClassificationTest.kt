package com.abracode.actionui.Common

import kotlinx.serialization.json.Json
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [stackChildDataFor] - how a stack classifies a child's flex on the
 * MAIN axis (fill) and the CROSS axis (crossFill). The load-bearing case: a TextField
 * is greedy on the WIDTH axis only (like SwiftUI), so it fills an HStack's main axis
 * but must NOT fill a VStack's vertical main axis (it filled it before, ballooning the
 * field) - in a VStack it fills the cross axis (width) instead and hugs its height.
 */
class StackChildClassificationTest {

    private val json: Json = ActionUIJson

    private fun element(text: String): ActionUIElement =
        json.decodeFromString(ActionUIElement.serializer(), text)

    @Test
    fun `TextField in a VStack does not fill the vertical main axis, fills width`() {
        val v = stackChildDataFor(element("""{"type":"TextField"}"""), horizontal = false)
        assertFalse("a TextField must not fill a VStack's vertical main axis", v.fill)
        assertTrue("a TextField fills the VStack width (cross axis)", v.crossFill)
    }

    @Test
    fun `TextField in an HStack fills the main axis (width), not the cross axis`() {
        val h = stackChildDataFor(element("""{"type":"TextField"}"""), horizontal = true)
        assertTrue("a TextField fills an HStack's main (width) axis", h.fill)
        assertFalse(h.crossFill)
    }

    @Test
    fun `SecureField behaves like TextField (width-greedy only)`() {
        val v = stackChildDataFor(element("""{"type":"SecureField"}"""), horizontal = false)
        assertFalse(v.fill)
        assertTrue(v.crossFill)
    }

    @Test
    fun `TextEditor is greedy on the main axis in both orientations`() {
        assertTrue(stackChildDataFor(element("""{"type":"TextEditor"}"""), horizontal = true).fill)
        assertTrue(
            "a multi-line TextEditor fills a VStack's height too",
            stackChildDataFor(element("""{"type":"TextEditor"}"""), horizontal = false).fill,
        )
    }

    @Test
    fun `an explicit width frame governs the cross axis, suppressing crossFill`() {
        val v = stackChildDataFor(
            element("""{"type":"TextField","properties":{"frame":{"width":120}}}"""),
            horizontal = false,
        )
        assertFalse(v.fill)
        assertFalse("an explicit width frame governs the cross axis, so no crossFill", v.crossFill)
    }

    @Test
    fun `a plain Text is content-sized on both axes`() {
        val t = """{"type":"Text","properties":{"text":"hi"}}"""
        assertFalse(stackChildDataFor(element(t), horizontal = false).fill)
        assertFalse(stackChildDataFor(element(t), horizontal = false).crossFill)
        assertFalse(stackChildDataFor(element(t), horizontal = true).fill)
    }
}
