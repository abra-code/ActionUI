package com.abracode.actionui.Common

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for [ActionUIModel.appendElementText]: appends to a String value, seeds an
 * unset String-typed value, and refuses a non-text element or an unknown view.
 */
class ActionUIModelAppendTextTest {

    private class CapturingLogger : ActionUILogger {
        val warnings = mutableListOf<String>()
        override fun log(message: String, level: LoggerLevel) {
            if (level == LoggerLevel.warning) warnings.add(message)
        }
    }

    private lateinit var logger: CapturingLogger

    @Before
    fun setUp() {
        logger = CapturingLogger()
        ActionUIModel.logger = logger
        val root = ActionUIElement(
            id = 100, type = "VStack",
            children = listOf(
                ActionUIElement(id = 1, type = "TextEditor"),
                ActionUIElement(id = 2, type = "TextField"),
                ActionUIElement(id = 3, type = "Slider"),
            ),
        )
        ActionUIModel.loadDescription(root, windowUUID = "")
    }

    @After
    fun tearDown() {
        ActionUIModel.unregisterWindow("")
        ActionUIModel.logger = ConsoleLogger()
    }

    @Test
    fun `appends to a TextEditor value`() {
        ActionUIModel.setElementValue(viewID = 1, value = "Hello")
        assertTrue(ActionUIModel.appendElementText(viewID = 1, text = ", world"))
        assertEquals("Hello, world", ActionUIModel.getElementValue(viewID = 1))
    }

    @Test
    fun `appends to a TextField value`() {
        ActionUIModel.setElementValue(viewID = 2, value = "ab")
        assertTrue(ActionUIModel.appendElementText(viewID = 2, text = "cd"))
        assertEquals("abcd", ActionUIModel.getElementValue(viewID = 2))
    }

    @Test
    fun `an unset String value becomes the text`() {
        assertNull(ActionUIModel.getElementValue(viewID = 1))
        assertTrue(ActionUIModel.appendElementText(viewID = 1, text = "first"))
        assertEquals("first", ActionUIModel.getElementValue(viewID = 1))
    }

    @Test
    fun `refused for a non-text element`() {
        ActionUIModel.setElementValue(viewID = 3, value = 0.5)
        assertFalse(ActionUIModel.appendElementText(viewID = 3, text = "x"))
        assertEquals(0.5, ActionUIModel.getElementValue(viewID = 3))
        assertEquals(1, logger.warnings.size)
    }

    @Test
    fun `refused for an unset non-text element`() {
        assertFalse(ActionUIModel.appendElementText(viewID = 3, text = "x"))
        assertNull(ActionUIModel.getElementValue(viewID = 3))
    }

    @Test
    fun `refused for an unknown view`() {
        assertFalse(ActionUIModel.appendElementText(viewID = 404, text = "x"))
        assertEquals(1, logger.warnings.size)
    }
}
